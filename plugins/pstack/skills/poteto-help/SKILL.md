---
name: poteto-help
description: Guides users through pstack setup, /poteto-mode, and picking the skill, playbook, or principle for a task. Type /poteto-help with a question.
disable-model-invocation: true
---

# Poteto help

Answer the user's question about pstack, hand them a prompt they can send, and link the file the answer came from. For a help question, don't start the work. The user asked how, and a pstack run spends real tokens, so let them send the prompt.

A message that asks for work, such as "use pstack to fix this bug", is not a help question. Read [`poteto-mode`](../poteto-mode/SKILL.md), do the work under it, and mention once that `/poteto-mode on` keeps it pinned.

This file maps questions to the skills and guide pages that hold the answers. Those files own the details. Read the file you route to before you quote it, and trust it when it disagrees with this map. Link installed skill and runtime files directly. For a public copy of ported behavior, use `https://github.com/negoro26/pstack-omp/blob/main/plugins/pstack/` followed by the installed plugin-relative path. Guide URLs point to upstream for workflow background only; use this port's README and runtime skills for OMP commands.

## Find out what they need

Infer the need from the message and the conversation. A named situation, such as "which skill reviews a PR?", goes straight to its section. If the need is still unclear, ask one multiple-choice question with these options, then answer only the section they pick:

- Get set up
- Start a task with `/skill:poteto-mode`
- Pick a skill for a situation
- Fix a run that went wrong
- Make pstack my own

Check the state that changes the answer, and mention it only when it does:

- No exact override for a role means its loaded agent frontmatter or the parent chat model selects its model. Absence of an override does not prove setup was never run.
- No `verify-*` skill or other app harness in the project means agents have no scripted way to drive the app. Mention `/skill:create-verification-skill` when the question is about proving a change works.
- No formal verification skill in the project means no property is checked past what tests reach. Mention `/skill:create-formal-verification-skill` when the question is about a race, an invariant, or another case tests rarely hit. When one exists and the code it covers changed after the commit it records as last in sync, mention `/skill:maintain-formal-verification-skill` if the question touches that code.

When required role overrides are missing and model selection matters, ask whether the user wants to pick a model for each role and a reasoning budget now. It matters when the user is new, the question is about setup or cost, or the answer depends on which models run. Ask at most once per chat. If the need is also unclear, ask both questions together. Offer two choices:

- Now: give them `/skill:setup-pstack` to type, and answer their question too.
- Later: answer their question, and say agent frontmatter or parent inheritance remains in effect until they configure exact role overrides.

## Get set up

1. Install with `/marketplace add negoro26/pstack-omp`, then `/marketplace install pstack@pstack-omp`.
2. Run [`/skill:setup-pstack`](../setup-pstack/SKILL.md). It selects models and a reasoning budget for exact discovered agents, writing three pstack-owned `modelRoles` aliases and `task.agentModelOverrides` entries in `~/.omp/agent/config.yml`. It does not create missing agents or select the chat model. Read the skill for activation and optional verification-skill setup.
3. Start a real task with `/skill:poteto-mode`, a goal, and a check that can pass or fail.

Skills run when invoked or routed. The installed extension also provides the session pin commands. `setup-pstack` is available for model-configuration requests. The [README](../../README.md) and [guide page 1](https://github.com/cursor/plugins/blob/main/pstack/docs/guide/01-setup.md) have the details. Offer to word their first prompt with them, per [`references/prompting.md`](references/prompting.md).

If cost is the worry, explain that extra workers and review panels spend more tokens. Rerun `/skill:setup-pstack` to choose a smaller reasoning budget or cheaper available models. An agent without a model override uses its frontmatter or inherits the chat model. Fewer configured reviewer slots mean fewer subagents. Never write `auto` or `inherit-parent` as an OMP model selector. Save `/skill:poteto-mode` for work that needs rigor.

pstack installs in omp with `/marketplace add negoro26/pstack-omp`, then `/marketplace install pstack@pstack-omp`. Invoke skills as `/skill:<name>`, such as `/skill:poteto-mode`. Read `skill://pstack-omp` for the live task and runtime contract and `skill://omp-mechanics` for pstack-specific OMP differences.

The engineering workflows come from upstream. `skill://pstack-omp` maps worker execution and lifecycle to OMP; `skill://setup-pstack` configures OMP models, and the mode extension preserves the session pin.

## Start a task with `/skill:poteto-mode`

`/skill:poteto-mode` matches the task to a playbook, copies the playbook's steps into the todo list, and runs the other skills as the steps need them. A step it skips stays in the list as `skip: <reason>`. A good prompt states the goal and how to tell it's done. It doesn't list skills, because a hand-written sequence tends to drop or reorder steps the playbook would keep. Read [`references/prompting.md`](references/prompting.md) before you help word one. [Guide page 2](https://github.com/cursor/plugins/blob/main/pstack/docs/guide/02-poteto-mode.md) has examples.

Choose whether to invoke the router once or pin it for the session:

- `/skill:poteto-mode` invokes the router for a task; it does not enable the persistent pin.
- `/poteto-mode on` pins the router for every turn, `/poteto-mode off` unpins it, and `/poteto-mode status` reports the current pin. These are the installed extension's OMP commands, not Cursor's Custom Mode UI.
- The extension registers Alt+Shift+T to toggle the pin when the terminal delivers that key. For print-mode runs use `omp --poteto -p '<task>'`. Do not claim Cursor's platform shortcuts work here.

Link the installed [OMP README](../../README.md) for pin commands and [runtime mapping](../pstack-omp/SKILL.md) for delegation. Mid-chat, "new task" makes the router match a fresh playbook. Resolve any helper against the live agent roster; use `poteto-agent` only when loaded, otherwise follow the runtime mapping's role and default-worker routing.

## Pick a skill

The default answer is `/skill:poteto-mode`, which runs most of the others when its steps need them. Name a skill directly when the user wants more or less of something than the playbook gives. Read the skill before you recommend it, and give one example prompt.

| The user wants to | Skill |
|---|---|
| Do any non-trivial task with rigor | [`/skill:poteto-mode`](../poteto-mode/SKILL.md) |
| Check that the agent understood their goal and the problem before it starts | [`/skill:in-your-own-words`](../in-your-own-words/SKILL.md) |
| Get a prompt rewritten deeper, not bigger, before sending it: what a top professional would add, their raw material and methods, and an outside check. It returns the prompt and doesn't do the task | [`/skill:sharpen`](../sharpen/SKILL.md) |
| Know how code works now, or where new code should live | [`/skill:how`](../how/SKILL.md) |
| Know why code is shaped this way, or where a number came from | [`/skill:why`](../why/SKILL.md) |
| Understand a change or subsystem, explained plainly | [`/skill:teach`](../teach/SKILL.md) |
| Catch up on their own recent work on a topic | [`/skill:recall`](../recall/SKILL.md) |
| Catch up on what changed in this chat since their last message, in plain words and small visuals, with every item waiting on them listed and decidable from the reply alone | [`/skill:ketchup`](../ketchup/SKILL.md) |
| Catch up like `/skill:ketchup`, in a short silent video of slides, with the waiting calls as text under it | [`/skill:ketchup-video`](../ketchup-video/SKILL.md) |
| Know what a small diff could break outside itself | [`/skill:blast-radius`](../blast-radius/SKILL.md) |
| Settle types and module shape before code that crosses a function boundary | [`/skill:architect`](../architect/SKILL.md) |
| Get several attempts at one brief, merged into the best one | [`/skill:arena`](../arena/SKILL.md) |
| Run parallel checks over slices, or race workers, as isolated subagents | [`/skill:swarm`](../swarm/SKILL.md) |
| Have different models review a diff and try to break it | [`/skill:interrogate`](../interrogate/SKILL.md) |
| Fix a bug test-first when a cheap local test exists | [`/skill:tdd`](../tdd/SKILL.md) |
| Apply TypeScript rules to `.ts` or `.tsx` work | [`/skill:typescript-best-practices`](../typescript-best-practices/SKILL.md) |
| Strip comments before review, using a reviewer that didn't write them | [`/skill:no-comments`](../no-comments/SKILL.md) |
| Clean AI tells out of prose | [`/skill:unslop`](../unslop/SKILL.md) |
| Write docs, an RFC, a README, a PR description, or a commit message to a standard | [`/skill:technical-writing`](../technical-writing/SKILL.md) |
| Hear the last reply again in plain words | [`/skill:bro`](../bro/SKILL.md) |
| Give agents a scripted way to drive the app and prove behavior | [`/skill:create-verification-skill`](../create-verification-skill/SKILL.md) |
| Bring a verification skill and its feature map back in line with the app | [`/skill:maintain-verification-skill`](../maintain-verification-skill/SKILL.md) |
| Formally verify a race, invariant, or other property that tests rarely reach | [`/skill:create-formal-verification-skill`](../create-formal-verification-skill/SKILL.md) |
| Bring a formal verification back in line after the code it covers changed, and learn whether a failure is drift or a bug | [`/skill:maintain-formal-verification-skill`](../maintain-formal-verification-skill/SKILL.md) |
| Show a PM or designer what the user sees as a chart checked by a TLA+ model, with the shortest path to each state that breaks a rule | [`/skill:statechart`](../statechart/SKILL.md) |
| Vet a performance number before reporting or acting on it | [`/skill:benchmark-checklist`](../benchmark-checklist/SKILL.md) |
| Run a large or cross-cutting change, or one to review after stepping away | [`/skill:figure-it-out`](../figure-it-out/SKILL.md) |
| Keep a decision log during a run, and review it afterward | [`/skill:show-me-your-work`](../show-me-your-work/SKILL.md) |
| Pick a model for each role and a reasoning budget | [`/skill:setup-pstack`](../setup-pstack/SKILL.md) |
| Turn their own working habits into a personal mode skill | [`/skill:automate-me`](../automate-me/SKILL.md) |
| Turn what a finished task taught into skill edits | [`/skill:reflect`](../reflect/SKILL.md) |
| Stop agents from repeating the same mistakes in this repo | [`/skill:correct`](../correct/SKILL.md) |
| Build a page whose buttons wake a Grok Bot over a webhook | [`/skill:make-bot-ui`](../make-bot-ui/SKILL.md) |
| Find their way around pstack | `/skill:poteto-help` |

If a skill directory next to this one is missing from the table, read its frontmatter and route by its description. The `principle-*` directories are covered under principles below.

Close calls:

- `/skill:how` explains what the code does. `/skill:why` explains the reasons. `/skill:teach` runs one or both and explains the result plainly.
- `/skill:arena` gives every worker the same brief and merges the best parts. `/skill:swarm` splits work into slices or a race and returns one report.
- `/skill:architect` implements right after it settles the design. Add "with checkpoint" to review the design before it writes code.
- `/skill:interrogate` reviews the diff. `/skill:blast-radius` looks for breakage outside the diff and proves the one fact that makes the change safe.
- `/skill:recall` rebuilds context across recent chats. `/skill:ketchup` covers only this chat since the user's last message. Resuming one specific chat or branch is the Session pickup playbook.
- `/skill:figure-it-out` designs one rigorous run. The Orchestrate playbook runs a program that spans days and many PRs. The Autonomous run playbook drives one task to a finish condition.

Not in pstack:

- Prose cleanup uses `skill://unslop`. Diagnostics use the project's documented read-only checks, with LSP diagnostics only when a live server is configured. OMP exposes browser interaction through its eval prelude and CLI interaction through named bash services and `proc://`. Do not run `omp cleanse` as a diagnostic check.
- `/loop` is an OMP runtime command when exposed. Skill authoring uses the [authoring playbook](../poteto-mode/playbooks/authoring-a-skill.md); there is no assumed Cursor `/create-skill` command.
- pstack has no `/orchestrate` skill. Orchestrate is a `/skill:poteto-mode` playbook. If the slash menu shows `/orchestrate`, another plugin provides it.

## Playbooks and principles

Playbooks are step lists inside `/skill:poteto-mode`, not skills, so they have no slash command. Inside `/skill:poteto-mode`, describing the task picks one, and these phrases name one directly:

- "babysit this pr" or "check on pr 123" runs Babysit. It drives the PR to merge-ready and stops there. It doesn't merge unless the user asks to merge, land, or ship.
- "land the stack" runs Shipping.
- "take over this branch" runs Session pickup.
- "pause safely" runs Pause safely.
- "full autopilot on this queue" runs Autopilot-full. "stack them, don't ship" runs Autopilot-stack.
- "run the eval playbook" runs Eval.

Without `/skill:poteto-mode`, the runtime may route a phrase using other enabled skills. Invoke the router explicitly to select pstack's playbook. The Playbooks section of [`poteto-mode`](../poteto-mode/SKILL.md) lists every playbook and when it applies. [Guide page 6](https://github.com/cursor/plugins/blob/main/pstack/docs/guide/06-verify-and-ship.md) gives upstream workflow examples, not OMP runtime commands.

pstack has no planning skill. For work that spans phases or stacked PRs, asking `/skill:poteto-mode` for a plan runs the [Multi-phase plan playbook](../poteto-mode/playbooks/multi-phase-plan.md), which writes the plan and doesn't implement it. For a design question, the Prototype playbook or `/skill:architect` settles it in code first.

Principles are one-rule skills that `/skill:poteto-mode` reads and cites in its replies. The user rarely invokes one. They steer with the names instead, as in "apply prove it works. show me the real output." Typing `/skill:principle-<name>` loads one on demand. [Guide page 8](https://github.com/cursor/plugins/blob/main/pstack/docs/guide/08-principles.md) lists them.

## Fix a run that went wrong

| Symptom | Fix |
|---|---|
| The mode stopped applying after a few turns | Check `/poteto-mode status`. Use `/poteto-mode on` to pin it, or invoke `/skill:poteto-mode` for each task. |
| A question got treated as the next step of the last task | Say "new task", or say the turn doesn't need the mode. |
| A new model choice had no effect | Confirm the loaded agent name and its exact `task.agentModelOverrides` entry. Follow `/skill:setup-pstack` activation guidance; an override cannot create an agent. |
| Runs cost more than expected | See the cost paragraph under Get set up. |
| A skill didn't load on its own | Invoke `/skill:<name>` explicitly or let the router load it. Only skills enabled for model invocation appear in the per-turn index. |
| Parallel agents overwrote each other | Give each agent its own worktree, or run them as isolated subagents, which get private worktrees, not separate machines. |
| An overnight run moved but finished nothing | `/loop` needs a check that can pass or fail, not a duration. See [guide page 7](https://github.com/cursor/plugins/blob/main/pstack/docs/guide/07-overnight.md). |
| The reply claims success from a green build | Ask for the real command, flow, stored value, or profile. That's the prove-it-works principle. |

For a run that drifts, [`references/prompting.md`](references/prompting.md) has one-line steers. [Guide page 10](https://github.com/cursor/plugins/blob/main/pstack/docs/guide/10-recipes-and-pitfalls.md) has more pitfalls and the recipes worth copying.

## Make pstack my own

- [`/skill:automate-me`](../automate-me/SKILL.md) drafts a personal mode skill from the user's own history, to use alongside `/skill:poteto-mode`.
- [`/skill:reflect`](../reflect/SKILL.md) after a session turns its lessons into skill edits the user approves.
- `/poteto-mode write a skill for <workflow>` runs the authoring playbook. The eval playbook tests a skill change blind.
- Fix a misbehaving skill in its own PR, not inside the feature work where it went wrong.

[Guide page 9](https://github.com/cursor/plugins/blob/main/pstack/docs/guide/09-make-it-yours.md) covers each of these.

## Reply

Lead with the answer. Give at most one example prompt in a code block, adapted from [`references/recipes.md`](references/recipes.md) when one fits, then the link to that file. Keep it short unless the user asked for the whole map.
