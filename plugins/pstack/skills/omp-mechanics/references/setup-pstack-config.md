# The OMP shape of pstack model configuration

This reference is the file shape for **setup-pstack**. It does not define a second routing contract.

```yaml
modelRoles:
  pstack_fast_code: "<detected-selector>:<effort>"
  pstack_judgment: "<detected-selector>:<effort>"
  pstack_instruction: "<detected-selector>:<effort>"
task:
  agentModelOverrides:
    <exact discovered agent name>: "@pstack_fast_code"
```

Replace the agent placeholder with a name from the live roster. The three `modelRoles` keys are the complete pstack-owned alias set. A `task.agentModelOverrides` entry is pstack-owned only when its value is one of those three `@pstack_*` aliases and its key is an exact discovered agent. Update or remove only those entries. Preserve unrelated model roles, agent overrides, and operator entries. Never use a `pstack_*` key as an agent name.

Validate a `modelRoles` value by accepting either an exact detected selector or exactly one supported effort suffix from `max`, `xhigh`, `high`, `medium`, `low`, and `minimal`. Strip only that supported suffix and require the remaining base to equal a selector from `omp models --json`. Require the suffix to appear in the selected model's `thinking.efforts` list. The CLI can serialize that list directly as `thinking`; follow the live JSON shape. A task override value is either an exact detected selector or an `@role` alias already present in `modelRoles`; `inherit-parent` and `auto` are not values.

An omitted task override uses the discovered agent's frontmatter model first, then the parent session's active or default model.

The capability aliases may resolve to the same selector and the same family. Family diversity is optional. Do not fabricate a second family when the operator's model policy or roster provides one. Setup reports weaker diversity, and the workflows report it too.
