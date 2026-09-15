---
name: omp-mechanics
description: The omp-specific levers for every pstack skill. Read it after `skill://poteto-mode`, and again whenever a pstack skill or playbook tells you to spawn a subagent, pick a model, drive a surface, or wake yourself later. Every entry names the upstream step it amends and the omp instruction that replaces or extends it.
disable-model-invocation: true
---

# omp mechanics

pstack's skills are mirrored from Cursor and their mechanics are rewritten for omp by
`omp-port/rules.sed`. That rewrite is a token substitution, so anything omp does differently in
kind rather than in name lands here instead. Each section names a skill or playbook and amends a
numbered step.

This file is the port's only hand-written skill. Every other file under `skills/` and `agents/` is
built from upstream, so an omp instruction added there is deleted by the next sync.

## Every task call

These hold for every `task` spawn any pstack skill asks for.

- **No `model` field.** The `task` tool takes no per-call model. The only per-spawn lever is
  `task.agentModelOverrides` in `~/.omp/agent/config.yml`, keyed by agent name, and its value may
  be a capability alias the operator binds in `modelRoles`. Read the tool's schema before assuming
  a field. A role with no entry runs on the parent chat model, which is the correct default. A role
  that needs its own model needs its own thin agent file plus its own entry, so a four-arm model
  race is four agent files. `inherit-parent` and `auto` mean "leave this role out of the map".
- **No `readonly` field.** A read-only worker is posture carried in the brief, never a wire field.
  Name the tools the worker may use and forbid writes. The per-item `tools` field exposes only
  eval-defined kernel tools, so it is not a tool grant. The one per-spawn restriction omp enforces
  is `tools` in an agent's frontmatter, which binds to an agent definition and not to a task call.
- **One call, many items.** Every parallel spawn goes in one `task` call with all items in
  `tasks[]`. `task.maxConcurrency` in `~/.omp/agent/config.yml` caps how many run at once.
- **`isolated: true` is opt-in and gated.** It gives the worker its own worktree. It reaches the
  tool only while `task.isolation.enabled` is true, so check it (`omp config list | grep
  task.isolation.enabled`) before relying on it. Without the flag a worker shares the parent
  checkout, so switching branches there is not isolation. The parent must run from inside a git
  checkout, since isolated preparation builds a worktree from it. When the gate is off, give each
  worker its own `git worktree` or its own `/tmp/<slug>/worker-<n>/` directory instead.
  Cursor's `environment` and cloud-base-branch arguments are rejected outright.
- **A subagent starts blank.** No conversation history, and an isolated one cannot see your
  uncommitted files or its siblings. Inline what it needs or point at absolute paths.
- **Yield first.** End every brief with a yield-first line. Tell the worker to call the yield tool
  with its result as data and to write no text outside that call. Thinking models default to
  answering in prose and skipping the call, which the harness counts as failed even when the text
  is right. Measured 13 of 20 without the line, 20 of 20 with it, same model, same width.
- **Reaching a running agent.** `hub` `op: "list"` and `op: "jobs"` are the read-only probes.
  `op: "send"` wakes an idle or parked peer without restarting it. `op: "wait"` blocks, so never
  call it inside an agent that still owes its parent a turn. A finished agent's result is at
  `agent://<id>` and its transcript at `history://<id>`.
- **Proving a claim.** Run the check under `hub` `op: "start"`, wait on it with a timeout, read the
  output with `op: "logs"`. Timeout is a fail. Non-zero exit is a fail.

## architect, arena, interrogate, reflect

These four exist to get a different model's priors, so they need one agent file and one
`task.agentModelOverrides` entry per slot. Four runners is four agent files.

- Resolve the families at run time from what `omp models` reports. Give each slot a family that
  differs from the other slots and from the parent that wrote the code.
- When `omp models` reports one family, run the full slot count anyway and record in the verdict
  or synthesis note that the review is weaker for it. Never bind two slots to one family and call
  the result diverse, and never drop a slot to avoid writing the note.
- **arena** Phase C and **interrogate**: the judge's and reviewers' read-only grant is posture per
  **Every task call**, not a sandbox.
- **reflect** step 3: keep Divergent on a different family from Judgment. The lens earns its name
  from different priors, not a different prompt.
- **interrogate** step 2: Reviewer A with no override entry runs on the parent chat model, which is
  the case where the family spread collapses first.

## bug-fix

Amends step 2. Before reaching for runtime evidence, narrow the suspect set statically with `lsp`
action `definition` for where a value is set and `lsp` action `references` for every caller of a
suspect function.

When program state is unclear the `debug` tool is the first instrument, ahead of bespoke logging.
With `debug.enabled` on, launch the reproducing path with action `launch`, drop a `set_breakpoint`
on the suspect line, drive it with `step_over` and `step_in`, and read exact state with `evaluate`.
Fall back to logging only when the tool is off or the runtime has no adapter.

## feature

Amends step 5. Run the typecheck and lint lane with `lsp` action `diagnostics`, `file` set to `"*"`
for the whole workspace or to a concrete file or glob for a scoped check, alongside the test lane.
Require the new code clean before the surface check. With `lsp.enabled` off, fall back to the
project's own typecheck and lint commands.

## refactoring

Amends step 5. A text rename silently misses callsites, so the language server is the guard and not
an eyeball spot-check. With `lsp.enabled` on, take the migrate-every-caller inventory from `lsp`
action `references` and apply each rename with action `rename`, which builds and applies a real
`WorkspaceEdit`. For a module move use action `rename_file`, which rewrites every import across
files. Run action `diagnostics` over the touched files afterwards. Then grep string literals,
prose, and back-references by hand, which a symbol rename never touches. With the tool off, a
project-wide grep of the symbol name is the whole guard.

## swarm

Amends steps 3 through 6. Every worker already runs on this machine. Read **Every task call** for
the `isolated: true` gate, the per-worker output fallback, and the yield-first line, all of which
this skill depends on.

## multi-phase-plan

The plan template's read list points at the install path, `~/.omp/plugins/node_modules/pstack/`,
because the skill is installed here and not vendored in the product repo. One `git show
origin/main:` line stays in the list for docs the product repo vendors itself, which is also what
`scripts/check-plan.mjs` looks for.

For the control-surface line, the omp tool doc is the artifact to read, such as
`omp://tools/browser.md`.

## orchestrate

Nesting works to depth 3 and a nested spawn carries the full task schema, `isolated` included. Cap
in-flight children at what one drain can process. `task.maxConcurrency` is the hard ceiling, so a
wave wider than that queues rather than running.

There is no cross-session messaging on omp. Same-session `hub` `send`, `wait`, and `inbox` are the
sanctioned coordination primitives and they reach siblings only.

## make-bot-ui

Half of this skill is a Grok Bot mechanic with no counterpart here. Read
`references/make-bot-ui-on-omp.md` before starting, and never stand up a webhook routine on omp.

## typescript-best-practices

omp carries `globs` as skill metadata and does not auto-attach a skill on a file match. Read
`skill://typescript-best-practices` yourself when you touch a `.ts` or `.tsx` file.

## setup-pstack

The file this skill writes is `~/.omp/agent/config.yml`, not a Cursor rule file. The example block
in step 5 is the role-to-capability table, not the file format. `references/setup-pstack-config.md`
holds the omp shape, the four capabilities, and the one-agent-file-per-slot rule.

`omp config get task.agentModelOverrides` prints the current map. `omp models` lists the machine's
models, and step 1 must group them by family and count the families, because the review roles are
defined by family difference.

A real slug belongs in `modelRoles` and nowhere else, so a provider rename touches one line in the
operator's config and no skill at all.

## recall, reflect, eval, session-pickup, show-me-your-work, automate-me

All five read the session store. One bucket per cwd at
`~/.omp/agent/sessions/<encoded-cwd>/`, encoded as the cwd with `$HOME` stripped and each `/`
rewritten as `-`. One flat `<ISO-timestamp>_<uuid>.jsonl` per session, with `<AgentName>.jsonl`
subagent sidecars under the matching `<ISO-timestamp>_<uuid>/` directory. Stay inside your own
bucket. Globbing sibling buckets reads private sessions from unrelated projects.

The first line of a transcript is a `type:title` object, not a message.

## Upstream text that does not apply here

These stay as upstream wrote them, because the port has nothing to substitute.

- **poteto-mode** routers and **babysit** step 0 warn against Cursor's built-in `babysit` skill.
  omp ships no such skill, so the warning is inert and the playbook is the only route anyway.
- **bugbot-triage** rates Bugbot, which is Cursor's hosted review product. On a repository without
  it, apply the rubric to whatever review bot posts on your PRs, omp's own `security-reviewer`
  included.
- **make-bot-ui** names `api2.cursor.sh` and the routine panel. Both are Grok Bot surfaces.
- **worktree-cleanup** step 6 lists `~/Library/Application Support/Cursor` among macOS reclaimers.
  There is no omp equivalent worth pruning, and the rest of that step is Xcode and package caches.
- **orchestrate** names Graphite (`gt`) for stack operations. `command -v gt` finds nothing on this
  machine, so every `gt` step is unexecutable as written and `gh` covers single-PR flows.
