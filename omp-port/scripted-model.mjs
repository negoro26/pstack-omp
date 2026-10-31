// A deterministic OpenAI-completions provider on loopback, so a smoke can drive real omp turns
// without a model. Every request body lands in `requests`. The last user message decides the reply:
//   a line `tool:<name> <json-args>`   one tool call with those arguments
//   a tool result as the last message  the text `scripted-model: tool result received`
//   anything else                      the text `scripted-model: no script for this prompt`

export const text = (content) =>
  typeof content === "string"
    ? content
    : (content ?? []).map((part) => (part.type === "text" ? part.text : "")).join("\n");

function decide(messages) {
  if (messages.at(-1)?.role === "tool") return { text: "scripted-model: tool result received" };
  const user = messages.findLast((m) => m.role === "user");
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

function reply(plan) {
  const call = plan.tool && { id: "call_scripted", type: "function", function: { name: plan.tool, arguments: plan.args } };
  const delta = call ? { role: "assistant", tool_calls: [{ index: 0, ...call }] } : { role: "assistant", content: plan.text };
  const usage = { prompt_tokens: 1, completion_tokens: 1, total_tokens: 2 };
  const body = chunk(delta, null) + chunk({}, call ? "tool_calls" : "stop", { usage }) + "data: [DONE]\n\n";
  return new Response(body, { headers: { "content-type": "text/event-stream" } });
}

export function scriptedModel() {
  const requests = [];
  const server = Bun.serve({
    hostname: "127.0.0.1",
    port: 0,
    async fetch(request) {
      if (!new URL(request.url).pathname.endsWith("/chat/completions")) return new Response("not found", { status: 404 });
      const body = await request.json();
      requests.push(body);
      return reply(decide(body.messages));
    },
  });
  return { baseUrl: `http://127.0.0.1:${server.port}/v1`, requests, stop: () => server.stop(true) };
}
