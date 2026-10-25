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

### 4. Plan with the script and confirm

`skill://` paths are not executable. Resolve the script once in the bash tool, which expands `skill://` inside `realpath`:

```bash
APPLY=$(realpath skill://setup-pstack)/scripts/apply-models.mjs
```

Turn the table into arguments: `--alias <alias>=<selector>[:<effort>]` per alias, `--agent <exact agent name>=@<alias>` per mapped agent, and `--unset-agent <exact agent name>` for an agent still bound to a pstack alias but no longer selected. Run `node "$APPLY" --dry-run <arguments>`; `bun` runs it too. It prints the planned changes, every pstack-owned agent with the model it resolves to, and the family count. Show that output with the table, mark unavailable agents and unresolved selectors, and ask whether to accept it. Offer only detected selectors, configured aliases, or omission with the exact agent-then-parent resolution above.

The script refuses and writes nothing when an alias is not one of the three, a base is not a selector from `omp models --json`, an effort is off the ladder or missing from the selected model's `thinking.efforts` list, or an agent value is not a `@pstack_*` alias defined in `modelRoles`. It never strips an arbitrary colon fragment. It also refuses to change or remove an agent entry pstack does not own, and any `pstack_*` agent key. Fix the row and rerun the dry run. Never edit `config.yml` by hand to get past a refusal.

### 5. Write the config

On acceptance, run the same command without `--dry-run`. It merges onto the current records, writes `modelRoles` before `task.agentModelOverrides`, and preserves every entry pstack does not own. A rerun with the same arguments writes nothing and says so. If it reports that `modelRoles` was written and `task.agentModelOverrides` was not, rerun the same command to finish.

### 6. Confirm

Report the exact aliases and agent keys written, the selectors and effort suffixes used, any unavailable capability, and the family count from the script's output. One family prints `weaker diversity: one family`; report it as information. State that the entries apply to new sessions and that rerunning updates them. `node "$APPLY" --show` prints the current aliases, agent mappings, and family count.

### 7. Offer a verification skill (optional)

Check whether the project has a way to drive the real app for proof. If not, offer once: "want a project-local verification skill, so agents can drive the app the way a user does and prove changes work? I can generate one." On yes, read `skill://create-verification-skill` in full and follow it. On no, move on without pushing.

### 8. Offer a formal verification skill (optional)

Check whether the project already has a formal verification skill (a project skill that runs a model checker, a proof, or another verifier against the code). If not, offer once: "want a formal verification skill, so agents can prove a key property of your code holds in every case in scope, not only the cases tests reach? I can generate one." On yes, read `skill://create-formal-verification-skill` in full and follow it. On no, move on without pushing.
