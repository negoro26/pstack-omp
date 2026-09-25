# The substitution table, executable. Run as `sed -E -i -f omp-port/rules.sed <file>` on every
# text file of an upstream `pstack/{skills,agents}` export. Port-only file, never upstream.
#
# One rule per line, ordered, each with a `#` comment naming the Cursor mechanic and the omp
# mechanic it maps to. This file replaces PORTING.md's substitution table: the table is here now.
# Order is load-bearing in three places, each marked below.
#
# Owned prose lives in the three skill paths named by omp-port/owned.txt. Script changes live in
# omp-port/patches. Neither belongs here.

## 1. Whole-sentence rewrites, which must read raw upstream text before any token rule edits it.

# Cursor's reasoning-effort ladder over its own slug names -> a selector omp models reports.
s#So `small` turns `claude-[a-z0-9.-]+` into `claude-[a-z0-9.-]+`, and `grok-[a-z0-9.-]+` into `[a-z0-9.-]+` when only that form is detected\.#So `small` takes the lowest-effort selector in the same family that `omp models` reports, and marks the role as needing a choice when that family offers none.#
# Cursor names the judgment slug twice in one clause; omp names the capability once.
s#go to your strongest judgment model \(`claude-[a-z0-9.-]+`\)#go to your strongest judgment model#
# Cursor reads the playbook from trunk because it is vendored there; omp reads the install.
s#Read these from trunk at program start\. Re-read them at every tick\.#Read these at program start and re-read them at every tick. The install on disk is authoritative, not a remote ref.#
# Router prose that used Cursor's local links or per-call model paragraph.
s#Prototype playbook \(`playbooks/prototype\.md`\)#Prototype playbook (`skill://poteto-mode/playbooks/prototype.md`)#
s#\*\*Babysit\*\* playbook \(`playbooks/babysit\.md`\)#**Babysit** playbook (`skill://poteto-mode/playbooks/babysit.md`)#
s#\*\*Shipping\*\* playbook \(`playbooks/shipping\.md`\)#**Shipping** playbook (`skill://poteto-mode/playbooks/shipping.md`)#
s#`references/bugbot-triage\.md`#`skill://poteto-mode/references/bugbot-triage.md`#
s#^\*\*Use `subagent_type: "poteto-agent"` for any subagent you spawn inside a playbook step\*\*.*$#`poteto-mode` selects the playbook, step order, canonical role, and lifecycle protocol. `skill://pstack-omp` is authoritative for every delegation instruction in this catalog, including imported task-shaped examples. Resolve roles against the live roster; bundled agent names are optional, never mandatory. Only pass fields exposed by the current tool schema.#
s#^\*\*Defaults for every `Task` call\.\*\* `run_in_background: true`.*Prose and judgment read `judgment and prose`\.$#Batch genuinely independent work when supported. Give each participant a standalone brief and explicit write ownership. The root starts additional participants and independent reviewers; ordinary workers do not start children. Runtime role configuration selects models. Preserve required independent contexts and report unavailable model diversity honestly. Do not change operator configuration merely to satisfy a skill example.\n\nModel selection belongs to `task.agentModelOverrides` and agent frontmatter, not to routed-skill task fields.#
# Autonomous run's exact post-Cursor workflow.
s#^\*\*You own the exit condition\. Define done, then drive to it without stopping\.\*\*$#**You own the exit condition. Define done, then drive to it without stopping.** For "going to bed", "run until done", or "continue until X".#
s#^1\. State the exit condition as a checkable predicate before the first iteration \(tests green, repro fixed, all N PRs merged, pixel-diff zero\)\.$#1. State the exit condition as a checkable predicate before the first iteration (tests green, repro fixed, all N PRs merged, pixel-diff zero). A vague goal stalls; a predicate lets you stop.#
s#^4\. Mid-run discoveries are yours\..*Keep the predicate as the main drive, and return to it after each side fix\.$#4. Mid-run discoveries are yours. Address broken skills, related bugs, flaky verifiers, review noise, tooling failures, orphaned follow-ups, and fixable drift yourself via poteto-mode. Put out-of-band fixes in their own PR. Do not park reversible work for the human or open a user question. Surface only irreversible actions, genuine product or preference calls no experiment can settle, or a real dead end. Keep the predicate as the main drive, and return to it after each side fix.#
s#^5\. Checkpoint every iteration via the \*\*show-me-your-work\*\* skill, a row for what changed and whether the predicate moved\.$#5. Checkpoint every iteration via the **show-me-your-work** skill, a row for what changed and whether the predicate moved. A run with no trail can't be audited or resumed.#
# Cursor's model paragraph -> exact discovered agents and runtime-selected models.
s#Each spawn below names a role line in the `pstack-models\.mdc` rule and a default\. Set `model` to that line's value, or to the default if the rule or the line is missing\. Leave `model` unset when the value is `auto` or `inherit-parent`\. If the Task tool rejects a slug, use the default and say so\. If it rejects the default, use the closest valid slug of the same family from its error message\.#Resolve exact discovered agent names for these roles. Each agent's frontmatter or `task.agentModelOverrides[<exact-name>]` selects its model; the task item has no `model` field.#
s#Resolve exact discovered agent names for these roles\.#Resolve agents against the live roster. Use an exact preferred agent only when it is present; otherwise follow the workflow's default-worker fallback.#
# Exact role bullets carry the agent choice. No broad Markdown token rule is needed.
s#^- `model`: the `how explorer` line, default `[^`]+`$#- `agent`: an exact discovered scout for repository-only exploration#
s#^- `model`: the `how explainer` line, default `[^`]+`$#- `agent`: an exact discovered explainer only when the live roster has one; otherwise omit `agent` for the default worker. Use the explainer and read-only brief in both cases. An override cannot create an agent.#
s#^- `model`: the `why investigators` line, default `[^`]+`$#- `agent`: an exact discovered full-access worker for every MCP-backed lane. The strict `scout` definition has no MCP grant, so never assign MCP work to it. A repository-only lane may use `scout` only when its file-only grant covers the evidence. Use another discovered worker when the lane needs `git`, `gh`, or other shell tools.#
s#^- `model`: the `why synthesizer` line, default `[^`]+`$#- `agent`: an exact discovered full-access worker for citation spot-checks that call MCP. The strict `scout` definition cannot serve that lane.#
# Cursor role-model defaults do not name loaded agents on omp.
s#Delegate implementation to a subagent using your configured bug-fix model \(default `[^`]+`\) with a specific scope\.#Delegate implementation to exact discovered writable implementer agents whose frontmatter or `task.agentModelOverrides[<exact-name>]` selects each model. The task item has no `model` field. Prefer distinct configured model families only when the operator's model policy and roster supply them; otherwise keep the exact agents and report weaker model diversity, with a specific scope.#
s#Delegate code-writing to a subagent using your configured feature model \(default `[^`]+`\) with a specific scope#Delegate code-writing to exact discovered writable implementer agents whose frontmatter or `task.agentModelOverrides[<exact-name>]` selects each model. The task item has no `model` field. Prefer distinct configured model families only when the operator's model policy and roster supply them; otherwise keep the exact agents and report weaker model diversity, with a specific scope#
s#Hand the change to a subagent using your configured hillclimb model \(default `[^`]+`\) with a tight scope\.#Hand the change to exact discovered writable implementer agents whose frontmatter or `task.agentModelOverrides[<exact-name>]` selects each model. The task item has no `model` field. Prefer distinct configured model families only when the operator's model policy and roster supply them; otherwise keep the exact agents and report weaker model diversity, with a tight scope.#
s#Delegate implementation to a subagent using your configured perf-issue model \(default `[^`]+`\)\.#Delegate implementation to exact discovered writable implementer agents whose frontmatter or `task.agentModelOverrides[<exact-name>]` selects each model. The task item has no `model` field. Prefer distinct configured model families only when the operator's model policy and roster supply them; otherwise keep the exact agents and report weaker model diversity.#
s#Delegate the mechanical edits to a subagent using your configured refactoring model \(default `[^`]+`\) with a specific scope#Delegate the mechanical edits to exact discovered writable implementer agents whose frontmatter or `task.agentModelOverrides[<exact-name>]` selects each model. The task item has no `model` field. Prefer distinct configured model families only when the operator's model policy and roster supply them; otherwise keep the exact agents and report weaker model diversity, with a specific scope#
# These exact task fields have no omp wire equivalent. The role bullet above is the agent choice.
/^- `subagent_type`: `generalPurpose`$/d
s#^- `readonly`: `true`$#- read-only posture. The brief grants only the tools the discovered agent actually has and forbids writes#
s#^- `readonly`: `false` \(agent mode\)\. \*\*Do not use readonly/Ask mode\.\*\* It strips MCP access, which disables MCP-backed investigators entirely\. Investigators still shouldn't write anything\.$#- read-only posture. The brief grants only the tools the discovered agent actually has and forbids file writes, git state changes, commits, pushes, pull requests, and external mutations#
s#^- `readonly`: `false` \(agent mode\)\. The synthesizer's quality check spot-verifies citations, which can require MCP access\. Readonly/Ask mode strips MCPs and defeats that\.$##
s#Work like a careful, cautious, precise investigator\.#Work like a careful, cautious, precise investigator. This investigation is read-only: do not write files, change git state, commit, push, open pull requests, or mutate any external system. Use only read-only operations exposed by your agent and assigned source.#
# One-item calls still use the live batch shape and required shared context.
s#Spawn one Task subagent that explores and explains in one pass:#Start one direct explainer in one `task` call with one item in `tasks[]` and the required shared `context`:#
s#Once all explorers have returned, spawn one Task subagent to synthesize their findings into one explanation:#After all explorers have returned, start the synthesis in one `task` call with one item in `tasks[]` and the required shared `context`, using Step 2b's explainer routing:#
s#Spawn one synthesizer subagent:#Start one synthesizer in one `task` call with one item in `tasks[]`, the required shared `context`, and an exact discovered full-access worker:#
s#Spawn all explorers in a single message:#Spawn all explorers in one `task` call with the required shared `context` and all items in `tasks[]`:#
s#Launch all matching investigators in a single message so they run concurrently\.#Launch all matching investigators in one `task` call with the required shared `context` and all items in `tasks[]` so they run concurrently.#
s#^Launch all reviewers in a single message using the Task tool\. Use the `interrogate reviewers` line in `~/\.cursor/rules/pstack-models\.mdc`, one reviewer per entry, extending or shrinking the Reviewer A/B/C labels below to the configured entry count\. If the rule or that line is missing, use the table defaults\.$#Launch all reviewers in one `task` call with the required shared `context` and all items in `tasks[]`. Resolve exact discovered reviewer agent names, use one agent per reviewer slot, and report when the live roster cannot provide the requested model-family diversity.#
# Cursor's per-reviewer opening becomes one reviewed batch.
s#^Spawn one reviewer per configured model to adversarially review code changes\. Each model gets the same prompt and rubric\.#Use exact discovered reviewer agents, one per configured family, in one `task` call with all items in `tasks[]` and the required shared `context`. Each reviewer gets the same prompt and rubric.#
s#Spawn all N subagents in one message with `run_in_background: true`, each with the task, the path to the shared grounding, its own output path, and instructions to produce both the artifact and a short rationale\.#Spawn all N subagents in one `task` call with all items in `tasks[]` and the required shared `context`, each with the task, the path to the shared grounding, its own output path, and instructions to produce both the artifact and a short rationale.#
s#Spawn all N workers in one message with `subagent_type: generalPurpose`, `environment: "cloud"`, `run_in_background: true`, and the step 4 model, left unset for `auto` or `inherit-parent`\. Use `environment: "local"` only when the worker needs access to something on the user's computer\.#Start all N workers in one `task` call. Put every item in `tasks[]` and pass the required shared `context`; set `isolated: true` only when the live task schema exposes it and the runtime's isolation settings allow it. Otherwise give each writer an explicit separate worktree or output directory.#
s#One message, three `Task` calls, `subagent_type: generalPurpose`, (explicit `model:` on each|with `model` set as below), agent mode \(`readonly: false`\)\.#One `task` call with three items in `tasks[]` and one required shared `context`, each item using an exact discovered agent name. Full tools per spawn. Run the three lenses on three different configured model families where available, and keep Divergent on a different model family from Judgment, since the lens earns its name from different priors and not a different prompt. Reviewers need full tools for MCP lookups (tickets, chat threads, observability traces referenced in the transcript); there is no task `readonly` field.#
s#Each reviewer and the synthesizer name a role line in the `pstack-models\.mdc` rule and a default\. Set `model` to that line's value, or to the default if the rule or the line is missing\. Leave `model` unset when the value is `auto` or `inherit-parent`\. If the Task tool rejects a slug, use the default and say so\. If it rejects the default, use the closest valid slug of the same family from its error message\.#Resolve exact discovered agent names for the three lenses and the synthesizer. Each agent's frontmatter or `task.agentModelOverrides[<exact-name>]` selects the model; the task item has no `model` field.#
s#One `Task` call, `subagent_type: generalPurpose`, with `model` from the `reflect judgment, divergent, synthesizer` line \(default `[^`]+`\), agent mode \(`readonly: false`\)\.#One `task` call with one item in `tasks[]`, the required shared `context`, and an exact discovered synthesizer agent name. Its frontmatter or `task.agentModelOverrides[<exact-name>]` selects the model; the task item has no `model` field. The synthesizer needs full tools for citation spot-checks; there is no task `readonly` field.#
# Remove the old MCP-mode claims left after the task-call rewrite.
s#Reviewers need MCP access for context lookups \(tickets, chat threads, observability traces referenced in the transcript\)\. Readonly strips MCPs\.##
s#The synthesizer's quality check includes spot-verifying citations, which can require MCP access\. Readonly strips MCPs\.##
s#there is no task `readonly` field\.  Use#there is no task `readonly` field. Use#
s#there is no task `readonly` field\.[[:space:]]*$#there is no task `readonly` field.#
s#\| Lens \| Role line \| Default `model` \| Prompt template \|#| Lens | Exact agent | Prompt template |#
s#^\| Judgment \| `reflect judgment, divergent, synthesizer` \| `[^`]+` \| `references/judgment-reviewer\.md` \|$#| Judgment | discovered judgment agent | `references/judgment-reviewer.md` |#
s#^\| Tooling \| `reflect tooling` \| `[^`]+` \| `references/tooling-reviewer\.md` \|$#| Tooling | discovered tooling agent | `references/tooling-reviewer.md` |#
s#^\| Divergent \| `reflect judgment, divergent, synthesizer` \| `[^`]+` \| `references/divergent-reviewer\.md` \|$#| Divergent | discovered divergent agent | `references/divergent-reviewer.md` |#
s#The synthesizer returns a structured Accepted / Rejected / Backlog list\.#Pass this explicit `outputSchema` when the live task schema exposes it:\n\n```json\n{"type":"object","required":["Accepted","Rejected","Backlog"],"properties":{"Accepted":{"type":"array","items":{"type":"object","required":["Problem","Proposal","Routing"],"properties":{"Problem":{"type":"string"},"Proposal":{"type":"string"},"Routing":{"type":"string"}}}},"Rejected":{"type":"array","items":{"type":"object","required":["Principle","Reason"],"properties":{"Principle":{"type":"string"},"Reason":{"type":"string"}}}},"Backlog":{"type":"array","items":{"type":"object","required":["Pattern","Hit","Mechanism"],"properties":{"Pattern":{"type":"string"},"Hit":{"type":"string"},"Mechanism":{"type":"string"}}}}}}\n```#
# These model-map sentences must match raw upstream before slug and path token rewrites.
s#^Take the runners from the `architect runners` line in the `pstack-models\.mdc` rule, in place of the `arena runners` line\. If the rule or that line is missing, use `claude-opus-[^`]+`, `gpt-[^`]+`, `grok-[^`]+`\. Alias and rejected entries follow the runner rules in the \*\*arena\*\* skill's Phase A\.$#Use the same exact discovered runner agents as Arena, with the architect role in each brief. Each agent's frontmatter or `task.agentModelOverrides[<exact-name>]` selects its model; the task item has no `model` field.#
s#^3\. Pick the runners\. Use the `arena runners` line in `~/\.cursor/rules/pstack-models\.mdc`\. If the rule or that line is missing, default to one each on `claude-opus-[^`]+`, `gpt-[^`]+`, `grok-[^`]+`\. An `auto` or `inherit-parent` entry in this line or the cross-judge line means the parent model, so omit `model` for it\. If the Task tool rejects a configured entry, run that seat on its family's default and say so\. Families go by prefix: `claude-\*`, `gpt-\*`, and `grok-\*`\. With no family match, use `claude-opus-[^`]+`\. If it rejects a default, use the closest valid slug of the same family from its error message\.#3. Pick the runners. Resolve exact discovered agent names and inspect each agent's frontmatter or `task.agentModelOverrides[<exact-name>]`. Prefer distinct configured model families when the roster supplies them; otherwise keep the independent contexts and report weaker model diversity. A model override cannot create an agent.#
s#After all Phase B candidates complete, choose one model from the `arena cross-judge pool` line in `~/.cursor/rules/pstack-models\.mdc`\. If the rule or that line is missing, choose from `claude-opus-[^`]+`, `gpt-[^`]+`, `grok-[^`]+`\. Prefer a different model family from the parent's\.#After all Phase B candidates complete, choose an exact discovered judge agent whose configured model differs from the parent's when the roster provides one.#
# The judge is one task item, with posture in its brief rather than a task field.
s#After all Phase B candidates complete, choose an exact discovered judge agent whose configured model differs from the parent's when the roster provides one\. Spawn one readonly judge subagent on that model\.#After all Phase B candidates complete, choose an exact discovered judge agent. Start the judge in one `task` call with one item in `tasks[]`, the required shared `context`, and that exact agent name. Its frontmatter or `task.agentModelOverrides[<exact-name>]` selects the model; the task item has no `model` field. The brief carries read-only posture, grants only the tools that discovered agent actually has, forbids writes, and has no task `readonly` field. Prefer a different configured model family when the operator's model policy and roster supply one; otherwise keep the exact agent and report weaker model diversity.#
s#^- `model`: the configured `interrogate reviewers` entry, or the table default with no configured line\. For an `auto` or `inherit-parent` entry, omit `model` so that reviewer runs on the parent model\.$#- `agent`: an exact discovered reviewer agent name. Its frontmatter or `task.agentModelOverrides[<exact-name>]` selects the model; the task item has no `model` field#
s#If the Task tool rejects a configured entry, run that reviewer on the table default of its family and say so\. Families go by prefix: `claude-\*`, `gpt-\*`, and `grok-\*`\. With no family match, use Reviewer A's default\. If it rejects a table default, check the valid slugs in the Task tool's error message, pick the closest equivalent \(prefer the highest-reasoning tier of the same family\), spawn with it, and open a separate PR to update the default table\. Do not block the review on the slug issue\. Never treat an alias entry as a rejected slug or apply either fallback to it\.#If the requested exact reviewer is absent, use another discovered reviewer with the same brief and report the missing model diversity. A model override cannot create an agent.#
s#^4\. Pick the worker model from the `swarm workers` line in `~/\.cursor/rules/pstack-models\.mdc`\. If the rule or that line is missing, use `grok-[^`]+`\. For `auto` or `inherit-parent`, omit `model` so the workers run on the parent model\. If the Task tool rejects a slug, use the default and say so\. If it rejects the default, use the closest valid slug of the same family from its error message\. For a model race, name each arm's model up front\.#4. Pick exact discovered agent names. Inspect each agent's frontmatter or `task.agentModelOverrides[<exact-name>]` for its model. A model race needs one loaded agent file and one exact override entry per arm; overrides cannot create agents.#
# Inline selectors that survive into patch context are exact values, not a Markdown catch-all.
s#`subagent_type: "poteto-agent"`#`agent`: `poteto-agent`#g
s#Shape: one or two questions with 4-6 options each, `allow_multiple: true` for category questions\.#Shape: one or two questions with 4-6 options each. Put `multi: true` on each category question object.#
s#^1\. Spawn `Task` with `subagent_type: "Comment Sicko"`\.#1. Spawn one `task` call with one item in `tasks[]` and the required shared `context`. Use the exact discovered `comment-sicko` agent when present; otherwise omit `agent` for the default worker. Resolve the loaded `skill://no-comments` path to its plugin root and put the comment-reviewer role plus the absolute `<plugin-root>/agents/comment-sicko.md` file pointer in its brief.#
# Plan lanes and the checker name an exact discovered worker agent, never a model-map role label.
s#per the \*\*swarm\*\* skill, on the `swarm workers` model \(default `grok-[^`]+`\)#per the **swarm** skill, using exact discovered worker agents. Inspect each agent's frontmatter or `task.agentModelOverrides[<exact-name>]` for its model#
s#<swarm workers model>#<exact discovered worker agent name>#g
s#with the model filled in#with the exact discovered agent name filled in#g
# Cursor's per-item pseudo-spawns become real batches or one-item calls.
s#^2\. \*\*Source wave\.\*\* One read-only subagent per feature file, launched concurrently\.#2. **Source wave.** Start one source-review batch in one `task` call with one item per feature file in `tasks[]`, the required shared `context`, and an exact discovered read-only reviewer agent for each item.#
s#^Spawn one investigator per category that has a matching MCP\.#Assign one investigator to each category that has a matching MCP.#
s#An event to watch \(CI, a merge, a ref advancing\) gets a watcher subagent that wakes you on the event,#For an event to watch (CI, a merge, a ref advancing), start one watcher in one `task` call with one item in `tasks[]`, the required shared `context`, and an exact discovered watcher agent; omit `agent` for the default worker with the watcher role when no specialist is discovered. It wakes you on the event,#
s#^- \[ \] Spawn one owner per PR with the full lifecycle the execution playbook names\.#- [ ] Start all owners in one `task` call with all items in `tasks[]`, the required shared `context`, and one exact discovered owner agent per independent PR; omit `agent` for the default worker with the owner role when no specialist is discovered. Give each owner the full lifecycle the execution playbook names.#
s#One subagent per PR, not batched, each a Cursor cloud agent, each exercising the real surface#Start all PR verifiers in one `task` call with all items in `tasks[]` and the required shared `context`; each item uses an exact discovered reviewer agent, or omits `agent` for the default worker with the reviewer role, and requests an isolated subagent. Each verifier exercises the real surface#

## 2. Model slugs. Tiered by capability first, then a catch-all for anything upstream adds later.

# Cursor's strongest reasoning slug -> the judgment capability the operator binds.
s#`claude-fable-[0-9.-]+(-(thinking-)?[a-z]+)?`#your strongest judgment model#g
# Cursor's second reasoning family -> the same judgment capability.
s#`claude-opus-[0-9.-]+(-(thinking-)?[a-z]+)?`#your strongest judgment model#g
# Cursor's instruction-following slug -> the instruction-following capability.
s#`gpt-[0-9.]+-sol-[a-z]+`#your strongest instruction-following model#g
# Cursor's fast coding slug, with or without an effort suffix -> the fast code capability.
s#`grok-[0-9.]+-([a-z]+-)?fast(-[a-z]+)?`#your fast code model#g
# The same family under Cursor's provider prefix, effort token in the middle.
s#`cursor-grok-[0-9.]+-([a-z]+-)?fast`#your fast code model#g
# The same tiers where the rule-file example writes a role value with no backticks. Anchored to
# the end of a `<role>: <slug>` line, which is the only place upstream writes a bare slug.
s#: claude-(fable|opus)-[0-9.-]+(-(thinking-)?[a-z]+)?$#: your strongest judgment model#
s#: gpt-[0-9.]+-sol-[a-z]+$#: your strongest instruction-following model#
s#: grok-[0-9.]+-([a-z]+-)?fast(-[a-z]+)?$#: your fast code model#
# Catch-all for a slug no tier above knows. Two hyphen groups required, so an illustrative
# `gpt-4` rename example is not a prescription and survives. omp-port reports what this rewrote.
s#`(claude|gpt|grok|gemini|opus)-[a-z0-9.]+-[a-z0-9.-]+`#your configured model for this role#g

## 3. Remaining exact task text and generated frontmatter.

# Cursor's Task-spawn slug enumeration and hypothetical models API -> `omp models`.
s#Enumerate the model slugs you can pass to a `Task` subagent in this session\. That is the dependable source\. If Cursor also exposes a models API or CLI that lists the user's entitled models, prefer it for completeness\.#Run `omp models` to list the models configured on this machine. That is the dependable source.#
# Cursor's blocking watch mode has the same liveness hazard without naming another runtime primitive.
s#Reaching for `drive` inside a phase agent stops that agent finishing its turn\.#Blocking inside a phase agent stops that agent finishing its turn.#
# These exact Cursor tool tokens survive only in otherwise rewritten sentences.
s#AskQuestion#ask#g
s#Substituting `generalPurpose` skips that read and drifts\.#Substituting `task` (omp's general-purpose bundled agent) skips that read and drifts.#
# Cursor agent frontmatter `is_background` -> omp does not model it.
/^is_background: true$/d
# omp gates nested spawning per agent definition, which Cursor has no counterpart for.
/^name: poteto-agent$/a spawns: "*"
# The router and its agent must name the omp levers file themselves, not only the pin reminder,
# so an unpinned read of skill://poteto-mode or a spawned poteto-agent still finds it.
s|^## Non-negotiables$|## Non-negotiables\n\n**Read `skill://omp-mechanics` and `skill://pstack-omp` right after this file.** `pstack-omp` is the sole live task, vibe, eval, and runtime contract. `omp-mechanics` keeps only pstack-specific OMP deltas.|
s#Reads the `poteto-mode` skill's `SKILL.md` in full before any work, including its inline Principles index\.#Reads the `poteto-mode` skill's `SKILL.md` in full before any work, including its inline Principles index, then `skill://omp-mechanics`.#
# Cursor derives a mode skill's registry name from a display title; omp uses the slug.
s#name: Poteto Mode#name: poteto-mode#

## 4. Cloud agents. Cursor runs them on its own VMs; omp runs isolated subagents on this machine.

s#`environment: "cloud"`#`isolated: true`#g
s#the full Task schema including `environment`#the full Task schema including `isolated`#g
# `cloud_base_branch` is not accepted by omp's task tool; a worktree on that base is the answer.
s#When a worker must start from a non-default pushed branch, pass `cloud_base_branch`\.#When a worker must start from a non-default base, create its `git worktree` on that base first and point the worker at that path.#
s#One Cursor cloud agent#One isolated subagent (`isolated: true`)#g
s#each a Cursor cloud agent#an isolated subagent (`isolated: true`)#g
s#Cloud agents cannot read the local store, so their briefs inline what they need or point at repo paths\.#An isolated worker runs on this machine in its own worktree with no conversation history, so its brief inlines what it needs or points at absolute paths.#
# Cursor's cloud dashboard -> `hub`, omp's live agent and job roster.
s#the cloud agent's status in the Cursor dashboard#agent state from `hub` `op: "list"` and `hub` `op: "jobs"`#
# Cursor's cloud PR tooling defaults to draft; omp's github tool defaults to ready.
s#Cloud-agent PR tools default to draft, so set `draft: false` on every PR creation call\.#omp's `github` tool opens a ready PR from `op: "pr_create"` unless you pass `draft: true`, so leave that flag off.#
s#Each live lane runs on its own cloud VM at the PR head\.#Each live lane runs in its own subagent at the PR head, asking for a private worktree with `isolated: true`.#
s#Fan out N parallel cloud workers\.#Fan out N parallel workers.#
s#N is total workers, not the cloud concurrency limit\.#N is total workers. `task.maxConcurrency` in `~/.omp/agent/config.yml` caps how many run at once.#
# Cursor hands out a cloud-agent URL; omp's prior-run handles are internal URIs.
s#cloud-agent URL#prior agent's `history://<id>` or `agent://<id>`#g
# Cursor's local-versus-cloud split -> shared parent checkout versus a private worktree.
s#cloud spawns#isolated spawns#g
s#its spawn budget with the cloud default and the local exception list#its spawn budget with the isolated default and the shared-checkout exception list#
s#Restacks run in cloud\. A local restack at this scale takes the laptop down\.#Restacks run in an isolated subagent with its own worktree, never in the parent checkout.#
s#After a Cursor restart: local agents are dead, cloud work is not\.#An omp restart stops every agent. Resuming the session rebuilds its subagents as parked rows that `hub` `op: "send"` revives, except isolated ones, which leave only a `history://<id>` transcript.#
s#reattach cloud work by PR and branch rather than agent id#reattach pushed work by PR and branch rather than agent id#
s#a Cursor restart#an omp restart#g
s#cloud agent#isolated subagent#g
s#Cloud agent#Isolated subagent#g

## 5. Wake mechanisms. Cursor's `/loop` builtin and cloud sleeper -> omp's `/loop`, named bash processes, and systemd.

s#Drive a long or stubborn hunt with Cursor's `/loop` command\.#Drive a long or stubborn hunt with omp's `/loop`, which re-submits the same prompt after every yield. State the exit condition as a shell command and pass it as `--until '<cmd>'`, which gates each iteration on that command's exit status.#
s#Pick the wake mechanism using Cursor's `/loop` command \(a built-in, not a pstack skill\)\.#Pick the wake mechanism. In session, omp's `/loop [count|duration] [--while|--until '<cmd>'] [prompt]` re-submits the same prompt after every yield and gates each iteration on a shell command's exit status. A wake that must land out of session runs as a named bash process observed through `proc://`, or under a systemd user timer.#
s#A local root arms each tick as a real terminal `/loop`\. The loop uses a monitored-shell 30-minute sleep and emits an output-notification sentinel\.#A root in session arms each tick with omp's `/loop`, which re-submits the tick prompt after every yield.#
s#A cloud root uses the existing cloud-sleeper wake chain instead\.#A wake that has to land out of session runs as a named bash process observed through `proc://`, or under a systemd user timer instead.#
s#In a local session, a real terminal `/loop`\. In a cloud root, a cloud-sleeper wake chain\.#In session, omp's `/loop`. For a wake that must land out of session, use a named bash process observed through `proc://`, or a systemd user timer.#
s#Run `drive` and `background` under `/loop` in dynamic mode\.#Run `drive` and `background` under omp's `/loop` while `loop.mode` is `prompt`, or under a named bash process observed through `proc://` when the wake must land out of session.#
s#Hold the watch under `/loop` in dynamic mode\.#Hold the watch under omp's `/loop` while `loop.mode` is `prompt`, or under a named bash process observed through `proc://` when the wake must land out of session.#
s#`/loop` per component until the diff is zero\.#Hold a named bash process observed through `proc://`, or a systemd timer, per component until the diff is zero.#
s#a frontier watcher wake \(arm it via the loop skill, with a long heartbeat fallback\)#a frontier watcher wake (hold a named bash process observed through `proc://`, or a systemd timer, with a long fallback heartbeat)#
s#"/loop until X"#"run until X"#g
# Cursor's `/goal` is on by default; omp ships it behind a settings gate.
s#arm a `/goal` with the full program objective\.#arm a `/goal` with the full program objective. omp's `/goal` is native but gated, so turn on `goal.enabled` in settings first. Since 18.0.2 the tool registers lazily, so turning it on mid-session also works.#g
s#arm a `/goal` with this exact text\.#arm a `/goal` with this exact text. omp's `/goal` is native but gated, so turn on `goal.enabled` in settings first. Since 18.0.2 the tool registers lazily, so turning it on mid-session also works.#

## 6. cursor-team-kit. Cursor's companion plugin -> omp's built-in tools.

# `/deslop` -> the `unslop` skill plus `omp cleanse` for diagnostics.
s#the `deslop` skill from the `cursor-team-kit` plugin \(`/deslop`\)#the `unslop` skill (`skill://unslop`) plus `omp cleanse --all` for diagnostics#g
s#Run `/deslop` from `cursor-team-kit` over the diff before commit\.#Run the `unslop` skill (`skill://unslop`) plus `omp cleanse --all` over the diff before commit. A bare `omp cleanse` opens an interactive picker and blocks.#
s#`/deslop`#the `unslop` skill (`skill://unslop`) plus `omp cleanse --all`#g
# `control-ui` / `control-cli` -> browser, computer, and named bash processes.
s#`control-ui` or `control-cli` runtime verification \(from `cursor-team-kit`\)#`browser` or `computer` for UIs, or bash with a unique async `name`, `ready` checks, and `proc://` state for CLIs and TUIs#
s#\(`control-cli` or `control-ui` from `cursor-team-kit` as the change demands\)#(`browser` or `computer` for UIs, bash with a unique async `name`, `ready` checks, and `proc://` state for CLIs and TUIs, as the change demands)#
s#\(`control-ui` or `control-cli` from `cursor-team-kit` as the change demands\)#(`browser` or `computer` for UIs, bash with a unique async `name`, `ready` checks, and `proc://` state for CLIs and TUIs, as the change demands)#
s#Drive through `control-ui` or `control-cli` from `cursor-team-kit`\.#Drive through `browser` or `computer` for UIs, and bash with a unique async `name`, `ready` checks, and `proc://` state for CLIs and TUIs.#
s#Browser, Electron, and web UIs use `control-ui` from `cursor-team-kit`\. CLIs and TUIs use `control-cli` from `cursor-team-kit`\.#Browser, Electron, and web UIs use the `browser` eval prelude, and native desktop UIs use `computer`. Both are code in an `eval` cell and not tools. CLIs and TUIs use bash with a unique async `name`, `ready` checks, and `proc://` state.#
s#`cursor-team-kit` publishes `control-cli` \(CLIs and TUIs\) and `control-ui` \(browser / Electron / web UIs\)\.#omp provides the levers directly. Bash with a unique async `name`, `ready` checks, and `proc://` state drives CLIs and TUIs, the `browser` eval prelude drives browser, Electron, and web UIs over CDP, and the `computer` prelude drives native desktop. Both preludes are code in an `eval` cell and neither is a tool with its own schema.#
s#\*\*Control skill\.\*\* Pick it by surface\.#**Control surface.** Pick it by surface.#
s#through the control skill's commands#through the control surface's own calls#
s#`control-ui`#the `browser` eval prelude#g
s#`control-cli`#bash with a unique async `name`, `ready` checks, and `proc://` state#g
s#`cursor-team-kit`#omp's built-in tools#g
s#cursor-team-kit#omp's built-in tools#g

## 7. create-skill. Cursor's SKILL.md authoring builtin -> pstack's own authoring playbook.

# The playbook cannot route to itself, so its step 1 states the omp authoring path directly.
s#^1\. Use the \*\*create-skill\*\* skill \(Cursor's built-in for authoring SKILL\.md files\)\.$#1. Write the SKILL.md yourself with `write` or `edit`. omp's `manage_skill` writes only under `~/.omp/agent/managed-skills` and never touches a user-authored skill. Give it YAML frontmatter with `name` matching its directory, a `description` naming what the skill does and when to reach for it, and `disable-model-invocation: true` so it stays out of the per-turn index.#
s#the \*\*create-skill\*\* skill \(Cursor's built-in for authoring SKILL\.md files\)#the **authoring-a-skill** playbook (`playbooks/authoring-a-skill.md`)#g
s#\*\*authoring-a-skill\*\* playbook \(`playbooks/authoring-a-skill\.md`\)#**authoring-a-skill** playbook (`skill://poteto-mode/playbooks/authoring-a-skill.md`)#
s#A `create-skill`-style#An `authoring-a-skill`-style#g
s#Cursor's built-in `create-skill` skill#the `authoring-a-skill` playbook#g
s#Cursor's built-in `create-skill`#the `authoring-a-skill` playbook#g
s#`create-skill`'s#the `authoring-a-skill` playbook's#g
s#new skill via create-skill:#new skill via authoring-a-skill:#g
s#draft a new skill via create-skill#draft a new skill via the authoring-a-skill playbook#g
s#via create-skill \+ unslop#via the authoring-a-skill playbook + unslop#g
s#`create-skill`#the `authoring-a-skill` playbook#g

## 8. Transcripts. Cursor's per-project transcript directory -> omp's session store.

s#`~/\.cursor/projects/<slug>/agent-transcripts/<uuid>/<uuid>\.jsonl`#the session store, by default `~/.omp/agent/sessions/<encoded-cwd>/<timestamp>_<session-id>.jsonl`#
s#where `<slug>` is the workspace path with the leading slash dropped and each "/" turned into "-" \(so `/Users/you/proj` becomes `Users-you-proj`\)#where `<encoded-cwd>` is the cwd with $HOME stripped and each "/" turned into "-" (so `~/proj` becomes `-proj`)#
s#Every line is one chat message\.#Every line is one JSON object. The first is a fixed-width `type:title` slot, the second a `type:session` header, and the rest messages whose roles are camelCase (`toolResult`, not `tool_result`).#
s#the active workspace's `agent-transcripts/` directory#the session transcript tree `~/.omp/agent/sessions/<encoded-cwd>/*.jsonl`, with subagent sidecars at `<session-stem>/<AgentId>.jsonl`#g
s#the workspace's `agent-transcripts/` directory#the session transcript tree `~/.omp/agent/sessions/<encoded-cwd>/*.jsonl`, with subagent sidecars at `<session-stem>/<AgentId>.jsonl`#g
s#local transcripts under `agent-transcripts/`#local transcripts under `~/.omp/agent/sessions/<encoded-cwd>/`#
s#`~/\.cursor/projects/\*/`#sibling `~/.omp/agent/sessions/<other-cwd>/` buckets#g
s#<agent-transcripts>#~/.omp/agent/sessions/<encoded-cwd>#g
# Cursor kept three historical transcript layouts; omp writes one.
s#Three transcript layouts: legacy flat \(`<id>\.jsonl`\), current nested \(`<id>/<id>\.jsonl`\), and subagent \(`<parent>/subagents/<child>\.jsonl`\)\.#One transcript layout. A flat `<timestamp>_<session-id>.jsonl` per session in the bucket, with `<AgentId>.jsonl` sidecars in the sibling directory named for that stem, and one further subdirectory per nesting level whose files carry the full dotted id.#
s#For each candidate, read the first JSONL line and check that `message\.content\[0\]\.text` contains the conversation's opening user prompt\.#The first line of an omp transcript is a fixed-width `type:title` slot and the second a `type:session` header, neither of them a message. For each candidate, scan for the first `type:message` line with `role:user` and check that its text contains the conversation's opening user prompt.#
# Cursor's skill roots -> omp's workspace, user, and plugin skill roots.
s#~/\.cursor/skills/#~/.omp/agent/skills/#g
s#\.cursor/skills/#.omp/skills/#g
s#, or plugin-installed paths under `~/\.cursor/plugins/`#, or plugin-installed paths under `~/.omp/plugins/node_modules/`#g
# Cursor's worktree path convention -> whatever path the local tool manages.
s#misses one that lives at `\.cursor/worktrees/myrepo/x`#misses one that lives at a tool-managed path like `.worktrees/myrepo/x`#
# Cursor's pinned-chat sidebar -> omp's live roster plus the session store.
s#The pinned and active chats are the real artifact \(principle-prove-it-works\)\. Get that set from the user or sidebar and cross-check every candidate\. The lever has marked `safe` a worktree the user had pinned, so the pinned set wins\.#The live omp sessions are the real artifact (principle-prove-it-works). Get that set from `hub` `op: "list"` plus the session store at `~/.omp/agent/sessions/<encoded-cwd>/`, confirm it with the user, and cross-check every candidate. The lever has marked `safe` a worktree a live session still owned, so the live set wins.#
s#report whether the chat is pinned or ongoing and which worktrees it touches#report whether the session is still live and which worktrees it touches#
s#A pinned chat spawns arena and repro trees into sibling worktrees via background subagents, and those are in use even when their names never hit the sidebar\.#A live session spawns arena and repro trees into sibling worktrees via background subagents, and those are in use even when `hub` `op: "list"` never names them.#
# Cursor exposes enabled MCP servers as a directory; omp lists them in one config file.
s#Before spawning investigators, list the available MCPs from the Cursor environment\. Use the available-tools map when present\. Otherwise inspect the `mcps/` directory Cursor exposes for enabled MCP servers\.#Before spawning investigators, list the available MCPs from the session environment. Use the available-tools map when present. Otherwise read `~/.omp/agent/mcp.json` for enabled MCP servers.#
# Cursor resumes an idle agent to reach it; omp messages it and leaves it running.
s#Agents are spawned, resumed, and drained only through the Task tool\.#Agents are spawned and drained only through the Task tool, and resumed only through `hub` messaging.#
# Bugbot is a Cursor product, so the rubric names what plays its part on omp.
s#^Use this reference when the Babysit playbook \(`\.\./playbooks/babysit\.md`\) handles Bugbot or review-automation comments\.#Use this reference when the Babysit playbook (`../playbooks/babysit.md`) handles Bugbot or review-automation comments. Bugbot is Cursor's hosted review product, so without it this rubric applies to whatever review bot posts on your PRs, including omp's own `security-reviewer`.#
# Net for any Cursor home path a later upstream commit introduces.
s#~/\.cursor/#~/.omp/#g

## 9. Install paths. pstack is vendored in Cursor's monorepo and installed as a plugin on omp.
## Order is load-bearing: the trunk-read rewrites and the checklist append run before the
## generic pstack/skills/ rewrite, which is guarded so it cannot re-match its own output.

# One product-repo line survives, so check-plan.mjs's `git show origin/main:` marker stays real.
\%^  - \[ \] `git show origin/main:pstack/skills/<each other leaf skill the program uses>`$%a\
  - [ ] `git show origin/main:<each skill or doc the product repo vendors itself>`
s#re-read this playbook from trunk with `git show origin/main:pstack/#re-read this playbook from its install path, `~/.omp/plugins/node_modules/pstack/#g
s#Re-read the execution playbook from trunk and the armed /goal#Re-read the execution playbook from its install path and the armed /goal#g
s#`git show origin/main:<control skill path>`#the omp doc for the control surface, such as `omp://tools/browser.md`, remembering that `browser` and `computer` are eval preludes rather than tools#
s#`git show origin/main:pstack/#`~/.omp/plugins/node_modules/pstack/#g
s#([^/])pstack/skills/#\1~/.omp/plugins/node_modules/pstack/skills/#g
# Cursor's npm scope for skill tooling -> the port's own scope.
s#@cursor-skill/#@omp-skill/#g
# Cursor auto-attaches a skill on a file-glob match; omp carries `globs` as metadata only.
s#^paths: \[#globs: [#
