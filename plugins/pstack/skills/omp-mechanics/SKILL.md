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

These hold for every `task` spawn any pstack skill asks for. `references/task-wire-on-omp.md` holds
the item shape, the per-agent lever table, the isolation lifecycle, and the budgets.

- **No `model` field.** The `task` tool takes no per-call model. Four settings records in
  `~/.omp/agent/config.yml` carry model, service tier, prewalk, and advisor, all keyed by exact
  agent name, and a record entry beats the agent file's frontmatter. They are
  `task.agentModelOverrides`, whose value may be a `@role` alias the operator binds in
  `modelRoles`, `task.agentServiceTierOverrides`, `task.agentPrewalk`, and `task.agentAdvisor`. A
  role with no entry runs on the parent chat model, which is the correct default. A role that needs
  its own model needs its own thin agent file plus its own entry, so a four-arm model race is four
  agent files. `inherit-parent` and `auto` mean "leave this role out of the map".
- **No `readonly` field.** A read-only worker is posture carried in the brief, never a wire field.
  Name the tools the worker may use and forbid writes. The per-item `tools` field exposes only
  kernel tools the parent defined in an `eval` cell with `@tool` or `tool(fn, …)`, gated by
  `eval.tools.enabled`, so it is not a tool grant. The one per-spawn restriction omp enforces is
  `tools` in an agent's frontmatter, which binds to an agent definition and not to a task call, and
  even there omp keeps `hub` and adds `yield` regardless of what the list says.
- **One call, many items.** Every parallel spawn goes in one `task` call with all items in
  `tasks[]`. `context` is required and is rendered into every spawn's system prompt, so the shared
  contract goes there once instead of per item. `task.maxConcurrency` caps how many run at once.
  Eval holds the second fan-out primitive. `workpool()` queues items onto keep-alive workers and
  `agent()` returns a handle, both under the same cap, and a pool's name is its async job id, so
  poll it from outside the cell with `hub` `op: "wait"` and `ids: [pool.name]`. There is no
  `pool.wait()`. Unlike a task item, eval's `agent()` takes `apply` and `merge`.
- **`effort` is gated.** The per-spawn `effort` field is `"lo"`, `"med"`, or `"hi"`, it reaches the
  schema only while `task.enableEffort` is true, which is off by default, and `task.maxEffort` caps
  it. Check `omp config list | grep task.enableEffort` before a brief depends on it.
- **`isolated: true` is opt-in and gated.** It gives the worker its own worktree, and it reaches the
  tool only while `task.isolation.enabled` is true **and** plan mode is disabled, so check both
  (`omp config list | grep task.isolation`). Without the flag a worker shares the parent checkout,
  so switching branches there is not isolation. The parent must run from inside a git checkout. The
  worktree is a clone of the current checkout, uncommitted work included, not a checkout of `HEAD`.
  `task.isolation.apply`, default true, lands its changes automatically. Turn it off when the
  coordinator must review each patch first. When the gate is off, give each worker its own
  `git worktree` or its own `/tmp/<slug>/worker-<n>/` directory instead. Cursor's `environment` and
  cloud-base-branch arguments are rejected outright.
- **In plan mode a spawn can only read.** Every subagent is restricted to `read`, `grep`, `glob`,
  and `web_search`, and `isolated` and `tools` are rejected. A fan-out whose workers edit, or whose
  workers nest, runs outside plan mode.
- **A subagent starts blank.** No conversation history, and an isolated one cannot see its
  siblings. It does inherit the workspace tree, the skills, the context files, and the parent's
  `local://` root, so a large shared payload goes to `local://<name>.md` and the brief names that
  path. Otherwise inline what it needs or point at absolute paths.
- **Yield first.** End every brief with a yield-first line. Tell the worker to call the yield tool
  with its result as `data`, or a failure as `error`, both top-level arguments, and to write no text
  outside that call. Thinking models default to answering in prose and skipping the call, which
  costs three reminder prompts and then a `SYSTEM WARNING` with no structured output. Measured 13 of
  20 without the line, 20 of 20 with it, same model, same width. A reviewer that accumulates
  findings passes a non-empty `type` array to submit each as an incremental section, then a `type`
  string to finalize, which is what replaced the removed `report_finding` tool.
- **Budgets stop a long worker.** `task.softRequestBudget`, default 200 assistant requests, warns
  on crossing and force-stops the run at 1.5 times the budget. `task.maxRuntimeMs` is a hard
  per-spawn wall clock in milliseconds, 0 disabled. Brief a long worker to yield partial findings.
- **Reaching a running agent.** `hub` `op: "list"` and `op: "jobs"` are the read-only probes, and
  they cover this omp process's whole agent tree rather than one project. `op: "list"` returns
  running and idle peers plus counts, so parked archaeology needs `status: "parked"`. An `idle`
  agent parks after `task.agentIdleTtlMs`. A direct `op: "send"` revives a parked peer and a
  broadcast does not. An isolated agent ends parked with no reviver, so only its transcript
  survives. `op: "wait"` blocks, so never call it inside an agent that still owes its parent a
  turn. A finished agent's output artifact is at `agent://<id>`, a nested child's at
  `agent://<parent>/<child>`, one field at `agent://<id>?q=.<field>`, and the transcript at
  `history://<id>`. Job rows expire about five minutes after settling, and reading a settled one
  consumes its automatic delivery, so address the agent by id after that.
- **Proving a claim.** Run the check under `hub` `op: "start"`, wait on it with `op: "wait"` and a
  `name`, read the output with `op: "logs"`. That wait takes `timeout` in seconds. The message and
  job wait is the other one and takes `timeoutMs`. Supplying both `ready.log` and `ready.port`
  requires both to pass. Every pattern field here is a JavaScript regex compiled with `u`, so
  `(?i)` is rejected and `[Rr]eady` is the spelling. A readiness timeout leaves the process running
  and reports its state rather than killing it, so read the logs before calling it a fail. Nothing
  notifies the session when a supervised process exits. Non-zero exit is a fail.

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
- A retry can move a slot off the model its entry named, because `retry.fallbackChains` is keyed by
  the same role names and an aliased spawn inherits that role's chain instead of `default`. Record
  the model each arm actually ran on. `task.showResolvedModelBadge` prints it in the task widget.

## bug-fix

Amends step 2. Before reaching for runtime evidence, narrow the suspect set statically with `lsp`
action `definition` for where a value is set and `lsp` action `references` for every caller of a
suspect function. `task.enableLsp` is off by default, so a delegated worker has no `lsp` tool at
all and this narrowing is the parent's job unless that setting is on.

When program state is unclear the `debug` tool is the first instrument, ahead of bespoke logging.
With `debug.enabled` on, launch the reproducing path with action `launch`, drop a `set_breakpoint`
on the suspect line, drive it with `step_over` and `step_in`, and read exact state with `evaluate`.
Fall back to logging only when the tool is off or the runtime has no adapter.

## feature

Amends step 5. Run the typecheck and lint lane with `lsp` action `diagnostics` alongside the test
lane, and require the new code clean before the surface check. `file` set to `"*"` is not a
whole-workspace sweep. It runs one external checker for the first project type it matches, in the
order Rust, TypeScript, Go, Python, caps its output at the first 50 lines, and spawns nothing at all
for a project type it does not recognise. So name concrete files or a glob when the change spans
languages, and cap a glob at 20 files. A server failure is softened rather than fatal, so a clean
result means nothing was reported and not that nothing is wrong. Confirm a server is live with
action `status` before treating clean as proof. With `lsp.enabled` off, fall back to the project's
own typecheck and lint commands.

## refactoring

Amends step 5. A text rename silently misses callsites, so the language server is the guard and not
an eyeball spot-check. With `lsp.enabled` on, take the migrate-every-caller inventory from `lsp`
action `references` and apply each rename with action `rename`, which builds and applies a real
`WorkspaceEdit`. For a module move use action `rename_file`, which rewrites every import across
files. Both actions apply by default, so pass `apply: false` to preview one. Run action
`diagnostics` over the touched files afterwards, naming them rather than `"*"`. Then grep string
literals, prose, and back-references by hand, which a symbol rename never touches. With the tool
off, or in a worker spawned while `task.enableLsp` is false, a project-wide grep of the symbol name
is the whole guard.

## swarm

Amends steps 3 through 6. Every worker already runs on this machine. Read **Every task call** for
the `isolated: true` gate, the per-worker output fallback, and the yield-first line, all of which
this skill depends on.

For a long open-ended item stream, eval's `workpool()` beats a fixed `tasks[]` array. It queues
items onto keep-alive workers, `eval.workpool.freshAgents` opts into a new agent per item, and the
pool name doubles as the async job id you pass to `hub` `op: "wait"`. A fixed coverage matrix stays
one `task` call.

## multi-phase-plan

The plan template's read list points at the install path, `~/.omp/plugins/node_modules/pstack/`,
because the skill is installed here and not vendored in the product repo. One `git show
origin/main:` line stays in the list for docs the product repo vendors itself, which is also what
`scripts/check-plan.mjs` looks for.

For the control-surface line, the omp doc for that surface is the artifact to read, such as
`omp://tools/browser.md`. Read **Control surfaces** below before writing the line, because the
artifact describes an eval prelude and not a tool.

## orchestrate

`task.maxRecursionDepth` caps nesting and defaults to 2, so a wave of grandchildren needs that
raised first. An agent nests only when its own file declares `spawns`. A nested spawn carries the
full task schema, `isolated` included. Cap in-flight children at what one drain can process.
`task.maxConcurrency` is the hard ceiling, so a wave wider than that queues rather than running.

`hub` messaging reaches this omp process's agent tree and nothing outside it. `send`, `wait`, and
`inbox` are the sanctioned coordination primitives. `collab.autoStart` and `omp collab link` host a
session for a human to watch or drive, which is not an agent-to-agent channel and gives a
coordinator no way to reach another session's workers.

## Control surfaces

`browser` and `computer` are not tools and have no schema of their own. Since 18.1.9 both are
preludes inside the `eval` runtime, gated by `browser.enabled` and `computer.enabled`, so every
call is code in an `eval` cell, as in
`const tab = await browser.open({ name: "main", url }); await tab.close();`. Element handles come
from `tab.observe()` through `tab.id(n)` and from `tab.ariaSnapshot()` through `tab.ref("e5")`, and
a navigation invalidates both, so re-observe and act in the same cell. `computer` drives native
desktop the same way, through `computer.window(...)`, `win.ax()`, and element handles. Prefer the
accessibility tree over pixel coordinates, and never mix accessibility coordinates with screenshot
pixels.

omp freezes its own headless tabs when a turn settles (`browser.freezeOnTurnEnd`) and closes them
after `browser.idleCloseSec` idle seconds, so a login or any flow that must survive across turns
passes `persist: true` to `browser.open`. A prelude call emits no tool call and no tool result, so
a verification claim resting on one cites the cell's own output as its evidence.

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

All five read the session store. `references/session-store-on-omp.md` holds the layout. Four facts
decide whether a glob finds anything.

- The root is resolved, not fixed. It defaults to `~/.omp/agent/sessions/`, and a named profile,
  `PI_CODING_AGENT_DIR`, or `XDG_DATA_HOME` can move it. Resolve it before globbing.
- The bucket is the canonicalized cwd with each `/` rewritten to `-`, which leaves a leading
  hyphen for a path under `$HOME`, so `~/Desktop/proj` is the directory `-Desktop-proj`. Stay
  inside your own bucket. Globbing sibling buckets reads private sessions from unrelated projects.
- A transcript's first line is a fixed-width `type:title` slot and not a message, and persisted
  roles are camelCase, so the spelling is `toolResult` rather than `tool_result`.
- For an agent in this process, skip the glob. Bare `history://` lists every agent with its status
  and its parent, `history://<id>:1-50` pages one transcript, and `agent://<id>` serves that
  agent's final output.

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
