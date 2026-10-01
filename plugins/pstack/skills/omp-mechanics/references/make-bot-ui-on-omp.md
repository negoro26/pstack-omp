# make-bot-ui on omp

Amends every step of **make-bot-ui**. Half the skill is a Grok Bot mechanic with no counterpart in
this install. Read the marked steps as the upstream design, and probe before claiming this harness
can perform them. `omp --help` and the live `bash` tool schema are the check. If a later version
grows a routine store or an inbound webhook, prefer it over anything here.

## Grok Bot only

None of this exists on omp. There is no routine store, no inbound webhook endpoint, and no card
that collects a secret without showing it in the transcript.

- Webhook routines, and the routine mechanic's `update_state` call.
- The routine panel that holds the URL and sender key, and the `api2.cursor.sh` endpoint.
- The `SendToUser` secret-request card.
- The `[routine]` wake turn, and every inbound webhook wake.

## Works here

Serving the page, the local server that holds the key, the outbound POST, the Tailscale exposure,
and every probe.

Run the server as a named async `bash` process. Give it a unique `name` and set `ready.port` so
readiness is observed rather than assumed. Read its output at `proc://<job-id>` and stop it at
`proc://<job-id>/kill`. Probe it with the `browser` eval prelude or with `curl`.

Serving a page and putting it on the tailnet is the whole job when the target is a plain HTTP
endpoint you already own. Reach for this skill for that half.

## Secrets

There is no card on omp that hides the value. `ask` puts whatever the user types into the
transcript, so never use it for a secret.

Name the config file the server reads, tell the user to write the key into it themselves, and never
read that file. Give them a `chmod 600` path under the UI's own directory. Read only whether the
file exists, not what is in it.

## Waking on new work

Nothing pushes a turn into an omp session from outside, so poll instead. A named `bash` process
observed through `proc://`, or a systemd user timer, reads the local log the server appends to and
starts an `omp -p` run when there is new work. That is a pull, so the polling interval is the latency floor.
