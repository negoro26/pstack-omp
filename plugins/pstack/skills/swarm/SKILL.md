---
name: swarm
description: "Fan out N parallel workers, drain them, and return one report. Use for /swarm, 'swarm this', or parallel coverage, races, gauntlets, and exploration."
disable-model-invocation: true
---

# Swarm

Fan out N parallel workers. They may cover separate slices, race the same brief, or mix both. The parent waits, aggregates, and returns one report.

## Start

Open a todolist with one entry per phase before launching anything.

1. Frame
2. Fan out
3. Aggregate
4. Report

## Phase A: Frame

1. State the done predicate and the artifact or report the swarm must return.
2. Choose the shape. Partition into slices, race N workers on identical briefs, or mix both. For a race or mixed shape, declare `first pass`, `rank all`, or `best-of` before spawning.
<<<<<<< HEAD
3. Set N from the user or derive it from the shape. N is total workers. `task.maxConcurrency` in `~/.omp/agent/config.yml` caps how many of them run at once.
4. Pick the worker model through `task.agentModelOverrides` in `~/.omp/agent/config.yml`, keyed by agent name. That is the only per-spawn model lever omp exposes, because the `task` tool has no `model` field. With no override entry the worker runs on the parent's model. A model race therefore needs one thin agent file per arm, each with its own override entry.
5. Give each worker its own writable output when it writes. Use a `git worktree` or `/tmp/swarm-<slug>/worker-<n>/`. Workers share the parent's checkout, so switching branches in it is not isolation.
=======
3. Set N from the user or derive it from the shape. N is total workers, not the cloud concurrency limit.
4. Pick the worker model from `swarm workers` in `~/.cursor/rules/pstack-models.mdc` when present. Otherwise use `grok-4.6-fast-xhigh`. For a model race, name each arm's model up front.
5. Give each worker its own writable output when it writes.
>>>>>>> 73a65b3a94b88bfde798ed3a9261234d7d41c7f3

## Phase B: Fan out

Spawn all N workers in one message with `agent`: `task` (omp’s general-purpose bundled agent), one `task` call with all items in `tasks[]` (batched in parallel). Every worker already runs on this machine, in the parent's checkout. `isolated: true` requires `task.isolation.enabled: true` in `~/.omp/agent/config.yml`; omp strips the field when that is false, so do not rely on it without checking. The default is the shared checkout even with the gate open, so each brief that writes must request `isolated: true` explicitly. The parent must run from inside a git checkout, since isolated preparation builds a worktree from it, and fails fast outside one. The fallback for per-worker writable output is a per-worker `git worktree` or a `/tmp/swarm-<slug>/worker-<n>/` directory.

When a worker must start from a non-default base, create its `git worktree` on that base first and point the worker at that path.

Every brief stands alone. Include the goal, scope, exact slice or race arm, how to verify, and what to report. Reports use `PASS`, `ISSUES`, or `BLOCKED` with evidence.
End every brief with a yield-first line: tell the worker to call the yield tool with its result as data and to write no text outside that call. Thinking models default to answering in prose and skipping the call, which the harness counts as failed even when the text is right. Measured 13 of 20 without the line, 20 of 20 with it, same model, same width.
Prove every claim with a command that exits. Run the check with `hub` `op:"start"`, wait on it with a timeout, read the output with `hub` `op:"logs"`. Timeout is fail. Non-zero exit is fail. The verdict is `PASS` or `FAIL` plus the output, written where the parent reads it. No new tool is needed. `hub` plus wait already is the gate.

If a worker drops out, proceed with N-1 and note it.

## Phase C: Aggregate

Read the terminal results. For coverage, every required slice needs a result. For a race, apply the selection rule declared up front. Use first pass, rank all, or best-of. Do not paste raw worker dumps.

Keep a compact result table, one-line evidenced issues, and explicit gaps or dropouts.

## Phase D: Report

Return one consolidated in-chat report with the table, issue one-liners, gaps or dropouts, and the race rule when used.
