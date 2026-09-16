---
name: pstack-omp
description: "Translate poteto-mode roles and lifecycle protocols to the live OMP task or vibe worker surface. Use for pstack delegation, standalone briefs, panels, owners, and watchers."
---

# pstack on OMP

`skill://poteto-mode` selects the playbook, role, step order, and gates. This adapter owns dispatch mechanics. Read it before following a task-shaped instruction in any imported skill. Its live-tool mapping takes precedence over examples in imported prose. It does not weaken a playbook's verification or safety gate.

## Detect the live surface

Inspect the tools and schemas exposed in this session, not a version number or a remembered roster.

- With `task`, use the task contract below. Only pass fields actually exposed. Use `hub` operations only when their live schema exposes them.
- Without `task`, when `vibe_spawn`, `vibe_send`, `vibe_wait`, `vibe_list`, and `vibe_kill` are exposed, use the vibe contract below. Do not try to enable task or escape director restrictions.
- With neither surface, do bounded work directly only when the current mode permits it. If independent review or unavailable execution is required, report the exact missing capability. Never claim a panel ran locally as one session.

## Canonical roles

| Role | Task preference, if listed | Vibe tier | Brief posture |
|---|---|---|---|
| explorer | scout | fast | Read-only repository reconnaissance and artifact reduction. |
| watcher | scout | fast | Observe one generation and event, then finish. |
| planner | designer | good | Technical architecture and competing shapes. |
| designer | designer | good | Visual, interaction, and product design. |
| reviewer | reviewer | good | Independent code or behavioral verdict. |
| security reviewer | security-reviewer | good | Read-only security lane, separate from ordinary review. |
| researcher | librarian | fast | Source-verified external research. |
| synthesizer | reviewer | good | Adjudicate frozen evidence, not new implementation. |
| implementer | default worker | good | Bounded implementation with explicit write ownership. |
| owner | default worker | good | Retain context for one coupled workstream. |
| mechanical | sonic | fast | Fully specified low-judgment edits. |

The live roster is authoritative. Never invent missing specialists. When a preferred specialist is absent, use an available worker with the role explicitly in its brief; omit `agent` for the default worker. `poteto-agent` and `comment-sicko` are optional bundled custom agents. Use their exact names only when discovered. Otherwise include their skill/agent instructions as file pointers in an available worker's brief.

Agent selection is not model selection. `modelRoles` and `task.agentModelOverrides` are operator configuration, not task payload fields. Vibe's `fast` and `good` are runtime tiers, not model names. Claim independence of models or providers only when returned resolved-model/fallback metadata proves it. Independent contexts remain useful when only one model is available; report that limitation.

## Standalone brief

Children start blank and do not inherit the parent conversation. Every brief must contain:

- **Target:** outcome, canonical role, repository/worktree, exact writable paths, forbidden paths, and output artifact.
- **Change:** relevant source pointers, settled contract, constraints, dependencies, base SHA or generation, and decisions already made.
- **Acceptance:** observable done predicates, required evidence, allowed verification commands or an explicit root-only validation rule, report format, and stop conditions.

Common immutable material belongs in batch context or an accessible artifact. Never substitute a file pointer for the brief's goal or ownership. Tell ordinary children not to start subagents or ask the user directly. A role change requires a fresh context. A coupled correction may reuse the owner. Children report only checks actually executed; the root independently accepts or rejects the result.

## Task contract

When `tasks[]` is exposed, start all independent participants in one batch. Give each a unique name and self-contained `task`; use shared `context` shaped as Goal, Constraints, Contract when exposed. With a flat schema, start one participant per call, all before waiting. No invented batch switch.

`effort`, `isolated`, `outputSchema`, and `schemaMode` are optional only if exposed. A task item has no assumed per-call `model`, `readonly`, `apply`, or `merge`. A read-only brief is not a sandbox. Use a restricted discovered specialist when available and still state the write ban.

Give concurrent writers disjoint paths or separate worktrees. If `isolated` is exposed, inspect returned isolation metadata to learn where changes landed. Otherwise arrange explicit worktrees through available execution, or serialize a genuinely shared write. Never switch branches in a shared checkout and call that isolation.

Record returned agent and job identifiers. Results auto-deliver. Read complete output at `agent://<id>` when the runtime exposes it, and otherwise the delivered report; inspect `history://<id>` for incomplete or suspicious reports. `hub` jobs/wait uses job IDs; peer list/send uses agent IDs. Use only the live operation schema. Reuse a session only when the host reports it can be resumed. Cancel superseded jobs by exact ID; do not infer liveness from transcript timestamps.

## Vibe contract

These are documented OMP wire shapes; confirm the live schema before calling them:

- `vibe_spawn({ cli: "fast" | "good", prompt, name? })` starts a blank persistent worker. Put the canonical role and exact workspace in `prompt`; there is no task-style `agent`, `tasks[]`, `context`, or `isolated` field.
- `vibe_send({ session, message })` steers or resumes the recorded worker for a coupled phase or bounded correction.
- `vibe_wait({ sessions?, timeout? })` waits for a watched turn to settle. It is not an all-workers barrier. Account for every required participant before advancing.
- `vibe_list({})` gives current workers and resolved metadata.
- `vibe_kill({ session })` ends a superseded worker after required artifacts are durable.

Spawn independent workstreams before waiting. Use one persistent worker per coupled workstream. Workers share the configured workspace unless an explicit worktree is arranged in their briefs; do not assume isolation. Start independent verification in a separate worker after implementation artifacts freeze. A director without execution tools sends exact verification commands to that verifier, reads its evidence and touched files, and owns acceptance. It must not bypass its restricted tools to run commands itself.

Results self-deliver into the director conversation; the vibe tool schema does not guarantee an `agent://<id>` resource, so use one when the runtime returns it and otherwise read the delivered report. Transcripts, when the runtime reports them, live at `history://<id>`. Preserve the actual returned identifiers instead of constructing them from display names. Vibe sessions belong to the current owner/scope; never control another scope's worker. Restarted workers require live-state reconciliation before sending new work.

## Lifecycle protocols

### Bounded session

Start one standalone assignment, collect its complete report and artifacts, then independently verify acceptance. An in-scope correction can go to the same resumable worker. A different role or unit gets a fresh worker.

### Panel

Partition slices or candidates with distinct ownership. Start all participants before waiting, track them by identity rather than arrival order, and account for missing or canceled lanes. Freeze candidates before separate reviewers start. Freeze reviews before a separate synthesizer. The root chooses; consensus is evidence, not proof.

### Long-lived owner

Keep one worker on one coupled unit. Record its workspace and identity. Send only coupled next phases, evidence-based answers, or bounded corrections. Require a report at each acceptance boundary; independently verify before authorizing the next phase. Do not give the same branch to a sibling owner.

### One-shot watcher

Observe one branch/head/generation and one exact predicate, with stop conditions and a time limit. Return one meaningful event and finish. A changed head invalidates the report and requires a new watcher. Watchers do not fix, merge, authorize, or follow a new generation silently.

## Root ownership

The root keeps user interaction, scope, approvals, integration, external-write authorization, merges, deletion decisions, and final verification acceptance. Ordinary workers skip shared formatting, linting, and project-wide suites unless their brief explicitly assigns that verification lane. Do not race validation against unfinished sibling edits.

A new commit, rebase, conflict resolution, or applied patch requires rechecking the evidence generation. Preserve patch-id exceptions only when the Shipping playbook explicitly permits them. Report PASS, ISSUES, or BLOCKED with exact paths, generation, executed commands, results, deviations, and remaining gaps. A successful worker exit is not artifact acceptance.
