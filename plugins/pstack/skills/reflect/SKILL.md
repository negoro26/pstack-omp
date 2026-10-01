---
name: reflect
description: Spawn three parallel review subagents over the active transcript, surface learnings, and route each to a concrete edit on an existing skill. Use when the user says reflect.
disable-model-invocation: true
---

# Reflect

Mine the current conversation for durable learnings, then route them into skill edits.

## When to invoke

Invoke when the user says "reflect" or "/reflect". Skip when the conversation is trivial, off-topic, or already covered by an existing skill the parent followed correctly. One-offs are not learnings.

## Process

### 1. Locate the active transcript

The parent finds its own transcript file before fanning out. The system prompt names the session transcript tree `~/.omp/agent/sessions/<encoded-cwd>/*.jsonl`, with subagent sidecars at `<session-stem>/<AgentId>.jsonl`. Use that path. Do not glob across sibling `~/.omp/agent/sessions/<other-cwd>/` buckets. That crosses workspace boundaries and reads private chats from unrelated projects.

```bash
ls -t ~/.omp/agent/sessions/<encoded-cwd>/*.jsonl ~/.omp/agent/sessions/<encoded-cwd>/*/*.jsonl ~/.omp/agent/sessions/<encoded-cwd>/*/subagents/*.jsonl 2>/dev/null | head -10
```

One transcript layout. A flat `<timestamp>_<session-id>.jsonl` per session in the bucket, with `<AgentId>.jsonl` sidecars in the sibling directory named for that stem, and one further subdirectory per nesting level whose files carry the full dotted id.

The first line of an omp transcript is a fixed-width `type:title` slot and the second a `type:session` header, neither of them a message. For each candidate, scan for the first `type:message` line with `role:user` and check that its text contains the conversation's opening user prompt. Take the matching path. If no path resolves, write a tight digest of the session and pass that instead.

### 2. Spawn three reviewers in parallel

One `task` call with three items in `tasks[]` and one required shared `context`, each item using an exact discovered agent name. Full tools per spawn. Run the three lenses on three different configured model families where available, and keep Divergent on a different model family from Judgment, since the lens earns its name from different priors and not a different prompt. Reviewers need full tools for MCP lookups (tickets, chat threads, observability traces referenced in the transcript); there is no task `readonly` field.

Resolve exact discovered agent names for the three lenses and the synthesizer. Each agent's frontmatter or `task.agentModelOverrides[<exact-name>]` selects the model; the task item has no `model` field.

| Lens | Exact agent | Prompt template |
|---|---|---|---|
| Judgment | discovered judgment agent | `references/judgment-reviewer.md` |
| Tooling | discovered tooling agent | `references/tooling-reviewer.md` |
| Divergent | discovered divergent agent | `references/divergent-reviewer.md` |

Pass each template verbatim, substituting the transcript path or digest where marked. Reviewers return findings in the `Task` response body.

### 3. Synthesize

One `task` call with one item in `tasks[]`, the required shared `context`, and an exact discovered synthesizer agent name. Its frontmatter or `task.agentModelOverrides[<exact-name>]` selects the model; the task item has no `model` field. The synthesizer needs full tools for citation spot-checks; there is no task `readonly` field. Use `references/synthesizer.md` verbatim, with each reviewer's full output inlined where marked. Pass this explicit `outputSchema` when the live task schema exposes it:

```json
{"type":"object","required":["Accepted","Rejected","Backlog"],"properties":{"Accepted":{"type":"array","items":{"type":"object","required":["Problem","Proposal","Routing"],"properties":{"Problem":{"type":"string"},"Proposal":{"type":"string"},"Routing":{"type":"string"}}}},"Rejected":{"type":"array","items":{"type":"object","required":["Principle","Reason"],"properties":{"Principle":{"type":"string"},"Reason":{"type":"string"}}}},"Backlog":{"type":"array","items":{"type":"object","required":["Pattern","Hit","Mechanism"],"properties":{"Pattern":{"type":"string"},"Hit":{"type":"string"},"Mechanism":{"type":"string"}}}}}}
```

### 4. Structural enforcement check

Sanity-check the synthesizer's Accepted list. For any item that would be enforced more reliably by a lint rule, script, metadata flag, or runtime check, move it from Accepted to Backlog. See the **encode-lessons-in-structure** principle skill.

### 5. Apply

Before applying any Accepted edit, present the synthesizer's full Accepted/Rejected/Backlog output to the user and wait for explicit approval. The user picks which subset to apply and may redirect routings. Skill changes affect every future agent in the org. Do not auto-apply.

Backlog items file to whatever devex / backlog tracker your team uses automatically. Only the Accepted list waits for approval.

For each approved Accepted item, follow the Routing field exactly:

- Trivial existing-skill edit (a one-line bullet, a tightened sentence, a stale fact corrected): parent does directly.
- Substantive existing-skill edit (a new section, a new pattern table, more than ~10 lines): hand to the `authoring-a-skill` playbook and run its draft / test / iterate loop.
- `tune description: <skill path>` (the skill exists but didn't trigger when it should have): hand to the `authoring-a-skill` playbook and run its description-optimization loop.
- `new skill via authoring-a-skill: <kebab-name>`: hand creation to the `authoring-a-skill` playbook. Do not invent the shape ad hoc.

If your environment ships a SKILL.md validator, run it on every touched skill before declaring done. Skip this step if it doesn't.

### 6. Summarize for the user

Short list, no preamble:

- Edits applied: `<skill path>`. What changed, one line each.
- New skills created: `<skill path>`. One line each (rare).
- Backlog filed to the devex tracker: `<issue title>` (`<tags>`). One line each.
- Dropped: one line per rejected finding + reason from the synthesizer.
