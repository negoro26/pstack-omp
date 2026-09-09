---
name: how
description: "Use for \"how does X work\", code walkthroughs before changing something, and placement / ownership / layering questions (\"where should this live\", \"which package owns this\", \"is this the right layer\"). Explains subsystem architecture, runtime flow, onboarding mental models. Use why for motivation."
disable-model-invocation: true
---

# How

Explore the codebase to answer "how does X work?" questions. Produce architectural explanations at the level of a senior engineer onboarding onto a subsystem, enough to build a working mental model, not so much that it reads like annotated source code.

## Step 1. Assess Complexity

If the scope is ambiguous, state your interpretation and explore. The user can redirect.

- **Simple** (a single module, a small utility, a narrow question such as "how does function X work"): no explorers. One explainer explores and explains in a single pass. Go to Step 2b.
- **Complex** (a subsystem spanning multiple files or services, a cross-cutting feature, a full architectural overview): spawn parallel explorers first, then hand off to the explainer. Go to Step 2a.

When in doubt, take the simple path.

Every `model` line below names a role, not a per-call argument. Pin the role by agent name in `task.agentModelOverrides`, and give each role its own agent name when the roles need different models. The **setup-pstack** skill owns that configuration. A role with no entry runs on the parent chat model. Read-only in this skill is posture, not a sandbox. omp's task wire has no `readonly` field, and the per-item `tools` field only exposes eval-defined kernel tools to a spawn, so the wire cannot enforce a tool grant. Each brief names the tools the worker may use and forbids writes. The one per-spawn restriction omp enforces is `tools` in an agent's frontmatter, which binds to an agent definition, not a task call.

## Step 2a. Explore (complex questions only)

Decompose the question into 2 to 4 exploration angles, each a distinct slice of the subsystem. Spawn all explorers in a single message:

- `agent`: `task` (omp’s general-purpose bundled agent)
- `model`: your configured how-explorer model, pinned by agent name (defaults to your fast code model)
- read-only: the brief grants the explorer only Glob, Grep, and Read, and forbids writes

Each explorer gets the prompt in `references/explorer-prompt.md` with its angle filled in. Then go to Step 3.

## Step 2b. Direct Explain (simple questions)

Spawn one Task subagent that explores and explains in one pass:

- `agent`: `task` (omp’s general-purpose bundled agent)
- `model`: your configured how-explainer model, pinned by agent name (defaults to your prose model)
- read-only: the brief grants the explainer only Glob, Grep, and Read, and forbids writes

Build its prompt from `references/explainer-prompt.md` without the explorer-findings section. Go to Step 4.

## Step 3. Synthesize (complex questions only)

Once all explorers have returned, spawn one Task subagent to synthesize their findings into one explanation:

- `agent`: `task` (omp’s general-purpose bundled agent)
- `model`: your configured how-explainer model, pinned by agent name (defaults to your prose model)
- read-only: the brief grants the explainer only Glob, Grep, and Read, and forbids writes

Build its prompt from `references/explainer-prompt.md` with every explorer's findings filled in.

## Step 4. Present

Present the explainer's output to the user. Light edits for clarity or context from the conversation are fine. Do not substantially rewrite it.

## Output Format

The explanation uses the sections defined in `references/explainer-prompt.md`, dropping any that do not apply: Overview, Key Concepts, How It Works, Where Things Live, Gotchas.
