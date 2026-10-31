# poteto-mode pin

The potetomode extension lets a user pin poteto-mode for a session. While pinned, the status line shows a `poteto pinned` pill and every model request carries a reminder to route the task through `skill://poteto-mode`. The pin survives turns, follows the session branch, and does not leak into a `/new` session.

## Sub-features

- `pin-on` pins with `/poteto-mode on` and shows the pill.
- `pin-off` unpins with `/poteto-mode off` and clears the pill.
- `pin-status` reports the pin with `/poteto-mode status`.
- `pin-reminder` adds `poteto-mode is PINNED for this session.` to the system prompt only while pinned.
- `pin-task` pins and starts the work with `/poteto-mode <task>`.
- `pin-flag` starts the session pinned with `omp --poteto`.
- `pin-shortcut` toggles the pin with `alt+shift+t`.
- `pin-new-session` leaves a `/new` session unpinned unless `--poteto` is set.

## How to get to it (user POV)

- Type `/poteto-mode on`, `/poteto-mode off`, `/poteto-mode status`, or `/poteto-mode <task>` in the omp editor.
- Press `alt+shift+t`.
- Start omp with `--poteto`.
- Type `/new` to start a fresh session in the same process.

## Driving it with control-pstack

Preconditions:

- `$C launch pin-<n>` succeeded with no extra flags, and `$C doctor pin-<n>` prints no `FAIL`.
- The pane shows no `poteto pinned` pill.

- **Pin.** Run `$C type pin-<n> '/poteto-mode on'`, `$C press pin-<n> Enter`, and `$C wait pin-<n> 'poteto-mode pinned for this session'`. The status area shows `○ poteto pinned`.
- **Reminder while pinned.** Run `$C type pin-<n> 'hello pin'`, `$C press pin-<n> Enter`, `$C wait pin-<n> 'no script for this prompt'`, and `$C capture pin-<n> poteto-mode-pin.pin-reminder`. Then run `jq -r 'select((.body.tools|length)>0) | [(.body.messages|map(select(.role=="user"))|last|.content|tostring|test("hello pin")), ([.body.messages[]|select(.role=="system" or .role=="developer")|.content|tostring|test("poteto-mode is PINNED")]|any)] | @tsv' "$($C evidence pin-<n>)/poteto-mode-pin.pin-reminder.model-requests.jsonl"`. The row for the `hello pin` request reads `true	true`.
- **Unpin.** Run `$C type pin-<n> '/poteto-mode off'`, `$C press pin-<n> Enter`, and `$C wait pin-<n> 'poteto-mode unpinned'`. The pill is gone. Send `hello unpinned` the same way and capture `poteto-mode-pin.pin-off`. The same `jq` with `test("hello unpinned")` gives `true	false` for that request.
- **Status.** Run `$C type pin-<n> '/poteto-mode status'`, `$C press pin-<n> Enter`, and `$C wait pin-<n> 'poteto-mode: (not )?pinned'`. The new line reads `poteto-mode: not pinned` after an unpin and `poteto-mode: pinned` after a pin.
- **Task form.** Run `$C type pin-<n> '/poteto-mode hello task'`, `$C press pin-<n> Enter`, and `$C wait pin-<n> 'no script for this prompt'`. The pin notice appears, and the model log has a request whose last user message contains `hello task` and whose system prompt contains the reminder.
- **Shortcut.** Run `$C press pin-<n> M-T` and `$C wait pin-<n> 'poteto-mode (pinned for this session|unpinned)\.'`. The new line is the opposite of the prior state. Press it again to flip back.
- **New session.** Pin, then run `$C type pin-<n> '/new'`, `$C press pin-<n> Enter`, and `$C wait pin-<n> 'New session started'`. Then type `/poteto-mode status`, press Enter, and `$C wait pin-<n> 'poteto-mode: not pinned'`.
- **Flag.** Run `$C cleanup pin-<n>`, then `$C launch pin-<n>-flag -- --poteto` and `$C wait pin-<n>-flag 'poteto pinned'`. Type `/poteto-mode status`, press Enter, and `$C wait pin-<n>-flag 'poteto-mode: pinned'`.
- **Clean up.** Run `$C cleanup` for each run id used.

## Gotchas

- With `--poteto`, a `/new` session is pinned again, because the flag is the default when the new branch has no saved pin. Prove `pin-new-session` without the flag.
- tmux names `alt+shift+t` as `M-T`. `M-t` is a different key.
- The pill reads `○` while idle and `●` during a turn. Match on `poteto pinned`, not the glyph.
- The reminder text lives in `plugins/pstack/extensions/potetomode/index.js`. If that string changes, update the `test("poteto-mode is PINNED")` pattern here rather than loosening it.
- `bun omp-port/smoke-plugin.mjs` covers on, off, and `new_session` over RPC. It never sees the pill, the reminder in a real request, the shortcut, or the flag.
