### Perf issue

**You own the measurement story. Plan, review, verify the numbers.** Tie every fix to a measurement, don't read source instead of measuring.

1. Capture a baseline trace via the matching control skill. Vet the baseline, and each later number, with the **benchmark-checklist** skill.
2. `how` to ground hypotheses. Don't claim a perf ceiling without running it first.
   Try the performance mantras in order, cheapest first:
   1. Don't do it. Stop work whose result nothing uses rather than cheapening it.
   2. Do it, but don't do it again.
   3. Do it less.
   4. Do it later.
   5. Do it when they're not looking.
   6. Do it concurrently.
   7. Do it cheaper.

   When an earlier mantra meets the target, stop.
3. Plan the fix from the trace. If it crosses a function boundary, `architect` first. Delegate implementation to exact discovered writable implementer agents whose frontmatter or `task.agentModelOverrides[<exact-name>]` selects each model. The task item has no `model` field. Prefer distinct configured model families only when the operator's model policy and roster supply them; otherwise keep the exact agents and report weaker model diversity. Use the reasoning and speed already selected by agent frontmatter or exact `task.agentModelOverrides` entries. Do not change operator configuration to satisfy a skill example.
   Apply the **sequence-verifiable-units** principle skill, verifying each attempt before trying the next.
4. Parse and compare the artifacts (JSON to sqlite, diff). "Inconclusive" or wrong-surface is not a pass. Flag it.
5. Cite the measurement in the PR.
6. Run **Opening a PR**.

For sustained improvement against a metric rather than a one-off fix, use the Hillclimb playbook (`playbooks/hillclimb.md`).

**Reply:** baseline number, post-fix number, delta, artifact path.
