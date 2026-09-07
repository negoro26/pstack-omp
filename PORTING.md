# pstack on omp, the port

## Upstream truth and the pinned baseline

The true upstream is **`cursor/plugins`, subdirectory `pstack`** (MIT). The pinned baseline for this
port is commit **`7314f72`** (`fix(pstack): shrink logo under 512KiB (#309)`, authored and committed
`2026-09-03T04:37:11Z`, plugin version `0.14.8`). The sync brief called that commit 2026-09-02;
`gh api repos/cursor/plugins/commits/7314f72 --jq '.commit.author.date'` returns
`2026-09-03T04:37:11Z`, so the later date is the one recorded here.

**`backnotprop/pstack` is a mirror and it is stale. Never use it as the parity baseline again.** This
port was originally built from that mirror at `18e0e90` (2026-08-19), which was two weeks behind
canonical. Diffing the mirror against `7314f72` shows 224 changed content lines, counted as
`diff -ru <mirror> <canonical> | grep -cE '^[+-][^+-]'`, so header, hunk, context, and blank lines
do not count, plus three structural changes, so every parity claim made against the mirror inherited
the staleness. This checkout's git
`origin` is still `https://github.com/backnotprop/pstack.git` with branches `main` and `omp-port`, so
`git pull origin main` here pulls the mirror, not the truth. Fetch canonical from the monorepo
instead.

### Drift check (one command, run it verbatim)

```bash
gh api repos/cursor/plugins/compare/7314f72...main --jq '.files[]? | select(.filename|startswith("pstack/")) | "\(.status)\t\(.filename)"'
```

Empty output means no drift since the pinned baseline. Any line is a canonical change to port
forward, prefixed by its status (`modified`, `added`, `removed`, `renamed`).

Run at this sync, output empty. Proof the command detects real drift, same command against the
previous pstack commit `efa2a53`:

```
modified	pstack/.cursor-plugin/plugin.json
modified	pstack/assets/logo.png
```

### How to re-sync

1. Run the drift command above. Empty output means there is nothing to do.
2. Clone canonical and keep the old baseline as the merge ancestor.
   `git clone --depth 1 https://github.com/cursor/plugins /tmp/cursor-plugins`
3. For each file the drift command listed, three-way it. Ancestor is the pinned baseline's content,
   theirs is `/tmp/cursor-plugins/pstack/<path>`, ours is `~/.omp/pstack/<path>`. Take theirs as the
   content baseline, then re-apply the substitution table below to any text that arrived or changed.
4. Check the result with `diff -u /tmp/cursor-plugins/pstack/<path> ~/.omp/pstack/<path>`. Every
   remaining line must be an intended omp substitution. Anything else is a porting mistake.
5. Update the pinned commit, its date, and the drift command in this file. The command hardcodes the
   baseline, so a stale pin silently reports drift that was already ported.

Never substitute the `backnotprop/pstack` mirror for step 2.

## Structural changes in the `18e0e90` to `7314f72` sync

- **Added** `skills/make-bot-ui/` (webhook-driven Grok Bot UI skill). Listed in the README skill
  table and installed as a skill here.
- **Deleted** `skills/poteto-mode/references/plan.md`. Canonical replaced the prose reference with an
  executable checker, `skills/poteto-mode/scripts/check-plan.mjs`. Both moves are reflected on disk
  in this port.
- **Added** `assets/logo.png` plus a `"logo": "assets/logo.png"` field in `.cursor-plugin/plugin.json`.
  The 353 KiB PNG is **not carried**. It is a Cursor marketplace image with no omp consumer, nothing
  in omp reads it, and no skill or doc links it. The manifest field is kept so `.cursor-plugin/plugin.json`
  stays byte-identical to canonical and future drift diffs show only real changes. The consequence is
  one unresolved relative path inside a file nothing on this machine parses.
- Canonical also moved Shipping and Autopilot-stack off Graphite merge-when-ready to landing one PR at
  a time "through GitHub by default or Origin when its CLI is available". That wording is ported into
  `docs/guide/06-verify-and-ship.md`, `docs/guide/07-overnight.md`, and the README playbook table.

`.cursor-plugin/plugin.json` is kept for upstream fidelity only. omp never reads it. The install is
symlinks into omp's own discovery roots, and `omp plugin link` is unusable here because it requires a
`package.json`. Editing the manifest changes no runtime behavior on this machine.

## Install (verified live)

Two shapes. The marketplace is the one the README documents. The symlink tree is the original
port and still works.

### Marketplace

```
/marketplace add negoro26/pstack-omp
/marketplace install pstack@pstack-omp
```

That caches the plugin at `~/.omp/plugins/cache/plugins/pstack-omp___pstack___<version>` and links
it at `~/.omp/plugins/node_modules/pstack`. Verified on omp 18.1.13, 2026-09-07. The 45 skills
load, `fan-out` and `setup-pstack` enter the `<skills>` block and the rest hide, and the
`potetomode` extension loads from `package.json` `omp.extensions`, so `--poteto` injects the
reminder in `-p` mode.

The agents do not load. omp scans a marketplace plugin's `agents/` directory only through the
`claude-plugins` discovery provider, which is off by default (`enabledProviders: []`). Turning it
on put `poteto-agent` and `Comment Sicko` on the roster and also loaded every Claude Code plugin
cached under `~/.claude/plugins`, about thirty skill descriptions per turn on the machine that
measured it. The install therefore adds two symlinks into omp's native user root:

```
~/.omp/agent/agents/poteto-agent.md  -> ../../plugins/node_modules/pstack/agents/poteto-agent.md
~/.omp/agent/agents/comment-sicko.md -> ../../plugins/node_modules/pstack/agents/comment-sicko.md
```

Relative through `node_modules/pstack`, so `/marketplace upgrade` retargets them. Verified after
linking: both names on the `task` roster in a fresh `omp -p --no-session` session, and
`task agent="poteto-agent"` spawned and returned its one-word reply. If a later omp scans
marketplace `agents/` natively, the two links become duplicates of the same name and first-wins
dedup keeps the native-root copy, so they are harmless to leave and safe to delete.

### Symlink tree

```
~/.omp/agent/skills/<name>    -> ~/.omp/pstack/skills/<name>     # 45 symlinks
~/.omp/agent/agents/<name>.md -> ~/.omp/pstack/agents/<name>.md  #  2 symlinks
```

Counted at this sync, 45 skill directories under `skills/` and 45 matching symlinks in
`~/.omp/agent/skills/`, plus 2 agent symlinks. The count rose from 44 because canonical `7314f72`
added `make-bot-ui`.

Those are omp's own discovery roots, `<dir>/.omp/skills/` walking up ancestors, then user-level
`~/.omp/agent/skills/`. There is no `~/.omp/skills/`. Verified earlier in the port,
`skill://poteto-mode`, `skill://swarm` and `skill://create-verification-skill` resolve with no
`--plugin-dir`, and `task agent="poteto-agent"` spawns. Symlinks mean a re-sync updates every skill
in place.

Context cost stays low. Most skills set `disable-model-invocation: true`, which omp maps to
`hide: true`, so only a handful enter the prompt and the rest are read on demand.

Not ported, and inert on omp, `automations/benny`, which is Cursor Automations plus Bugbot wiring.

Treat the port as prose mirrored and mechanics substituted, not as the shipped Cursor plugin
installed.

## Substitution rules applied

Re-apply every row to any text that arrives from canonical on a re-sync. The rules are the rule set,
not a census. Occurrence counts are deliberately absent because they were measured against the stale
mirror and go stale again at each sync.

| Cursor mechanic | omp mechanic |
|---|---|
| `.cursor/skills/`, `~/.cursor/skills/` | `.omp/skills/`, `~/.omp/agent/skills/` |
| `subagent_type: X` | `` `agent`: X `` (the task tool's field) |
| `generalPurpose` | `task` (omp's bundled general-purpose agent) |
| `~/.cursor/rules/pstack-models.mdc` | `~/.omp/agent/models.yml` modelRoles, or `task.agentModelOverrides` |
| `/loop` (Cursor builtin) | omp ships its own `/loop` for in-session iteration. A `hub` supervised watcher or a systemd user timer covers an out-of-session wake. `hub` is an omp tool, never a Cursor feature |
| Cursor cloud agents, `environment: "cloud"` | `isolated: true` subagents, which run on this machine |
| `cloud_base_branch` | not accepted by omp's task tool. Use a `git worktree` on the wanted base |
| `agent-transcripts/`, `~/.cursor/projects/...` | `~/.omp/agent/sessions/<encoded-cwd>/*.jsonl`, subagents at `<session>/<AgentName>.jsonl` |
| `cursor-team-kit` `control-ui`/`control-cli`/`deslop` | `browser` and `computer` tools, `hub` plus bash, `skill://unslop` plus `omp cleanse` |
| `AskQuestion` (Cursor's ask tool) | `ask` (omp's tool name) |
| `is_background: true` (agent frontmatter) | removed, omp does not model it |
| poteto-mode frontmatter `name: Poteto Mode` | `name: poteto-mode` (kept, omp derives the registry slug from the frontmatter name) |

Known deltas the port mirrors faithfully and will not diverge on. The guide says the verification feature map lives at `references/features` while both trees write `features/`. The guide recommends a daily `/maintain-verification-skill` run while both trees state no cadence.

## The one thing that needed new code

omp ignores the skill frontmatter keys `mode:` and `reminder:`, which is how Cursor pins
`/poteto-mode` as a Custom Mode (`Opt+Enter`). That is reproduced natively in
`~/.omp/agent/extensions/potetomode/index.js` using the pattern proven by the installed `ponytail`
extension, `appendEntry` to persist, `session_start` plus `getBranch()` to restore,
`before_agent_start` to inject, and `registerCommand` for `/poteto-mode`.

The injected reminder is a pointer, not the playbook. It tells the agent to read
`skill://poteto-mode` on demand instead of inlining the whole SKILL.md every turn.

## What omp already does, so pstack's version is redundant

- **Worktree isolation.** `task.isolation.enabled` gates it. With it on, two concurrent
  `isolated: true` agents ran in `~/.omp/wt/t<id>/m`, the first patch applied to the main checkout and
  the second conflicted and was parked at `<session>/Beta.patch` rather than clobbering. Backends,
  `isolation.backend=auto` (btrfs/reflink/overlayfs COW), `merge=patch|branch`, `apply=true`. The
  anti-worktree argument about storage cost is about plain `git worktree` copies, and COW clones on
  this btrfs box do not carry it, so Cursor cloud agents are a bigger machine here rather than a
  missing capability.
- **The control CLI's driving surface.** `browser` (CDP, `tab.observe`/`screenshot`/`evaluate`),
  `computer` (native desktop plus a11y tree), `hub` (`op:start` with `ready:{log,port}` readiness),
  `debug` (full DAP, breakpoints, eval, stack). A generated `control-<app>` script only needs
  app-specific semantics, `doctor`, `new-session`, `seed`/auth, `feature-flag`, `wait-settle`.
- **`swarm` / `arena` / `interrogate`.** One `task` call with a `tasks[]` batch,
  `task.maxConcurrency=100`, `isolated: true` per candidate, `outputSchema` for judged verdicts.
- **Never-block.** Subagents run `approvalMode: yolo`, and `proofgate`'s `session_stop` veto is the
  enforced backstop.
- **Sibling coordination.** Same-session `hub` `send`, `wait`, and `inbox` ship in the harness and are the sanctioned primitive when workers must coordinate instead of running independent. Pstack never calls them yet. Cross-session messaging does not exist locally and gets no workaround here. It is tracked upstream and stays open.

## Still missing in omp

No scheduler. Nothing in omp's docs provides cron, timer, or routine, so an **out-of-session wake** is
the real gap. A systemd user timer plus `loginctl enable-linger` covers it. That plus a durable queue
(GitHub issues with `blocked-by:`) is all such a daemon should be. It must not manage worktrees,
patches, or conflicts, because omp already does.

## Next action

The verification skill is generated, not ported. Run `/create-verification-skill` inside a real repo,
which writes `<repo>/.omp/skills/verify-<app>/` (SKILL.md plus control script plus a `features/`
feature map), then `/maintain-verification-skill` on a schedule. Pick a repo with a runnable UI. A
React or Vite app with a dev server is the easiest first target.

## Switching the model `poteto-agent` runs on

`agents/poteto-agent.md` declares `model: "@poteto"`. That alias expands through `modelRoles` in
`~/.omp/agent/config.yml`, so one binding rebinds every `poteto-agent` spawn, including a 100-wide
fan-out. Precedence is `task.agentModelOverrides[poteto-agent]`, then this frontmatter alias, then
the parent's model.

Set the alias with `/model` or with `omp config set modelRoles '<full json>'`. A dotted key such as
`modelRoles.poteto` is rejected, so pass the whole record. `inherit-parent` is NOT a usable value
here; it resolves to `No model selected` and the spawn fails. Bind a real selector.

Bind it to your strongest judgment model for quality, or to a free local model for wide fan-out. Name
the selector `omp models` reports on your machine, never a slug from someone else's.

One finding worth carrying to any local thinking model. Under a small `max_tokens` budget a thinking
model can spend the whole budget in its reasoning field and return empty content with
`finish_reason=length`, which makes wide fan-outs unreliable. An OpenAI-compatible proxy in front of
the endpoint can expose a second model id that sets `chat_template_kwargs.enable_thinking` to false.
Same weights, thinking template off. Measured on one such deployment with the same prompt shape:
9/12 with thinking, then 24/24 and 40/40 without. Bind the fan-out alias to that id and keep the
thinking id for judgment work.

## Honest limitations, still open

- **Graphite is not installed.** `command -v gt` finds nothing on this machine, so every `gt` stack
  step in Shipping, Babysit, Autopilot-stack and Orchestrate is unexecutable as written. `gh` is
  installed and authenticated, so single-PR flows work. Canonical `7314f72` reduces the exposure by
  landing through GitHub by default, but the stacking commands still name `gt`.
- **`isolated: true` is opt-in per spawn, and the gate is open.** `task.isolation.enabled` is `true` in `~/.omp/agent/config.yml`, so the field reaches the task tool instead of being stripped. Two facts verified live. Absent the flag a worker shares the parent checkout, so each swarm brief must request it. And the parent must run from inside a git checkout, since isolated preparation builds a worktree from it. Outside a repo the spawn fails fast with a clear error rather than silently sharing. omp's task tool also rejects `environment`, `cloud_base_branch`, and a per-spawn `model`. Per-spawn model choice is only `task.agentModelOverrides`, keyed by agent name.
- **The agents have no marketplace path.** The skills and the extension install through the
  marketplace; `disable-model-invocation: true` maps to `hide` and the extra frontmatter keys
  (`mode`, `reminder`, `icon`, `color`) are ignored without error. The `agents/` directory is the
  one surface the marketplace install does not reach without the `claude-plugins` provider, hence
  the two agent symlinks in the Install section. Nothing needs fixing in the agent files. The install
  shape is the fix.
- **The extension is the pin mechanism until a probe says otherwise.** Never read this off a version
  number, because the binary updates often. Probe it:

  ```
  grep -c -a -F 'Pin or unpin a mode skill' "$(command -v omp)"
  ```

  Zero means omp has no native `mode:` or `reminder:` handling and
  `~/.omp/agent/extensions/potetomode/index.js` is what pins the mode. Nonzero means omp ships it
  natively, both injectors will fire and collide, and the extension should be deleted or gated at
  that point. The same rule applies to every capability in this document. State the probe, not the
  version.
