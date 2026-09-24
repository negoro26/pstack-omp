---
name: setup-pstack
description: Configure which models pstack uses per role and at what reasoning budget. Detects your available models and writes an always-applied rule that overrides the skill defaults. Use for /setup-pstack, "configure pstack models", "pstack budget", or changing pstack's model choices.
---

# Setup pstack

Write `task.agentModelOverrides` in `~/.omp/agent/config.yml`, the keyed override map that sets pstack's model per role agent. The chat model stays the operator's choice, made with `/model`, and pstack never overrides it. `skill://omp-mechanics` holds the file shape.

## Steps

### 1. Detect available models

Run `omp models` to list the models configured on this machine. That is the dependable source. If you cannot detect any, ask the user to paste the slugs they have access to. Never write a real slug you have not confirmed is available. The aliases `inherit-parent` and `auto` are always valid even though they are not detected slugs.

### 2. Load current state

The default role-to-model mapping is the rule shape shown in step 5 below. If `task.agentModelOverrides` in `~/.omp/agent/config.yml` already exists, read it and treat its `# budget` line and its role values as the current choices. Otherwise start from those defaults. A line whose role is not in step 5, such as `how critics`, is from a retired role. Drop it.

### 3. Budget, map, and confirm

**(a) Ask for a budget.** Prefer `ask` over free text. Offer these four options with these exact labels, and name the current budget when the rule records one.

- `unlimited — keep max`
- `large — xhigh reasoning`
- `medium — high reasoning`
- `small — medium reasoning`

**(b) Apply it.** Build the working table from the skill defaults, and on a re-run keep any role you changed by family, list, or alias (`inherit-parent`, `auto`). `unlimited` leaves every effort as in that table. `large`, `medium`, and `small` set the effort token of every real slug, panel entries included, to `xhigh`, `high`, or `medium`. The effort token is the last token, or the one before a trailing `fast`, on the ladder `max` > `xhigh` > `high` > `medium` > `low`. If the result is not a detected slug, use the same family's detected slug with the highest effort at or below the target, else mark the role as needing a choice. `inherit-parent` and `auto` do not change. So `small` turns your strongest judgment model into your strongest judgment model, and your fast code model into your fast code model.

**(c) Show the roles and confirm.** Show every role with its model, marking any real slug not in the detected set as needing a choice. Also list each line step 2 dropped. Ask whether to accept as-is or change specific roles, offering the detected models plus `inherit-parent` and `auto` (both mean: this role runs on the parent chat model, which is how Auto users stay on Auto) as the options. Prefer `ask` over free text. For panel roles (arena runners, architect runners, interrogate reviewers) the value is a list, and one subagent runs per entry, alias entries included, so the list length sets the count. `arena cross-judge pool` is also a list, but Arena selects one value from it whose model family differs from the parent's when possible. `swarm workers` is the default model for every worker unless a race or comparison assigns another model per arm.

### 4. Validate

Every real slug written must be in the detected set. `inherit-parent` and `auto` always pass. If a chosen real slug is not available, stop and ask again.

### 5. Write the rule

Write `task.agentModelOverrides` and `modelRoles` in `~/.omp/agent/config.yml`, with a `# budget` comment carrying the chosen label and its target effort, and one entry per role agent, using the same labels poteto-mode uses. Overwrite the whole pstack part of both maps so re-runs stay idempotent. The block below is the role-to-capability table and not the file format, which `skill://omp-mechanics` holds. Shape:

```
---
description: pstack per-role model choices (overrides skill defaults)
---
# pstack model configuration. One line per role. Delete a line to fall back to the skill default.
# `inherit-parent` or `auto` as a value: the role runs on the parent chat model (leave it out of `task.agentModelOverrides`). Alias entries in a panel list still count toward its fan-out.
# budget: unlimited (max)
feature, refactoring: your fast code model
bug-fix: your fast code model
perf-issue: your fast code model
hillclimb: your fast code model
judgment and prose: your strongest judgment model
hardest tasks: your strongest judgment model
how explorer: your fast code model
how explainer: your strongest judgment model
why investigators: your fast code model
why synthesizer: your strongest judgment model
reflect tooling: your strongest instruction-following model
reflect judgment, divergent, synthesizer: your strongest judgment model
arena runners: one model per distinct family omp models reports
arena cross-judge pool: one model per distinct family omp models reports
swarm workers: your fast code model
architect runners: one model per distinct family omp models reports
interrogate reviewers: one model per distinct family omp models reports
```

### 6. Confirm

Tell the user which entries were written and that they apply to new sessions. Re-running this skill updates it.

### 7. Offer a verification skill (optional)

Check whether the project has a way to drive the real app for proof (a `verify-*` skill, or an existing harness). If not, offer once: "want a project-local verification skill, so agents can drive the app the way a user does and prove changes work? I can generate one with /create-verification-skill." On yes, invoke `/create-verification-skill` (resolves wherever pstack is installed: workspace, user, or plugin). On no, move on without pushing.
