# The model-agnostic convention

Port-only document. pstack upstream names concrete model slugs. This install does not.

## Why

The operator picks the chat model with omp's `/model` command. A slug written into a skill
goes stale the moment a provider renames a model, and it silently misroutes work when the
named model is not on this machine. The port had 75 such occurrences across 15 files, and
one upstream rename churned 23 of them in a single commit.

## The rule

Name the capability you need. Never name a vendor, a family, or a slug.

| Role | Write this | Never this |
|---|---|---|
| Hardest judgment, vague intent, cross-cutting design | your strongest judgment model | a named thinking model |
| A precisely specified sequence to execute to the letter | your strongest instruction-following model | a named instruction model |
| Trivial mechanical edits, bulk collection | your fast code model | a named fast model |
| Prose, reviews, synthesis | your prose model | a named prose model |

## The two levers, and nothing else

The chat model is the operator's choice, made with `/model`. A skill never overrides it.

A per-agent model is `task.agentModelOverrides` in `~/.omp/agent/config.yml`, keyed by agent
name. omp's `task` tool has no `model` field, so this is the only per-spawn lever.

With no override entry a subagent runs on the parent chat model. That is the default and it
is correct. `inherit-parent` and `auto` state it explicitly.

A role that needs its own model needs its own thin agent file plus an override entry. A model
race therefore needs one agent file per arm. Say that rather than implying a `model` argument
exists.

## Model diversity is a property, not a slug

`interrogate`, `arena`, and `reflect` exist to get an independent second opinion. What makes
the opinion independent is that the reviewer runs on a different model family from the writer,
not that it runs on any particular model.

State the property. Resolve it at run time from what `omp models` lists. When only one family
is available, say the review is weaker for it. Never fake diversity by naming two slugs from
the same provider, and never skip the review silently.

## Gate

`bash omp-port/check-port.sh` fails on any vendor slug in `skills`, `agents`, or `docs`.
Illustrative prose that merely mentions a model name goes in `omp-port/slug-allowlist.txt`
with a reason, so the exception is reviewed rather than hidden.
