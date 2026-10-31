# pstack-omp

pstack-omp ports Lauren Tan's [pstack](https://github.com/cursor/plugins/tree/main/pstack) from
Cursor to [oh-my-pi](https://github.com/can1357/oh-my-pi) (`omp`). It is for omp users who want
pstack's `poteto-mode` router, its playbooks for bug fixes, features, reviews, and shipping, and its
review panels. The plugin carries 59 skills, with 23 playbooks and 24 principle leaves, and two
extensions.

## Install

```
/marketplace add negoro26/pstack-omp
/marketplace install pstack@pstack-omp
```

Then start a task:

```
/poteto-mode fix the flaky login test and prove it with a passing run
```

`/poteto-mode` pins the router for the session and sends the rest of the line as your first message.
It needs no configuration. Each agent runs on its frontmatter model, then on your chat model.
`/poteto-mode off` unpins the router.

The install loads the skills and both extensions, `potetomode` and `pstackpolicy`. It does not load
the two optional agents. The agent step is in [`plugins/pstack/README.md`](plugins/pstack/README.md).

## Choose models

To give an agent its own model, add an entry under `task.agentModelOverrides` in
`~/.omp/agent/config.yml`. [Choose models](plugins/pstack/skills/omp-mechanics/SKILL.md#choose-models)
in `omp-mechanics` gives the key, the value, and the optional `modelRoles` aliases. A review panel in
`arena` or `interrogate` gives a second opinion only when its agents resolve to different model
families. With no overrides, a panel agent without a frontmatter model runs on your chat model, so
check the model each panel agent resolves to before you trust a panel verdict.

## Why this port

- The plugin tree is a build, not a hand-kept copy. `omp-port/sync-upstream.sh` exports upstream
  `cursor/plugins` at the commit in `omp-port/UPSTREAM`, then applies `omp-port/rules.sed` and
  `omp-port/patches/`. `omp-port/check-port.sh` rebuilds that commit and fails when the tree differs.
  It also fails on a rule that drops upstream text nobody reviewed and on a rule that splices its
  match back into the line.
- `.github/workflows/upstream-sync.yml` syncs once a day. It runs `check-port.sh` on `main` and
  against the new upstream commit, builds the sync, runs the gate again on the result, and merges the
  sync pull request only when the build and the gate pass.
- The `pstackpolicy` extension refuses the forge mutations the playbooks otherwise only ask for in
  prose, such as `gh pr merge`, closing or retargeting a pull request, posting a review, and a push to
  `main`. It allows them only when omp starts with `PSTACK_LANDING_GRANT=1`. The full list is in
  [`plugins/pstack/README.md`](plugins/pstack/README.md).
- The `potetomode` extension pins `poteto-mode` per session. `/poteto-mode on|off|status`,
  `alt+shift+t`, and `omp --poteto` set the pin, and a resumed session keeps its saved state.

## Other OMP ports

[dsebban/skills](https://github.com/dsebban/skills) is Daniel Sebban's OMP port of pstack. You clone
it and list its `skills/` directory under `skills.customDirectories`. It ships skills this port does
not, such as `setup-pstack` for guided model configuration and `orchestrate-omp`. The `pstack-omp`
runtime adapter here incorporates his OMP routing work, which resolves the live task or vibe surface
without a fixed agent roster. [`THIRD_PARTY_NOTICES.md`](THIRD_PARTY_NOTICES.md) carries his license
notice.

## More

`PORTING.md` records every substitution and the re-sync procedure. Licensed MIT, same as upstream,
with Lauren Tan's copyright retained.
