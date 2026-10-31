# pstack-omp verification map

This directory is the maintained source for verifying what users of pstack-omp can observe. Read the index before driving, then use the matching feature file as the recipe. `../SKILL.md` owns launch, doctor, evidence, and cleanup.

## Baseline preconditions

- Commands run from the repository root with `C=.omp/skills/verify-pstack-omp/scripts/control-pstack` and `P=.omp/skills/verify-pstack-omp/prompts`.
- Plugin features need a fresh `$C launch <run>`, and `$C doctor <run>` must print no `FAIL`.
- Port features need no launch. They need `gh` logged in for upstream reads and the upstream clone at `CANON` (default `/tmp/cursor-plugins`).
- Every drive uses its own run id. Never drive an omp this run did not launch.

## Driving conventions

- Type prompts that name a forge mutation with `$C type-file`, never inline. The driver's own pstackpolicy refuses an inline one.
- Wait on visible text with `$C wait`, not on a fixed sleep. The pane strings each recipe names are stable output of the plugin or omp.
- Assert on model requests whose `tools` list is non-empty. Requests with an empty list are background skill-description compression.
- Run anything that rewrites `plugins/pstack` inside `$C clone <run>`, never in the checkout.
- Run `$C cleanup <run>` after every drive, failed ones included. It keeps the evidence.

## Proof and skip reporting

- Capture the user action and the resulting state with `$C capture <run> <name>`, not only the final screen.
- A refusal proof pairs an empty `<name>.gh-calls.log` with a control capture in which the same launch reaches the `gh` shim.
- Port proof includes the command, stdout and stderr, the exit code, and `git status --porcelain` before and after.
- Record the feature file and sub-feature ID in the capture name, for example `landing-gate.gate-refuse-bash`.
- Report an unreachable path with the attempted command and the unmet precondition.
- Do not report a skipped entry point as verified through a different path.

## Feature entry contract

Each feature file starts with an H1 title and one paragraph describing the user-visible behavior. It then uses exactly four H2 sections in this order.

1. `Sub-features` lists short IDs with one line for each behavior.
2. `How to get to it (user POV)` lists every user entry point.
3. `Driving it with control-pstack` starts with `Preconditions:` and uses labeled bullets that pair each user action with an exact command and observable result.
4. `Gotchas` lists traps that can waste or invalidate a verification run.

Keep implementation details out of the map. Name only user paths, stable handles, required state, commands, and observable proof.

## Features

- [Skill commands](./skill-commands.md) covers registration of every skill directory, `/skill:` autocomplete, and invoking a skill.
- [poteto-mode pin](./poteto-mode-pin.md) covers `/poteto-mode`, the status pill, the per-turn reminder, the `--poteto` flag, the shortcut, and `/new`.
- [Landing gate](./landing-gate.md) covers pstackpolicy refusing forge mutations from model-issued `bash` and `eval` calls, the allowed control, the grant, and the user's own `!` commands.
- [Port gate](./port-gate.md) covers `omp-port/check-port.sh` at the pin and against another upstream sha.
- [Upstream sync](./upstream-sync.md) covers `omp-port/sync-upstream.sh check`, `rebuild`, and a sync to a target sha.
