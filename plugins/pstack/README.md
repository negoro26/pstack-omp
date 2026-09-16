# pstack for oh-my-pi

Lauren Tan's pstack methodology, ported to omp. 49 skills, 23 playbooks, 23 principle
leaves, the `poteto-mode` pin, and the `poteto-agent` and `comment-sicko` agents.
47 skills are built from upstream; `omp-mechanics` and `pstack-omp` are port adapters.

## Install

```
/marketplace add negoro26/pstack-omp
/marketplace install pstack@pstack-omp
```

That loads the 49 skills and the `potetomode` extension. The two agents are optional.
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

## What differs from upstream

Every Cursor mechanic is substituted for its omp equivalent. Cloud agents become
`isolated: true` subagents. `/loop` wake becomes a `hub` supervised watcher. Cursor
transcripts become `~/.omp/agent/sessions/`. No skill names a vendor model. Name a
capability, bind it once in `modelRoles`, pick the chat model with `/model`.

`PORTING.md` at the repo root records every substitution and the re-sync procedure.

## Model for the agent

`poteto-agent` ships model-free and inherits your chat model. To pin it, add
`model: "@poteto"` to the agent file and bind `poteto` in `modelRoles`. An unbound
alias fails the spawn, so bind before you add. `/setup-pstack` walks through it.
