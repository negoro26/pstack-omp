---
name: interrogate
description: "Use for \"interrogate\", \"adversarial review\", \"multi-model review\", \"challenge this\", \"stress test this code\", \"find blind spots\", or \"tear this apart\". Multiple LLM reviewers challenge changes from independent angles."
disable-model-invocation: true
---

# Interrogate

Spawn one reviewer per configured model to adversarially review code changes. Each model gets the same prompt and rubric. The adversarial signal comes from model diversity, not assigned personas. Models differ in blind spots, priors, and reasoning patterns. Agreement across models is high-confidence signal; lone-model findings are worth reading but lower confidence.

The deliverable is a synthesized verdict. Do NOT auto-apply changes.

## Step 1, Determine Scope

Identify what to review from context:

- If the user points at specific files or a diff, use that
- If on a feature branch, run `git diff main...HEAD` (or the appropriate base branch) for the full changeset
- If the user's message references recent work, gather the relevant files

Package the diff (or file contents) plus any surrounding context files the reviewers need to understand the code.

## Step 2, State the Intent

Before spawning reviewers, state the intent explicitly. What is this code trying to accomplish? Derive this from:

- The user's message
- Commit messages
- PR description if one exists
- The code itself

Write one clear paragraph. Reviewers challenge whether the work achieves the intent well, not whether the intent itself is correct. If you're unsure about the intent, ask the user before proceeding.

## Step 3, Spawn Reviewers

Launch all reviewers in a single message using the Task tool. Use your configured `interrogate reviewers` list when present, one reviewer per entry, extending or shrinking the Reviewer A/B/C/D labels below to the configured entry count; otherwise use the table defaults.

| Subagent | Default capability |
|----------|--------------------|
| Reviewer A | your strongest judgment model |
| Reviewer B | your strongest instruction-following model |
| Reviewer C | your fast code model |
| Reviewer D | your prose model |

Model diversity is the property that makes this review worth running, so resolve it at run time from the families `omp models` lists. Give each reviewer a different model family from the other reviewers and from the parent that wrote the code. A reviewer sharing the writer's family shares the writer's blind spots, which is the one thing this skill exists to defeat.

When `omp models` reports only one model family, still spawn the full reviewer count and still run the review. Record in the verdict that the review is weaker for it, because every reviewer carries the same priors. Never fake diversity by naming two members of one family, and never drop a reviewer to avoid the note.

For each reviewer:
- `agent`: `task` (omp’s general-purpose bundled agent)
- `model`: the configured `interrogate reviewers` entry, or the table capability with no configured line, pinned by that reviewer's agent name in `task.agentModelOverrides`
- read-only: the brief grants the reviewer only Glob, Grep, and Read, and forbids writes. omp's task wire has no `readonly` field and the per-item `tools` field only exposes eval-defined kernel tools, so the grant is posture, not a sandbox

A reviewer with no override entry runs on the parent chat model, which is correct for Reviewer A and is the case where the family spread collapses. Give each reviewer that needs its own family its own thin agent file plus its own override entry. If an override entry names a model this machine cannot resolve, pick the closest equivalent from `omp models` (prefer the highest-reasoning tier of the same family), spawn with that, and open a separate PR to fix the entry. Do not block the review on it. The values `inherit-parent` and `auto` are not broken; they mean the reviewer runs on the parent chat model, so leave that reviewer out of the override map. The **setup-pstack** skill owns the configuration.

Read `references/reviewer-prompt.md` and fill in the template with:
1. The stated intent
2. The diff or file contents
3. The review rubric from `references/rubric.md`
4. The code-quality lens from `references/code-quality-review.md`

The same filled template goes to all reviewers, so every model applies the code-quality lens.

Each reviewer produces structured findings as described in the prompt template.

## Step 4, Synthesize

As results come back, build a unified picture:

1. **Parse all findings** from the reviewers
2. **Identify consensus**. Findings raised by 2+ models independently are highest signal.
3. **Identify lone-model findings**. Still worth reading, but weight accordingly.
4. **Deduplicate**. Different models may describe the same issue differently. Merge these and note which models raised it.
5. **Note disagreements**. If one model flags something and another explicitly says the opposite, that's useful context for the verdict.

## Step 5, Lead Judgment

You are the lead reviewer, a pragmatic senior engineer, not a neutral aggregator.

Read `references/lead-judgment.md` for the full framework. Reviewers only see a slice of the codebase. You have the full context (the goal, the constraints, the timeline, which tradeoffs were already considered). Use that context aggressively.

Categorize every finding using these buckets:

- **Act on**. Real issues affecting correctness, security, or maintainability given the actual goals. These would block a real PR.
- **Consider**. Legitimate points, but you're not sure they outweigh the cost of addressing them right now. Worth the user's attention.
- **Noted**. Technically valid but not actionable. Context-dependent, premature optimization, or low-impact given the current stage.
- **Dismissed**. Wrong, nitpicky, or missing context. Brief explanation why.

For each finding, include:
- Which model(s) raised it
- The category (act on / consider / noted / dismissed)
- A one-line rationale for the categorization

## Output Format

Present the verdict in this structure:

### Intent
> [The stated intent paragraph from Step 2]

### Reviewers
- Reviewer [label]: [model name], [N findings] (one bullet per reviewer)

### Act On
[Findings that should be addressed. For each: description, which models raised it, why it matters.]

### Consider
[Findings worth thinking about. For each: description, which models raised it, tradeoff involved.]

### Noted
[Valid but low-priority. Brief list.]

### Dismissed
[Rejected findings with brief rationale. This shows the user what was filtered out and why, so they can override your judgment if they disagree.]

### Agreement Map
[Where did models agree, where did they diverge, and what does the pattern of agreement/disagreement tell us?]
