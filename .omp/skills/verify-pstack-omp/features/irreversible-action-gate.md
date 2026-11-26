# Irreversible-action gate

The pstackpolicy extension refuses two irreversible actions that the model issues through the `bash` or `eval` tool, a force-push to the repository's default branch or to main, master, or trunk, and deleting the repository. These are the two items of upstream's pause list that a command can show. The refused command never runs. The agent receives the refusal as its tool result and is told to stop and return the step to the operator. Everything else passes, merges included, because the operator's prompt is the permission to land.

## Sub-features

- `gate-refuse-force-push` refuses a model `bash` call that force-pushes main, past the global option, and git never pushes.
- `gate-refuse-eval` refuses a model `eval` cell that force-pushes main through a Python argv list with `--force-with-lease` and a `+` refspec.
- `gate-refuse-repo-delete` refuses a model `bash` call that deletes the repository through the API.
- `gate-agent-told` returns the refusal text to the agent as the tool result, with the instruction to return the step to the operator.
- `gate-allow-merge` lets a `gh pr merge` reach the `gh` shim in the same session.
- `gate-allow-feature-push` lets a force-push to a feature branch reach the `git` shim.
- `gate-user-bang` leaves the user's own `!` command ungated, because the operator typed it.

## How to get to it (user POV)

- Ask the agent to do something that ends in a force-push to the default branch or a repository delete. The gate fires when the model's tool call carries the command.
- Ask the agent to merge a pull request or force-push a feature branch. Nothing fires.
- Type `!<command>` to run a shell command yourself.

## Driving it with control-pstack

Preconditions:

- `$C launch gate-<n>` succeeded, and `$C doctor gate-<n>` prints no `FAIL`, including the line that omp's environment holds no `PSTACK_` variable.
- The run id is new, so `$C evidence gate-<n>` prints a directory that did not exist before.

- **Refuse a bash force-push.** Run `$C type-file gate-<n> $P/gate-force-push-main.txt`, `$C press gate-<n> Enter`, `$C wait gate-<n> 'refused force-pushing a default or trunk branch'`, `$C wait gate-<n> 'tool result received'`, and `$C capture gate-<n> irreversible-action-gate.gate-refuse-force-push`. The pane shows the typed `tool:bash` prompt, a tool block whose command line is `git -C . push --force origin main`, and output starting `pstackpolicy: refused force-pushing a default or trunk branch.` `irreversible-action-gate.gate-refuse-force-push.git-calls.log` is empty.
- **Agent receives the refusal.** Run `jq -r 'select(.body.messages[-1].role=="tool") | .body.messages[-1].content' "$($C evidence gate-<n>)/irreversible-action-gate.gate-refuse-force-push.model-requests.jsonl"`. It prints the same `pstackpolicy: refused` text, which ends with `Stop here and return this step to the operator`.
- **Refuse an eval force-push.** Run `$C type-file gate-<n> $P/gate-eval-force-push.txt`, `$C press gate-<n> Enter`, `$C wait gate-<n> 'refused force-pushing a default or trunk branch'`, `$C wait gate-<n> 'tool result received'`, and `$C capture gate-<n> irreversible-action-gate.gate-refuse-eval`. The pane shows the `tool:eval` prompt followed by the refusal. The git-calls log is still empty.
- **Refuse a repository delete.** Run `$C type-file gate-<n> $P/gate-repo-delete.txt`, `$C press gate-<n> Enter`, `$C wait gate-<n> 'refused deleting the repository'`, `$C wait gate-<n> 'tool result received'`, and `$C capture gate-<n> irreversible-action-gate.gate-refuse-repo-delete`. The gh-calls log is empty.
- **Allowed merge.** Run `$C type-file gate-<n> $P/gate-merge.txt`, `$C press gate-<n> Enter`, `$C wait gate-<n> 'gh-shim: pr merge'`, `$C wait gate-<n> 'tool result received'`, and `$C capture gate-<n> irreversible-action-gate.gate-allow-merge`. The tool block output is `gh-shim: pr merge 1 --repo pstack-verify/no-such-repo --squash`, and that capture's gh-calls log has exactly that one line. This is the control that proves the shim was reachable while the refusals above ran.
- **Allowed feature push.** Run `$C type-file gate-<n> $P/gate-feature-push.txt`, `$C press gate-<n> Enter`, `$C wait gate-<n> 'git-shim: -C . push'`, `$C wait gate-<n> 'tool result received'`, and `$C capture gate-<n> irreversible-action-gate.gate-allow-feature-push`. The git-calls log has exactly `-C . push --force-with-lease origin feature/verify`.
- **User bang command.** Run `$C type-file gate-<n> $P/user-bang-force-push.txt`, `$C press gate-<n> Enter`, `$C wait gate-<n> 'git-shim: push --force origin main'`, and `$C capture gate-<n> irreversible-action-gate.gate-user-bang`. The pane shows the shim output with no model turn after it, and the git-calls log gains a `push --force origin main` line.
- **Clean up.** Run `$C cleanup gate-<n>`, then `ls` the evidence dir.

## Gotchas

- The driver's own pstackpolicy refuses an inline prompt or a `grep` whose command line contains a force-push to main. Use `type-file` for prompts and read evidence with `read` or a pattern such as `'push --force'`.
- The shim logs are cumulative for a run. Capture each refusal before the allowed controls, or the refusal capture shows the control's line.
- Wait for `tool result received` before typing the next prompt, so each capture holds one finished turn.
- The gate reads only model-issued `bash` and `eval` calls. The user's `!` command, the `browser` and `computer` preludes, and a command built by string concatenation inside a cell are outside it by design.
- The scratch `work/` directory is not a git checkout, so a force-push to a feature branch passes because the extension finds no default branch and no checked-out trunk there.
- The prompts target `pstack-verify/no-such-repo`. If the shims were missing, the real `gh` would still fail, since the scratch HOME has no login.
