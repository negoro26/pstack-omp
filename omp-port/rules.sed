# The substitution table, executable. Run as `sed -E -i -f omp-port/rules.sed <file>` on every
# text file of an upstream `pstack/{skills,agents}` export. Port-only file, never upstream.
#
# One rule per line, ordered, each with a `#` comment naming the Cursor mechanic and the omp
# mechanic it maps to. This file replaces PORTING.md's substitution table: the table is here now.
# Order is load-bearing in three places, each marked below.
#
# Owned prose lives in the two skill paths named by omp-port/owned.txt. Script changes live in
# omp-port/patches. Upstream paths the port does not ship are in omp-port/excluded.txt. None of
# these belongs here.

## 1. Whole-sentence rewrites, which must read raw upstream text before any token rule edits it.

# Comment Sicko's actual upstream name is the lowercase agent id, and it has to match before the
# generic field-token rules below rewrite `subagent_type` out from under it.
s#^1\. Spawn `Task` with `subagent_type: "comment-sicko"`\..*$#1. Start one `task` call with one item in `tasks[]` and the required shared `context`. Use the exact discovered `comment-sicko` agent when present; otherwise omit `agent` for the default worker. Resolve the loaded `skill://no-comments` path to its plugin root and put the comment-reviewer role, scope, and absolute `<plugin-root>/agents/comment-sicko.md` pointer in the brief. Pick each subagent's reasoning level for the job, per the Subagents section of the **poteto-mode** skill. Do not restate the reviewer's rules.#
# The how and why contracts are one paragraph upstream, not role bullets. Cursor's `generalPurpose`
# agent does not exist on omp, so the whole paragraph goes, before the token rules see it.
s#^Every spawn is a Task subagent with `subagent_type: generalPurpose`.*$#Every delegation uses one `task` call with the required shared `context` and all independent items in `tasks[]`. Resolve exact agent names against the live roster, not configuration keys. Repository explorers use a discovered `scout`; explainers use a discovered explainer or omit `agent` for the default worker with the explainer brief. Each item's `task` is standalone and carries its angle and prompt template. All work is read-only. Models, reasoning, and speed come from agent frontmatter or `task.agentModelOverrides[<exact-name>]`, never per-call model fields or family fallbacks. Overrides cannot create agents.#
s#^Every spawn is `generalPurpose` with `readonly: false`.*$#Use exact discovered investigators and a synthesizer from the live roster. Omit `agent` for the default worker when no matching specialist is loaded. MCP tools are inherited, including by `scout`; choose a worker whose exposed tools cover the assigned evidence source. Carry read-only posture in each brief: no file writes, git mutations, commits, pushes, PRs, or external mutations. There is no task `readonly` field.#
# Inline why role annotations are not task model selectors.
s#`model`: the `why investigators` line, default `[^`]+`\.#Use an exact discovered investigator agent; its frontmatter or `task.agentModelOverrides[<exact-name>]` selects the model.#
s#`model`: the `why synthesizer` line, default `[^`]+`\.#Use an exact discovered synthesizer or omit `agent` for the default worker with the synthesizer brief. Its frontmatter or exact override selects the model.#
# Interrogate writes its call contract as prose and its defaults as a two-seat slug table. Both run
# before the slug tiers, which would otherwise leave a capability name in a "Default model" column.
s#^Each reviewer gets `subagent_type: generalPurpose`, `readonly: true`, and `model` set to its configured entry,.*$#Each task item uses an exact discovered reviewer agent or omits `agent` for the default worker with the same reviewer brief. Carry read-only posture in the brief, not a `readonly` field. Agent frontmatter or `task.agentModelOverrides[<exact-name>]` selects the model; do not pass `model`. Shared `context` carries the intent and rubric, while each item carries the standalone review task.#
s#^\| Subagent \| Default model \|$#| Reviewer slot | Runtime agent |#
s#^\| Reviewer A \| `[^`]+` \|$#| Reviewer A | discovered reviewer agent or default worker |#
s#^\| Reviewer B \| `[^`]+` \|$#| Reviewer B | independently configured reviewer agent or default worker; report unavailable diversity |#
s#Read the `interrogate reviewers` line in place of `arena runners`\.#Use exact discovered review-capable agents in place of Arena's runners. Each agent's frontmatter or `task.agentModelOverrides[<exact-name>]` selects its model.#
s#Spawn each adversary as `generalPurpose`\.#Use exact discovered review-capable agents, or omit `agent` for the default worker with the adversary brief.#
# The router's model paragraph tunes a per-call Cursor slug and retries a family default on
# rejection. omp's task item takes no model, and its only per-spawn knob is the gated `effort`
# field. Upstream's per-site "Pick each subagent's reasoning level" pointer needs no rule, because
# the Subagents section it names is this replacement.
s#^\*\*Match the model to the job\.\*\*.*$#**Match the role to the job.** Resolve the required capability against the live agent roster and use that agent's configured reasoning and speed. Pass a per-spawn `effort` only when the live task schema exposes it. When it does, panel seats keep their configured level, any other role goes up one level for the hardest or subtlest work, down one for judgment, and down two or more for routine work, and no role runs above `xhigh`. Verification always runs on the agent the swarm worker role resolves to. Agent frontmatter or `task.agentModelOverrides[<exact-name>]` selects the model. Do not adjust a per-call slug, retry a family default, or change operator configuration to satisfy an example. Report unavailable diversity honestly.#
# Poteto help's install, model defaults, pin UI, and guide links describe Cursor. On omp the install
# is the marketplace, the model map is config.yml, and the pin is the potetomode extension's
# `/poteto-mode on|off|status`, `alt+shift+t`, and `--poteto` flag. These run before the
# `/skill:<name>` rule, which would otherwise rewrite the `/poteto-mode` their left sides quote.
s#^1\. Install with `/add-plugin pstack` in chat, or from Customize in the sidebar\.$#1. Install with `/marketplace add negoro26/pstack-omp`, then `/marketplace install pstack@pstack-omp`.#
s#^2\. Run \[`/setup-pstack`\].*$#2. Models need no configuration. Each agent runs on its frontmatter model, then on the chat model. To pick models per agent, follow [Choose models](../omp-mechanics/SKILL.md\#choose-models). Offer once each to generate a verification skill with `/skill:create-verification-skill` and a formal verification skill with `/skill:create-formal-verification-skill`, unless the project already has one.#
s#^- No `~/\.cursor/rules/pstack-models\.mdc` means.*$#- No exact override for a role means its loaded agent frontmatter or the parent chat model selects its model.#
s#When the model rule is missing and it matters,#When required role overrides are missing and model selection matters,#
s#^- Now: give them `/setup-pstack` to type, and answer their question too\.$#- Now: point them to [Choose models](../omp-mechanics/SKILL.md\#choose-models), and answer their question too.#
s#^- Later: answer their question, and add one line saying every role keeps its default model until they run `/setup-pstack`\.$#- Later: answer their question, and say agent frontmatter or parent inheritance remains in effect until they configure exact role overrides.#
s#^If cost is the worry, say where the tokens go and how to spend fewer\..*$#If cost is the worry, explain that extra workers and review panels spend more tokens. To spend fewer, pick a lower effort or cheaper available models per [Choose models](../omp-mechanics/SKILL.md\#choose-models). An agent without a model override uses its frontmatter or inherits the chat model. Never write `auto` or `inherit-parent` as an OMP model selector. Save `/poteto-mode` for work that needs rigor.#
s#Installing changes nothing until the user invokes a skill\. Only `/setup-pstack` loads from the user's words\.#Skills run when invoked or routed. The installed extension also provides the session pin commands.#
s#^Whether `/poteto-mode` stays on depends on how the user starts it:$#Choose whether to invoke the router once or pin it for the session:#
s#^- Enter on `/poteto-mode` attaches.*$#- `/skill:poteto-mode` invokes the router for a task; it does not enable the persistent pin.#
s#^- Option\+Enter on Mac or Alt\+Enter on Windows,.*$#- `/poteto-mode on` pins the router for every turn, `/poteto-mode off` unpins it, and `/poteto-mode status` reports the current pin. These are the installed extension's OMP commands, not Cursor's Custom Mode UI.#
s#^- Cursor's docs list Custom Modes.*$#- The extension registers Alt+Shift+T to toggle the pin when the terminal delivers that key. For print-mode runs use `omp --poteto -p '<task>'`. Do not claim Cursor's platform shortcuts work here.#
s#^Link \[Cursor's skills docs\].*$#Link the installed [OMP README](../../README.md) for pin commands and [runtime mapping](../pstack-omp/SKILL.md) for delegation. Mid-chat, "new task" makes the router match a fresh playbook. Resolve any helper against the live agent roster; use `poteto-agent` only when loaded, otherwise follow the runtime mapping's role and default-worker routing.#
s#a Custom Mode keeps it on#`/poteto-mode on` keeps it pinned#g
s#^\| The mode stopped applying after a few turns \|.*$#| The mode stopped applying after a few turns | Check `/poteto-mode status`. Use `/poteto-mode on` to pin it, or invoke `/skill:poteto-mode` for each task. |#
s#^\| A new model choice had no effect \|.*$#| A new model choice had no effect | Confirm the loaded agent name and its exact `task.agentModelOverrides` entry, then start a new session. An override cannot create an agent. |#
s#^\| Pick a model for each role and a reasoning budget \| \[`/setup-pstack`\]\(\.\./setup-pstack/SKILL\.md\) \|$#| Pick a model for each role and a reasoning budget | [Choose models](../omp-mechanics/SKILL.md\#choose-models) |#
s#^\| A skill didn't load on its own \|.*$#| A skill didn't load on its own | Invoke `/skill:<name>` explicitly or let the router load it. Only skills enabled for model invocation appear in the per-turn index. |#
s#which each get their own machine#which get private worktrees, not separate machines#g
s#^- `/loop` and `/create-skill` are Cursor built-ins\.$#- `/loop` is an OMP runtime command when exposed. Skill authoring uses the [authoring playbook](../poteto-mode/playbooks/authoring-a-skill.md); there is no assumed Cursor `/create-skill` command.#
s#^Without `/poteto-mode`, a phrase such as.*$#Without `/poteto-mode`, the runtime may route a phrase using other enabled skills. Invoke the router explicitly to select pstack's playbook. The Playbooks section of [`poteto-mode`](../poteto-mode/SKILL.md) lists every playbook. [Guide page 6](../../docs/guide/06-verify-and-ship.md) gives upstream workflow examples, not OMP runtime commands.#
# omp has a plan mode of its own, so the sentence names no Cursor feature rather than denying one.
s#pstack has no planning skill\. Cursor's Plan Mode works alongside it\.#pstack has no planning skill.#
s#Typing `/principle-<name>` still loads one on demand\.#Typing `/skill:principle-<name>` loads one on demand.#
# The build extracts only skills/ and agents/, so a relative guide link resolves to nothing. Point
# it at upstream's public copy, and the public-copy rule at this port's tree.
s#\]\(../../docs/guide/([0-9][0-9]-[a-z-]+\.md)\)#](https://github.com/cursor/plugins/blob/main/pstack/docs/guide/\1)#g
s#The links here point into the installed plugin, which the user may not be able to open, so give the user the file's public copy: `https://github.com/cursor/plugins/blob/main/pstack/` followed by its path\.#Link installed skill and runtime files directly. For a public copy of ported behavior, use `https://github.com/negoro26/pstack-omp/blob/main/plugins/pstack/` followed by the installed plugin-relative path. Guide URLs point to upstream for workflow background only; use this port's README and runtime skills for OMP commands.#
# Poteto help's companion list. `omp cleanse` detects AND fixes repo-wide, so it is no diagnostic.
s#^- `/deslop`, `control-cli`, and `control-ui` ship in the `cursor-team-kit` plugin\.$#- Prose cleanup uses `skill://unslop`. Diagnostics use the project's documented read-only checks, with LSP diagnostics only when a live server is configured. OMP exposes browser interaction through its eval prelude and CLI interaction through named bash services and `proc://`. Do not run `omp cleanse` as a diagnostic check.#
s#^Other tools can read the skills, because they use the Agent Skills format.*$#The engineering workflows come from upstream. `skill://pstack-omp` maps worker execution and lifecycle to OMP, `skill://omp-mechanics` says how to choose models, and the mode extension preserves the session pin.#

# Cursor's reasoning-effort ladder over its own slug names -> a selector omp models reports. The
# left-hand side is upstream's sentence as it stands at the pin, nothing more: it used to end "when
# only that form is detected.", a clause upstream dropped, and the rule then matched nothing at all
# while sed still exited 0. That is the whole failure this gate exists to catch, caught here by
# rewriting the left-hand side rather than by adding an exemption, because the translation it
# carries is still wanted and the replacement text was already sitting unused below.
s#So `small` turns `claude-[a-z0-9.-]+` into `claude-[a-z0-9.-]+`, and `grok-[a-z0-9.-]+` into `grok-[a-z0-9.-]+`\.#So `small` takes the lowest-effort selector in the same family that `omp models` reports, and marks the role as needing a choice when that family offers none.#
# Router prose that names Cursor's spawn surfaces, agent defaults, or per-call model paragraph.
s#Starting any agent, whether a Task subagent or a Project worker →#Starting any agent, whether a `task` item or a `vibe_spawn` worker →#
s#^\*\*Use `subagent_type: "poteto-agent"` for any subagent you spawn directly inside a playbook step\.\*\* The chat that receives `/poteto-mode` runs the playbook itself\. Routed workflow skills \(`interrogate`, `swarm`\) set their own `subagent_type`\. Respect it\.$#`poteto-mode` selects the playbook, step order, canonical role, and lifecycle protocol. `skill://pstack-omp` is authoritative for every delegation instruction in this catalog, including imported task-shaped examples. Resolve roles against the live roster; bundled agent names are optional, never mandatory. Use a discovered `poteto-agent` for a subagent you start directly inside a playbook step. The chat that receives `/poteto-mode` runs the playbook itself. Routed workflow skills (`interrogate`, `swarm`) name their own roles. Respect them. Only pass fields exposed by the current tool schema.#
s#^\*\*Defaults for every `Task` call\.\*\* `run_in_background: true`.*Keep honoring its lines, and tell the user once per session to rerun `/setup-pstack`\.$#Batch genuinely independent work when supported. Give each participant a standalone brief and explicit write ownership. The root starts additional participants and independent reviewers; ordinary workers do not start children. Runtime role configuration selects models for every spawn, on any worker surface. Review and design panels default to three runners, each on a different configured model family when the roster supplies one. A role with no override entry runs on its agent's frontmatter model, then on the parent chat model. The bundled `poteto-agent` ships without a model line, so it inherits the parent chat model unless an override binds it. Preserve required independent contexts and report unavailable model diversity honestly. Do not change operator configuration merely to satisfy a skill example.\n\nModel selection belongs to `task.agentModelOverrides` and agent frontmatter, not to routed-skill task fields. The defaults below name capabilities, not slugs.#
# Upstream names its costliest model and its default judgment model by product. The slug tiers map
# those to your strongest judgment model and your default judgment model.
s#^\*\*Fable [0-9.]+ is an exception\.\*\* It runs outside a panel only when the user named it for this task or two Opus [0-9.]+ xhigh runs of the same brief failed its check\.#**Your strongest judgment model is an exception.** It runs outside a panel only when the user named it for this task or two runs of the same brief on your default judgment model at `xhigh` failed its check.#
# Autonomous run's exact post-Cursor workflow.
s#^\*\*You own the exit condition\. Define done, then drive to it without stopping\.\*\*$#**You own the exit condition. Define done, then drive to it without stopping.** For "going to bed", "run until done", or "continue until X".#
s#^1\. State the exit condition as a checkable predicate before the first iteration \(tests green, repro fixed, all N PRs merged, pixel-diff zero\)\.$#1. State the exit condition as a checkable predicate before the first iteration (tests green, repro fixed, all N PRs merged, pixel-diff zero). A vague goal stalls; a predicate lets you stop.#
s#^4\. Mid-run discoveries( that support the goal)? are yours\..*Keep the predicate as the main drive, and return to it after each side fix\.$#4. Mid-run discoveries that support the goal are yours. Address broken skills, related bugs, flaky verifiers, review noise, tooling failures, orphaned follow-ups, and fixable drift yourself via poteto-mode. Put out-of-band fixes in their own PR. Do not park reversible work for the human or open a user question. Surface only irreversible actions, genuine product or preference calls no experiment can settle, or a real dead end. Keep the predicate as the main drive, and return to it after each side fix.#
s#^5\. Checkpoint every iteration via the \*\*show-me-your-work\*\* skill, a row for what changed and whether the predicate moved\.$#5. Checkpoint every iteration via the **show-me-your-work** skill, a row for what changed and whether the predicate moved. A run with no trail can't be audited or resumed.#
# Cursor's model paragraph -> exact discovered agents and runtime-selected models.
s#Each spawn below names a role line in the `pstack-models\.mdc` rule and a default\. Set `model` to that line's value, or to the default if the rule or the line is missing\. Leave `model` unset when the value is `auto` or `inherit-parent`\. If the Task tool rejects a slug, use the default and say so\. If it rejects the default, use the closest valid slug of the same family from its error message\.#Resolve agents against the live roster. Use an exact preferred agent only when it is present; otherwise follow the workflow's default-worker fallback. Each agent's frontmatter or `task.agentModelOverrides[<exact-name>]` selects its model; the task item has no `model` field.#
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
s#Spawn one Task subagent with `subagent_type: generalPurpose` and `readonly: true` that explores and explains in one pass\.#Start one explainer in one `task` call with one item in `tasks[]` and the required shared `context`. Use an exact discovered explainer agent when the live roster has one; otherwise omit `agent` for the default worker. It explores and explains in one pass, and its brief carries read-only posture, since there is no task `readonly` field.#
s#Once all explorers have returned, spawn one Task subagent to synthesize their findings into one explanation:#After all explorers have returned, start the synthesis in one `task` call with one item in `tasks[]` and the required shared `context`, using Step 2b's explainer routing:#
s#Spawn one synthesizer subagent:#Start one synthesizer in one `task` call with one item in `tasks[]`, the required shared `context`, and an exact discovered full-access worker:#
s#Spawn all explorers in a single message,#Start all explorers in one `task` call with the required shared `context` and all independent items in `tasks[]`,#
s#Launch all matching investigators in a single message so they run concurrently\.#Launch all matching investigators in one `task` call with the required shared `context` and all items in `tasks[]` so they run concurrently.#
s#^Launch all reviewers in a single message with the Task tool, one per entry on the `interrogate reviewers` line in `~/\.cursor/rules/pstack-models\.mdc`, labeled Reviewer A, B, and so on to match the entry count\. If the rule or that line is missing, use the table defaults\.$#Launch all reviewers in one `task` call with the required shared `context` and all items in `tasks[]`. Resolve exact discovered reviewer agents from the live roster, one per configured slot, labeled Reviewer A, B, and so on. Omit `agent` for the default worker with the reviewer brief when a specialist is absent. Report unavailable model-family diversity; never invent an agent from an override key.#
# Cursor's per-reviewer opening becomes one reviewed batch.
s#^Spawn one reviewer per configured model to adversarially review code changes\. Each model gets the same prompt and rubric\.#Use exact discovered reviewer agents, one per configured family, in one `task` call with all items in `tasks[]` and the required shared `context`. Each reviewer gets the same prompt and rubric.#
s#Spawn all N subagents in one message with `run_in_background: true`, each with the task, the path to the shared grounding, its own output path, and instructions to produce both the artifact and a short rationale\.#Spawn all N subagents in one `task` call with all items in `tasks[]` and the required shared `context`, each with the task, the path to the shared grounding, its own output path, and instructions to produce both the artifact and a short rationale.#
s#Spawn all N workers in one message with `subagent_type: generalPurpose`, `environment: "cloud"`, `run_in_background: true`, and the step [0-9]+ model, left unset for `auto` or `inherit-parent`\. Use `environment: "local"` only when the worker needs access to something on the user's computer\.#Start all N workers in one `task` call. Put every item in `tasks[]` and pass the required shared `context`; set `isolated: true` only when the live task schema exposes it and the runtime's isolation settings allow it. Otherwise give each writer an explicit separate worktree or output directory.#
# Remove the old MCP-mode claims left after the task-call rewrite.
s#Reviewers need MCP access for context lookups \(tickets, chat threads, observability traces referenced in the transcript\)\. Readonly strips MCPs\.##
s#The synthesizer's quality check includes spot-verifying citations, which can require MCP access\. Readonly strips MCPs\.##
s#there is no task `readonly` field\.  Use#there is no task `readonly` field. Use#
s#The synthesizer returns a structured Accepted / Rejected / Backlog list\.#Pass this explicit `outputSchema` when the live task schema exposes it:\n\n```json\n{"type":"object","required":["Accepted","Rejected","Backlog"],"properties":{"Accepted":{"type":"array","items":{"type":"object","required":["Problem","Proposal","Routing"],"properties":{"Problem":{"type":"string"},"Proposal":{"type":"string"},"Routing":{"type":"string"}}}},"Rejected":{"type":"array","items":{"type":"object","required":["Principle","Reason"],"properties":{"Principle":{"type":"string"},"Reason":{"type":"string"}}}},"Backlog":{"type":"array","items":{"type":"object","required":["Pattern","Hit","Mechanism"],"properties":{"Pattern":{"type":"string"},"Hit":{"type":"string"},"Mechanism":{"type":"string"}}}}}}\n```#
# These model-map sentences must match raw upstream before slug and path token rewrites. They name
# every slug position with `[^`]+` and no wildcard, so an upstream reword goes stale rather than
# swallowed.
s#^3\. Pick the runners from the `arena runners` line in `~/\.cursor/rules/pstack-models\.mdc`, by default `[^`]+`, `[^`]+`, and `[^`]+`\. An `auto` or `inherit-parent` entry is the parent model, so omit `model` and spawn `generalPurpose`\. If the Task tool rejects a slug, use the nearest valid slug of the same family or drop the seat, keep at least two runners, and say so\. Families go by prefix, and the longest match wins: `claude-fable-\*`, `claude-\*`, and `gemini-\*`, after dropping a leading `cursor-`\. Any other slug's family is its text before the first hyphen\.#3. Pick the runners. Run three by default. Resolve exact discovered agent names and inspect each agent's frontmatter or `task.agentModelOverrides[<exact-name>]`. Prefer distinct configured model families when the roster supplies them; otherwise keep the independent contexts and report weaker model diversity. An agent with no override and no frontmatter model runs on the parent model. If a runner cannot start, drop that seat, keep at least two runners, and say so. A model override cannot create an agent.#
s#After all Phase B candidates complete, spawn one readonly judge from the `arena cross-judge pool` line in `~/\.cursor/rules/pstack-models\.mdc`, by default `[^`]+`, `[^`]+`\. The judge is never from the parent's vendor, and Fable counts as Claude for that check, so use the first entry from another vendor\. An `auto` or `inherit-parent` entry is the parent model\. If you do not know the parent's model, use the first real slug and say that the vendor check did not run\. If the Task tool rejects a slug, use the nearest valid slug of the same family, then the next such entry, or skip the judge, and say so\.#After all Phase B candidates complete, choose an exact discovered judge agent whose configured model is from a different vendor than the parent's. Two model families from one vendor, such as two Claude lines, count as one vendor. An agent with no override and no frontmatter model inherits the parent's model, so it never judges. Start the judge in one `task` call with one item in `tasks[]`, the required shared `context`, and that exact agent name. Its frontmatter or `task.agentModelOverrides[<exact-name>]` selects the model; the task item has no `model` field. The brief carries read-only posture and forbids writes; there is no task `readonly` field. If you do not know the parent's model, choose a judge whose model its frontmatter or exact override sets, and say that the vendor check did not run. If no judge from another vendor can start, skip the judge, and say so.#
s#^- `model`: the configured `interrogate reviewers` entry, or the table default with no configured line\. For an `auto` or `inherit-parent` entry, omit `model` so that reviewer runs on the parent model\.$#- `agent`: an exact discovered reviewer agent name. Its frontmatter or `task.agentModelOverrides[<exact-name>]` selects the model; the task item has no `model` field#
s#If the Task tool rejects a configured entry, run that reviewer on its family's table default and say so\. Families go by prefix: `claude-\*`, and `grok-\*` with `cursor-grok-\*` and `composer-\*`\. A refused `composer-\*` entry runs on Reviewer B's default\. With no family match, use Reviewer A's default\. If it rejects a table default, spawn with the closest equivalent from the valid slugs in its error message \(prefer the same family and reasoning tier\), and open a separate PR to update the default table\. Do not block the review on the slug issue\. Never treat an alias entry as a rejected slug or apply either fallback to it\.#If the requested exact reviewer is absent, use another discovered reviewer with the same brief and report the missing model diversity. A model override cannot create an agent.#
s#^([0-9]+)\. Pick the worker model from the `swarm workers` line in `~/\.cursor/rules/pstack-models\.mdc`\. If the rule or that line is missing, use `[^`]+`\. For `auto` or `inherit-parent`, omit `model` so the workers run on the parent model\. If the Task tool rejects a slug, use the default and say so\. If it rejects the default, use the closest valid slug of the same family from its error message\. For a model race, name each arm's model up front\.#\1. Pick exact discovered agent names. Inspect each agent's frontmatter or `task.agentModelOverrides[<exact-name>]` for its model. A model race needs one loaded agent file and one exact override entry per arm; overrides cannot create agents.#
# The Cursor wire fields, as tokens rather than as sentences. The sentence rules above carry the
# meaning; this net is what keeps a Cursor field out of the tree when upstream rewords the
# sentence those rules anchor on, which it does routinely. Each left side is a field name that
# has no omp equivalent, so matching the token is always correct and never over-rewrites.
s#`subagent_type: "([^"]+)"`#`agent`: `\1`#g
s#`subagent_type`: `([^`]+)`#`agent`: `\1`#g
s#`subagent_type`#`agent`#g
s#subagent_type#agent#g
s#`run_in_background: true`#one `task` call with all items in `tasks[]`#g
s#`readonly: true`#read-only posture carried in the brief#g
s#agent mode \(`readonly: false`\)#full tools per spawn#g
s#`readonly: false`#full tools per spawn#g
s#`readonly`: `true`#read-only posture carried in the brief#g
s#readonly strips MCPs\.#nothing strips MCPs here.#g
# A judge is spawned with read posture in its brief, never as a field. Matched on the field name
# rather than the sentence, because upstream rewords the sentence and the field never survives it.
s#Spawn one readonly judge subagent( on that model)?\.#Start one judge in one `task` call with one item in `tasks[]`, the required shared `context`, and a brief that grants read tools only.#
# `model`: the <role> line -> the agent that role names. Same reason: the field has no omp wire
# equivalent, so replacing the token is always right and never over-rewrites.
s#`model`: the `([^`]+)` line#`agent`: an exact discovered \1 agent#g
s#`model` from the `([^`]+)` line#`agent` from the `task.agentModelOverrides` entry for an exact discovered \1 agent#g
# A single spawn still uses the batch shape: one call, one item, one shared context.
s#Spawn one investigator per category that has a matching MCP, all in a single message so they run concurrently#Assign one investigator to each category that has a matching MCP, in one `task` call with all items in `tasks[]` and the required shared `context` so they run concurrently#
s#Spawn one synthesizer\.#Start one synthesizer in one `task` call with one item in `tasks[]` and the required shared `context`.#
# Inline selectors that survive into patch context are exact values, not a Markdown catch-all.
s#Shape: one or two questions with 4-6 options each, `allow_multiple: true` for category questions\.#Shape: one or two questions with 4-6 options each. Put `multi: true` on each category question object.#
# Cursor's per-item pseudo-spawns become real batches or one-item calls.
s#^2\. \*\*Source wave\.\*\* One read-only subagent per feature file, launched concurrently\.#2. **Source wave.** Start one source-review batch in one `task` call with one item per feature file in `tasks[]`, the required shared `context`, and an exact discovered read-only reviewer agent for each item.#
s#^Spawn one investigator per category that has a matching MCP\.#Assign one investigator to each category that has a matching MCP.#
s#An event to watch \(CI, a merge, a ref advancing\) gets a watcher subagent that wakes you on the event,#For an event to watch (CI, a merge, a ref advancing), start one watcher in one `task` call with one item in `tasks[]`, the required shared `context`, and an exact discovered watcher agent; omit `agent` for the default worker with the watcher role when no specialist is discovered. It wakes you on the event,#
s#One subagent per PR, not batched, each a Cursor cloud agent, each exercising the real surface#Start all PR verifiers in one `task` call with all items in `tasks[]` and the required shared `context`; each item uses an exact discovered reviewer agent, or omits `agent` for the default worker with the reviewer role, and requests an isolated subagent. Each verifier exercises the real surface#
# Recall's shared-record sweep spawns its own investigators now that why has none to hand it.
s#Spawn one investigator subagent per source, in agent mode because readonly strips MCP access, and ask each#Start one investigator per source in one `task` call with all items in `tasks[]` and the required shared `context`. Each needs its source's MCP tools, which omp task agents inherit, so pick workers that expose them. Ask each#

## 2. Model slugs. Tiered by capability first, then a catch-all for anything upstream adds later.

# Opus-first routing (upstream 2f87c85) caps every role at xhigh and always runs Opus on its fast
# slug, so an xhigh fast slug is the default for code, prose, and judgment, not the fast code tier.
# It sits above the fast tier, which still sits above the judgment tiers below so an effort-less or
# lower fast slug stays the fast code model.
s#`claude-[a-z]+-[0-9.-]+-xhigh-fast`#your default judgment model#g
# Cursor's fast slug in a Claude family, effort token in the middle -> the fast code capability.
s#`claude-[a-z]+-[0-9.-]+-([a-z]+-)?fast`#your fast code model#g
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
# Cursor's third-vendor panel slug, with or without an effort suffix (`gemini-4-neon`,
# `gemini-4-neon-xhigh`) -> the capability a panel uses it for.
s#`gemini-[0-9.]+-[a-z]+(-[a-z]+)?`#your strongest model from another vendor#g
# Catch-all for a slug no tier above knows. Two hyphen groups required, so a short illustrative
# name such as `gpt-4` is not read as a prescription. omp-port reports what this rewrote.
s#`(claude|gpt|grok|gemini|opus)-[a-z0-9.]+-[a-z0-9.-]+`#your configured model for this role#g

## 3. Remaining exact task text and generated frontmatter.

# These exact Cursor tool tokens survive only in otherwise rewritten sentences.
s#AskQuestion#ask#g
s#Substituting `generalPurpose` skips that read and drifts\.#Substituting `task` (omp's general-purpose bundled agent) skips that read and drifts.#
# Cursor agent frontmatter `is_background` -> omp does not model it.
/^is_background: true$/d
# A frontmatter slug pins an agent to a Cursor model. omp resolves an agent's model from
# task.agentModelOverrides, then frontmatter, then the parent, and the port ships poteto-agent with
# no model line so it inherits the chat model.
/^model: (claude|gpt|grok|gemini|opus|composer|cursor)-[a-z0-9.-]+$/d
# omp gates nested spawning per agent definition, which Cursor has no counterpart for.
/^name: poteto-agent$/a spawns: "*"
# The router and its agent must name the omp levers file themselves, not only the pin reminder,
# so an unpinned read of skill://poteto-mode or a spawned poteto-agent still finds it.
s|^## Non-negotiables$|## Non-negotiables\n\n**Read `skill://omp-mechanics` and `skill://pstack-omp` right after this file.** `pstack-omp` is the sole live task, vibe, eval, and runtime contract. `omp-mechanics` keeps only pstack-specific OMP deltas.|
s#Reads the `poteto-mode` skill's `SKILL.md` in full before any work, including its inline Principles index\.#Reads the `poteto-mode` skill's `SKILL.md` in full before any work, including its inline Principles index, then `skill://omp-mechanics`.#

## 4. Cloud agents. Cursor runs them on its own VMs; omp runs isolated subagents on this machine.

s#`environment: "cloud"`#`isolated: true`#g
# `cloud_base_branch` is not accepted by omp's task tool; a worktree on that base is the answer.
s#When a worker must start from a non-default pushed branch, pass `cloud_base_branch`\.#When a worker must start from a non-default base, create its `git worktree` on that base first and point the worker at that path.#
s#One Cursor cloud agent#One isolated subagent (`isolated: true`)#g
s#each a Cursor cloud agent#an isolated subagent (`isolated: true`)#g
s#is a Cursor cloud agent#is an isolated subagent (`isolated: true`)#g
# Cursor's cloud PR tooling defaults to draft; omp's github tool defaults to ready.
s#Cloud-agent PR tools default to draft, so set `draft: false` on every PR creation call\.#omp's `github` tool opens a ready PR from `op: "pr_create"` unless you pass `draft: true`, so leave that flag off.#
s#Fan out N parallel cloud workers\.#Fan out N parallel workers.#
s#N is total workers, not the cloud concurrency limit\.#N is total workers. `task.maxConcurrency` in `~/.omp/agent/config.yml` caps how many run at once.#
# Cursor hands out a cloud-agent URL; omp's prior-run handles are internal URIs.
s#cloud-agent URL#prior agent's `history://<id>` or `agent://<id>`#g
# Cursor's local-versus-cloud split -> shared parent checkout versus a private worktree.
s#Restacks run in cloud\. A local restack at this scale takes the laptop down\.#Restacks run in an isolated subagent with its own worktree, never in the parent checkout.#
s#a Cursor restart#an omp restart#g
s#cloud agent#isolated subagent#g

## 5. Wake mechanisms. Cursor's `/loop` builtin and cloud sleeper -> omp's `/loop`, named bash processes, and systemd.

s#Drive a long or stubborn hunt with Cursor's `/loop` command\.#Drive a long or stubborn hunt with omp's `/loop`, which re-submits the same prompt after every yield. State the exit condition as a shell command and pass it as `--until '<cmd>'`, which gates each iteration on that command's exit status.#
s#Pick the wake mechanism using Cursor's `/loop` command \(a built-in, not a pstack skill\)\.#Pick the wake mechanism. In session, omp's `/loop [count|duration] [--while|--until '<cmd>'] [prompt]` re-submits the same prompt after every yield and gates each iteration on a shell command's exit status. A wake that must land out of session runs as a named bash process observed through `proc://`, or under a systemd user timer.#
s#A local root arms each tick as a real terminal `/loop`\. The loop uses a monitored-shell 30-minute sleep and emits an output-notification sentinel\.#A root in session arms each tick with omp's `/loop`, which re-submits the tick prompt after every yield.#
s#A cloud root uses the existing cloud-sleeper wake chain instead\.#A wake that has to land out of session runs as a named bash process observed through `proc://`, or under a systemd user timer instead.#
s#In a local session, a real terminal `/loop`\. In a cloud root, a cloud-sleeper wake chain\.#In session, omp's `/loop`. For a wake that must land out of session, use a named bash process observed through `proc://`, or a systemd user timer.#
# Cursor's Babysit modes. `drive`, `threads-only`, and `check` are Cursor commands with no omp
# counterpart: the port's own watcher declares WatchMode "single" | "stack" | "queued-stack" with no
# mode argument at all. Each mode is named as an invocation of scripts/watch-pr/watch-pr, which is
# what the playbook already points at for the verdict.
s#^- Declare the mode in your first line, before any poll\. Modes: `drive` loops to merge-ready, `threads-only` touches only review threads, `check` is one status pass and a report\.$#- Name the watcher invocation in your first line, before any poll. `drive`, `threads-only`, and `check` name no command on this runtime; each is a way to invoke `scripts/watch-pr/watch-pr`. To loop to merge-ready, invoke the watcher bare and let it poll to a terminal verdict. To touch only review threads, stop on the watcher's `BLOCKER` verdict with reason `review-threads` and work only those threads. For one status pass and a report, pass `--status-only`.#
s#status comes from the mode's watcher at#status comes from the watcher at#
s#In `check` mode pass `--status-only`\.#For a single status pass, pass `--status-only`.#
s#\*\*Reply:\*\* the mode, the frontier and its active-forge state#**Reply:** the watcher invocation, the frontier and its active-forge state#
s#Hold the watch under `/loop` in dynamic mode\.#Hold the watch under omp's `/loop` while `loop.mode` is `prompt`, or under a named bash process observed through `proc://` when the wake must land out of session.#
s#`/loop` per component until the diff is zero\.#Hold a named bash process observed through `proc://`, or a systemd timer, per component until the diff is zero.#
s#"/loop until X"#"run until X"#g
# Cursor's default goal arming needs an omp-specific fallback that preserves the predicate.
s#arm a `/goal` with the full program objective\.#arm a `/goal` with the full program objective. Use `/goal` only if exposed and enabled; otherwise retain the predicate in the durable plan. Do not change global configuration.#g
s#arm a `/goal` with this exact text\.#arm a `/goal` with this exact text. Use `/goal` only if exposed and enabled; otherwise retain the predicate in the durable plan. Do not change global configuration.#

## 6. cursor-team-kit. Cursor's companion plugin -> omp's built-in tools.

# `/deslop` -> the `unslop` skill plus the repository's own non-mutating diagnostics, scoped to the
# diff. Never `omp cleanse`: its CLI help reads "Detect and fix project diagnostics with weighted
# parallel subagents", so `--all` runs every discovered checker repo-wide and edits unrelated files.
# The gate's `runtime unscoped-cleanup` check rejects the command if it ever comes back.
s#the `deslop` skill from the `cursor-team-kit` plugin \(`/deslop`\)#the `unslop` skill (`skill://unslop`) plus non-mutating repository diagnostics scoped to the diff#g
s#Run `/deslop` from `cursor-team-kit` over the diff before commit#Run the `unslop` skill (`skill://unslop`) and non-mutating repository diagnostics scoped to the diff before commit#
# The router's one-line commit trigger names the same companion plugin without the skill wrapper.
s#`/deslop` from the `cursor-team-kit` plugin#the `unslop` skill (`skill://unslop`) plus non-mutating repository diagnostics scoped to the diff#g
s#`/deslop`#the `unslop` skill (`skill://unslop`)#g
# `control-ui` / `control-cli` -> browser, computer, and named bash processes.
s#\(`control-cli` or `control-ui` from `cursor-team-kit` as the change demands\)#(`browser` or `computer` for UIs, bash with a unique `name`, a `ready` check, and `proc://` state for CLIs and TUIs, as the change demands)#
s#\(`control-ui` or `control-cli` from `cursor-team-kit` as the change demands\)#(`browser` or `computer` for UIs, bash with a unique `name`, a `ready` check, and `proc://` state for CLIs and TUIs, as the change demands)#
s#Shipping UI / IDE / CLI → `control-ui` or `control-cli` from `cursor-team-kit`\.#Shipping UI / IDE / CLI → the matching control surface. omp provides the levers directly. Bash with a unique `name`, `ready` checks, and `proc://` state drives CLIs and TUIs, the `browser` eval prelude drives browser, Electron, and web UIs over CDP, and the `computer` prelude drives native desktop. Both preludes are code in an `eval` cell and neither is a tool with its own schema.#
s#`control-ui`#the `browser` eval prelude#g
s#`control-cli`#bash with a unique `name`, a `ready` check, and `proc://` state#g
s#`cursor-team-kit`#omp's built-in tools#g
s#cursor-team-kit#omp's built-in tools#g

## 7. create-skill. Cursor's SKILL.md authoring builtin -> pstack's own authoring playbook.

# The playbook cannot route to itself, so its step 1 states the omp authoring path directly.
s#^1\. Use the \*\*create-skill\*\* skill \(Cursor's built-in for authoring SKILL\.md files\)\.$#1. Write the SKILL.md yourself with `write` or `edit`. omp's `manage_skill` writes only under `~/.omp/agent/managed-skills` and never touches a user-authored skill. Give it YAML frontmatter with `name` matching its directory, a `description` naming what the skill does and when to reach for it, and `disable-model-invocation: true` so it stays out of the per-turn index.#
s#the \*\*create-skill\*\* skill \(Cursor's built-in for authoring SKILL\.md files\)#the **authoring-a-skill** playbook (`playbooks/authoring-a-skill.md`)#g
s#A `create-skill`-style#An `authoring-a-skill`-style#g
s#Cursor's built-in `create-skill` skill#the `authoring-a-skill` playbook#g
s#Cursor's built-in `create-skill`#the `authoring-a-skill` playbook#g
s#`create-skill`'s#the `authoring-a-skill` playbook's#g
s#via create-skill \+ unslop#via the authoring-a-skill playbook + unslop#g
s#`create-skill`#the `authoring-a-skill` playbook#g

## 8. Transcripts. Cursor's per-project transcript directory -> omp's session store.

s#`~/\.cursor/projects/<slug>/agent-transcripts/<uuid>/<uuid>\.jsonl`#the session store, by default `~/.omp/agent/sessions/<encoded-cwd>/<timestamp>_<session-id>.jsonl`#
s#where `<slug>` is the workspace path with the leading slash dropped and each "/" turned into "-" \(so `/Users/you/proj` becomes `Users-you-proj`\)#where `<encoded-cwd>` is the cwd with $HOME stripped and each "/" turned into "-" (so `~/proj` becomes `-proj`)#
s#Every line is one chat message\.#Every line is one JSON object. The first is a fixed-width `type:title` slot, the second a `type:session` header, and the rest messages whose roles are camelCase (`toolResult`, not `tool_result`).#
# No omp system prompt names a transcript path. The session-store reference resolves the root, so
# automate-me's locate step points there. Runs before the directory token below rewrites half of it.
s#The system prompt names the workspace's `agent-transcripts/` directory\.#Resolve the session transcript tree, by default `~/.omp/agent/sessions/<encoded-cwd>/*.jsonl` with subagent sidecars at `<session-stem>/<AgentId>.jsonl`, through `skill://omp-mechanics/references/session-store-on-omp.md`.#
s#the active workspace's `agent-transcripts/` directory#the session transcript tree `~/.omp/agent/sessions/<encoded-cwd>/*.jsonl`, with subagent sidecars at `<session-stem>/<AgentId>.jsonl`#g
s#the workspace's `agent-transcripts/` directory#the session transcript tree `~/.omp/agent/sessions/<encoded-cwd>/*.jsonl`, with subagent sidecars at `<session-stem>/<AgentId>.jsonl`#g
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
s#The pinned and active chats are the real artifact \(principle-prove-it-works\)\. Get that set from the user or sidebar and cross-check every candidate\. The lever has marked `safe` a worktree the user had pinned, so the pinned set wins\.#The live omp sessions are the real artifact (principle-prove-it-works). Get that set from `read history://` plus the session store at `~/.omp/agent/sessions/<encoded-cwd>/`, confirm it with the user, and cross-check every candidate. The lever has marked `safe` a worktree a live session still owned, so the live set wins.#
s#report whether the chat is pinned or ongoing and which worktrees it touches#report whether the session is still live and which worktrees it touches#
s#A pinned chat spawns arena and repro trees into sibling worktrees via background subagents, and those are in use even when their names never hit the sidebar\.#A live session spawns arena and repro trees into sibling worktrees via background subagents, and those are in use even when `read history://` never names them.#
# Cursor exposes enabled MCP servers as a directory; omp lists them in one config file.
s#Before spawning investigators, list the available MCPs from the Cursor environment\. Use the available-tools map when present\. Otherwise inspect the `mcps/` directory Cursor exposes for enabled MCP servers\.#Before spawning investigators, list the available MCPs from the session environment. Use the available-tools map when present. Otherwise read `~/.omp/agent/mcp.json` for enabled MCP servers.#
# Bugbot is a Cursor product, so the rubric names what plays its part on omp.
s#^Use this reference when the Babysit playbook \(`\.\./playbooks/babysit\.md`\) handles Bugbot or review-automation comments\.#Use this reference when the Babysit playbook (`../playbooks/babysit.md`) handles Bugbot or review-automation comments. Bugbot is Cursor's hosted review product, so without it this rubric applies to whatever review bot posts on your PRs, including omp's own `security-reviewer`.#
s#`,? in place of the `(arena|architect|swarm|interrogate) reviewers?` line##g
s#the `arena cross-judge pool` line in the `pstack-models\.mdc` rule#an exact discovered judge agent whose configured model differs from the parent's when the roster provides one#g
# Upstream's effort-matching step names the role's own line, which is a Cursor key on omp. The
# capability it stands for is the budget the setup skill writes, so point there instead.
s#the role.s line or default#the role's entry in `~/.omp/agent/config.yml`, or its default#g
s#the `swarm workers` model and speed \(your fast code model by default\)#the swarm role's own entry and speed#g
s#the `(architect|arena|swarm|interrogate) runners` line in the `pstack-models\.mdc` rule#the exact discovered runner agents#g
s#the `interrogate reviewers` line in the `pstack-models\.mdc` rule#one exact discovered reviewer agent per configured entry#g
s#the `arena cross-judge pool` line in `~?/?\.cursor/rules/pstack-models\.mdc`#an exact discovered judge agent whose configured model differs from the parent's when the roster provides one, in `~/.omp/agent/config.yml`#g
s#the `(architect|arena|swarm|interrogate) runners` line in `~?/?\.cursor/rules/pstack-models\.mdc`#the exact discovered runner agents in `~/.omp/agent/config.yml`#g
# The last two Cursor role labels. Same reasoning as the runner lines above: the label is a key
# in a rule file that omp does not have, so naming it names nothing. The capability it stood for
# is what the port writes instead.
s#the `how (explorer|explainer)` line#an exact discovered \1 agent in `~/.omp/agent/config.yml`#g
s#one per entry on the `interrogate reviewers` line in `~?/?(\.cursor/rules/pstack-models\.mdc|task\.agentModelOverrides in ~?/?\.omp/agent/config\.yml)`#one per configured entry in `~/.omp/agent/config.yml`#g
s#Set `model` to that line.s value, or to the default if the rule or the line is missing\.#Each discovered agent's frontmatter or `task.agentModelOverrides[<exact-name>]` selects its model; the item has no `model` field.#g
s#Leave `model` unset when the value is `auto` or `inherit-parent`\.#An `auto` or `inherit-parent` entry means the parent chat model, so omit that role from the map.#g
s#the `interrogate reviewers` line in `~?/?\.cursor/rules/pstack-models\.mdc`#one exact discovered reviewer agent per configured entry in `~/.omp/agent/config.yml`#g
s#the `architect runners` line in the `task\.agentModelOverrides` entries in `~/\.omp/agent/config\.yml`#the same exact discovered runner agents Arena uses, with the architect role in each brief, in `~/.omp/agent/config.yml`#g
s#an exact discovered (why investigators|why synthesizer|interrogate reviewers|swarm workers|architect runners|arena runners|arena cross-judge pool|reflect tooling|reflect judgment, divergent, synthesizer) agent#an exact discovered agent filling that role#g
# A single spawn is still one task call with one item and the required shared context. Each rule
# appends that clause after the whole sentence, because the noun phrase after "spawn one" varies
# ("one blinded judge", "one owner per PR") and a word-level match split it.
s#(Spawn one explainer that explores and explains in one pass, built from `references/explainer-prompt\.md` without the explorer-findings section\.)#\1 Start it in one `task` call with one item in `tasks[]` and the required shared `context`.#
s#(spawn one explainer with `references/explainer-prompt\.md` and every explorer's findings filled in\.)#\1 Start it in one `task` call with one item in `tasks[]` and the required shared `context`.#
s#(\*\*Spawn one blinded judge\*\* on a different model family per the \*\*arena\*\* skill's Phase C\.)#\1 Start it in one `task` call with one item in `tasks[]` and the required shared `context`.#
# Owners run in parallel off trunk (step 3 of the same playbook), so they start together in one
# batch.
s#\*\*Spawn one owner per PR, and keep its work#**Spawn one owner per PR, all in one `task` call with one item per PR in `tasks[]` and the required shared `context`, and keep its work#
s#, in place of the .(arena|architect|swarm|interrogate) runners. line#.#g
s#`agent`: an exact discovered (how explorer|how explainer) (agent|line)#`agent`: an exact discovered agent filling that role#g

# Net for any Cursor home path a later upstream commit introduces. The model-rule file is named
# before the general net because omp has no rules directory: a specific rule that missed on a
# reworded sentence used to leave this for the net to turn into a path that resolves to nothing.
# The role label is Cursor's key name and dies with Cursor's rule file. omp keys the map by exact
# agent name, so "the `arena runners` line" names a key that does not exist, and calling it an
# agent is just as wrong. Point at the capability instead: resolve exact discovered runner agents
# and let each one's frontmatter or task.agentModelOverrides entry pick its model. This runs
# before the path rules below so it still sees the upstream path.
s#`~?/?\.cursor/rules/pstack-models\.mdc`#`task.agentModelOverrides` in `~/.omp/agent/config.yml`#g
# The same file named without a path, which upstream does in the sentences above. Pointing it at
# the config is correct whether or not a path was written, so this matches the bare name too.
s#the `pstack-models\.mdc` rule#the `task.agentModelOverrides` entries in `~/.omp/agent/config.yml`#g
s#~/\.cursor/#~/.omp/#g
# The built plugin carries its version only in its root `package.json`. Cursor's manifest is not
# shipped, so a selection rule that reads it cannot run.
s#`\.cursor-plugin/plugin\.json`#`package.json` beside its `skills/` directory#g

## 9. Install paths. pstack is vendored in Cursor's monorepo and installed as a plugin on omp.
## Order is load-bearing: the trunk-read rewrites run before the generic pstack/skills/ rewrite,
## which is guarded so it cannot re-match its own output.

s#re-read this playbook from trunk with `git show origin/main:pstack/#re-read this playbook from its install path, `~/.omp/plugins/node_modules/pstack/#g
s#Re-read the execution playbook from trunk and the armed /goal#Re-read the execution playbook from its install path and the armed /goal#g
s#`git show origin/main:pstack/#`~/.omp/plugins/node_modules/pstack/#g
s#([^/])pstack/skills/#\1~/.omp/plugins/node_modules/pstack/skills/#g
# Cursor's npm scope for skill tooling -> the port's own scope.
s#@cursor-skill/#@omp-skill/#g
# Cursor auto-attaches a skill on a file-glob match; omp carries `globs` as metadata only.
s#^paths: \[#globs: [#
# Subagent prompt templates are the one place a wrong tool name is fatal rather than cosmetic:
# the lens greps the transcript for the tools that were called and finds none, so it returns
# nothing. Each pattern carries enough surrounding context to match the instruction and not the
# English verb of the same word.
s#- `Read` tool calls against any#- `read` calls against any#
s#- `Task` prompts that name a skill path#- `task` calls whose brief names a skill path#
s#Use Glob to find directories and files, Grep to find key symbols, Read to understand#Use `glob` to find directories and files, `grep` to find key symbols, `read` to understand#
s#Use Read, Grep, and Glob as needed\.#Use `read`, `grep`, and `glob` as needed.#
# setup-pstack is in omp-port/excluded.txt, so the build ships no such skill. The poteto-help
# sentence rules above point at the omp-mechanics model note; these nets catch a line upstream
# rewords, ahead of the /skill:<name> rule below.
s#\[`/setup-pstack`\]#[Choose models]#g
s#\.\./setup-pstack/SKILL\.md#../omp-mechanics/SKILL.md\#choose-models#g
s#`/setup-pstack`#the Choose models section of `skill://omp-mechanics`#g
# omp registers one slash command per skill as /skill:<name>; a bare /how is not a command on this
# harness, and with `disable-model-invocation: true` the skill is hidden from the index, so the
# model cannot recover it either. The build replaces @skill-names@ with the name of every skill
# directory in the tree it is building, owned skills included and poteto-mode left out, so a skill
# upstream adds is covered the day it lands. poteto-mode is a real extension command, registered
# by the port's own potetomode extension, and its bare form stays.
#
# A name is rewritten when it follows the start of a line, a space, `(`, a backtick, or `"`, and
# nothing that can continue a name, a path, or a longer name follows it: not a letter, digit, `_`,
# `/`, or `-`. So skills/how/, ../how/SKILL.md, skill://how, /how-to, and /reframed stay as they
# are. The rule consumes the one character after the name, which means two names a single space
# apart rewrite only the first; the `skill command form` check fails such a line rather than
# letting it ship.
s#(^|[ (`"])/(@skill-names@)([^A-Za-z0-9_/-]|$)#\1/skill:\2\3#g
# One verdict vocabulary. pstack-omp and swarm both name PASS/ISSUES/BLOCKED; shipping named a
# different three, and its landing rule tested for a different set, so a verifier told by one file
# and checked by another could not satisfy both.
s#posts `PASS`, `PASS\+NOTES`, or `FAIL` on that PR\.#posts `PASS`, `ISSUES`, or `BLOCKED`, the three verdicts `skill://pstack-omp` and **swarm** use, on that PR. Notes ride on a `PASS` rather than forming a fourth verdict, so a passing run with observations is still a pass.#
s#stop at the first one without `PASS` or `PASS\+NOTES`\.#stop at the first one whose verdict is not `PASS`.#
# Cursor's help names another harness's install commands and an adapter the port does not ship.
s#^pstack is built for Cursor, and it also installs in Claude Code with .*a one-line note\.$#pstack installs in omp with `/marketplace add negoro26/pstack-omp`, then `/marketplace install pstack@pstack-omp`. Invoke skills as `/skill:<name>`, such as `/skill:poteto-mode`. Read `skill://pstack-omp` for the live task and runtime contract and `skill://omp-mechanics` for pstack-specific OMP differences.#

## 10. Irreversible actions, and what the runtime actually enforces. Every replacement below
## exists because the original either contradicted another sentence in the same tree, named a
## surface omp does not have, or told an agent to do something the harness cannot stop. The
## machine half is plugins/pstack/extensions/pstackpolicy, which refuses the forge mutations
## unless the operator set PSTACK_LANDING_GRANT; prose alone cannot, because yolo auto-approves
## the exec tier and every pstack owner is a headless subagent.

# Landing is the one action the port routes a human toward and then never gated. The --auto branch
# of this same step already carries "and the user asked"; the immediate branch did not, so an agent
# reading step 5 alone had licence to merge under yolo with nothing to stop it.
s#If the bottom PR is mergeable now, squash it with#Merge only on an explicit request. If the bottom PR is mergeable now and the user asked to land, ship, or merge it, squash it with#

# The pause list is the port's only global gate and it omitted every forge action its own
# autopilots perform, so those actions fell through it entirely.
s#^\*\*Always pause\*\* for irreversible writes: force-push to shared branches, deploys, data deletion, customer messages\.$#**Always pause** for irreversible writes: pushing to trunk, merging a pull request, retargeting a pull request base, force-pushing a shared or trunk branch, closing a pull request, an issue, or a review thread, posting a review or review comment, resolving a review thread, deleting a branch on the forge, deploys, data deletion, customer messages.#

# Two lines below an unqualified "keep going" reads as "do not pause". It is not; it is the
# autonomy switch for reversible work.
s#^\*\*Session overrides:\*\* "Don't stop" / "going to bed" / "run until done" / "be fully autonomous" → keep going\.$#**Session overrides:** "Don't stop" / "going to bed" / "run until done" / "be fully autonomous" → keep going on reversible work. They never waive the pause list above; a request to be autonomous is not authorisation to land.#

# The worker kickoff's stop list (poteto-mode/worker.md) is upstream's copy of the router's pause
# list. It names the port's pause list verbatim and in order, so a worker stops for every forge
# action the router pauses for and pstackpolicy refuses.
s#Stop only for a deploy, deleted data, a force-push to a shared branch, or a message to someone outside the run\.#Stop only for pushing to trunk, merging a pull request, retargeting a pull request base, force-pushing a shared or trunk branch, closing a pull request, an issue, or a review thread, posting a review or review comment, resolving a review thread, deleting a branch on the forge, deploys, data deletion, or customer messages.#

# Leftover mode vocabulary. The four Cursor modes are gone, so naming one here contradicts the
# playbook this index points at.
s#\*\*You own the merge frontier\. Declare a mode, clear one PR at a time, stop where the human's call begins\.\*\*#**You own the merge frontier. Name the watcher invocation, clear one PR at a time, stop where the human's call begins.**#

## 11. Residual accuracy fixes. Each of these is a sentence that was wrong, incomplete, or
## contradicted another sentence in the same tree. None is a Cursor residue; they are the port's
## own claims about itself, which is the class nothing upstream can fix for us.

# autopilot-stack grants --force-with-lease and base retarget but omits the one line its sibling
# carries verbatim, so an agent reading only this playbook has licence to rewrite any branch in the
# chain, including one a human pushed to.
s#push with `--force-with-lease` only after an `ls-remote` check, and set the PR base to the parent branch\.#push with `--force-with-lease` only after an `ls-remote` check, and set the PR base to the parent branch. Never force-push a shared branch.#

# shipping step 4 retargets a base with no consent clause, and step 7 re-runs steps 3-6 for every PR
# in the stack, so an unguarded retarget here reaches the whole chain.
s#4\. \*\*Prepare only the bottom PR\.\*\* Fetch current trunk\.#4. **Prepare only the bottom PR**, and retarget only on the operator's explicit go: an operator approval to land a PR is not approval to rewrite the base of every PR above it. Fetch current trunk.#

# The autonomy sentence contradicted the pause-list scope added in section 10, and the index routes
# "full autopilot" straight here, so the trigger phrase the operator types is the phrase that clause
# disqualified.
s#The operator's full-autonomy grant plus the root's clean verdict is the merge authorization that babysitting alone never has\.#A full-autonomy grant authorises the owner to keep working without checking in; the root's clean verdict authorises a merge only inside that grant. Neither is implied by "go faster", and both still require the operator to have armed PSTACK_LANDING_GRANT for the merge itself.#

# `trash` is macOS, so the step could not be followed on this host, and the sentence forbade the one
# fallback that would work. Handled in zz-live-runtime-routing.patch instead, because that line is
# the patch's own output and a sed rule cannot see it.

## 12. Graphite. Four playbooks say "Never require Graphite (`gt`)", so no sentence may make `gt`
## mandatory or authoritative.

s#- Workers never rebase and never run `gt`\.#- Workers never rebase and never touch stack topology.#


## 12. Findings from a 71-agent per-file audit. Each rule here is a sentence that survived the
## rewrite and is wrong on omp. They cluster into two classes worth remembering: a document
## rewritten on one side of a page and not the other, and a paraphrase of a harness rule that
## dropped half of it. Both are invisible to a diff that only looks for Cursor vocabulary.

# `cursor location` is a Cursor composer affordance: the editor injects the caret position. omp is
# a terminal harness with no editor-state primitive, so an agent following the hint looks for a
# signal that does not exist.
s#open files, recent edits, cursor location, what was just discussed#open files, recent edits, what was just discussed#

# False: a subagent's `tools:` list does not remove MCP tools or server instructions
# (omp://system-prompt-customization.md). The real restriction on `scout` is the tool set, not MCP.
s#The strict `scout` definition has no MCP grant, so never assign MCP work to it\.#The strict `scout` definition has no write tools, so keep it off any lane that must edit. Its MCP tools are inherited: a task agent's `tools:` list does not remove them.#
s#an exact discovered full-access worker for citation spot-checks that call MCP\. The strict `scout` definition cannot serve that lane\.#an exact discovered full-access worker for citation spot-checks that call MCP. `scout` inherits MCP tools and can serve that lane, but it cannot write.#
# `subagents/` is a Cursor transcript layout level. On omp the third level is
# `<session-stem>/<AgentId>/<AgentId>.<Step>.jsonl`, and the prescribed glob matched 0 files against
# 181 that exist. The prose one line below was corrected; the command was not.
s#/\*/subagents/\*\.jsonl#/*/*/*.jsonl#

# No omp system prompt names the session transcript tree; `history://<id>` is the documented
# surface. The path is correct, the justification for trusting it was not. Eval says "this path",
# session-pickup and show-me-your-work say "the path".
s#the system prompt names (the|this) path#`history://<id>` is the documented surface#

# omp discovers skills one level under the root; the nested shape this prescribes is explicitly
# not discovered, so the skill it produces silently never registers.

# Unqualified force-push blocks the port's own rebase flow, which `pstackpolicy` explicitly permits
# and `autopilot-stack` prescribes. Scope the pause the way the rest of the port scopes it.
s#force-push, delete production data, send external messages#force-push to a shared or trunk branch, delete production data, send external messages#

## 13. Cursor's `Task` tool name. omp's tool is lowercase `task`, and capitalised it names nothing.
## Last on purpose: every sentence rule above quotes the capitalised form in its left-hand side, so
## this net only ever sees what no sentence rule claimed. The gate's `cursor tool names` check
## fails on any `Task` that survives it.

s#`Task`#`task`#g
s#the Task tool#the `task` tool#g
s#every Task spawn#every `task` spawn#g
s#then suggests a bucket\. The transcript scan is slow, so background it\.#then suggests a bucket. `hold-unpushed` means the worktree holds commits that exist nowhere else (ahead of its remote, no remote branch, or detached and not on the base, and HEAD is not the head of one of its PRs); push them or get a decision before anything else. A closed-but-unmerged PR is not evidence the work is safe. A `LAST_CHAT` of `?` means the omp session store could not be read, so the row holds at `verify-recent-chat`. The transcript scan is slow, so background it.#
s#`wip:N` is N tracked uncommitted edits\. Show the diff and get a decision first, since removing a clean worktree is recoverable from its branch but uncommitted work is gone\. `scratch:N` is untracked throwaway, safe to drop, but name the files\.#`wip:N` counts tracked, untracked, and ignored paths. For each candidate, run `git -C <worktree> status --porcelain=v1 --untracked-files=all --ignored=matching`; show diffs for tracked edits and list untracked and ignored paths without opening their contents, and get a decision first, since removing a clean worktree is recoverable from its branch but none of those files are. Never treat untracked or ignored files as disposable scratch.#
s#Per path, `git worktree remove --force <path>`\. If the dir survives on ignored build artifacts, `rm -rf` it, then `git worktree prune`\.#Re-run the step 4 status preflight immediately before removal, then per path `git worktree remove <path>`, which can still delete ignored-only files, so it is not a preservation check. If Git refuses, stop and retain the worktree; never `rm -rf` it or `git worktree prune` to bypass the refusal.#
