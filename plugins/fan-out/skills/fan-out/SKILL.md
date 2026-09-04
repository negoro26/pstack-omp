---
name: fan-out
description: Run many subagents in parallel on one machine (swarm, coverage matrix, race, gauntlet, N-wide sweep, "run 100 agents"). Width is `task.maxConcurrency`, default 32, unbounded at 0, applied from the next turn. Read before any wide run: covers isolation, aggregation, and the model-reliability floor that decides how wide is useful.
---

# Fan-out

Run N subagents at once, drain them, return one report. This is the local-machine equivalent of a cloud swarm: omp has every mechanical piece already, so nothing here needs new tooling.

## Pick the shape first

- **Partition.** N disjoint slices, each worker owns one. Every slice must come back or the sweep is incomplete.
- **Race.** N workers on the same brief. Declare the selection rule before spawning: `first pass`, `rank all`, or `best-of`.
- **Gauntlet.** N adversarial checks against one artifact. Retain majority survivors, not lone findings.

Mixing partition and race is fine. Say which is which in the briefs.

## Raise the ceiling

`task.maxConcurrency` defaults to **32**. It is a plain number with no min or max, so any value works; the settings UI stops at 64 but that list is presets, not a clamp. `0` means unlimited.

```bash
omp config set task.maxConcurrency 100
```

**It applies from the next turn.** A running session holds a settings snapshot, so a fan-out launched in the same turn as the `config set` still runs at the old width. Verified: a 100-item batch peaked at 32 immediately after setting 100, then at 100 one turn later.

Flat fan-out cannot deadlock. The provider semaphore brackets only the HTTP stream, so a parent waiting on children holds no provider slot. Deep spawn trees are the deadlock shape, and `task.maxRecursionDepth` (default 2) is what bounds those.

## Two ways to dispatch

**`task` tool, one call, all items in `tasks[]`.** Use when each worker is a self-contained assignment and you want the results delivered as they settle. Set `isolated: true` per item when workers write files: each gets a copy-on-write worktree, merged back by patch, with conflicts parked rather than clobbered.

**`eval` with `parallel()`.** Use when the fan-out is computed, needs a barrier (`pipeline()`), or feeds results into more code. The pool tracks `task.maxConcurrency` live.

```python
def slice_and_verify(s):
    found = agent(s["brief"], agent="scout", label=f"find:{s['id']}", schema=FINDINGS)
    return parallel([lambda f=f: agent(f"Refute if you can: {f['title']}",
                                       schema=VERDICT) for f in found["findings"]])
results = parallel([lambda s=s: slice_and_verify(s) for s in SLICES])
```

Wrap each per-item chain in one function and `parallel()` the functions, so a slow worker never blocks its siblings. Wrap risky workers in `try/except` and proceed with N-1, noting the dropout.

## The real ceiling is your model, not the harness

Measured on this machine, 100 subagents in one `parallel()` call: **92/100 succeeded, 343s wall, 23x speedup over serial**, per-agent p50 67s and max 254s.

Failures were **not** load-induced. Same task at lower width:

| Width | Agent | Success |
|---|---|---|
| 100 | sonic | 92/100 |
| 20 | sonic | 16/20 |
| 8 | sonic | 6/8 |
| 8 | task | 6/8 |
| 8 | scout | 8/8 |

Lower concurrency did worse, so contention was not the cause. The successful outputs show it: a weak local model improvises the structured-output envelope, returning `{"result": …}` or `{"status": "done", "reply": …}` instead of the requested shape. Roughly one in five schema-bound subagents fails its contract.

Consequences for planning a wide run:

- **Budget for a failure rate.** Treat 5-20% worker loss as normal on a weak model. A partition sweep must re-dispatch missing slices; a race can absorb the loss.
- **Width buys throughput, not latency.** One local endpoint serving 100 streams queues. If a single answer must be fast, do not fan out.
- **Match agent to reliability.** Looser output contracts survive weak models. Put schema-bound or judgment work on a stronger model via `task.agentModelOverrides`.

## Aggregate

Read the terminal results yourself and write your own summary. Never paste raw worker dumps. For a partition, confirm every slice returned. For a race, apply the rule you declared up front. For a gauntlet, keep findings that survived a majority of skeptics, and verify each survivor against the source before acting on it.

Workers do the legwork. The correctness of the conclusion is yours.
