#!/usr/bin/env bun
// Loads the plugin tree into a real omp once per install shape and checks what only omp can answer:
// every skill directory registers as a command, the pin extension records and reloads its state, a
// pinned turn's system prompt carries the poteto-mode reminder, and pstackpolicy refuses a bash
// `gh pr merge` before gh runs. Turns go to a scripted model on loopback, so no credential is used.
//
//   bun omp-port/smoke-plugin.mjs [plugin-dir]     plugin-dir defaults to plugins/pstack
//
// No omp on PATH prints SKIPPED and exits 0, unless OMP_SMOKE_REQUIRED=1 makes that a failure.
import assert from "node:assert";
import { spawn, spawnSync } from "node:child_process";
import { mkdir, mkdtemp, readFile, readdir, rm, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join, resolve } from "node:path";
import { createInterface } from "node:readline";
import { fileURLToPath } from "node:url";
import { scriptedModel, text } from "./scripted-model.mjs";

const plugin = resolve(process.argv[2] ?? fileURLToPath(new URL("../plugins/pstack", import.meta.url)));

const omp = Bun.which("omp");
if (!omp) {
  if (process.env.OMP_SMOKE_REQUIRED === "1") {
    console.error("smoke-plugin: FAIL  omp is not on PATH and OMP_SMOKE_REQUIRED=1");
    process.exit(1);
  }
  console.log("smoke-plugin: SKIPPED  omp is not on PATH; set OMP_SMOKE_REQUIRED=1 to fail instead");
  process.exit(0);
}
const version = spawnSync(omp, ["--version"], { encoding: "utf8" });
if (version.status !== 0) {
  console.error(`smoke-plugin: FAIL  omp --version exited ${version.status}: ${version.stderr}`);
  process.exit(1);
}

const skills = (await readdir(join(plugin, "skills"), { withFileTypes: true }))
  .filter((entry) => entry.isDirectory())
  .map((entry) => entry.name)
  .sort();

const MERGE = "gh pr merge 1 --repo pstack-verify/no-such-repo --squash";

// --plugin-dir adds the tree to skill discovery but does not load package.json omp.extensions, so
// the -e shape passes the directory twice. --no-extensions also drops a linked plugin's skills and
// extensions, so the link shape leaves discovery on.
const shapes = [
  { name: "-e", args: ["--no-extensions", "--plugin-dir", plugin, "-e", plugin] },
  { name: "omp plugin link", link: true, args: [] },
];

const systemPrompt = (body) =>
  body.messages.filter((m) => m.role === "system").map((m) => text(m.content)).join("\n");

async function leg(shape) {
  const home = await mkdtemp(join(tmpdir(), "pstack-smoke-"));
  const bin = join(home, "bin");
  const ghCalls = join(home, "gh-calls.log");
  const model = scriptedModel();
  let child;
  let exited;
  let timer;
  let stderr = "";
  try {
    await mkdir(join(home, ".omp", "agent"), { recursive: true });
    await mkdir(bin);
    await writeFile(
      join(home, ".omp", "agent", "models.yml"),
      [
        "providers:",
        "  smoke:",
        `    baseUrl: ${model.baseUrl}`,
        "    auth: none",
        "    api: openai-completions",
        "    models:",
        "      - id: scripted",
        "",
      ].join("\n"),
    );
    await writeFile(join(bin, "gh"), `#!/bin/sh\nprintf '%s\\n' "$*" >>'${ghCalls}'\necho "gh-shim: $*"\n`, {
      mode: 0o755,
    });
    // As under env -i, nothing from the operator's environment reaches omp. That keeps out every
    // credential, every variable that moves omp's roots past the scratch HOME, and the real gh.
    const env = { HOME: home, PATH: `${bin}:/usr/local/bin:/usr/bin:/bin` };

    if (shape.link) {
      const linked = spawnSync(omp, ["plugin", "link", plugin], { cwd: home, env, encoding: "utf8" });
      assert(linked.status === 0, `omp plugin link exited ${linked.status}: ${linked.stderr}`);
    }

    // Under yolo only pstackpolicy's tool_call veto stands between bash and gh. That is its case.
    child = spawn(
      omp,
      [
        "--mode", "rpc", "--no-session", "--no-title", "--no-lsp", "--no-rules", "--tools", "bash",
        "--approval-mode", "yolo", "--model", "smoke/scripted", ...shape.args,
      ],
      { cwd: home, env, stdio: ["pipe", "pipe", "pipe"] },
    );
    child.stderr.on("data", (chunk) => { stderr += chunk; });
    let spawnError;
    child.on("error", (error) => { spawnError = error; });
    exited = new Promise((done) => child.once("close", (code) => done(code)));
    const lines = createInterface({ input: child.stdout })[Symbol.asyncIterator]();
    timer = setTimeout(() => child.kill(), 60_000);

    const notices = [];
    async function frame() {
      const { value, done } = await lines.next();
      assert(!done, spawnError?.message ?? "omp exited before the smoke finished");
      const message = JSON.parse(value);
      assert(message.type !== "extension_error", `extension error: ${value}`);
      if (message.type === "extension_ui_request" && message.method === "notify") notices.push(message.message);
      return message;
    }

    let nextId = 0;
    async function request(type, fields = {}) {
      const id = String(++nextId);
      child.stdin.write(`${JSON.stringify({ id, type, ...fields })}\n`);
      for (;;) {
        const message = await frame();
        if (message.id !== id) continue;
        if (message.type === "response") {
          assert(message.success === true, `${type} failed: ${message.error}`);
          if (type !== "prompt" || message.data?.agentInvoked === false) return message.data;
        }
        if (message.type === "prompt_result") {
          assert(message.status === "completed", `${fields.message} ended ${message.status}: ${JSON.stringify(message.error)}`);
          return message;
        }
      }
    }

    const command = async (message) =>
      assert((await request("prompt", { message })).agentInvoked === false, `${message} reached the agent`);

    async function turn(message) {
      assert((await request("prompt", { message })).agentInvoked === true, `${message} started no model turn`);
      return model.requests.filter((body) =>
        text(body.messages.findLast((m) => m.role === "user")?.content).includes(message),
      );
    }

    async function bash(commandLine) {
      const requests = await turn(`tool:bash ${JSON.stringify({ command: commandLine })}`);
      const result = requests.map((body) => body.messages.at(-1)).find((m) => m.role === "tool");
      assert(result, `the model never got a tool result for ${commandLine}`);
      return text(result.content);
    }

    const pinEntry = async () =>
      (await request("get_entries")).entries
        .filter((entry) => entry.type === "custom" && entry.customType === "poteto-mode")
        .at(-1)?.data?.pinned;

    while ((await frame()).type !== "ready");

    const { commands } = await request("get_available_commands");
    const registered = new Set(commands.filter((c) => c.source === "skill").map((c) => c.name));
    const missing = skills.filter((name) => !registered.has(`skill:${name}`));
    assert(
      missing.length === 0,
      `${skills.length - missing.length} of ${skills.length} skill directories registered as skill:<name>; ` +
        `missing ${missing.slice(0, 5).join(", ")}${missing.length > 5 ? ` and ${missing.length - 5} more` : ""}`,
    );
    assert(
      commands.some((c) => c.name === "poteto-mode" && c.source === "extension"),
      "the potetomode extension did not register /poteto-mode",
    );

    const [unpinned] = await turn("smoke: unpinned turn");
    assert(unpinned, "the unpinned turn sent no request to the model");
    assert(
      !systemPrompt(unpinned).includes("skill://poteto-mode"),
      "an unpinned system prompt already names skill://poteto-mode, so the pinned check could not fail",
    );

    await command("/poteto-mode on");
    assert((await pinEntry()) === true, "/poteto-mode on did not record pinned: true");
    const [pinned] = await turn("smoke: pinned turn");
    assert(pinned, "the pinned turn sent no request to the model");
    assert(systemPrompt(pinned).includes("skill://poteto-mode"), "the pinned turn's system prompt lacks the poteto-mode reminder");

    assert((await bash("gh --version")).includes("gh-shim: --version"), "bash did not resolve gh to the logging shim");
    const merged = await bash(MERGE);
    assert(merged.includes("pstackpolicy: refused"), `the model got ${JSON.stringify(merged.slice(0, 200))} back for ${MERGE}`);
    const calls = (await readFile(ghCalls, "utf8")).trim().split("\n");
    assert.deepStrictEqual(calls, ["--version"], `gh ran for: ${calls.join(" | ")}`);

    await command("/poteto-mode off");
    assert((await pinEntry()) === false, "/poteto-mode off did not record pinned: false");

    // /new arrives as session_switch; the pin from the session it left must not follow it.
    await command("/poteto-mode on");
    await request("new_session");
    await command("/poteto-mode status");
    assert(notices.at(-1) === "poteto-mode: not pinned", `the pin survived new_session (${notices.at(-1)})`);

    child.stdin.end();
    assert((await exited) === 0, "omp did not exit cleanly");
  } catch (error) {
    if (stderr.trim()) error.message += `\nomp stderr:\n${stderr.trim()}`;
    throw error;
  } finally {
    clearTimeout(timer);
    if (child?.exitCode === null) child.kill();
    await exited;
    model.stop();
    await rm(home, { recursive: true, force: true });
  }
}

for (const shape of shapes) {
  try {
    await leg(shape);
    console.log(
      `smoke-plugin: PASS  ${version.stdout.trim()} via ${shape.name}: ${skills.length}/${skills.length} skills ` +
        "registered; /poteto-mode on/off recorded; pinned system prompt names skill://poteto-mode; " +
        "pstackpolicy refused the merge and gh never ran; pin reloaded on new_session",
    );
  } catch (error) {
    console.error(`smoke-plugin: FAIL  ${version.stdout.trim()} via ${shape.name}: ${error.message}`);
    process.exitCode = 1;
  }
}
