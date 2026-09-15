# The omp session store on disk

Amends **recall, reflect, eval, session-pickup, show-me-your-work, automate-me** in `SKILL.md`. Read
this before globbing for a transcript. Every path below came off a live store, so list a real bucket
before trusting this file after an upgrade.

## The root

Resolved, not fixed. The default is `~/.omp/agent/sessions/`. `PI_CODING_AGENT_SESSION_DIR` and an
explicit session-directory argument win, then `PI_CODING_AGENT_DIR` for the default profile, then
the profile root under `PI_CONFIG_DIR`, then `XDG_DATA_HOME`, which redirects only when its `omp`
root already exists. Resolve it once instead of hardcoding it.

## The bucket name

One bucket per canonicalized cwd, so two symlinked spellings of one directory share a bucket.

- A cwd under `$HOME` becomes the home-relative path with each `/` rewritten to `-`. The leading
  separator survives as a leading hyphen, so `/home/you/Desktop/proj` is `-Desktop-proj` and
  `/home/you/.omp/pstack` is `-.omp-pstack`.
- A cwd under the temp root becomes `-tmp-<rest>`.
- Anything else becomes `--<encoded-absolute>--`.

Two distinct paths that encode identically share one bucket, and 18.2.0 adds no digest to separate
them. A short-lived hashed scheme, `<scope>-<basename>-<sha256>`, shipped in 17.2.5 and was
reverted in 17.2.9. Old buckets in that form are migrated back to path-encoded names on access, so a
store with history may still show one.

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
`agent://<parent>/<child>` a nested child's, and `agent://<id>?q=.<field>` one field of a structured
result. Prefer `?q=` for a field, because the slash resolves a child agent first and only falls back
to JSON extraction.
