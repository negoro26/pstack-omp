import { expect, test } from "bun:test";
import potetomode from "./index.js";

const entry = (pinned) => ({ type: "custom", customType: "poteto-mode", data: { pinned } });
function host(flag = true) {
  const events = new Map();
  let command, shortcut, entries = [], status = "";
  const ctx = {
    sessionManager: { getBranch: () => entries },
    ui: { theme: { fg: (_color, text) => text }, setStatus: (_key, value) => { status = value; }, notify() {} },
  };
  potetomode({
    registerCommand: (_name, value) => { command = value.handler; },
    registerFlag() {},
    registerShortcut: (_name, value) => { shortcut = value.handler; },
    on: (name, handler) => events.set(name, handler),
    getFlag: () => flag,
    appendEntry: (_name, data) => entries.push(entry(data.pinned)),
    sendUserMessage() {},
  });
  return {
    start: async (branch = []) => { entries = branch; await events.get("session_start")({}, ctx); },
    before: (systemPrompt = ["original"]) => events.get("before_agent_start")({ systemPrompt }),
    command: (args) => command(args, ctx),
    shortcut: () => shortcut(ctx),
    status: () => status,
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
  expect(session.status()).toContain("PINNED");
  session.shortcut();
  expect(session.status()).toBe("");
  expect(await session.before()).toBeUndefined();
  await session.command("on");
  expect(session.status()).toContain("PINNED");
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
