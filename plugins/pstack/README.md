# pstack for oh-my-pi

Lauren Tan's pstack methodology, ported to omp. The full pstack skill set with its playbooks and
principle leaves, the `poteto-mode` pin, and the `poteto-agent` and `comment-sicko` agents.
Every skill but `omp-mechanics` and `pstack-omp` is built from upstream. Those two are port-owned.

## Install

```
/marketplace add negoro26/pstack-omp
/marketplace install pstack@pstack-omp
```

That loads every skill and both extensions, `potetomode` and `pstackpolicy`. The two agents are optional.
On omp 18.1.13 a marketplace plugin's `agents/` directory is scanned only through the
`claude-plugins` discovery provider, and enabling that provider also loads every Claude Code
plugin cached under `~/.claude/plugins`. Link the agents into omp's native root instead:

```
mkdir -p ~/.omp/agent/agents
ln -s ../../plugins/node_modules/pstack/agents/poteto-agent.md  ~/.omp/agent/agents/poteto-agent.md
ln -s ../../plugins/node_modules/pstack/agents/comment-sicko.md ~/.omp/agent/agents/comment-sicko.md
```

`node_modules/pstack` is the symlink the marketplace install maintains, so `/marketplace upgrade`
moves the agents with it. Check with a fresh session:

```
omp -p --no-session --thinking off "Do not call any tool. List every agent name in the task tool's Available Agents section."
```

Use these optional agents only when the live roster lists them; otherwise the adapter maps the role to an available worker.

Then `/poteto-mode on`, or `alt+shift+t`, or `omp -p --poteto '...'` for headless runs.

## What the policy extension refuses

`pstackpolicy` loads with the plugin and needs no configuration. It registers `tool_call` on `bash`
and `eval` and refuses exactly two things, the two items of upstream's pause list that a command can
show.

- A force-push to the repository's default branch, or to `main`, `master`, or `trunk`. A push is
  forced by `--force`, `--force-with-lease`, `-f` (also inside a flag cluster such as `-fu`), a `+`
  on the refspec, or `--mirror`. `HEAD` or a missing refspec pushes the checked-out branch, which the
  extension reads from the directory the tool call runs in: the session cwd, or the `cwd` the call
  passes, moved by each `git -C`. A `cd x && git push` inside the command line is not tracked. The
  default branch is whatever the remote's `HEAD` names. A `gh api` update of a trunk ref that sends
  `force=true` counts too. A force-push to any other branch stays allowed, because that is the
  port's own rebase flow, except where the shell names the destination, as in
  `git push --force-with-lease origin "$BRANCH"`. The command cannot show that value is not trunk, so
  it is refused with the instruction to write the branch name out literally and retry.
- Deleting the repository, with `gh repo delete` or `gh api -X DELETE repos/<owner>/<repo>` and no
  further path.

Everything else passes: merging, closing, reviews, retargeting a base, deleting a branch, plain
pushes, releases and secrets. Those are the playbooks' own work, and the operator's prompt is the
permission for them. `poteto-mode` ships upstream's pause list and its session-override line as
upstream wrote them, so a prompt such as "land the stack, I'm going to bed" is the permission to
merge, and the playbooks that land (Shipping, Autopilot-full) merge on it. Babysit still stops at
merge-ready. Deploys, data deletion and customer messages have no command shape this file could
read, so they stay with the prose.

A refusal tells the agent to stop and return the step to the operator, as the pause list says. The
extension does not enforce the playbooks and is no sandbox. It reads only model-issued `bash` and
`eval` calls. The `browser` and `computer` preludes emit no `tool_call`, and a command assembled by
string concatenation inside a cell matches no rule. A push's refspecs end at its own command, a
comment ends at its newline whatever quotes it holds, a redirection target is not a refspec, and
each line of a heredoc body is checked as a command, because a shell may run it.
`PORTING.md`'s "What omp can actually stop" carries the measurement behind it.

## What this plugin does not enforce

Subagents run with `approvalMode: yolo`, so a worker cannot stop to ask you a question. This plugin
ships no `session_stop` veto, so nothing here rejects a malformed subagent result for you. The gate
is the root's own: it reads each worker's result and accepts or rejects it, and a judged role runs as
an independent session. If you want a hard veto on a turn that yields nothing usable, install one as
a separate extension; do not expect this plugin to supply it.

## What differs from upstream

Every Cursor mechanic is substituted for its omp equivalent. Cloud agents become
`isolated: true` subagents. An out-of-session `/loop` wake becomes a supervised `bash` process
carrying a unique `name`, observed through `read proc://<name>`, or a systemd user timer. The
`name` selects service mode and cannot be combined with `async: true`; `async` is the separate
finite-command path and hands back a job id. Cursor transcripts become
`~/.omp/agent/sessions/`, and worker output is read at `agent://<id>`. No skill names a vendor
model. Name a capability, bind it once in `modelRoles`, pick the chat model with `/model`.

Judged roles return a typed result, not prose: `arena`'s cross-judge, `interrogate`'s reviewers,
and `reflect`'s synthesizer each pass an explicit `outputSchema`, and the verdict is read from the
spawn's structured result. In `shipping` and `babysit`, GitHub PRs and issues are read through the built-in URL schemes
(`pr://<n>`, `pr://<n>/diff`, `issue://<n>`) while the forge client stays the only writer. A
refilling fan-out uses a work pool rather than a fixed batch. `checkpoint` is used only for what it
does, which is collapsing conversation context.

`PORTING.md` at the repo root records every substitution and the re-sync procedure.

## Model for the agent

`poteto-agent` ships model-free and inherits your chat model. To pin it, add
`model: "@poteto"` to the agent file and bind `poteto` in `modelRoles`. An unbound
alias fails the spawn, so bind before you add. Bind it yourself with `/model`, or with
`omp config set modelRoles '<full json>'`, because a dotted `modelRoles.poteto` key is rejected and
`inherit-parent` resolves to `No model selected`, which also fails the spawn.
pstack needs no other model configuration. To choose models for other agents, follow
[Choose models](skills/omp-mechanics/SKILL.md#choose-models) in `omp-mechanics`.
