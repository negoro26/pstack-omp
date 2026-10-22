#!/usr/bin/env bun
// Loads the plugin tree into a real omp and checks what only omp can answer: that every skill
// directory registers as a command, and that the pin extension records and reloads its state.
//
//   bun omp-port/smoke-plugin.mjs [plugin-dir]     plugin-dir defaults to plugins/pstack
//
// No omp on PATH prints SKIPPED and exits 0, unless OMP_SMOKE_REQUIRED=1 makes that a failure.
import assert from "node:assert";
import { spawn, spawnSync } from "node:child_process";
import { mkdir, mkdtemp, readdir, rm, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join, resolve } from "node:path";
import { createInterface } from "node:readline";
import { fileURLToPath } from "node:url";

const plugin = resolve(process.argv[2] ?? fileURLToPath(new URL("../plugins/pstack", import.meta.url)));

const version = spawnSync("omp", ["--version"], { encoding: "utf8" });
if (version.error?.code === "ENOENT") {
  if (process.env.OMP_SMOKE_REQUIRED === "1") {
    console.error("smoke-plugin: FAIL  omp is not on PATH and OMP_SMOKE_REQUIRED=1");
    process.exit(1);
  }
  console.log("smoke-plugin: SKIPPED  omp is not on PATH; set OMP_SMOKE_REQUIRED=1 to fail instead");
  process.exit(0);
}
if (version.status !== 0) {
  console.error(`smoke-plugin: FAIL  omp --version exited ${version.status}: ${version.stderr}`);
  process.exit(1);
}

const skills = (await readdir(join(plugin, "skills"), { withFileTypes: true }))
  .filter((entry) => entry.isDirectory())
  .map((entry) => entry.name)
  .sort();

// A fresh HOME keeps the operator's plugins, extensions and credentials out. The variables stripped
// below would relocate omp's roots past it.
const home = await mkdtemp(join(tmpdir(), "pstack-smoke-"));
await mkdir(join(home, ".omp", "agent"), { recursive: true });
// omp refuses to start without a model. A local provider on the discard port satisfies that with
// no credentials, and a turn that did start fails on a refused connection instead of reaching one.
await writeFile(
  join(home, ".omp", "agent", "models.yml"),
  [
    "providers:",
    "  smoke:",
    "    baseUrl: http://127.0.0.1:9/v1",
    "    auth: none",
    "    api: openai-completions",
    "    models:",
    "      - id: no-inference",
    "",
  ].join("\n"),
);
const env = { ...process.env, HOME: home, USERPROFILE: home };
for (const key of Object.keys(env)) {
  if (/^(?:OMP_|PI_|XDG_(?:CONFIG|DATA|STATE|CACHE)_HOME$|CLAUDE_CONFIG_DIR$)|API_KEY|TOKEN|SECRET|PASSWORD/i.test(key)) {
    delete env[key];
  }
}

// --plugin-dir adds the tree to skill discovery but does not load package.json omp.extensions, so
// the same directory also goes in as -e, which does.
const child = spawn(
  "omp",
  [
    "--mode", "rpc", "--no-session", "--no-title", "--no-lsp", "--no-tools", "--no-rules",
    "--no-extensions", "--plugin-dir", plugin, "-e", plugin, "--model", "smoke/no-inference",
  ],
  { cwd: home, env, stdio: ["pipe", "pipe", "pipe"] },
);
let stderr = "";
child.stderr.on("data", (chunk) => { stderr += chunk; });
let spawnError;
child.on("error", (error) => { spawnError = error; });
const exited = new Promise((done) => child.once("close", (code) => done(code)));
const lines = createInterface({ input: child.stdout })[Symbol.asyncIterator]();
const timer = setTimeout(() => child.kill(), 60_000);

const notices = [];
async function frame() {
  const { value, done } = await lines.next();
  assert(!done, spawnError?.message ?? "omp exited before the smoke finished");
  const message = JSON.parse(value);
  assert(message.type !== "agent_start", "a smoke step started a model turn");
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
      assert(message.agentInvoked === false, `${fields.message} reached the agent`);
      assert(message.status === "completed", `${fields.message} ended ${message.status}`);
      return message;
    }
  }
}

const pinEntry = async () =>
  (await request("get_entries")).entries
    .filter((entry) => entry.type === "custom" && entry.customType === "poteto-mode")
    .at(-1)?.data?.pinned;

try {
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

  for (const [argument, pinned] of [["on", true], ["off", false]]) {
    await request("prompt", { message: `/poteto-mode ${argument}` });
    assert((await pinEntry()) === pinned, `/poteto-mode ${argument} did not record pinned: ${pinned}`);
  }

  // /new arrives as session_switch; the pin from the session it left must not follow it.
  await request("prompt", { message: "/poteto-mode on" });
  await request("new_session");
  await request("prompt", { message: "/poteto-mode status" });
  assert(notices.at(-1) === "poteto-mode: not pinned", `the pin survived new_session (${notices.at(-1)})`);

  child.stdin.end();
  assert((await exited) === 0, "omp did not exit cleanly");
  console.log(
    `smoke-plugin: PASS  ${version.stdout.trim()}: ${skills.length}/${skills.length} skills registered; ` +
      "/poteto-mode on/off recorded; pin reloaded on new_session; no model turn",
  );
} catch (error) {
  console.error(`smoke-plugin: FAIL  ${error.message}`);
  if (stderr.trim()) console.error(`omp stderr:\n${stderr.trim()}`);
  process.exitCode = 1;
} finally {
  clearTimeout(timer);
  if (child.exitCode === null) child.kill();
  await exited;
  await rm(home, { recursive: true, force: true });
}
