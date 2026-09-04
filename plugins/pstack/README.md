# pstack for oh-my-pi

Lauren Tan's pstack methodology, ported to omp. 45 skills, 23 playbooks, 21 principle
leaves, the `poteto-mode` pin, and the `poteto-agent` and `Comment Sicko` agents.

## Install

```
/marketplace add negoro26/pstack-omp
/marketplace install pstack@pstack-omp
```

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
