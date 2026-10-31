# Skill commands

Every directory under `plugins/pstack/skills/` registers in omp as a `/skill:<name>` command. Typing `/skill:` lists the plugin's skills with their descriptions, and submitting one sends that skill's body from the plugin tree to the model.

## Sub-features

- `skill-register` registers every skill directory as `skill:<dir>`, with no directory missing.
- `skill-autocomplete` lists matching plugin skills with descriptions while the user types `/skill:`.
- `skill-invoke` turns `/skill:<name> <text>` into a `✦ <name>` chip and sends the skill body from the plugin under test to the model.

## How to get to it (user POV)

- Type `/skill:` in the omp editor and pick from the list.
- Type `/skill:<name> <request>` and press Enter.
- CI's `smoke` job and `bun omp-port/smoke-plugin.mjs` ask omp's RPC mode for the registered commands.

## Driving it with control-pstack

Preconditions:

- `$C launch skills-<n>` succeeded and `$C doctor skills-<n>` prints no `FAIL`.
- `ls plugins/pstack/skills | wc -l` gives the expected skill count. It was 60 at pin `519d36a`.

- **Register every skill.** Run `OMP_SMOKE_REQUIRED=1 bun omp-port/smoke-plugin.mjs 2>&1 | tee "$($C evidence skills-<n>)/smoke.txt"`. Exit code `0` and stdout reads `smoke-plugin: PASS  omp/<version>: <N>/<N> skills registered`, where `<N>` equals the directory count.
- **Autocomplete.** Type a prefix. Run `$C type skills-<n> '/skill:create-verif'`, then `$C wait skills-<n> 'skill:create-verification-skil'` and `$C capture skills-<n> skill-commands.skill-autocomplete`. The pane lists `skill:create-verification-skil`, `skill:create-formal-verificati`, and `skill:maintain-verification-sk`, each with its description.
- **Clear the draft.** Run `$C press skills-<n> C-c`. The editor is empty.
- **Invoke a skill.** Run `$C type skills-<n> '/skill:unslop check this sentence'`, `$C press skills-<n> Enter`, `$C wait skills-<n> 'no script for this prompt'`, and `$C capture skills-<n> skill-commands.skill-invoke`. The pane shows a `✦ unslop  <n> lines` block above `check this sentence`, then `scripted-model: no script for this prompt`.
- **Proof of source.** Read the request the model got. Run `jq -r 'select((.body.tools|length)>0) | .body.messages | map(select(.role=="user")) | last | .content | tostring' "$($C evidence skills-<n>)/skill-commands.skill-invoke.model-requests.jsonl" | grep -o 'Skill directory: [^]\\]*'`. It prints `Skill directory: <repo>/plugins/pstack/skills/unslop`, which proves the body came from the tree under test.
- **Clean up.** Run `$C cleanup skills-<n>`.

## Gotchas

- Autocomplete truncates long names to the column width, so match on a prefix such as `skill:create-verification-skil`.
- `C-u` does not clear the editor. `C-c` does. Typing over a stale draft concatenates the two commands.
- The smoke script runs whichever `omp` is first on PATH, not `VERIFY_OMP_BIN`.
- The scratch HOME holds no other skills, so every `/skill:` entry comes from the plugin under test. Keep `--no-extensions` and the scratch HOME even when a skill seems missing.
- The skill count changes with each upstream sync. Compare against `ls plugins/pstack/skills`, not a remembered number.
