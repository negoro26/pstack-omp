---
name: verify-pstack-omp
description: Drive the pstack plugin inside a real, isolated omp TUI and the port CLI, and capture terminal evidence. Use to prove a change to plugins/pstack skills, the potetomode or pstackpolicy extension, or omp-port scripts behaves the way a user meets it.
---

# Verify pstack-omp

Users meet this repo in two places.

- The plugin tree `plugins/pstack` loaded into omp. Users type skills as `/skill:<name>`, pin poteto-mode with the `potetomode` extension, and run under the `pstackpolicy` extension, which refuses forge mutations in model-issued `bash` and `eval` calls unless `PSTACK_LANDING_GRANT=1`. This is the primary target.
- The maintainer's port CLI, `omp-port/check-port.sh` and `omp-port/sync-upstream.sh`.

`omp-port/smoke-plugin.mjs` is CI's RPC check for registration and the pin. This skill reuses its isolation recipe (scratch HOME, stripped environment, `--plugin-dir` plus `-e` on the same tree, a local provider in `models.yml`) and adds a TUI in tmux plus a scripted model, so a drive can make omp issue real tool calls.

Feature recipes live in [`features/README.md`](features/README.md). Run every command from the repository root.

```bash
C=.omp/skills/verify-pstack-omp/scripts/control-pstack
P=.omp/skills/verify-pstack-omp/prompts
```

## Launch

```bash
$C launch <run> [--grant] [-- <extra omp flags>]
```

`<run>` is 1 to 40 characters of `[a-z0-9-]`, one per drive. Launch refuses a run id whose scratch dir or tmux server already exists. It does this:

1. Creates scratch `${TMPDIR:-/tmp}/verify-pstack-omp-<run>/` with `home/` as omp's HOME, `work/` as its cwd, and `bin/gh`, a shim that appends its argv to `gh-calls.log` and never touches the network.
2. Writes `home/.omp/agent/config.yml` with `setupVersion: 2`, which skips omp's first-run login wizard.
3. Starts a private tmux server, `tmux -L verify-pstack-omp-<run> -f /dev/null`. Session `model` runs `scripts/scripted-model.mjs` on a free loopback port. `models.yml` names it as provider `verify`, model `scripted`.
4. Starts session `omp` under `env -i` with only HOME, USER, TERM, LANG, SHELL, and PATH, with the scratch `bin` first. `--grant` adds `PSTACK_LANDING_GRANT=1`. The flags are `--no-session --no-title --no-lsp --no-rules --no-extensions --plugin-dir <plugin> -e <plugin> --model verify/scripted --approval-mode yolo`. yolo is the mode pstackpolicy exists for.
5. Waits up to 30s for the status line to name `scripted`, which means omp accepts input. It took about 2s on this host. Launch then writes `launch.txt` to the evidence dir and prints the attach command.

Overrides are `VERIFY_OMP_BIN` (default `omp` on PATH), `VERIFY_PSTACK_PLUGIN` (default this checkout's `plugins/pstack`), and `VERIFY_PSTACK_EVIDENCE` (the evidence root).

Never load the plugin into the real `~/.omp`, and never `/marketplace install` while verifying. Two run ids never share state, so parallel drives are safe. A shared run id is refused.

The port CLI needs no launch. `$C clone <run>` prints a throwaway clone of HEAD at `<scratch>/repo` for any command that rewrites `plugins/pstack`.

Teardown is [Cleanup](#cleanup).

## Doctor

```bash
$C doctor <run>
```

Read-only. It prints one `ok` or `FAIL` line per check and exits 1 on any FAIL. It checks that both tmux sessions exist, the omp pane is alive and runs `VERIFY_OMP_BIN` at the printed version, omp loads the expected plugin path, omp's HOME is the scratch home, omp's environment holds no credential or omp root variable, the scripted model answers `/health`, and the status line names `scripted`. The last line reports `grant armed` or `grant absent`. Run it first, and again whenever a drive surprises you.

## Drive

The scripted model reads the last user message.

- A line `tool:<name> <one-line json>` makes it call that tool with those arguments. omp's `bash` tool requires `command` and `i`. `eval` requires `language` and `code`.
- After a tool result it answers `scripted-model: tool result received`.
- Anything else gets `scripted-model: no script for this prompt`.

The verbs drive the omp pane.

```bash
$C type <run> '<literal text>'         # into the editor, no Enter
$C type-file <run> $P/<prompt>.txt     # the file's first line, no Enter
$C press <run> Enter                   # or any tmux key name, such as Escape, C-c, M-T
$C wait <run> '<extended regex>' [30]  # a matching line the pane lacked at the last press
$C capture <run> <name>                # evidence snapshot, see below
```

`wait` reads the whole pane with scrollback and succeeds only when it holds more matching lines than it did at the last `press`. So a second `wait 'tool result received'` waits for the second turn instead of matching the first. Wait on output the action produces, never on text you typed, because the typed text moves from the editor into the transcript and the count does not grow.

Type a prompt that names a forge mutation with `type-file`. When the agent driving this skill runs omp with pstack installed, pstackpolicy reads that agent's own bash command line too, so `$C type <run> '...gh pr merge...'` is refused in the driver's session and never reaches tmux. `prompts/` holds every such prompt.

Editor handles that the recipes rely on:

- `/skill:<name>` followed by a space becomes a `✦ <name>` chip.
- `C-c` clears an unsent draft. `C-u` does not.
- `Escape` closes the autocomplete list.
- A leading `!` runs the user's own shell command, outside any model turn.

## Evidence

Evidence goes to `${VERIFY_PSTACK_EVIDENCE:-${XDG_STATE_HOME:-$HOME/.local/state}/verify-pstack-omp}/<run>/`. It is outside the repository and the scratch dir, and cleanup never removes it. `$C evidence <run>` creates and prints it.

- `launch.txt` names the run, the omp binary and version, the plugin path, its git HEAD with a dirty-file count, the grant, the extra flags, and the scratch path.
- `actions.log` timestamps every launch, type, type-file, press, capture, clone, and cleanup.
- `<name>.pane.txt` is the whole pane with scrollback, so it holds the typed prompt, the tool block, and its output.
- `<name>.model-requests.jsonl` is every request omp sent the model, so it holds the system prompt and the tool result the agent got back.
- `<name>.gh-calls.log` is the argv of every `gh` call that reached a shell. An empty file means none did.
- `omp-logs/` is omp's own log directory, copied at cleanup.

For the port CLI, `tee` the command's stdout and stderr into the evidence dir, append its exit code, and save `git status --porcelain` before and after.

Proof standards:

- Drive through the TUI the way a user does, with typed prompts and slash commands. Importing an extension module is the unit tests' job (`plugins/pstack/extensions/*/index.test.js`), not this skill's.
- Capture the action and the resulting state. The pane shows the prompt and the result, and the model log shows what the agent received.
- Verify side effects. A refusal proof needs an empty `gh-calls.log` plus a control in which the same launch reaches the shim, through an allowed command or the same command under `--grant`. Without the control, an empty log could also mean the shim was never on PATH.
- The scripted model and the `gh` shim are the only stand-ins. The model replaces the provider at its HTTP boundary. The shim replaces `gh` on PATH, so a gate failure cannot reach the forge. omp, the plugin, both extensions, and the bash and eval tools are real.
- Skip model requests whose `tools` list is empty when asserting. Those are omp compressing skill descriptions in the background.
- `sync-upstream.sh <sha>` and `rebuild` rewrite the checkout. Run them only inside `$C clone <run>`, and read the result with `git status --porcelain` and `git diff --stat` there.

## Cleanup

```bash
$C cleanup <run>
```

It kills the run's private tmux server, which ends both sessions, and deletes the server's socket file, which tmux 3.8 leaves behind. It then waits up to 10s for every process whose environment holds `HOME=<scratch>/home` to exit, omp's `__omp_worker_*` daemons included, and sends SIGTERM by PID to any still running after 5s. Nothing else on the host carries that HOME, so this kills only what the run started. It never kills by process name. It copies omp's logs into the evidence dir, removes the scratch dir, fails if any process still carries the marker, and lists the evidence dir last. Run it after every failed iteration too. Afterwards `ls <evidence dir>` must still list the artifacts.

## Helpers

- `scripts/control-pstack` takes the verbs above: `launch`, `doctor`, `type`, `type-file`, `press`, `wait`, `capture`, `clone`, `evidence`, `cleanup`. Its header repeats the usage.
- `scripts/scripted-model.mjs <state-dir>` is the scripted provider. Launch starts it. Run `bun .omp/skills/verify-pstack-omp/scripts/scripted-model.mjs /tmp/somewhere` by hand only to debug it. It writes `model.port` and `model-requests.jsonl` into that dir.
- `prompts/*.txt` holds one-line prompts for `type-file`.

## Gotchas

- Three omp binaries are on this host. `omp` on PATH is `~/.local/share/tern/omp/bin/omp` at 18.14.1, `~/.bun/bin/omp` is 18.9.1, and CI's `smoke` job pins v18.12.6. Doctor prints the version in use. Set `VERIFY_OMP_BIN` to match the release you are proving.
- omp starts worker daemons (`__omp_worker_daemon_broker`, `__omp_worker_text_predict`) under the same scratch HOME, in their own process sessions. Cleanup waits for them and confirms none remain. A `__omp_worker_*` process with a different HOME is not yours.
- The scratch HOME has no `gh` login and no token, so a `gh` call that bypassed the shim fails at authentication. That is a second safety net, not the proof.
