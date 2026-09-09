### Authoring or modifying a skill

**You own the skill's voice.**

1. Write the SKILL.md yourself with `write`/`edit`; `manage_skill` writes only to `~/.omp/agent/managed-skills` and never touches a user-authored skill. Give it YAML frontmatter with `name` matching its directory, a `description` naming what the skill does and when to reach for it (discovery keys off that sentence, so a vague description means the skill never fires), and `disable-model-invocation: true` so it stays out of the per-turn index and fires only when invoked by name or by a playbook.
2. Validate the skill: frontmatter has `name` and `description`, referenced files exist, cross-skill links resolve.
3. Test cases if structural. Skip if subjective.
4. Run **Opening a PR**.

When in doubt, delete. Keep only prose that changes a decision. Tell it to do the thing and skip the reason. Explain only when the rule is confusing without one. Match tone to scope. Point at structural sources (types, READMEs, config) per the **encode-lessons-in-structure** principle skill. Delegate to other skills by path. Don't restate. A workflow you keep hitting but isn't captured → propose a new skill.

**Reply:** summary of the skill, key design decisions, validation notes.
