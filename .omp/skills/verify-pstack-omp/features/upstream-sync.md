# Upstream sync

`omp-port/sync-upstream.sh` is how the maintainer follows upstream `cursor/plugins` pstack. `check` lists upstream commits since the pin without touching the checkout. `rebuild` regenerates `plugins/pstack` at the pin and must reproduce the committed tree. A sync to a target sha rebuilds the tree there and moves the pin, or refuses and leaves both untouched when a port patch no longer applies.

## Sub-features

- `sync-check` lists upstream pstack commits since the pin, newest first, and names the target sha.
- `sync-check-target-out` also writes the target sha to the file named by `SYNC_TARGET_OUT`.
- `sync-rebuild` rebuilds at the pin with zero changed files.
- `sync-move` rebuilds at a target sha and moves `omp-port/UPSTREAM` to it.
- `sync-refuse` exits 1 and leaves the tree and the pin untouched when the build at the target fails.

## How to get to it (user POV)

- Run `bash omp-port/sync-upstream.sh check` from the repository root.
- Run `bash omp-port/sync-upstream.sh rebuild` after editing `omp-port/rules.sed`, `omp-port/patches/`, or `omp-port/owned.txt`.
- Run `bash omp-port/sync-upstream.sh <full-40-hex-sha>` to sync.
- The scheduled `upstream-sync` workflow runs the same commands in CI and opens a `sync/upstream-<sha7>` PR. It writes to the forge, so this map does not drive it. Read its runs with `gh run list --workflow upstream-sync.yml`.

## Driving it with control-pstack

Preconditions:

- `gh auth status` succeeds. `check` and a target lookup call `gh api`.
- `CANON` names an upstream clone, default `/tmp/cursor-plugins`. Without it the scripts clone upstream over the network.
- `E=$($C evidence sync-<n>)` holds the evidence dir.

- **Check.** In the checkout, run `git status --porcelain >"$E/status-before.txt"`, then `SYNC_TARGET_OUT="$E/target.txt" bash omp-port/sync-upstream.sh check >"$E/check.out" 2>"$E/check.err"; echo "exit=$?" >>"$E/check.err"`, then `git status --porcelain >"$E/status-after.txt"`. `check.out` has one `<sha7>	<date>	<subject>` line per upstream commit since the pin, or nothing when there is no drift. `check.err` starts `target <40-hex sha>`, carries one `shadowed <path>: ...` line per owned path, and ends `exit=0`. `target.txt` holds the same sha. The two status files are identical.
- **Rebuild.** Run `R=$($C clone sync-<n>)`, then `(cd "$R" && setsid -w bash omp-port/sync-upstream.sh rebuild) 2>&1 | tee "$E/rebuild.txt"` and `git -C "$R" status --porcelain | tee "$E/rebuild-status.txt"`. The summary reads `pin <sha7> -> <sha7>` and `changed 0 files under plugins/pstack`, and the status file is empty. It took 24s on this host.
- **Sync to a target.** In the same clone, run `(cd "$R" && setsid -w bash omp-port/sync-upstream.sh <target-sha>; echo "exit=$?") 2>&1 | tee "$E/sync.txt"`, then `cat "$R/omp-port/UPSTREAM"` and `git -C "$R" diff --stat | tail -n 1`. On success the summary reads `pin <old7> -> <new7>`, `UPSTREAM` holds the target, and the diff is the rebuilt tree.
- **Refusal.** When a port patch does not apply at the target, `sync.txt` ends `sync-upstream: build at <sha7> failed, see the output above` and `exit=1`, `UPSTREAM` still holds the old pin, and `git -C "$R" status --porcelain` is empty. Main at pin `519d36a` syncing to `c742dd6` did this, because upstream deleted files the port patches.
- **Clean up.** Run `$C cleanup sync-<n>`. It removes the clone and keeps `$E`.

## Gotchas

- `rebuild` and a sync rewrite `plugins/pstack` in whatever checkout they run in. Never run them outside `$C clone`.
- The clone holds HEAD only. Commit the change you want to prove first, or the clone verifies the previous commit.
- `patch` asks `File to patch:` on the terminal when a hunk's file is gone, then waits for an answer. A tmux pane sat at that prompt for 25s before it was killed. `setsid -w` drops the terminal so `patch` skips the hunk and the build fails cleanly. `</dev/null` does not help, because the patch file is already on stdin.
- `sync-move` needs a target at which the port's patches apply. When no such target exists, the journey ends at `sync-refuse`. Report it as a failure with that reason, not as a pass.
- `check` reads the last 100 upstream pstack commits. A pin older than that fails with `pin <sha> is not among the last 100 upstream pstack commits`.
- `CANON` is a shared cache. Another worktree's run can fetch into it at the same time. Use a private `CANON` path when two port drives run at once.
- A target must be a full 40-hex sha that touched `pstack/`. A short sha is refused.
