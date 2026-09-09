---
name: setup-pstack
description: Configure which models pstack uses per role. Detects your available models and writes an always-applied rule that overrides the skill defaults. Use for /setup-pstack, "configure pstack models", or changing pstack's model choices.
---

# Setup pstack

The chat model is the operator's choice, made with `/model`. pstack never overrides it. This skill writes the per-role layer instead. A capability alias per role agent goes in `task.agentModelOverrides` in `~/.omp/agent/config.yml`, keyed by agent name, and the operator binds each alias to a real model in `modelRoles` in the same file. Check the `task` tool's parameters before you look for anything else. It exposes no `model` field, so an override entry is the per-spawn lever, and if a later omp adds one, prefer it. A role with no entry runs on the parent chat model.

## Steps

### 1. Detect available models

Run `omp models` to list the models configured on this machine. That is the dependable source. If it lists none, ask the user to paste the slugs they have access to. Never write a real slug you have not confirmed is available. The aliases `inherit-parent` and `auto` are always valid even though they are not detected slugs. Group what you detect by model family and count the families, because the review roles in step 3 are defined by family difference and you cannot honor that without knowing what this machine has.

### 2. Load current state

The default role-to-capability mapping is the shape shown in step 5 below. Read `task.agentModelOverrides` and `modelRoles` from `~/.omp/agent/config.yml`, which `omp config get task.agentModelOverrides` prints directly, and treat their values as the current choices. Otherwise start from those defaults.

### 3. Map and confirm

Show every role with the capability it asks for and the model currently bound to that capability, marking any capability with no binding as needing a choice. Ask whether to accept as-is or change specific capabilities, offering the detected models plus `inherit-parent` and `auto` (both mean: this role runs on the parent chat model, which is how Auto users stay on Auto) as the options. Prefer `ask` over free text. Four capabilities cover every role, so four answers configure the whole stack. For panel roles (arena runners, architect runners, interrogate reviewers) the value is a list of slots, one subagent runs per slot, alias slots included, so the list length sets the count, and each slot needs its own thin agent file plus its own override entry. `arena cross-judge pool` is also a list, but Arena selects one entry whose model family differs from the parent's when possible. `swarm workers` is the default capability for every worker. A race or comparison that wants a model per arm needs one thin agent file per arm with its own `task.agentModelOverrides` entry.

### 4. Validate

Every real slug written must be in the detected set. `inherit-parent` and `auto` always pass. A slug belongs in `modelRoles` and nowhere else, because the role entries carry capability aliases, so a provider rename touches one line in the operator's config and no skill at all. If a chosen real slug is not available, stop and ask again. Then check the panel roles against the family count from step 1. If this machine has two or more families, bind each panel slot to a different one. If it has one, say so plainly, tell the user that arena, architect, interrogate, and reflect give a weaker review when writer and reviewer share a family, and keep the review anyway. Never bind two panel slots to the same family and call the result diverse.

### 5. Write the rule

Write both keys in `~/.omp/agent/config.yml`. `task.agentModelOverrides` maps an agent name to a capability alias, and omp expands that alias through `modelRoles`. The binding line is the operator's to write, carrying the answer they gave in step 3. Overwrite the whole pstack part of both maps so re-runs stay idempotent, and leave omp's own roles alone. The block below is an example to adapt, not a schema. The alias namespace is the operator's, and nothing in pstack reads a specific alias name. What is fixed is the four capabilities and the role labels, which are the ones poteto-mode and the routed skills use. A role that needs its own model needs its own thin agent file plus its own entry here, so a panel of four is four agent files. Shape:

```yaml
# pstack model configuration. One entry per role agent, one alias per capability.
# Delete an entry and that agent runs on the parent chat model, which is the right
# default and needs no configuration. `inherit-parent` and `auto` are always-valid
# values that state it out loud. An alias entry in a panel list still counts toward
# its fan-out.
task:
  agentModelOverrides:
    pstack_feature: "@pstack_fast_code"           # feature, refactoring
    pstack_refactoring: "@pstack_fast_code"       # feature, refactoring
    pstack_bug_fix: "@pstack_judgment"            # bug-fix
    pstack_perf_issue: "@pstack_judgment"         # perf-issue
    pstack_hillclimb: "@pstack_judgment"          # hillclimb
    pstack_judgment: "@pstack_judgment"           # judgment and prose
    pstack_prose: "@pstack_prose"                 # judgment and prose
    pstack_hardest: "@pstack_judgment"            # hardest tasks
    pstack_how_explorer: "@pstack_fast_code"      # how explorer
    pstack_how_explainer: "@pstack_prose"         # how explainer
    pstack_why_investigator: "@pstack_fast_code"  # why investigators
    pstack_why_synthesizer: "@pstack_prose"       # why synthesizer
    pstack_reflect_tooling: "@pstack_instruction" # reflect tooling
    pstack_reflect_judgment: "@pstack_judgment"   # reflect judgment, divergent, synthesizer
    pstack_reflect_divergent: "@pstack_judgment"
    pstack_reflect_synthesizer: "@pstack_prose"
    pstack_arena_runner_1: "@pstack_family_1"     # arena runners
    pstack_arena_runner_2: "@pstack_family_2"
    pstack_arena_runner_3: "@pstack_family_3"
    pstack_arena_runner_4: "@pstack_family_4"
    pstack_arena_judge_1: "@pstack_family_1"      # arena cross-judge pool
    pstack_arena_judge_2: "@pstack_family_2"
    pstack_arena_judge_3: "@pstack_family_3"
    pstack_arena_judge_4: "@pstack_family_4"
    pstack_swarm_worker: "@pstack_fast_code"      # swarm workers
    pstack_architect_runner_1: "@pstack_family_1" # architect runners
    pstack_architect_runner_2: "@pstack_family_2"
    pstack_architect_runner_3: "@pstack_family_3"
    pstack_architect_runner_4: "@pstack_family_4"
    pstack_interrogate_reviewer_1: "@pstack_family_1" # interrogate reviewers
    pstack_interrogate_reviewer_2: "@pstack_family_2"
    pstack_interrogate_reviewer_3: "@pstack_family_3"
    pstack_interrogate_reviewer_4: "@pstack_family_4"
modelRoles:
  # One line per alias. Each value is a selector `omp models` printed on this machine,
  # taken from the user's step 3 answer. Write no slug you did not detect. Omit an alias
  # and drop its entries above to run those roles on the parent chat model.
  #   pstack_judgment     your strongest judgment model, for vague intent and cross-cutting design
  #   pstack_instruction  your strongest instruction-following model, for a precisely specified sequence
  #   pstack_fast_code    your fast code model, for trivial mechanical edits and bulk collection
  #   pstack_prose        your prose model, for reviews and synthesis
  #   pstack_family_1..4  one strong reviewer per distinct detected model family, in family order
```

### 6. Confirm

Tell the user which entries were written, that `modelRoles` now carries their model choices, and that both apply to new sessions. Re-running this skill updates them.

### 7. Offer a verification skill (optional)

Check whether the project has a way to drive the real app for proof (a `verify-*` skill, or an existing harness). If not, offer once: "want a project-local verification skill, so agents can drive the app the way a user does and prove changes work? I can generate one with /create-verification-skill." On yes, invoke `/create-verification-skill` (resolves wherever pstack is installed: workspace, user, or plugin). On no, move on without pushing.
