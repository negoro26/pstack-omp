# pstack-omp

An omp marketplace carrying one plugin.

`pstack` is Lauren Tan's engineering methodology for Cursor, ported to oh-my-pi and made
model and provider agnostic, 59 skills with 23 playbooks and 24 principle leaves.
Wide parallel runs are a `swarm` dispatch, not a separate plugin.

```
/marketplace add negoro26/pstack-omp
/marketplace install pstack@pstack-omp
```

The marketplace install loads the skills and both extensions, `potetomode` and `pstackpolicy`. It
does not load the two agents; see the agent step in `plugins/pstack/README.md`.

`PORTING.md` is the full porting record. `omp-port/check-port.sh` is the gate the port
passes before any release. Upstream is `cursor/plugins` at the commit named in the catalog.
Licensed MIT, same as upstream, with Lauren Tan's copyright retained.

The `pstack-omp` runtime adapter incorporates Daniel Sebban's OMP routing work from
[dsebban/skills](https://github.com/dsebban/skills). It resolves the live task or vibe
surface without requiring a fixed agent roster. The original scripts remain in place.
The pin respects saved on/off state before the `--poteto` default on session resume.
