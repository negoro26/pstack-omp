---
name: reflect
description: Spawn three parallel review subagents over the active transcript, surface learnings, and route each to a concrete edit on an existing skill. Use when the user says reflect.
disable-model-invocation: true
---

# Reflect

Mine the current conversation for durable learnings, then route them into skill edits.

## When to invoke

- The user said "reflect" or "/reflect".
- A complex task (5+ tool calls) just landed cleanly and the recipe is worth keeping.
- The agent hit dead ends, found the working path, and the path generalizes.
- The user corrected the agent's approach mid-task.
- A non-trivial workflow emerged that isn't captured anywhere.

Skip when the conversation is trivial, off-topic, or already covered by an existing skill the parent followed correctly. One-offs are not learnings.

## Process

### 1. Locate the active transcript

The parent finds its own transcript file before fanning out. The system prompt names the session transcript tree `~/.omp/agent/sessions/<encoded-cwd>/*.jsonl` (subagents: `<session>/<AgentName>.jsonl`); use that path. Do not glob across sibling `~/.omp/agent/sessions/<other-cwd>/` buckets. That crosses workspace boundaries and reads private chats from unrelated projects.

```bash
ls -t ~/.omp/agent/sessions/<encoded-cwd>/*.jsonl ~/.omp/agent/sessions/<encoded-cwd>/*/*.jsonl ~/.omp/agent/sessions/<encoded-cwd>/*/subagents/*.jsonl 2>/dev/null | head -10
```

One transcript layout: flat `<ISO-timestamp>_<uuid>.jsonl` per session in the bucket, with `<AgentName>.jsonl` subagent sidecars under the matching `<ISO-timestamp>_<uuid>/` directory.

The first line of a real transcript is a `type:title` object, not a message. For each candidate, scan for the first `type:message` line with `role:user` and check that its text contains the conversation's opening user prompt. Take the matching path. If no path resolves, take the newest file in the bucket. If the bucket is empty, write a tight digest of the session and pass that instead.

### 2. Spawn three reviewers in parallel

One message, three `Task` calls, `agent`: `task` (omp's general-purpose bundled agent), each lens pinned by its own agent name, full tools per spawn. Reviewers need MCP access for context lookups (tickets, chat threads, observability traces referenced in the transcript), and the task wire has no `readonly` field to strip it. The prompt forbids file writes, which omp cannot enforce. The parent applies edits.

| Lens | Model | Prompt template |
|---|---|---|
| Judgment | your configured reflect-judgment model, defaulting to your strongest judgment model | `references/judgment-reviewer.md` |
| Tooling | your configured reflect-tooling model, defaulting to your strongest instruction-following model | `references/tooling-reviewer.md` |
| Divergent | your configured reflect-divergent model, defaulting to your prose model | `references/divergent-reviewer.md` |

Run the three lenses on three different model families where `omp models` offers them, and keep Divergent on a different model family from Judgment in particular. The Divergent lens earns its name from a different set of priors, not from a different prompt. When only one family is available, run all three lenses anyway and say in the summary that the divergent read is weaker for it. Each lens takes its family from a `task.agentModelOverrides` entry keyed by its agent name; a lens with no entry runs on the parent chat model. The **setup-pstack** skill owns the configuration.

Pass each template verbatim, substituting the transcript path or digest where marked. Reviewers return findings in the `Task` response body.

### 3. Synthesize

One `Task` call, `agent`: `task` (omp's general-purpose bundled agent), using your configured reflect-synthesizer model, defaulting to your strongest judgment model, full tools per spawn. The synthesizer's quality check includes spot-verifying citations, which can require MCP access, and the task wire has no `readonly` field to strip it. Use `references/synthesizer.md` verbatim, with each reviewer's full output inlined where marked. The synthesizer returns a structured Accepted / Rejected / Backlog list.

### 4. Structural enforcement check

Sanity-check the synthesizer's Accepted list. For any item that would be enforced more reliably by a lint rule, script, metadata flag, or runtime check, move it from Accepted to Backlog. The synthesizer already applies this criterion; this is a final pass before edits land. See the **encode-lessons-in-structure** principle skill.

### 5. Apply

Before applying any Accepted edit, present the synthesizer's full Accepted/Rejected/Backlog output to the user and wait for explicit approval. The user picks which subset to apply and may redirect routings. Skill changes affect every future agent in the org; do not auto-apply.

Backlog items file to whatever devex / backlog tracker your team uses automatically. Those are tracker submissions, not skill edits. Only the Accepted list waits for approval.

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
