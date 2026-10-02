# pstack for oh-my-pi

Lauren Tan's pstack methodology, ported to omp. 49 skills, 23 playbooks, 23 principle
leaves, the `poteto-mode` pin, and the `poteto-agent` and `comment-sicko` agents.
46 skills are built from upstream. `omp-mechanics`, `pstack-omp`, and `setup-pstack` are port-owned.

## Install

```
/marketplace add negoro26/pstack-omp
/marketplace install pstack@pstack-omp
```

That loads the 49 skills and both extensions, `potetomode` and `pstackpolicy`. The two agents are optional.
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
and `eval`, and refuses the forge mutations the playbooks only ask for in prose: `gh pr merge`,
merge and close through `gh api`, `gh pr close|reopen|delete`, `gh pr edit --base`, `gh pr review`,
merge-when-ready, `gh repo delete`, `gh release create|delete|upload`,
`gh secret|variable set|delete`, `gh workflow run --ref <trunk>`, the same forge calls made with
`curl`, and `gt submit|rebase|restack`. Locally it refuses `git update-ref`, `git branch -D`,
`git reset --hard` against a remote, and `git reflog expire --expire=now --all`. Any `git push`
whose refspec lands on `main`, `master`, `trunk`, `develop`, or `release` is refused, forced or not;
a force push to a feature branch stays allowed, because that is the port's own rebase flow.

To land, set `PSTACK_LANDING_GRANT=1` in the environment omp starts from. It is an environment
variable and not a flag or a slash command because a flag an agent can pass is not a grant you made.
The refusal names the variable, so the agent tells you exactly what to set. `PORTING.md`'s
"What omp can actually stop" carries the measurement behind the list.

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
`/skill:setup-pstack` will not make this binding for you: its ownership contract limits it to the
three `pstack_*` aliases and says never to treat `poteto`, `default`, or another operator role as
pstack-owned. It is still the right command for the pstack-owned aliases, and omp registers one
slash command per skill as `/skill:<name>`, so a bare `/setup-pstack` is not a command.
