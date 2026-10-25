#!/usr/bin/env bash
# Offline regression test for the worktree audit that omp-port/patches/worktree-audit-omp.patch
# produces. Port-only file, never upstream.
#
# Usage: bash omp-port/test-worktree-audit.sh [path/to/worktree-audit.sh]
#   Defaults to the generated plugins/pstack/skills/poteto-mode/scripts/worktree-audit.sh. Pass an
#   older build of the script to prove a regression. Exit 0 PASS, 1 when any assertion fails.
#
# Builds a throwaway repo with a local bare origin, a fake gh and origin CLI, and fixture omp
# session stores, then runs the audit under each store layout omp resolves. Needs git and jq. It
# never reaches the network, the real gh, or the real session store. When omp is on PATH it also
# asks that omp, under the fixture HOME and with no model turn, which transcript it would write;
# without omp that probe prints SKIPPED.
set -euo pipefail

PORT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)
AUDIT=${1:-$PORT_DIR/../plugins/pstack/skills/poteto-mode/scripts/worktree-audit.sh}
case "$AUDIT" in /*) ;; *) AUDIT="$PWD/$AUDIT" ;; esac
[ -f "$AUDIT" ] || { echo "no audit script at $AUDIT" >&2; exit 1; }
for cmd in git jq; do
	command -v "$cmd" >/dev/null || { echo "missing dependency: $cmd" >&2; exit 1; }
done

FIXTURE=$(mktemp -d "${TMPDIR:-/tmp}/worktree-audit-test.XXXXXX")
trap 'chmod -R u+rwX "$FIXTURE" 2>/dev/null; rm -rf "$FIXTURE"' EXIT
FIXTURE=$(cd "$FIXTURE" && pwd -P)

# HOME and TMPDIR are symlinks, the way macOS hands out /var/folders, so every path git reports is
# the canonical spelling and only a canonicalizing audit finds the bucket omp wrote. TMPDIR sits
# inside HOME so the temp-before-home order is observable.
CH="$FIXTURE/real home"
mkdir -p "$CH/scratch" "$FIXTURE/bin" "$FIXTURE/portable-bin"
ln -s "real home" "$FIXTURE/home"
export HOME="$FIXTURE/home" TMPDIR="$FIXTURE/home/scratch"
CT="$CH/scratch"
unset TMP TEMP CDPATH GIT_DIR GIT_WORK_TREE GIT_COMMON_DIR GIT_INDEX_FILE \
	PI_CODING_AGENT_SESSION_DIR PI_CODING_AGENT_DIR PI_CONFIG_DIR OMP_PROFILE PI_PROFILE XDG_DATA_HOME
export GIT_CONFIG_NOSYSTEM=1 GIT_CONFIG_GLOBAL=/dev/null GIT_TERMINAL_PROMPT=0
export GIT_AUTHOR_NAME=audit GIT_AUTHOR_EMAIL=audit@example.invalid
export GIT_COMMITTER_NAME=audit GIT_COMMITTER_EMAIL=audit@example.invalid
export FIXTURE PR_PROVIDER=gh REAL_STAT REAL_DATE
REAL_STAT=$(command -v stat)
REAL_DATE=$(command -v date)
export PATH="$FIXTURE/bin:$PATH"

g() { git -C "$1" "${@:2}" >/dev/null 2>&1; }
ORIGIN="$FIXTURE/origin.git"
REPO="$CH/main repo"
git init -q --bare "$ORIGIN"
git init -q "$REPO"
git -C "$REPO" symbolic-ref HEAD refs/heads/main
printf 'build/\n*.log\n' >"$REPO/.gitignore"
printf 'seed\n' >"$REPO/tracked"
g "$REPO" add .gitignore tracked
g "$REPO" commit -qm seed
g "$REPO" remote add origin "$ORIGIN"
g "$REPO" push -q origin main

wt() { g "$REPO" worktree add -q -b "$1" "$2" main; }
commit() {
	printf '%s\n' "$2" >"$1/$2"
	g "$1" add "$2"
	g "$1" commit -qm "$2"
	git -C "$1" rev-parse HEAD
}
for name in open draft closed-pushed closed-unpushed squash local-only untracked ignored tracked \
	locked broken sibling unrelated plain subdir; do
	wt "$name" "$CH/$name"
done
RECENT='recent [one].worktree'
wt recent "$CH/$RECENT"
wt nested "$CH/nest/deep:wt"
wt temp "$CT/temp:wt"
wt absolute "$FIXTURE/abs:wt"
wt sub-absolute "$FIXTURE/sub:abs"
g "$REPO" worktree add -q --detach "$CH/detached" main

OPEN_HEAD=$(git -C "$CH/open" rev-parse HEAD)
g "$CH/open" push -q origin open
CLOSED_PUSHED=$(commit "$CH/closed-pushed" closed)
g "$CH/closed-pushed" push -q origin closed-pushed
CLOSED_UNPUSHED=$(commit "$CH/closed-unpushed" pushed)
g "$CH/closed-unpushed" push -q origin closed-unpushed
commit "$CH/closed-unpushed" local-only >/dev/null
SQUASH=$(commit "$CH/squash" squashed)
g "$CH/squash" push -q origin squash
g "$REPO" merge --squash squash
g "$REPO" commit -qm 'Squash squash'
g "$REPO" push -q origin main
g "$REPO" push -q origin --delete squash
commit "$CH/local-only" unpushed >/dev/null
commit "$CH/detached" detached >/dev/null
printf 'notes\n' >"$CH/untracked/notes.md"
mkdir "$CH/ignored/build"
printf 'bin\n' >"$CH/ignored/build/artifact.bin"
printf 'log\n' >"$CH/ignored/run.log"
printf 'edit\n' >>"$CH/tracked/tracked"
g "$REPO" worktree lock --reason 'keep this worktree' "$CH/locked"
printf 'gitdir: %s/missing\n' "$FIXTURE" >"$CH/broken/.git"
ROWS=21

# A closed PR on a reused branch name sits first, so the audit has to prefer the PR whose head is
# HEAD. gh reports uppercase states; the audit lowercases them.
jq -n --arg open "$OPEN_HEAD" --arg cp "$CLOSED_PUSHED" --arg cu "$CLOSED_UNPUSHED" --arg sq "$SQUASH" '[
	{number: 8, state: "CLOSED", headRefName: "squash", headRefOid: ("0" * 40)},
	{number: 1, state: "OPEN", headRefName: "open", headRefOid: $open},
	{number: 5, state: "OPEN", headRefName: "draft", headRefOid: ""},
	{number: 2, state: "CLOSED", headRefName: "closed-pushed", headRefOid: $cp},
	{number: 3, state: "CLOSED", headRefName: "closed-unpushed", headRefOid: $cu},
	{number: 4, state: "MERGED", headRefName: "squash", headRefOid: $sq}]' >"$FIXTURE/gh.json"
printf '%s\n' '[{"number":1,"status":"OPEN","headRef":"open"},{"number":5,"status":"draft","headRef":"draft"},{"number":2,"status":"closed","headRef":"closed-pushed"}]' >"$FIXTURE/origin.json"
cat >"$FIXTURE/bin/gh" <<'SH'
#!/usr/bin/env bash
[ "$PR_PROVIDER" = gh ] || { : >"$FIXTURE/gh-called"; exit 1; }
cat "$FIXTURE/gh.json"
SH
cat >"$FIXTURE/bin/origin" <<'SH'
#!/usr/bin/env bash
[ "$PR_PROVIDER" = origin ] || exit 1
cat "$FIXTURE/origin.json"
SH
# BSD spellings on any host: GNU stat -c and date -d are refused, while stat -f <format> with %m
# and %N and date -r <epoch> are served the way BSD serves them. And no ripgrep at all.
cat >"$FIXTURE/portable-bin/stat" <<'SH'
#!/usr/bin/env bash
[ "$1" = -f ] || { echo "stat: illegal option" >&2; exit 1; }
fmt=$2
shift 2
for f; do
	m=$("$REAL_STAT" -c %Y "$f" 2>/dev/null || "$REAL_STAT" -f %m "$f") || exit 1
	out=${fmt//%m/$m}
	printf '%s\n' "${out//%N/$f}"
done
SH
cat >"$FIXTURE/portable-bin/date" <<'SH'
#!/usr/bin/env bash
case "$1" in
-d) echo "date: illegal option -- d" >&2; exit 1 ;;
-r) "$REAL_DATE" -d "@$2" "$3" 2>/dev/null || "$REAL_DATE" -r "$2" "$3" ;;
*) exec "$REAL_DATE" "$@" ;;
esac
SH
printf '#!/bin/sh\necho "rg: command not found" >&2\nexit 127\n' >"$FIXTURE/portable-bin/rg"
chmod +x "$FIXTURE"/bin/* "$FIXTURE"/portable-bin/*

# omp's bucket names, written out by hand rather than derived, since they are the contract.
SESSIONS="$HOME/.omp/agent/sessions"
ABS_BUCKET="--$(printf '%s' "${FIXTURE#/}" | tr '/' '-')-abs-wt--"
chat() { mkdir -p "$1" && printf '{"type":"session","cwd":"%s"}\n' "$3" >"$1/$2.jsonl"; }
chat "$SESSIONS/-main repo" repo "$REPO"
chat "$SESSIONS/-recent [one].worktree" own "$CH/recent [one].worktree"
# A session in one worktree that worked in another still marks the other as in use.
printf '{"type":"message","path":"%s/notes.md"}\n' "$CH/sibling" >>"$SESSIONS/-recent [one].worktree/own.jsonl"
chat "$SESSIONS/-nest-deep-wt" own "$CH/nest/deep:wt"
chat "$SESSIONS/-tmp-temp-wt" own "$CT/temp:wt"
chat "$SESSIONS/$ABS_BUCKET" own "$FIXTURE/abs:wt"
# A session started in a subdirectory sits in that subdirectory's bucket, for a home and an
# absolute worktree alike. A bucket that only shares a name prefix with a worktree is no chat in it.
chat "$SESSIONS/-subdir-src" sub "$CH/subdir/src"
chat "$SESSIONS/--$(printf '%s' "${FIXTURE#/}" | tr '/' '-')-sub-abs-src--" sub "$FIXTURE/sub:abs/src"
chat "$SESSIONS/-plain-old" old "$CH/plain-old"
chat "$SESSIONS/-another-project" other "$CH/unrelated"
TODAY=$(date '+%Y-%m-%d')

FAILS=0
fail() { printf 'FAIL [%s] %s\n' "$LABEL" "$*"; FAILS=$((FAILS + 1)); }
cell() {
	awk -F '\t' -v name="/$1" -v col="$2" '
		/^# / { next }
		$1 == "SIZE" { for (i = 1; i <= NF; i++) idx[$i] = i; next }
		substr($NF, length($NF) - length(name) + 1) == name { print (idx[col] ? $(idx[col]) : "<no column>"); n++ }
		END { if (n != 1) exit 1 }' "$OUT"
}
expect() {
	local got
	got=$(cell "$1" "$2") || got="<no single row>"
	[ "$got" = "$3" ] || fail "$1 $2: want '$3', got '$got'"
}
audit() {
	LABEL=$1
	shift
	OUT="$FIXTURE/$LABEL.tsv"
	if ! env "$@" bash "$AUDIT" -b main "$REPO" >"$OUT" 2>"$FIXTURE/$LABEL.err"; then
		fail "audit exited non-zero: $(tr '\n' ' ' <"$FIXTURE/$LABEL.err")"
	fi
}

audit gh
awk -F '\t' -v rows="$ROWS" '
	/^# / { next }
	$1 == "SIZE" { h++; if (NF != 11) bad = 1; next }
	{ r++; if (NF != 11) bad = 1 }
	END { exit !(h == 1 && r == rows && !bad) }' "$OUT" ||
	fail "want one 11-column header and $ROWS 11-column rows"
expect open PR '#1/open'
expect open REMOTE pushed
expect open BUCKET hold-open-pr
expect draft BUCKET hold-open-pr
expect closed-pushed PR '#2/closed'
expect closed-pushed BUCKET review
expect closed-unpushed REMOTE ahead1
expect closed-unpushed BUCKET hold-unpushed
expect squash PR '#4/merged'
expect squash MERGED no
expect squash REMOTE no-remote
expect squash BUCKET safe
expect local-only REMOTE no-remote
expect local-only BUCKET hold-unpushed
expect detached REMOTE detached
expect detached BUCKET hold-unpushed
expect untracked DIRTY wip:1
expect untracked BUCKET hold-wip
expect ignored DIRTY wip:2
expect ignored BUCKET hold-wip
expect tracked DIRTY wip:1
expect tracked BUCKET hold-wip
expect locked LOCKED 'keep this worktree'
expect locked INSPECT ok
expect locked BUCKET hold-locked
expect broken INSPECT status-error
expect broken BUCKET hold-error
expect plain LOCKED -
expect plain INSPECT ok
expect plain LAST_CHAT -
expect plain BUCKET safe
for name in "$RECENT" sibling deep:wt temp:wt abs:wt subdir sub:abs; do
	expect "$name" LAST_CHAT "$TODAY"
	expect "$name" BUCKET verify-recent-chat
done
expect unrelated LAST_CHAT -
expect unrelated BUCKET safe

audit origin PR_PROVIDER=origin
expect open PR '#1/open'
expect open BUCKET hold-open-pr
expect draft PR '#5/draft'
expect draft BUCKET hold-open-pr
expect closed-pushed BUCKET review
[ ! -e "$FIXTURE/gh-called" ] || fail "gh was called although origin answered"

audit portable PATH="$FIXTURE/portable-bin:$PATH"
for name in "$RECENT" deep:wt temp:wt abs:wt; do
	expect "$name" LAST_CHAT "$TODAY"
	expect "$name" BUCKET verify-recent-chat
done

# An explicit session directory holds transcripts directly, with no cwd bucket under it. The bucket
# store still counts, since a session launched without the variable lands there.
chat "$FIXTURE/direct sessions" direct "$CH/plain"
audit explicit-dir PI_CODING_AGENT_SESSION_DIR="$FIXTURE/direct sessions"
expect plain LAST_CHAT "$TODAY"
expect plain BUCKET verify-recent-chat
expect "$RECENT" LAST_CHAT "$TODAY"

# A session launched with --profile work sits in that profile's store, which an audit under any
# profile reads. The audit's own profile names the store that has to exist, and under a profile
# PI_CODING_AGENT_DIR does not name it.
chat "$HOME/.omp/profiles/work/agent/sessions/-plain" profile "$CH/plain"
audit other-profile
expect plain LAST_CHAT "$TODAY"
expect plain BUCKET verify-recent-chat
audit profile OMP_PROFILE=work PI_CODING_AGENT_DIR="$FIXTURE/decoy"
expect plain LAST_CHAT "$TODAY"
expect "$RECENT" LAST_CHAT "$TODAY"
rm -r "$HOME/.omp/profiles"

# An existing XDG_DATA_HOME/omp replaces the default data root, with no agent/ under it. The store
# it replaced still counts.
chat "$FIXTURE/xdg/omp/sessions/-plain" xdg "$CH/plain"
audit xdg XDG_DATA_HOME="$FIXTURE/xdg"
expect plain LAST_CHAT "$TODAY"
expect "$RECENT" LAST_CHAT "$TODAY"

# omp lists each transcript it writes outside the bucket store, from --session-dir, an explicit
# PI_CODING_AGENT_SESSION_DIR or a --resume of a moved file, as one absolute path per file in the
# agent dir's custom-session-files, or XDG_STATE_HOME/omp's when that exists. A subagent transcript
# sits in the directory named after its parent. A listed transcript that is gone is no chat, and an
# index that cannot be read is unknown.
INDEX="$HOME/.omp/agent/custom-session-files"
chat "$FIXTURE/custom dir" custom "$FIXTURE"
chat "$FIXTURE/custom dir/custom" Child "$CH/plain"
mkdir -p "$INDEX"
printf '%s' "$FIXTURE/custom dir/custom.jsonl" >"$INDEX/0a1b2c3"
printf '%s' "$FIXTURE/gone/x.jsonl" >"$INDEX/4d5e6f7"
audit custom-dir
expect plain LAST_CHAT "$TODAY"
expect plain BUCKET verify-recent-chat
if [ "$(id -u)" != 0 ]; then
	chmod 000 "$INDEX"
	audit unreadable-index
	expect plain LAST_CHAT '?'
	chmod 755 "$INDEX"
fi
mkdir -p "$FIXTURE/state/omp"
mv "$INDEX" "$FIXTURE/state/omp/"
audit state-index XDG_STATE_HOME="$FIXTURE/state"
expect plain LAST_CHAT "$TODAY"

# omp fills each unset variable from four .env files, the launch directory's, the agent
# directory's, the config root's and the home directory's, and reads an OMP_ key in one as its PI_
# alias. A store moved from one of them holds a recent chat the audit cannot see.
MOVED="$FIXTURE/moved store"
chat "$MOVED/agent/sessions/-plain" moved "$CH/plain"
chat "$MOVED/data/omp/sessions/-plain" moved "$CH/plain"
dotenv() {
	printf '%s\n' "$3" >"$2"
	audit "dotenv-$1"
	expect plain LAST_CHAT '?'
	expect plain BUCKET verify-recent-chat
	rm "$2"
}
dotenv project "$REPO/.env" "PI_CODING_AGENT_DIR=\"$MOVED/agent\""
dotenv agent "$HOME/.omp/agent/.env" "export OMP_CODING_AGENT_DIR=\"$MOVED/agent\""
dotenv config "$HOME/.omp/.env" "PI_CODING_AGENT_SESSION_DIR: \"$MOVED/agent/sessions/-plain\""
dotenv home "$HOME/.env" "XDG_DATA_HOME=\"$MOVED/data\""
printf 'EDITOR=vi\n# PI_CODING_AGENT_DIR="%s"\n' "$MOVED/agent" >"$HOME/.env"
audit dotenv-unrelated
expect plain LAST_CHAT -
expect plain BUCKET safe
rm "$HOME/.env"

# A store that cannot be read is unknown, never "no chat": the row holds for verification while
# the stronger holds keep their own bucket.
audit missing-store PI_CODING_AGENT_DIR="$FIXTURE/nowhere"
expect plain LAST_CHAT '?'
expect plain BUCKET verify-recent-chat
expect unrelated BUCKET verify-recent-chat
expect open BUCKET hold-open-pr
expect tracked BUCKET hold-wip
expect local-only BUCKET hold-unpushed
expect detached BUCKET hold-unpushed
if [ "$(id -u)" != 0 ]; then
	chmod 000 "$SESSIONS/-main repo/repo.jsonl"
	audit unreadable-transcript
	expect plain LAST_CHAT '?'
	expect plain BUCKET verify-recent-chat
	chmod 644 "$SESSIONS/-main repo/repo.jsonl"
fi

# Without TMPDIR nothing may land in the repository.
audit no-tmpdir -u TMPDIR
[ ! -e "$REPO/.pstack-scratch" ] || fail "scratch written inside the repo: $REPO/.pstack-scratch"
[ -z "$(git -C "$REPO" status --porcelain --ignored)" ] || fail "the audit left files in the repo"

# omp names the transcript it would write for a cwd without a model turn. A chat written at that
# path has to reach the audit for a home, a temp and an absolute worktree, for a session started in
# a subdirectory of one, and for one launched with --profile or --session-dir.
probe() {
	local file
	wt "$1" "$2"
	mkdir -p "$3"
	if ! file=$(cd "$3" && printf '%s\n' '{"id":"s","type":"get_state"}' |
		env -i HOME="$HOME" TMPDIR="$TMPDIR" PATH="$PATH" omp --mode rpc --no-title --no-lsp --no-tools \
			--no-rules --no-extensions --no-skills --model probe/no-inference "${@:4}" 2>"$FIXTURE/live-omp.err" |
		jq -r 'select(.type == "response" and .id == "s") | .data.sessionFile // empty') || [ -z "$file" ]; then
		fail "omp reported no session file for $3: $(tr '\n' ' ' <"$FIXTURE/live-omp.err")"
		return
	fi
	chat "$(dirname "$file")" "$(basename "$file" .jsonl)" "$3"
}
if ! command -v omp >/dev/null 2>&1; then
	printf 'worktree audit: live omp probe SKIPPED, omp is not on PATH\n'
else
	LABEL=live-omp
	printf '%s\n' providers: '  probe:' '    baseUrl: http://127.0.0.1:9/v1' '    auth: none' \
		'    api: openai-completions' '    models:' '      - id: no-inference' >"$HOME/.omp/agent/models.yml"
	mkdir -p "$HOME/.omp/profiles/live/agent"
	cp "$HOME/.omp/agent/models.yml" "$HOME/.omp/profiles/live/agent/"
	probe probe-home "$CH/probe home" "$CH/probe home"
	probe probe-temp "$CT/probe:temp" "$CT/probe:temp"
	probe probe-abs "$FIXTURE/probe:abs" "$FIXTURE/probe:abs"
	probe probe-sub "$CH/probe sub" "$CH/probe sub/src"
	probe probe-sub-abs "$FIXTURE/probe:sub" "$FIXTURE/probe:sub/src"
	probe probe-profile "$CH/probe profile" "$CH/probe profile" --profile live
	probe probe-session-dir "$CH/probe sdir" "$CH/probe sdir" --session-dir "$FIXTURE/live sessions"
	audit live-omp
	for name in "probe home" probe:temp probe:abs "probe sub" probe:sub "probe profile" "probe sdir"; do
		expect "$name" LAST_CHAT "$TODAY"
	done
fi

if [ "$FAILS" -gt 0 ]; then
	printf 'worktree audit: FAIL (%d)\n' "$FAILS"
	exit 1
fi
printf 'worktree audit: PASS\n'
