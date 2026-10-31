# Port gate

`omp-port/check-port.sh` is the gate the port passes before any release. At the pin it checks the plugin tree's contracts, runs the fixture mutation and worktree-audit suites, and rebuilds the pin to prove the tree is reproducible. Pointed at another upstream sha, it also asks whether the port's rules and patches still apply to text nobody has ported yet.

## Sub-features

- `gate-pin` passes at the pin with one `PASS`, `SKIP`, or `REPORT` line per check and a final `check-port: PASS`.
- `gate-target` builds and lints against a target sha and fails `target builds` or `rule staleness` when the port has fallen behind.
- `gate-readonly` leaves the checkout unchanged in both modes.

## How to get to it (user POV)

- Run `bash omp-port/check-port.sh` from the repository root.
- Run `bash omp-port/check-port.sh "" <target-sha>` to gate a sha other than the pin. The empty first argument keeps `CANON` from the environment.
- CI runs it as the `Port gate` step of `.github/workflows/gate.yml` on every PR, and `upstream-sync.yml` runs it at the pin and at the target.

## Driving it with control-pstack

Preconditions:

- `CANON` names an upstream clone, default `/tmp/cursor-plugins`, holding the pin and any target sha. Without it the gate clones upstream over the network.
- `omp` is on PATH, so the worktree-audit suite runs its live probe instead of printing SKIPPED.
- `E=$($C evidence port-<n>)` holds the evidence dir.

- **Gate at the pin.** Run `git status --porcelain >"$E/status-before.txt"`, then `setsid -w bash omp-port/check-port.sh >"$E/check-port.txt" 2>&1; echo "exit=$?" >>"$E/check-port.txt"`, then `git status --porcelain >"$E/status-after.txt"`. The log ends `check-port: PASS` and `exit=0`. `grep -E '^(reproducible|gate mutations|counts) +PASS' "$E/check-port.txt"` prints three lines, naming the pin, the rejected fixture mutations, and the skill, playbook, and principle counts. `diff "$E/status-before.txt" "$E/status-after.txt"` prints nothing. It took 67s on this host.
- **Gate a target.** Run `setsid -w bash omp-port/check-port.sh "" <target-sha> >"$E/check-port-target.txt" 2>&1; echo "exit=$?" >>"$E/check-port-target.txt"` and diff the status again. A port that still builds there ends `check-port: PASS`. A port that has fallen behind matches `grep -E '^(target builds|rule staleness) +FAIL'` with indented reasons below, ends `check-port: FAIL` and `exit=1`, and still leaves the status unchanged. Main at pin `519d36a` gated against `c742dd6` failed both checks in 90s.
- **Read the reports.** `REPORT` lines, such as `owned drift` and `rule liveness`, inform the maintainer and never fail the gate. Do not count them as failures or passes.
- **Clean up.** Run `$C cleanup port-<n>`. It removes nothing from the checkout and keeps `$E`.

## Gotchas

- The target build applies `omp-port/patches/` with `patch`, which asks `File to patch:` on the terminal when a hunk's file is gone and then waits. `setsid -w` drops the terminal so `patch` skips instead. A plain run in the bash tool has no terminal and does not hang.
- `CANON` is shared with other worktrees on this host. A concurrent fetch into it can contend for its git lock. Use a private `CANON` when two port drives run at once.
- The gate runs `omp-port/test-gate-mutations.sh` and `omp-port/test-worktree-audit.sh` itself. Their own failures appear under `gate mutations` and `worktree audit`.
- Several checks print long `REPORT` lists of rules. Search the log for `FAIL` rather than reading it top to bottom.
