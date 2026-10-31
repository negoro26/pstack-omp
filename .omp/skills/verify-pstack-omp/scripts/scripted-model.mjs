#!/usr/bin/env bun
// A deterministic OpenAI-completions provider for driving omp without a real model.
//
//   bun scripted-model.mjs <state-dir>
//
// Listens on 127.0.0.1 at a free port, writes the port to <state-dir>/model.port, and appends every
// request body to <state-dir>/model-requests.jsonl. The last user message decides the reply:
//   a line `tool:<name> <json-args>`  one tool call with those arguments
//   a tool result as the last message  the text `scripted-model: tool result received`
//   anything else                      the text `scripted-model: no script for this prompt`
import { appendFileSync, writeFileSync } from "node:fs";
import { join } from "node:path";

const dir = process.argv[2];
if (!dir) {
  console.error("usage: bun scripted-model.mjs <state-dir>");
  process.exit(2);
}
const log = join(dir, "model-requests.jsonl");

const text = (content) =>
  typeof content === "string"
    ? content
    : (content ?? []).map((part) => (part.type === "text" ? part.text : "")).join("\n");

function decide(messages) {
  const last = messages.at(-1);
  if (last?.role === "tool") return { text: "scripted-model: tool result received" };
  const user = [...messages].reverse().find((m) => m.role === "user");
  const call = /^tool:(\w+) (\{.*\})\s*$/m.exec(text(user?.content));
  if (call) return { tool: call[1], args: call[2] };
  return { text: "scripted-model: no script for this prompt" };
}

const chunk = (delta, finish, extra = {}) =>
  `data: ${JSON.stringify({
    id: "scripted",
    object: "chat.completion.chunk",
    created: 0,
    model: "scripted",
    choices: [{ index: 0, delta, finish_reason: finish }],
    ...extra,
  })}\n\n`;

function reply(plan, stream) {
  const call = plan.tool && { id: "call_scripted", type: "function", function: { name: plan.tool, arguments: plan.args } };
  const finish = call ? "tool_calls" : "stop";
  const usage = { prompt_tokens: 1, completion_tokens: 1, total_tokens: 2 };
  if (!stream) {
    const message = call ? { role: "assistant", content: null, tool_calls: [call] } : { role: "assistant", content: plan.text };
    return Response.json({
      id: "scripted",
      object: "chat.completion",
      created: 0,
      model: "scripted",
      choices: [{ index: 0, message, finish_reason: finish }],
      usage,
    });
  }
  const delta = call ? { role: "assistant", tool_calls: [{ index: 0, ...call }] } : { role: "assistant", content: plan.text };
  const body = chunk(delta, null) + chunk({}, finish, { usage }) + "data: [DONE]\n\n";
  return new Response(body, { headers: { "content-type": "text/event-stream" } });
}

const server = Bun.serve({
  hostname: "127.0.0.1",
  port: 0,
  async fetch(request) {
    const url = new URL(request.url);
    if (url.pathname.endsWith("/health")) return new Response("ok");
    const body = request.method === "POST" ? await request.json().catch(() => null) : null;
    const plan = body?.messages ? decide(body.messages) : null;
    appendFileSync(log, `${JSON.stringify({ at: new Date().toISOString(), path: url.pathname, plan, body })}\n`);
    if (!url.pathname.endsWith("/chat/completions") || !plan) return new Response("not found", { status: 404 });
    return reply(plan, body.stream === true);
  },
});

writeFileSync(join(dir, "model.port"), `${server.port}\n`);
console.log(`scripted-model: listening on 127.0.0.1:${server.port}, logging to ${log}`);
