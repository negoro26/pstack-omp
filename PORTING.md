# pstack on omp, the port

## Upstream truth and the pinned baseline

The true upstream is **`cursor/plugins`, subdirectory `pstack`** (MIT). This repository is the
source of truth for the omp port. The old generator flow that built the port from a local `pstack`
tree is retired, so the files here are the artifact.

The baseline is one file, `omp-port/UPSTREAM`, holding the full 40-hex sha of the upstream commit
the port is synced to. Nothing else records it. Every derived field is generated from that sha by
`omp-port/sync-upstream.sh`, which writes the plugin version into `plugins/pstack/package.json` and
`.omp-plugin/marketplace.json` and regenerates the `pstack` catalog description from the live skill,
playbook, and principle counts.

**`backnotprop/pstack` is a mirror and it is stale. Never use it as the parity baseline again.**
This port was originally built from that mirror at `18e0e90` (2026-08-19), which was two weeks
behind canonical. Diffing the mirror against the then-current canonical commit shows 224 changed
content lines, counted as `diff -ru <mirror> <canonical> | grep -cE '^[+-][^+-]'`, so header, hunk,
context, and blank lines do not count, plus three structural changes. Every parity claim made
against the mirror inherited the staleness.

### Drift check

```bash
bash omp-port/sync-upstream.sh check
```

Empty output and exit 0 mean no drift since the pin. Each line is an upstream commit that touched
`pstack/`, newest first, as short sha then date then subject. The resolved target is the newest
commit that touched `pstack/`, printed to stderr, and written to the file named by
`SYNC_TARGET_OUT` when that variable is set. The workflow reads it from there instead of resolving
the head a second time and getting a different answer.

### How to re-sync

The port is a build, not a maintained tree. `plugins/pstack/skills` and `plugins/pstack/agents` are
upstream text at the pinned sha with `omp-port/rules.sed` applied, then `omp-port/patches/*.patch`,
then the paths in `omp-port/owned.txt` carried across. A hand edit under either directory fails the
`reproducible` check, which rebuilds the pin and diffs it against the tree, and the next build
deletes it. Put the change in `rules.sed`, in a patch, or in an owned path instead.

The `upstream-sync` workflow does this daily. It runs `bash omp-port/check-port.sh` on `main` first,
so a red trunk stops the run rather than being merged over, then builds at the newest upstream
commit that touched `pstack/`, opens a PR carrying the sync and gate output in its body, and squash
merges it with `--delete-branch` when both passed. Squash merging is safe because
`omp-port/UPSTREAM`, not the branch history, carries the base for the next build. It skips the run
while any open PR still carries a `sync/upstream-` head.

A maintainer runs `bash omp-port/sync-upstream.sh [<target-sha>]` for the same build locally, target
defaulting to that newest commit, or `bash omp-port/sync-upstream.sh rebuild` to rebuild at the
current pin after editing `rules.sed`, `patches/`, or `owned.txt`. A target that never touched
`pstack/` is refused, because the next run has to find that sha again in the path-filtered history.
Then run `bash omp-port/check-port.sh` and commit.

There is nothing to resolve. The build never edits an upstream file in place, so upstream text and
port text cannot collide. A patch that no longer applies exits 1, and that or a gate FAIL leaves the
PR open for a human with both outputs in the body and the reason printed in the job log. The build
runs `patch --force`, so a patch that no longer applies also exits 1 when `sync-upstream.sh` prints
the build to a terminal. Plain `patch` stops there at `File to patch:` or `Assume -R?` and waits,
and `--batch` answers that second prompt yes and applies the hunk backwards.

### What catches upstream moving

`rules.sed` is a table of exact rewrites, and a `sed` rule whose left-hand side stops matching
changes nothing while still exiting 0. That is the one failure mode in this port that is silent by
construction, so the gate treats it as the thing to prove rather than as an absence of errors.

- `rule liveness` runs one marked build and counts the rules that fired nothing. Every `s`, `d`
  and `a` command carries its own marker, so an address is probed the same as a left side. Each
  dead rule then gets one cause, decided by running it on raw upstream with the same `sed` and the
  same `-E` the build uses:
  - `stale` changes nothing in raw upstream either, so it can never fire again.
  - `shadowed` has raw matches that the rules above it rewrite when those matches are fed through
    them alone. A duplicate lands here, and so does a narrower rule placed above a broader one.
  - `consumed` has raw matches the rules above leave alone, because they rewrite the sentence
    around them. These are the token nets under the whole-sentence rules, and they fire when a
    sentence rule misses. They need nothing.
  - `catch-all` is the model-slug catch-all, which the tiered slug rules starve by design.
- `target builds` is the only upstream assertion that runs the whole build rather than probing
  text. Every other one reads upstream directly, and none of them runs `omp-port/patches`, so
  without it an upstream commit that rewords a line a patch matches on passes the gate and the sync
  it clears cannot be applied. It is skipped when the target is the pin, because `reproducible` has
  already built exactly that tree.
- `rule staleness` fails a stale rule with no row in `omp-port/stale-exempt.tsv`, and a row whose
  rule is not stale. That second kind records a decision about a rule that matches upstream again,
  and it would keep the rule from being reviewed the next time it goes stale.
- `rule shadowing` fails a shadowed rule with no row in `omp-port/shadow-exempt.tsv`, and a row
  whose rule is not shadowed. Rule 228 at 4275556 sat behind rule 227, which rewrote the same token
  first, and shipped its translation dead.
- `swallow ledger` holds every rule with `.*` or `.+` to a row in `omp-port/swallow.tsv`. The row
  carries the sha256 of every raw upstream span the rule's own left side matches, and why dropping
  that text is right. A wildcard swallows whatever upstream writes inside its span, so at c742dd6
  rule 89 dropped a new clause about steering a running agent and rule 35 dropped six new sentences,
  with no rule changing. When the hash moves the check fails and prints the spans, as a diff against
  the pin when the target is not the pin. Read the new text, then narrow the rule or record the new
  hash.

A stale rule that upstream has outrun **fails** the gate. It is not a report, because the
consequence is a Cursor API reaching a generated skill while every other check stays green. The
fix is to correct the left-hand side against what upstream actually says now, or to record the rule
in `omp-port/stale-exempt.tsv` with a reason. All three ledgers are keyed on a literal fragment of
the rule and never on a line number, because a line number moves the moment anyone edits a rule
above it and a row that silently stops applying is worse than no row. `stale exemptions`, `shadow
exemptions` and `rule wildcards` fail a fragment that matches more than one rule or none, and an
ambiguous fragment counts for nothing. A `run_in_background: true` fragment once matched a swarm
Phase B sentence rule as well as the token rule it was written for, and kept that rule from failing
when it went stale.

The probe's own exit status is part of each assertion. A probe that cannot run reports failure,
not a clean result: an empty list from a failed build is not evidence that nothing is stale.

Three checks read `rules.sed` as data and need no clone, so they also run in the mutation harness.
Each is a shape that shipped once while every other check passed.

- `rule replacement &` fails a bare `&` in a replacement, which writes the whole match back in.
  Rule 512 at 73f30d9 quoted `git fetch && git reset` and spliced its sentence into
  `opening-a-pr.md` three times.
- `rule paren groups` fails a left side that wraps upstream's literal parentheses in an ERE group
  it never references, when the replacement adds `(` back. Three rules at 73f30d9 shipped `((`.
- `rule wildcards` fails a `.*` that is followed by more pattern in a left side with no `$`
  anchor, unless `swallow.tsv` has its row. Such a match ends at the last place that pattern occurs
  on the line. Rule 34 at 4275556 ended `(\b.*)?\.` and deleted two sentences after its own.

`omp-port/test-gate-mutations.sh` breaks one thing per case in a copy of the tree and the port
files and expects one named check to fail on it, with the violation line it should print. The cases
that need upstream text run the whole gate nested. One case runs the pin's build alone with its
output on a pseudo-terminal and a deadline, so a patch prompt that waits for an answer fails the
harness. The gate itself sends build output to a file, where patch takes the default answer.

`bash omp-port/check-port.sh [canonical-clone] [sha]` takes the sha to gate, defaulting to the pin.
The tree assertions follow the pin, because they are about the checked-in tree; the upstream
assertions follow the target, because they are about upstream text. That split is what makes an
upstream change reviewable *before* it is synced: `upstream-sync` runs the gate a second time
against the candidate sha, so a commit that outruns a rule stops the run with the rule named,
rather than landing and being noticed later in a generated file. The same command answers the
question locally:

```bash
bash omp-port/check-port.sh "" "$(gh api 'repos/cursor/plugins/commits?path=pstack&sha=main&per_page=1' --jq '.[0].sha')"
```

The gate runs as its own workflow, `gate.yml`, on every pull request and on every push to `main`. A
PR opened with `github.token` does not trigger `pull_request` workflows, so the sync PR carries the
gate output in its body and the `push` to `main` run after the merge is the backstop.

Never substitute the `backnotprop/pstack` mirror for upstream.

## Structural changes carried from earlier syncs

These landed in syncs before the current pin and are recorded because each one still constrains what
the port carries, not as a census of the tree. `omp-port/UPSTREAM` is the only current record.

Everything below `pstack/skills` and `pstack/agents` is outside this port. The build is one
`git archive` of exactly those two subtrees, so `.cursor-plugin/`, `docs/`, `assets/`, and
`automations/` are structurally absent rather than carried and edited.

- **Added** `skills/make-bot-ui/` (webhook-driven Grok Bot UI skill). Listed in the README skill
  table and installed as a skill here.
- **Deleted** `skills/poteto-mode/references/plan.md`. Canonical replaced the prose reference with an
  executable checker, `skills/poteto-mode/scripts/check-plan.mjs`. Both moves are reflected on disk
  in this port.
- **Not carried** `assets/logo.png` and its `"logo": "assets/logo.png"` field. They are a Cursor
  marketplace image with no omp consumer. An earlier tree vendored the manifest beside it so that
  future drift diffs would show only real changes; that ended when the build narrowed to the two
  subtrees it archives, so no dangling reference is left to fix here.
- Canonical also moved Shipping and Autopilot-stack off Graphite merge-when-ready to landing one PR
  at a time "through GitHub by default or Origin when its CLI is available". That wording reaches
  this port through the two playbooks themselves, not through `docs/guide/`, which the build does
  not extract.

`.cursor-plugin/plugin.json` is not vendored and never was in the current build: it sits outside the
two subtrees `omp-port/lib.sh` archives, and omp never read it. Nothing in the tree parses it.

`pstack/plugin.json`, upstream's Agent Plugins manifest, is not carried either. At the plugin root it
makes omp's `agent-plugins` provider claim the package, and that provider checks skill frontmatter
against a closed field set. It skipped every skill with `disable-model-invocation`, `icon`, `color`,
or `globs`, 54 of 56 at 0.15.25 on omp 18.12.2. Without it, the `omp-plugins` provider reads the
plugin root's `skills/` directory and loads all of them. The `plugin manifest` gate asserts the absence.

## Install, the two live shapes

`omp plugin link <checkout>/plugins/pstack` is the maintainer shape. It registers the checkout as an
omp extension root, so the skills load straight out of the working tree and a re-sync is live with no
relink. That is how this machine runs the port, `~/.omp/plugins/node_modules/pstack` being a symlink
to `plugins/pstack` in the checkout. The agents load from the same root. Verified 2026-09-09 on omp
18.1.13 with no agent symlinks present, a fresh `omp -p --no-session` roster listed `poteto-agent`
and `Comment Sicko` beside `task`. Re-run that probe (it is in `plugins/pstack/README.md`) after an
omp upgrade rather than trusting this line.

The marketplace install is the user shape.

```
/marketplace add negoro26/pstack-omp
/marketplace install pstack@pstack-omp
```

That caches the plugin at `~/.omp/plugins/cache/plugins/pstack-omp___pstack___<version>` and links
it at the same `~/.omp/plugins/node_modules/pstack` path. Verified on omp 18.1.13, 2026-09-07. The
skills load, `setup-pstack` is among them and the rest hide, and both extensions register from
`package.json` `omp.extensions`, so `--poteto` injects the reminder in `-p` mode.

The agents do not load from a marketplace root. omp scans a marketplace plugin's `agents/` directory
only through the `claude-plugins` discovery provider, which is off by default
(`enabledProviders: []`). Turning it on put `poteto-agent` and `Comment Sicko` on the roster and
also loaded every Claude Code plugin cached under `~/.claude/plugins`, about thirty skill
descriptions per turn on the machine that measured it. The install therefore adds two symlinks into
omp's native user root:

```
~/.omp/agent/agents/poteto-agent.md  -> ../../plugins/node_modules/pstack/agents/poteto-agent.md
~/.omp/agent/agents/comment-sicko.md -> ../../plugins/node_modules/pstack/agents/comment-sicko.md
```

Relative through `node_modules/pstack`, so `/marketplace upgrade` retargets them. Verified after
linking: both names on the `task` roster in a fresh `omp -p --no-session` session, and
`task agent="poteto-agent"` spawned and returned its one-word reply. If a later omp scans
marketplace `agents/` natively, the two links become duplicates of the same name and first-wins
dedup keeps the native-root copy, so they are harmless to leave and safe to delete.

Both shapes resolve to the same tree under `~/.omp/plugins/node_modules/pstack/`, which is the
install path the playbooks name. The retired `~/.omp/pstack` tree exists nowhere, and neither does
`~/.omp/skills`.

Context cost stays low. Most skills set `disable-model-invocation: true`, which omp maps to
`hide: true`, so only a handful enter the prompt and the rest are read on demand.

Not ported, and inert on omp, `automations/benny`, which is Cursor Automations plus Bugbot wiring.

Treat the port as prose mirrored and mechanics substituted, not as the shipped Cursor plugin
installed.

## Where the port's changes live

`omp-port/rules.sed` is the substitution table, one ordered `sed -E` rule per line, tiered rules for
the model slugs upstream names first and a catch-all under them whose hits the sync and the gate
report as `untiered` so they earn a tiered rule. `omp-port/patches/` carries the port's own code as
unified diffs applied after the rules, which is where a change no substitution can express belongs.
`omp-port/owned.txt` names three port-owned skills. `pstack-omp` is the sole live task, vibe, eval,
and runtime contract. `omp-mechanics` keeps only pstack-specific OMP deltas, and `setup-pstack`
owns model selection and config writes. Upstream syncs preserve these paths without rewriting them.

### A patch rewrites code, never prose

A unified diff matches on context lines, so a patch against upstream markdown is a bet that
upstream will not retype the paragraph around the change. Upstream reworks its skill prose
constantly: one commit inside a single sync window distilled 36 files. The patch this replaced was
98% prose by byte count, across 25 markdown files, which is why every daily sync failed on patch
application while `rules.sed` stayed clean.

The split is by kind, not by size.

- A token or a field name goes in `rules.sed`. `subagent_type`, `run_in_background`, `readonly`,
  and Cursor's per-project rule-file path are matched as tokens rather than as sentences, so an
  upstream reword cannot break them. This is what makes the layer durable: a rule that stops matching costs one
  line, a patch that stops matching costs a merge.
- Port prose goes in the owned skills, which `install_tree` restores from `HEAD` and which
  therefore cannot conflict with upstream at all.
- A patch is for code: control flow, a data shape, a file upstream does not have.
  `worktree-audit-omp.patch` and `zzz-script-typecheck.patch` are the port's own changes; the
  second typechecks `bootstrap.ts` as well as `watch-pr/`. `zzz-make-bot-ui-omp.patch` is the one
  markdown patch, a notice that the skill's webhook mechanic does not exist on omp. One `zzz*`
  patch carries an open upstream PR. `zzz-watch-pr-fixes.patch` carries #769. When upstream merges
  an equivalent, delete the hunks it covers rather than resolving them, and do not wait for the
  patch to fail first. A hunk that only adds lines can still find its context at an offset and
  apply a second time.

Author a patch against **post-rules** text. `rules.sed` runs first, so a hunk quoting the raw
upstream line fails whenever an earlier rule rewrote it. `worktree-audit-omp.patch` deletes a
comment line that the path rule has already rewritten, and its hunk quotes the rewritten form.

Two failure modes this caught, both silent until a sync ran. An owned path missing from
`owned.txt` is not owned: `install_tree` rebuilds `plugins/pstack/skills` from upstream and
restores only the listed paths, so dropping `skills/setup-pstack` shipped upstream's hardcoded
model slugs. And a gate check that greps for a literal goes stale when upstream changes shape:
upstream dropped the per-entry slug from its router index and documented the title-to-kebab rule in
the index preamble instead, so both parity checks read every entry as unnamed and failed against a
correct tree. They now derive the name the way the preamble tells the agent to.

The gate used to assert that port-authored prose sat *inside* upstream's playbooks, which is the
opposite of mirroring upstream and made every one of those assertions a rule that went stale. Those
checks are gone. What remains is residue detection: Cursor wire fields and tool names, Cursor's
transcript layout, model slugs, retired role keys, install paths, a claimed `hub` tool, an unscoped
`omp cleanse --all` recommended as a diagnostic, and build integrity.

`skills/setup-pstack` is port-owned, so the build restores it from `HEAD` and never rebuilds it from
upstream. Upstream's version writes a Cursor rules file with no omp meaning, so the fork is
deliberate, but the drift list alone does not mark it: an upstream edit to that skill shows up as an
ordinary pstack commit with no patch conflict and no reminder to re-derive it.
`bash omp-port/sync-upstream.sh check` therefore writes a `shadowed <path>:` line per owned path to
stderr, counting the upstream commits sitting ahead of the pin on that path. That count resets the
moment the pin moves past the commit, which is how ab1f702's edit to setup-pstack step 3(c) went
unread through the c742dd6 sync. So `omp-port/owned.txt` also records, per owned path, the upstream
object a maintainer last read against the owned copy, and `owned drift` fails when upstream's
object at the target differs. The failure prints both objects and the `git diff` that shows the
change. Carry what the owned copy needs, then record the new object. The two other owned paths have
no upstream counterpart and record `-`, so upstream adding one fails the same way.

`skills/setup-pstack/scripts/apply-models.mjs` makes the config write. `omp config set` stores a
selector the catalog does not have and an alias no role defines without complaint, so a bad value
used to surface only at spawn. The script checks every alias, effort, and agent value against
`omp models --json` and the merged `modelRoles` before its first write, preserves every entry pstack
does not own, and converges on a rerun. Its tests run in the gate against a stub `omp` on `PATH`,
and the `setup config contract` check asserts the skill still routes through it.

Known deltas the port mirrors faithfully and will not diverge on. The guide says the verification feature map lives at `references/features` while both trees write `features/`. The guide recommends a daily `/maintain-verification-skill` run while both trees state no cadence.

## The one thing that needed new code

omp ignores the skill frontmatter keys `mode:` and `reminder:`, which is how Cursor pins
`/poteto-mode` as a Custom Mode (`Opt+Enter`). That is reproduced natively in
`~/.omp/agent/extensions/potetomode/index.js` using the pattern proven by the installed `ponytail`
extension, `appendEntry` to persist, `session_start`, `session_switch`, `session_branch`, and
`session_tree` plus `getBranch()` to restore, `before_agent_start` to inject, and `registerCommand`
for `/poteto-mode`.

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
- **The control CLI's driving surface.** `browser` (CDP, `tab.observe`/`screenshot`/`evaluate`) and
  `computer` (native desktop plus a11y tree) are eval preludes, not tools. Long-running processes
  are a `bash` call with a unique `name`, a `ready` block, and `read proc://<name>` for state. The
  `name` selects supervised service mode and is incompatible with `async: true` or a supplied
  `timeout`; `async` is the other backgrounding path, for a finite command, and it hands back a job
  id read at `proc://<id>`. Two mechanisms, not two flags on one call.
  Agent Hub is a human-facing TUI, not a programmatic interface, so nothing addresses workers
  through it. `debug` is full DAP with breakpoints, eval, and stack. A generated `control-<app>`
  script only needs app-specific semantics, `doctor`, `new-session`, `seed`/auth, `feature-flag`,
  `wait-settle`.
- **`swarm` / `arena` / `interrogate`.** One `task` call with a `tasks[]` batch,
  `task.maxConcurrency=100`, `isolated: true` per candidate, `outputSchema` for judged verdicts.
- **Never-block.** Subagents run `approvalMode: yolo`, so a worker cannot stop to ask. **Nothing
  here vetoes a malformed subagent result.** The plugin ships two extensions, `potetomode` and
  `pstackpolicy`, and neither one registers a `session_stop`; `pstackpolicy` vetoes at `tool_call`
  and only for the forge mutations, so a result that is merely wrong still gets through. What
  pstack relies on for that is the root's own acceptance discipline: `skill://pstack-omp` requires
  the root to read each result and accept or reject it, and a `judge`/`verifier` role is the
  independent check on a worker's claim. That is the whole backstop for a malformed result. Landing
  is a separate gate and it is enforced in process rather than in prose; see
  [What omp can actually stop](#what-omp-can-actually-stop) below.
  Returning `{"decision":"block"}` from `session_stop` is the one native veto contract, and
  `~/.omp/agent/extensions/proofgate/` implements it, dormant unless `$OMP_PROOF_FILE` is set, so
  treat the veto as absent unless you have verified that variable yourself. Its own `VERDICT.md`
  prefers an external check over it and calls the case unmeasured, so treat it as a local
  experiment rather than the answer. This repository neither ships nor requires it.
- **Sibling coordination.** `write agent://<id>` steers or follows up with a running, idle, or parked
  worker, `agent://all` broadcasts to visible live peers, `read history://` lists registered agents
  with status and parent, `read proc://` lists background jobs and project services, and the `wait`
  tool blocks until the next settled job or peer message. These are the sanctioned primitives when
  workers must coordinate instead of running independent. There is no `hub` tool. Probe it rather
  than trusting this line: `grep -a -A40 'src/tools/builtin-names.ts' "$(readlink -f "$(command -v omp)")"`
  prints the binary's builtin tool list, which on 18.12.6 carries `wait` and no `hub`; the binary's
  only other `hub` is the `/hub` slash command that opens Agent Hub. An earlier tree read a `hub`
  tool with list/send/inbox/wait ops off a stale pi-coding-agent 17.x package, and the gate now
  fails any shipped sentence that names one. Cross-session messaging does not exist locally and
  gets no workaround here. It is tracked upstream and stays open.

## Still missing in omp

No scheduler. Nothing in omp's docs provides cron, timer, or routine, so an **out-of-session wake** is
the real gap. A systemd user timer plus `loginctl enable-linger` covers it. That plus a durable queue
(GitHub issues with `blocked-by:`) is all such a daemon should be. It must not manage worktrees,
patches, or conflicts, because omp already does.

## Next action

The verification skill is generated, not ported. Run `skill://create-verification-skill` inside a real repo,
which writes `<repo>/.omp/skills/verify-<app>/` (SKILL.md plus control script plus a `features/`
feature map), then `/maintain-verification-skill` on a schedule. Pick a repo with a runnable UI. A
React or Vite app with a dev server is the easiest first target.

## Switching the model `poteto-agent` runs on

The published `agents/poteto-agent.md` ships with no `model:` line and inherits the chat model. To
pin it, add `model: "@poteto"`. That alias expands through `modelRoles` in
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
  installed and authenticated, so single-PR flows work. Canonical now lands through GitHub by
  default, which reduces the exposure, but the stacking commands still name `gt`.
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

### What omp can actually stop

The playbooks say "stop where the human's call begins", and until recently that was advice with
nothing behind it. Three facts from `omp://approval-mode.md`, on omp 18.4.10, decide what an
instruction is worth here:

- `yolo` auto-approves the `read`, `write`, **and `exec`** tiers. A `gh pr merge` inside a bash
  call is an `exec` call, so it runs with no prompt.
- Subagents run headless with `tools.approvalMode: yolo`, and "the parent `task` approval is the
  authorization boundary". Every pstack owner is a subagent, so the boundary is the spawn, not the
  instruction.
- A call that resolves to `prompt` is **rejected** in a headless subagent, because there is no one
  to answer it. A backstop therefore has to *refuse*, not prompt.

bash's built-in critical-pattern list covers `rm -rf /`, fork bombs, remote-fetch-then-execute,
`/etc/passwd`, and host shutdown. **A merge is not on it.** So is not a force-push to trunk, a base
retarget, a PR close, or a review comment.

That is why the port now ships `plugins/pstack/extensions/pstackpolicy`, a second extension beside
the mode pin. It registers `tool_call` and refuses the forge mutations outright unless the operator
set `PSTACK_LANDING_GRANT=1`. The grant is an environment variable rather than a flag or a slash
command because a flag an agent can pass is not a grant a human made, and an agent cannot set its
own process environment. Refusals name the variable, so the operator is told exactly what to set.

A force push to a **feature** branch stays allowed: that is the port's own rebase flow, and blocking
it would fail every stack owner mid-rebase and make the extension unusable without a grant. A force
push that names a trunk ref is refused, which is the case the playbooks keep escalating.
