# The omp task wire

Amends **Every task call** in `SKILL.md`. Read this before a fan-out whose workers need their own
model, their own worktree, or a budget. Every fact below is one `omp config list`, `omp config get
<key> --json`, `omp://tools/task.md`, or `task` schema read away, so probe rather than trust this
file after an upgrade.

## The item shape

With `task.batch` on, which is the default, one call is `{ context, tasks: item[] }` and one item is
`{ name?, agent?, task, effort?, outputSchema?, schemaMode?, isolated?, tools? }`. There is no
`model`, no `readonly`, no `apply`, and no `merge` on an item.

`context` is required and non-empty, and it is rendered into every spawn's system prompt. Put the
shared contract there once instead of repeating it per item. Item names must be unique within a
call, compared case-insensitively.

With `task.batch` off the shape is flat, exactly one spawn per call, and `tasks` and `context` are
both rejected. Shared background then goes in a `local://` file that each spawn's `task` names.
Subagents share the parent's `local://` root, so that path resolves for them.

`effort` is `"lo" | "med" | "hi"`. It is present in the schema only while `task.enableEffort` is
true, which defaults to false, and it is clamped by `task.maxEffort`, which defaults to `max`. Check
`omp config list | grep task.enableEffort` before writing a brief that depends on it.

`tools` names kernel tools the parent defined in an `eval` cell with `@tool` in Python or
`tool(fn, …)` in JavaScript. It is gated by `eval.tools.enabled`, which defaults to true. Each call
runs inside the parent's kernel. An unknown name fails the call. It grants no harness tool.

## The per-agent levers

Four settings records in `~/.omp/agent/config.yml`, each keyed by the exact, case-sensitive agent
name. A record entry overrides the agent file's frontmatter.

- `task.agentModelOverrides` picks the model. A value may be a `@role` alias that expands through
  `modelRoles`, and a `modelRoles` value may carry an effort suffix, written
  `<selector>:<effort>`.
- `task.agentServiceTierOverrides` picks the provider service tier, one of `inherit`, `none`,
  `auto`, `default`, `flex`, `scale`, `priority`. It overrides `tier.subagent` and applies only
  where the resolved model's provider family supports the value.
- `task.agentPrewalk` arms prewalk, which starts the spawn on its resolved model and hands off to a
  cheaper one at the first edit or write. Values are `"on"`, `"off"`, or a model pattern.
  `task.prewalk` arms the same behaviour for the bundled `task` agent only.
- `task.agentAdvisor` pairs the spawn with an advisor model. Values are `"on"`, `"off"`, or a model
  pattern. Subagents run unadvised by default. The old global `advisor.subagents` is gone, and
  `omp config get advisor.subagents` answers `Unknown setting`.

A slot with no entry in any of these runs on the parent chat model with no tier override, no
prewalk, and no advisor. That is the correct default for most roles.

`retry.fallbackChains` is keyed by the same role names. A spawn reached through a `@role` alias
inherits that role's chain rather than the `default` chain, so a retry can move a review slot onto
a different model than the one its entry named. A panel that depends on family spread should record
the model each arm actually ran on, which `task.showResolvedModelBadge` displays in the task widget.

## Isolation

`isolated: true` appears in the schema only while `task.isolation.enabled` is true and plan mode is
disabled. Check both. The workspace is a clone of the current checkout produced by the backend
`isolation.backend` resolves, so the parent's uncommitted work is in the worker's starting state,
and the result is diffed against a baseline captured at spawn time.

- `task.isolation.apply`, default true, decides whether a successful run's changes land in the
  parent checkout. Turn it off to hold patch or branch artifacts for review first.
- `task.isolation.merge` is `patch` or `branch`. Branch mode commits to `omp/task/<id>` and
  cherry-picks. Patch mode writes `<id>.patch` and applies it only when it applies cleanly.
- `worktree.base` is the parent directory for isolation copies and `github` PR checkouts. Unset
  means `~/.omp/wt`. `OMP_WORKTREE_DIR` overrides it.

An isolated run ends `parked` with no reviver. It is not revivable and cannot take a follow-up
message. Only its `history://<id>` transcript survives. A non-isolated run ends `idle` with its
session attached and is revivable.

## Budgets and lifecycle

- `task.maxConcurrency` caps concurrent subagents. The default is 32 and 0 is unbounded. The
  semaphore is resized in place, so a mid-session change affects work already queued.
- `task.maxRecursionDepth`, default 2, caps nesting. At the cap the `task` tool is hidden from the
  child. An agent file needs `spawns` for its agent to nest at all.
- `task.softRequestBudget`, default 200 assistant requests, injects a wrap-up notice on crossing
  and force-stops the run at 1.5 times the budget so it yields partial findings. 0 disables it.
- `task.maxRuntimeMs` is a hard wall clock per spawn in milliseconds. 0 disables it. A timeout
  aborts the agent terminally.
- `task.agentIdleTtlMs`, default 420000, is how long an `idle` agent stays in memory before parking
  to disk. `hub` `op: "send"` revives a parked agent. `Main` is never parked.
- `task.enableLsp`, default false, decides whether a spawn gets the `lsp` tool at all.
- `task.eager` is `default`, `preferred`, or `always`, and sets how hard the harness pushes work
  toward subagents. An agent file's `blocking: true` makes its item run inline instead of in the
  background, and no bundled agent declares it.

## Plan mode

While a plan is being written, a spawn is restricted to `read`, `grep`, `glob`, and `web_search`,
its `spawns` and `prewalk` are cleared, and `isolated` and `tools` are rejected. A pstack fan-out
that needs workers to edit or to nest must run outside plan mode.
