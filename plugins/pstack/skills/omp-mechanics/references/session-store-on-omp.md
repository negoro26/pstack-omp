# The omp session store on disk

Amends **recall, reflect, eval, session-pickup, show-me-your-work, automate-me** in `SKILL.md`. Read
this before globbing for a transcript. Every path below came off a live store, so list a real bucket
before trusting this file after an upgrade.

## The root

Resolved, not fixed. The default is `~/.omp/agent/sessions/`, one bucket per cwd under it. Resolve
it once instead of hardcoding it.

- `PI_CODING_AGENT_SESSION_DIR` or an explicit `--session-dir` wins, and that directory holds the
  transcripts themselves, `<dir>/*.jsonl`, with no cwd bucket under it. Never append a bucket to it.
- Otherwise a profile, `OMP_PROFILE` and then `PI_PROFILE`, moves the root to
  `~/${PI_CONFIG_DIR:-.omp}/profiles/<name>/agent/sessions/` and `PI_CODING_AGENT_DIR` is ignored.
  With no profile, `PI_CODING_AGENT_DIR` replaces the agent directory and `sessions/` sits under it.
- While the agent directory is the default one, an existing `$XDG_DATA_HOME/omp`, or
  `$XDG_DATA_HOME/omp/profiles/<name>` under a profile, replaces it as the data root, and the
  sessions sit directly under that, `$XDG_DATA_HOME/omp/sessions/`, with no `agent/` segment.

The process environment is not the whole input. omp fills each variable that is unset or empty
from four `.env` files, and the first file that sets it wins. The process environment beats all
four. Every fact here came off `get_state.sessionFile` in a throwaway `HOME`, so rerun the probe at
the end of this section after an upgrade rather than trusting the list.

1. The launch cwd's own `.env`. A parent directory's or the git root's is not read.
2. The active agent directory's `.env`. That directory stays put under an existing
   `$XDG_DATA_HOME/omp`, whose own `.env` is not read.
3. The active config root's `.env`, so `~/.omp/profiles/<name>/.env` under a profile.
4. `~/.env`.

In any of the four, `PI_CODING_AGENT_SESSION_DIR`, `PI_CODING_AGENT_DIR`, `PI_CONFIG_DIR`, and
`XDG_DATA_HOME` move the store. So do `OMP_CODING_AGENT_SESSION_DIR`, `OMP_CODING_AGENT_DIR`, and
`OMP_CONFIG_DIR`, because a file reads an `OMP_` key as its `PI_` name and that value beats the
same file's `PI_` line. `export KEY=v`, `KEY: v`, and `KEY = v` all count. An empty value does not.
`~/.omp/agent/.env` can move the agent directory itself, and the moved directory's `.env` is then
not read. `OMP_PROFILE` and `PI_PROFILE` in a `.env` select nothing. `.env.local` and
`.env.<NODE_ENV>` in the cwd moved nothing. A process-level `PI_CODING_AGENT_SESSION_DIR` is
the one root no `.env` can move.

When the answer matters, ask omp. Launched from the cwd in question, `omp --mode rpc` answers
`{"type":"get_state"}` with `sessionFile`, the transcript it would write. That creates the
bucket directory and writes no transcript before the first message.

## The bucket name

One bucket per canonicalized cwd, so two symlinked spellings of one directory share a bucket. The
home and temp roots are canonicalized too, and `/`, `\`, and `:` all become `-` in every form.

- A cwd under the temp root, `$TMPDIR`, then `$TMP`, `$TEMP`, `/tmp`, becomes `-tmp-<rest>`, the
  root itself `-tmp`. The temp root is checked first, so a temp directory inside `$HOME` still
  yields `-tmp-`.
- A cwd under `$HOME` becomes the home-relative path with each separator rewritten to `-`. The
  leading separator survives as a leading hyphen, so `/home/you/Desktop/proj` is `-Desktop-proj` and
  `/home/you/.omp/pstack` is `-.omp-pstack`.
- Anything else drops its leading `/` and becomes `--<encoded-absolute>--`, so `/srv/a:b` is
  `--srv-a-b--`.

Two distinct paths that encode identically share one bucket unless the live runtime separates them.
Probe the current store after an upgrade. Older stores may contain a short-lived hashed form,
`<scope>-<basename>-<sha256>`, which is migrated back to path-encoded names on access.

## The files

One flat transcript per session, `<timestamp>_<session-id>.jsonl`. The timestamp is ISO-8601 with
its colons and its millisecond dot rewritten to hyphens, because a colon is path-hostile. A real
name, verbatim:

```
2026-09-08T08-48-08-964Z_01a08034-0904-74d7-ad70-398d79c17e89.jsonl
```

A sibling directory named with the same stem and no `.jsonl` is that session's artifact namespace.
It holds one `<AgentId>.jsonl` sidecar per direct child, each child's final output as `<AgentId>.md`
and `<AgentId>.json`, the `local://` scratch root, and one subdirectory per child that spawned
further. Files in those subdirectories carry the full dotted id:

```
<stem>/SliceA.jsonl
<stem>/SliceA.md
<stem>/Maintainer/Maintainer.SrcNav.jsonl
```

## Reading a transcript

Line 1 is a fixed-width 256-byte `type:title` slot, padded with spaces so a retitle rewrites in
place. It is not a message, and its title can diverge from the header's; the slot's title is the
live one. Line 2 is the `type:session` header carrying `id`, `timestamp`, `cwd`, and `title`. A
legacy file may start at the header.

To find the session that ran a given conversation, scan for the first `type:message` line with
`role:user` and match its text. Persisted roles are camelCase. A scan for `tool_result` finds
nothing, because the role is `toolResult`, and `toolCall` is a content block inside an assistant
message rather than a role.

`/clear` appends a durable `reset_boundary` entry. The model's context starts after the latest
boundary, but the file still holds everything before it, so a pickup reading the raw JSONL sees
material the previous agent could no longer see.

## Prefer the URIs

For a prior agent in this process, the internal URIs beat globbing. Bare `history://` lists every
agent with its status and its parent. `history://<id>` renders one transcript and takes line
selectors, as in `history://<id>:1-50`. `agent://<id>` serves that agent's final output artifact,
result. Take a structured result from the spawn's own return value, which carries the parsed
`data` alongside its validation status, rather than extracting it out of the prose artifact. A
nested child is addressed with a dotted id, `agent://<id>.<child>`, because a slash is
always JSON extraction: `agent://<id>/<key>/<index>/...` pulls that value out of a JSON output.
