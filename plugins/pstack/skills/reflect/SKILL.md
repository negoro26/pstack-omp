---
name: reflect
description: Spawn three parallel review subagents over the active transcript, surface learnings, and route each to a concrete edit on an existing skill. Use when the user says reflect.
disable-model-invocation: true
---

# Reflect

Mine the current conversation for durable learnings, then route them into skill edits.

Invoke when the user says "reflect" or "/reflect". Skip when the conversation is trivial, off-topic, or already covered by an existing skill the parent followed correctly. One-offs are not learnings.

## 1. Locate the active transcript

Before fanning out, read `skill://omp-mechanics/references/session-store-on-omp.md`. Prefer `history://<id>` for an agent registered in this process. Resolve this conversation's transcript directory using that reference. An explicit session-directory override is already the transcript directory; otherwise select the canonical-cwd bucket under the selected profile root. Search only that directory, never unrelated workspace chats.

```text
Use glob on <resolved-transcript-directory>/*.jsonl and the selected session's <session-stem>/**/*.jsonl sidecars. Resolve placeholders first, then inspect candidates with read.
```

OMP stores flat `<timestamp>_<session-id>.jsonl` root sessions and `<session-stem>/<AgentId>.jsonl` child sidecars; nested child directories carry full dotted IDs. A current file starts with a fixed-width `type:title` slot, then a `type:session` header. Legacy files may start at the header. Neither is a user message. Match the opening user prompt against the first `type:message` entry whose `message.role` is `user`, reading its `message.content` text. If no candidate matches, pass a tight digest of this session instead. When a transcript has `reset_boundary` entries, review only the active context after the latest boundary unless the user explicitly asks to review earlier history.

## 2. Spawn three reviewers in parallel

Start the three lenses in one `task` call with three items in `tasks[]` and the required shared `context`. Resolve exact discovered judgment, tooling, and divergent agents; omit `agent` for the default worker with the corresponding lens brief when a specialist is absent. Keep independent contexts. Prefer different configured model families, especially for Divergent versus Judgment, only when the roster supplies them; report weaker diversity otherwise. Reviewers may use inherited MCP tools for read-only citation checks. The brief forbids mutations; there is no task `readonly` field.

Resolve exact discovered agent names for the three lenses and the synthesizer. Each agent's frontmatter or `task.agentModelOverrides[<exact-name>]` selects the model; the task item has no `model` field. Use the reasoning and speed already selected by agent frontmatter or exact `task.agentModelOverrides` entries. Do not change operator configuration to satisfy a skill example.

| Lens | Exact agent | Prompt template |
|---|---|---|
| Judgment | discovered judgment agent | `references/judgment-reviewer.md` |
| Tooling | discovered tooling agent | `references/tooling-reviewer.md` |
| Divergent | discovered divergent agent | `references/divergent-reviewer.md` |

Pass each template verbatim, substituting the transcript path or digest where marked. Reviewers return findings in the spawn result's structured `data`, or in the delivered report when no schema was requested.

## 3. Synthesize

Start the synthesizer in one `task` call with one item in `tasks[]` and the required shared `context`. Use an exact discovered synthesizer, or omit `agent` for the default worker with the synthesizer brief. Agent frontmatter or `task.agentModelOverrides[<exact-name>]` selects the model. Pass `references/synthesizer.md` verbatim, with each reviewer's full output inlined where marked. Permit read-only MCP citation checks and forbid mutations in the brief. It returns an Accepted / Rejected / Backlog list.

## 4. Structural enforcement check

Move any Accepted item that a lint rule, script, metadata flag, or runtime check would enforce more reliably to Backlog. See the **encode-lessons-in-structure** principle skill.

## 5. Apply

Present the synthesizer's full Accepted / Rejected / Backlog output and wait for explicit approval before applying any Accepted edit. The user picks the subset and may redirect routings. Skill changes affect every future agent in the org. Do not auto-apply.

File each Backlog item to your team's devex or backlog tracker without waiting. Only the Accepted list waits for approval.

Never edit a skill under `plugins/cache/`. Before approval, show its destination, `.omp/skills/<skill>/` or `~/.omp/agent/skills/<skill>/`. After approval, copy the skill folder there and edit the copy. Never open a PR or push.

Follow each approved row's Routing exactly:

- Trivial existing-skill edit (a one-line bullet, a tightened sentence, a stale fact corrected): the parent does it directly.
- Substantive existing-skill edit (a new section, a new pattern table, more than ~10 lines): hand to the `authoring-a-skill` playbook and run its draft / test / iterate loop.
- `tune description: <skill path>` (the skill exists but didn't trigger when it should have): hand to the `authoring-a-skill` playbook and run its description-optimization loop.
- `new skill via authoring-a-skill: <kebab-name>`: hand creation to the `authoring-a-skill` playbook. Do not invent the shape ad hoc.

If your environment ships a SKILL.md validator, run it on every touched skill before declaring done.

## 6. Summarize for the user

Short list, no preamble:

- Edits applied: `<skill path>`. What changed, one line each.
- New skills created: `<skill path>`. One line each (rare).
- Backlog filed to the devex tracker: `<issue title>` (`<tags>`). One line each.
- Dropped: one line per rejected finding + reason from the synthesizer.
