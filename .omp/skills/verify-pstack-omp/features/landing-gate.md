# Landing gate

The pstackpolicy extension refuses forge mutations that the model issues through the `bash` or `eval` tool, such as merging a pull request or pushing to trunk, unless the operator started omp with `PSTACK_LANDING_GRANT=1`. The refused command never runs. The agent receives the refusal as its tool result, and the user sees it in the tool block.

## Sub-features

- `gate-refuse-bash` refuses a model `bash` call that merges a pull request, and nothing runs.
- `gate-refuse-eval` refuses a model `eval` cell that merges a pull request through a Python argv list.
- `gate-refuse-push` refuses a model `git -C . push origin HEAD:main`, past the global option.
- `gate-agent-told` returns the refusal text to the agent as the tool result.
- `gate-allow-read` lets a non-mutating `gh pr view` run in the same session.
- `gate-grant` lets the same merge run when omp started with `PSTACK_LANDING_GRANT=1`.
- `gate-user-bang` leaves the user's own `!` command ungated, because the operator typed it.

## How to get to it (user POV)

- Ask the agent to do something that ends in a merge, a close, a base retarget, a review post, a trunk push, a release, or a repository delete. The gate fires when the model's tool call carries the command.
- Start omp with `PSTACK_LANDING_GRANT=1` in its environment to allow those commands for that process.
- Type `!<command>` to run a shell command yourself.

## Driving it with control-pstack

Preconditions:

- `$C launch gate-<n>` succeeded without `--grant`, and `$C doctor gate-<n>` prints `grant absent` and no `FAIL`.
- The run id is new, so `$C evidence gate-<n>` prints a directory that did not exist before.

- **Refuse a bash merge.** Run `$C type-file gate-<n> $P/landing-merge.txt`, `$C press gate-<n> Enter`, `$C wait gate-<n> 'refused merging a pull request'`, `$C wait gate-<n> 'tool result received'`, and `$C capture gate-<n> landing-gate.gate-refuse-bash`. The pane shows the typed `tool:bash` prompt, a tool block whose command line is the merge, and output starting `pstackpolicy: refused merging a pull request.` `landing-gate.gate-refuse-bash.gh-calls.log` is empty.
- **Agent receives the refusal.** Run `jq -r 'select(.body.messages[-1].role=="tool") | .body.messages[-1].content' "$($C evidence gate-<n>)/landing-gate.gate-refuse-bash.model-requests.jsonl"`. It prints the same `pstackpolicy: refused merging a pull request.` text.
- **Refuse an eval merge.** Run `$C type-file gate-<n> $P/landing-eval-merge.txt`, `$C press gate-<n> Enter`, `$C wait gate-<n> 'refused merging a pull request'`, `$C wait gate-<n> 'tool result received'`, and `$C capture gate-<n> landing-gate.gate-refuse-eval`. The pane shows the `tool:eval` prompt followed by `pstackpolicy: refused merging a pull request.` The gh-calls log is still empty.
- **Refuse a trunk push.** Run `$C type-file gate-<n> $P/landing-push-trunk.txt`, `$C press gate-<n> Enter`, `$C wait gate-<n> 'refused pushing to trunk'`, `$C wait gate-<n> 'tool result received'`, and `$C capture gate-<n> landing-gate.gate-refuse-push`. The tool block shows `$ git -C . push origin HEAD:main` and `pstackpolicy: refused pushing to trunk.` The gh-calls log is still empty.
- **Allowed control.** Run `$C type-file gate-<n> $P/landing-view.txt`, `$C press gate-<n> Enter`, `$C wait gate-<n> 'gh-shim: pr view'`, `$C wait gate-<n> 'tool result received'`, and `$C capture gate-<n> landing-gate.gate-allow-read`. The tool block output is `gh-shim: pr view 1 --repo pstack-verify/no-such-repo`, and that capture's gh-calls log has exactly that one line. This proves the shim was reachable while the refusals above ran.
- **User bang command.** Run `$C type-file gate-<n> $P/user-bang-merge.txt`, `$C press gate-<n> Enter`, `$C wait gate-<n> 'gh-shim: pr merge'`, and `$C capture gate-<n> landing-gate.gate-user-bang`. The pane shows the shim output with no model turn after it, and the gh-calls log gains a `pr merge 1 ...` line.
- **Grant.** Run `$C cleanup gate-<n>`, then `$C launch gate-<n>-grant --grant`. `$C doctor gate-<n>-grant` prints `grant armed`. Type `$P/landing-merge.txt` the same way, `$C wait gate-<n>-grant 'gh-shim: pr merge'`, and capture `landing-gate.gate-grant`. Its gh-calls log has `pr merge 1 --repo pstack-verify/no-such-repo --squash`.
- **Clean up.** Run `$C cleanup` for each run id used, then `ls` both evidence dirs.

## Gotchas

- The driver's own pstackpolicy refuses an inline prompt or a `grep` whose command line contains `gh` followed by `pr merge`. Use `type-file` for prompts and read evidence with `read` or a pattern such as `'pr merge'`.
- The shim log is cumulative for a run. Capture each refusal before the allowed control, or the refusal capture shows the control's line.
- Wait for `tool result received` before typing the next prompt, so each capture holds one finished turn.
- The gate reads only model-issued `bash` and `eval` calls. The user's `!` command, the `browser` and `computer` preludes, and a command built by string concatenation inside a cell are outside it by design.
- The grant is read from omp's process environment. Exporting it in the driver's shell does nothing, because launch runs omp under `env -i`. Use `--grant`.
- The prompts target `pstack-verify/no-such-repo`. If the shim were missing, the real `gh` would still fail, since the scratch HOME has no login.
