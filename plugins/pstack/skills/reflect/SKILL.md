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

One `task` call with three items in `tasks[]`, each `agent`: `task` (omp's general-purpose bundled agent) pinned by its own agent name, full tools per spawn. Run the three lenses on three different model families where `omp models` offers them, and keep Divergent on a different model family from Judgment, since the lens earns its name from different priors and not a different prompt. Reviewers need MCP access for context lookups (tickets, chat threads, observability traces referenced in the transcript). There is no such field on omp's task wire, so nothing strips MCPs.

| Lens | `model` | Prompt template |
|---|---|---|
| Judgment | your configured reflect-judgment model (default your strongest judgment model) | `references/judgment-reviewer.md` |
| Tooling | your configured reflect-tooling model (default your strongest instruction-following model) | `references/tooling-reviewer.md` |
| Divergent | your configured reflect-judgment model (default your strongest judgment model) | `references/divergent-reviewer.md` |

Pass each template verbatim, substituting the transcript path or digest where marked. Reviewers return findings in the `Task` response body.

### 3. Synthesize

One `Task` call, `agent`: `task` (omp's general-purpose bundled agent), using your configured reflect-judgment model (default your strongest judgment model), full tools per spawn. The synthesizer's quality check includes spot-verifying citations, which can require MCP access. There is no such field on omp's task wire, so nothing strips MCPs. Use `references/synthesizer.md` verbatim, with each reviewer's full output inlined where marked. The synthesizer returns a structured Accepted / Rejected / Backlog list.

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
