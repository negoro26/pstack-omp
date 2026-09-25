---
name: omp-mechanics
description: The pstack-specific OMP amendments that sit outside live worker dispatch. Read it after `skill://poteto-mode`; use `skill://pstack-omp` for task, vibe, eval, and runtime mechanics.
disable-model-invocation: true
---

# OMP mechanics

`skill://pstack-omp` is the sole live task, vibe, eval, and runtime contract. Read it before dispatch. This skill keeps only the OMP amendments that belong to specific pstack workflows. It does not restate wire fields, batch shapes, result resources, or process lifecycle.

## Review workflows

The `architect`, `arena`, `interrogate`, and `reflect` workflows need independent contexts. Resolve their canonical roles through `skill://pstack-omp`. Prefer configured model-family diversity when the roster and operator policy provide it, and record the resolved model or fallback evidence. If only one family is available, keep the independent contexts and report weaker diversity. If independent execution is unavailable, report the blocked gate.

## LSP and debugging

For `bug-fix`, use `lsp` action `definition` and `references` to narrow a suspect value before runtime evidence. The parent owns this step when `task.enableLsp` is off.

When program state is unclear, use the `debug` tool before custom logging. With `debug.enabled` on, launch the reproduction, set a breakpoint, step with `step_over` and `step_in`, and read state with `evaluate`. Fall back to logging only when the tool or adapter is unavailable.

## Feature and refactoring

For `feature`, run the project's typecheck and lint lane with `lsp` action `diagnostics` when the server is live. Name concrete files or a capped glob. A server failure is not proof of a clean result. Without LSP, use the project's own checks.

For `refactoring`, use `lsp` action `references` for a rename inventory and action `rename` for the edit. Use action `rename_file` for a module move, then action `diagnostics` on the named files. Search prose and string literals separately. Without LSP, use a project-wide symbol search.

## Multi-phase plans

Resolve the installed `poteto-mode` skill directory for `scripts/check-plan.mjs`; do not assume a global package path. The control-surface line points to `skill://pstack-omp` and the live eval surface.

## Make Bot UI

Read `references/make-bot-ui-on-omp.md` before starting. The upstream Grok Bot webhook routine has no OMP equivalent, so do not create one.

## TypeScript

OMP does not auto-attach a skill from `globs`. Read `skill://typescript-best-practices` before editing a `.ts` or `.tsx` file.

## Setup pstack

Read `references/setup-pstack-config.md` for the file shape. The `setup-pstack` skill owns discovery and selection. Use `omp models --json` for each selected model's effort list, and preserve unrelated config entries.

## Session store

Before `recall`, `reflect`, `eval`, `session-pickup`, `show-me-your-work`, or `automate-me` reads transcripts, read `references/session-store-on-omp.md`. It owns root resolution, workspace bucket encoding, and the live history format.

## Upstream text that does not apply

- `poteto-mode` and `babysit` warn against Cursor's built-in `babysit` skill. OMP has no such skill, so the warning is inert.
- `bugbot-triage` still applies to OMP's security reviewer and other review comments.
- `make-bot-ui` names `api2.cursor.sh` and the Grok Bot routine panel. Neither maps to OMP.
- `worktree-cleanup` names macOS application-support paths. Keep the OMP-neutral cleanup steps and skip that platform-only step.
- `orchestrate` names Graphite (`gt`). Prefer the active forge client and do not require `gt`.
