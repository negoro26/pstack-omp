# The omp shape of pstack's model configuration

Amends **setup-pstack** steps 2, 3, 5, and 6. The block in the skill's step 5 is the
role-to-capability table. This file is the file format.

Two keys in `~/.omp/agent/config.yml`. `task.agentModelOverrides` maps an agent name to a
capability alias, and omp expands that alias through `modelRoles`. The alias namespace is the
operator's, and nothing in pstack reads a specific alias name. What is fixed is the four
capabilities and the role labels, which are the ones poteto-mode and the routed skills use.

Overwrite the whole pstack part of both maps so re-runs stay idempotent, and leave omp's own roles
alone. Adapt the names below rather than copying them.

```yaml
task:
  agentModelOverrides:
    # One entry per role agent, one alias per capability. Delete an entry and that
    # agent runs on the parent chat model, which is the right default and needs no
    # configuration. `inherit-parent` and `auto` are always-valid values that state
    # it out loud. An alias entry in a panel list still counts toward its fan-out.
    pstack_feature: "@pstack_fast_code"            # feature, refactoring
    pstack_refactoring: "@pstack_fast_code"
    pstack_bug_fix: "@pstack_fast_code"            # bug-fix
    pstack_perf_issue: "@pstack_fast_code"         # perf-issue
    pstack_hillclimb: "@pstack_fast_code"          # hillclimb
    pstack_judgment: "@pstack_judgment"            # judgment and prose
    pstack_hardest: "@pstack_judgment"             # hardest tasks
    pstack_how_explorer: "@pstack_fast_code"       # how explorer
    pstack_how_explainer: "@pstack_judgment"       # how explainer
    pstack_why_investigator: "@pstack_fast_code"   # why investigators
    pstack_why_synthesizer: "@pstack_judgment"     # why synthesizer
    pstack_reflect_tooling: "@pstack_instruction"  # reflect tooling
    pstack_reflect_judgment: "@pstack_judgment"    # reflect judgment, divergent, synthesizer
    pstack_reflect_divergent: "@pstack_family_2"
    pstack_reflect_synthesizer: "@pstack_judgment"
    pstack_swarm_worker: "@pstack_fast_code"       # swarm workers
    pstack_arena_runner_1: "@pstack_family_1"      # arena runners
    pstack_arena_runner_2: "@pstack_family_2"
    pstack_arena_runner_3: "@pstack_family_3"
    pstack_arena_runner_4: "@pstack_family_4"
    pstack_arena_judge_1: "@pstack_family_1"       # arena cross-judge pool
    pstack_arena_judge_2: "@pstack_family_2"
    pstack_architect_runner_1: "@pstack_family_1"  # architect runners
    pstack_architect_runner_2: "@pstack_family_2"
    pstack_architect_runner_3: "@pstack_family_3"
    pstack_architect_runner_4: "@pstack_family_4"
    pstack_interrogate_reviewer_1: "@pstack_family_1"  # interrogate reviewers
    pstack_interrogate_reviewer_2: "@pstack_family_2"
    pstack_interrogate_reviewer_3: "@pstack_family_3"
    pstack_interrogate_reviewer_4: "@pstack_family_4"
modelRoles:
  # One line per alias. Each value is a selector `omp models` printed on this machine,
  # taken from the user's step 3 answer. Write no slug you did not detect. Omit an
  # alias and drop its entries above to run those roles on the parent chat model.
  #   pstack_judgment     strongest judgment, for vague intent and cross-cutting design
  #   pstack_instruction  strongest instruction following, for a precisely specified sequence
  #   pstack_fast_code    fast code, for mechanical edits and bulk collection
  #   pstack_family_1..4  one strong reviewer per distinct detected family, in family order
```

Four capabilities cover every role, so four answers configure the whole stack. The panel roles are
the exception. Each slot is a separate agent name, needs its own thin agent file, and takes its
family from its own entry. A slot with no entry runs on the parent chat model, and four slots with
no entries are four runs of the same model.

The budget question in step 3 still applies. It picks the effort tier inside each family. With no
selector at the asked-for tier, take the same family's highest tier at or below the target, and
mark the role as needing a choice when that family offers none.

Step 6 reports which entries were written, that `modelRoles` now carries the model choices, and
that both apply to new sessions.
