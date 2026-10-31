import { expect, test } from "bun:test";
import potetomode from "./index.js";

const entry = (pinned) => ({ type: "custom", customType: "poteto-mode", data: { pinned } });
function host(flag = true) {
  const events = new Map();
  let command, shortcut, entries = [], status = "", idle = true;
  const sent = [];
  const ctx = {
    sessionManager: { getBranch: () => entries },
    ui: { theme: { fg: (_color, text) => text }, setStatus: (_key, value) => { status = value; }, notify() {} },
    isIdle: () => idle,
  };
  potetomode({
    registerCommand: (_name, value) => { command = value.handler; },
    registerFlag() {},
    registerShortcut: (_name, value) => { shortcut = value.handler; },
    on: (name, handler) => events.set(name, handler),
    getFlag: () => flag,
    appendEntry: (_name, data) => entries.push(entry(data.pinned)),
    sendUserMessage: (text, options) => sent.push({ text, options }),
  });
  return {
    start: async (branch = []) => { entries = branch; await events.get("session_start")({}, ctx); },
    emit: async (name, branch = []) => { entries = branch; await events.get(name)?.({}, ctx); },
    before: (systemPrompt = ["original"]) => events.get("before_agent_start")({ systemPrompt }),
    command: (args) => command(args, ctx),
    shortcut: () => shortcut(ctx),
    status: () => status,
    busy: () => { idle = false; },
    sent,
  };
}

test("persisted explicit off survives a restart with --poteto", async () => {
  const session = host();
  await session.start([entry(false)]);
  expect(await session.before()).toBeUndefined();
});

test("--poteto still enables a session without a saved override", async () => {
  const session = host();
  await session.start();
  expect((await session.before()).systemPrompt[1]).toContain("poteto-mode is PINNED");
});

test("malformed stored booleans never activate the pin", async () => {
  const session = host();
  for (const pinned of ["false", 1, null, undefined]) {
    await session.start([entry(pinned)]);
    expect(await session.before()).toBeUndefined();
  }
});

test("latest entry wins and a new session resets the previous override", async () => {
  const session = host();
  await session.start([entry(true), entry(false)]);
  expect(await session.before()).toBeUndefined();
  await session.start();
  expect(await session.before()).toBeDefined();
  await session.start([entry(false), entry(true)]);
  expect(await session.before()).toBeDefined();
});

test("shortcut, status, command and injection share one effective state", async () => {
  const session = host();
  await session.start();
  expect(session.status()).not.toBe("");
  session.shortcut();
  expect(session.status()).toBe("");
  expect(await session.before()).toBeUndefined();
  await session.command("on");
  expect(session.status()).not.toBe("");
  expect(await session.before()).toBeDefined();
  await session.command("off");
  expect(await session.before()).toBeUndefined();
});

test("prompt block boundaries and input blocks remain intact", async () => {
  const session = host();
  await session.start();
  const blocks = ["first", "second"];
  const result = await session.before(blocks);
  expect(result.systemPrompt.slice(0, 2)).toEqual(blocks);
  expect(blocks).toEqual(["first", "second"]);
  expect(result.systemPrompt).toHaveLength(3);
});

test("switch, branch and tree navigation reload the pin from the branch they land on", async () => {
  for (const event of ["session_switch", "session_branch", "session_tree"]) {
    const session = host(false);
    await session.start([entry(true)]);
    await session.emit(event);
    expect(await session.before()).toBeUndefined();
    expect(session.status()).toBe("");
    await session.emit(event, [entry(true)]);
    expect((await session.before()).systemPrompt[1]).toContain("poteto-mode is PINNED");
  }
});

test("/poteto-mode <task> pins the session and starts the task", async () => {
  const session = host(false);
  await session.start();
  await session.command("  Fix the bug in parser.ts ");
  expect(session.sent).toHaveLength(1);
  expect(session.sent[0].text).toBe("Fix the bug in parser.ts");
  expect(session.sent[0].options?.deliverAs).toBeUndefined();
  expect(await session.before()).toBeDefined();
});

test("/poteto-mode <task> queues the task as a follow-up while a turn is running", async () => {
  const session = host(false);
  await session.start();
  session.busy();
  await session.command("fix the bug");
  expect(session.sent).toEqual([{ text: "fix the bug", options: { deliverAs: "followUp" } }]);
});

test("/poteto-mode status sends nothing and leaves the pin where it was", async () => {
  for (const flag of [true, false]) {
    const session = host(flag);
    await session.start();
    await session.command("status");
    expect(session.sent).toEqual([]);
    expect((await session.before()) !== undefined).toBe(flag);
  }
});
