---
name: setup-pstack
description: Configure pstack model selectors and reasoning budget. Detects available models and writes `modelRoles` plus exact-agent overrides. Use for /setup-pstack, "configure pstack models", "pstack budget", or changing pstack's model choices.
---

# Setup pstack

Read `skill://omp-mechanics/references/setup-pstack-config.md` for the file shape. This skill owns the selection procedure. It writes `task.agentModelOverrides` and three pstack-owned `modelRoles` aliases in `~/.omp/agent/config.yml`. It never creates agents, selects the chat model, or replaces `/model`.

## Ownership contract

The only pstack-owned `modelRoles` keys are `pstack_fast_code`, `pstack_judgment`, and `pstack_instruction`.
A `task.agentModelOverrides` entry is pstack-owned only when its exact key is a discovered agent and its value is one of `@pstack_fast_code`, `@pstack_judgment`, or `@pstack_instruction`.
Never infer ownership from a key spelling. Never treat `default`, `poteto`, `judge`, or another operator role as pstack-owned.
Preserve every unrelated entry in both maps.

## Steps

### 1. Detect models, aliases, and agents

Run `omp models --json`, read `modelRoles` and `task.agentModelOverrides` with `omp config get ... --json`, and inspect the live task roster. Inspect each discovered agent's exact name, frontmatter, declared tools, and description. For every candidate selector, read the selected model's `thinking.efforts` list from the model metadata. The CLI can serialize the same list directly as `thinking`; follow the live JSON shape. Respect any operator model policy, including a single-family policy. If no selectors are detected, ask for selectors the operator can use. `inherit-parent` and `auto` are not override values.

An omitted override uses the discovered agent's frontmatter model first, then the parent session's active or default model. Offer omission only with that exact result.

### 2. Build the exact mapping

Before asking for the budget, make a table with one row per capability and these columns: capability, exact discovered agent name, current effective model, and planned alias. Use only names present in the live roster.

- `pstack_fast_code`: discovered agents whose declared tools and description support implementation writes.
- `pstack_judgment`: discovered review-capable agents. If none exists, use a discovered full-access worker with a reviewer brief.
- `pstack_instruction`: discovered full-access agents that can follow an exact tool sequence. Do not assign a strict read-only specialist.

For each capability, prefer an exact agent already bound to that pstack alias, then the operator's confirmed choice, then roster order. One exact agent has one override value. If the roster has fewer distinct agents than capabilities, leave an alias defined but do not invent an agent; point the aliases at the same selected selector when that is the only policy-compliant choice. All three aliases may resolve to one family. Family diversity is optional, so report weaker diversity when the policy or roster supplies one family.

### 3. Ask for and apply the budget

Prefer `ask`. Offer these exact labels and name the current budget when recorded:

- `unlimited — keep max`
- `large — xhigh reasoning`
- `medium — high reasoning`
- `small — medium reasoning`
- `tiny — minimal reasoning`

The effort ladder is `max > xhigh > high > medium > low > minimal`. Keep the detected selector as the base. Choose the requested effort only when it appears in that model's `thinking.efforts` list. Otherwise choose the highest listed effort below it. If none exists, mark that alias unresolved. `unlimited` uses the highest listed effort. Never write a requested suffix that the selected model does not support.

### 4. Validate and confirm

For each `modelRoles` value, allow an exact detected selector, or one supported `:max`, `:xhigh`, `:high`, `:medium`, `:low`, or `:minimal` suffix. Strip only that supported suffix and require the remaining base to equal a selector from `omp models --json`. Require the suffix to appear in the selected model's `thinking.efforts` list. Never strip an arbitrary colon fragment. Every `task.agentModelOverrides` value must be an exact detected selector or an `@role` alias already present in the current `modelRoles` map. Show the exact mapping table and ask whether to accept it. Mark unavailable agents and unresolved selectors. Offer only detected selectors, configured aliases, or omission with the exact agent-then-parent resolution above.

### 5. Write the config

Use the shape in `skill://omp-mechanics/references/setup-pstack-config.md`. Write only the three pstack aliases and exact discovered agent keys selected in the table. Update entries currently bound to a pstack alias idempotently, and remove stale entries only when they still point to a pstack alias and their exact agent is no longer selected. Preserve unrelated aliases, overrides, and operator entries. Never write a `pstack_*` agent key.

### 6. Confirm

Report the exact aliases and agent keys written, the selectors and effort suffixes used, any unavailable capability, and the family count. State that the entries apply to new sessions and that rerunning updates them.

### 7. Offer a verification skill (optional)

Check whether the project has a way to drive the real app for proof. If not, offer once: "want a project-local verification skill, so agents can drive the app the way a user does and prove changes work? I can generate one with /create-verification-skill." On yes, invoke `/create-verification-skill`. On no, move on without pushing.
