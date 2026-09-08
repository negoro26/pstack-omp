# pstack-omp

An omp marketplace carrying two plugins.

`pstack` is Lauren Tan's engineering methodology for Cursor, ported to oh-my-pi and made
model and provider agnostic, 47 skills with 23 playbooks and 23 principle leaves.
`fan-out` is a small omp-native skill for wide parallel runs, written from measurement
rather than doctrine.

```
/marketplace add negoro26/pstack-omp
/marketplace install pstack@pstack-omp
/marketplace install fan-out@pstack-omp
```

The marketplace install loads the skills and the `potetomode` extension. It does not load
the two agents; see the agent step in `plugins/pstack/README.md`.

`PORTING.md` is the full porting record. `omp-port/check-port.sh` is the gate the port
passes before any release. Upstream is `cursor/plugins` at the commit named in the catalog.
Licensed MIT, same as upstream, with Lauren Tan's copyright retained.
