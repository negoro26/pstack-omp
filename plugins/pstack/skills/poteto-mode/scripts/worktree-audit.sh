#!/usr/bin/env bash
# Read-only worktree prune audit. Classifies every git worktree by size, merge
# state, uncommitted work, remote/PR state, and the most recent chat that
# operated in it. Emits a table sorted by size with a suggested bucket. Never
# deletes anything; deletion stays a human-gated step in the playbook.
#
# Usage: worktree-audit.sh [-b|--base <ref>] [repo-path]
#   repo-path defaults to the current repo.
#   -b sets the ref the MERGED column checks against (e.g. origin/integration).
#   Without it the base is origin/HEAD, then origin/main, then origin/master.
#   origin/HEAD is the remote's default branch, not necessarily the branch PRs
#   merge into; pass -b when they differ.
set -u

base=""
while [ $# -gt 0 ]; do
	case "$1" in
	-b|--base) [ $# -ge 2 ] || { echo "error: $1 needs a ref" >&2; exit 2; }; base="$2"; shift 2 ;;
	-h|--help) sed -n '2,/^set -u/p' "$0" | sed '$d; s/^# \{0,1\}//'; exit 0 ;;
	-*) echo "error: unknown option: $1" >&2; exit 2 ;;
	*) break ;;
	esac
done

repo="${1:-$(git rev-parse --show-toplevel 2>/dev/null)}"
[ -z "$repo" ] && { echo "not in a git repo; pass a repo path" >&2; exit 1; }
cd "$repo" || exit 1
git rev-parse --git-dir >/dev/null 2>&1 || { echo "error: not a git repo: $repo" >&2; exit 1; }

# Main worktree is the first entry; everything else is a candidate.
# Strip the record prefix rather than splitting fields, so a path with spaces survives.
if ! worktree_records=$(git worktree list --porcelain); then
	echo "could not inspect git worktrees" >&2
	exit 1
fi
main_wt=$(printf '%s\n' "$worktree_records" | awk '/^worktree /{sub(/^worktree /, ""); print; exit}')

if [ -z "$base" ]; then
	for cand in "$(git symbolic-ref --short refs/remotes/origin/HEAD 2>/dev/null)" origin/main origin/master; do
		[ -n "$cand" ] && git rev-parse --verify --quiet "$cand^{commit}" >/dev/null && { base="$cand"; break; }
	done
	[ -z "$base" ] && { echo "error: no base ref (origin/HEAD, origin/main, origin/master all missing); pass -b <ref>" >&2; exit 1; }
	echo "warn: no -b given; MERGED checks against $base" >&2
fi

# The base drives the merge check. The fetch is best-effort (stale is fine for
# a first pass) and runs before the check, since -b may name a branch not
# fetched yet. The explicit refspec creates it even in a single-branch clone.
case "$base" in
origin/*) git fetch origin "+refs/heads/${base#origin/}:refs/remotes/$base" --quiet 2>/dev/null \
	|| echo "warn: could not fetch $base; merged column may be stale" >&2 ;;
esac
git rev-parse --verify --quiet "$base^{commit}" >/dev/null 2>&1 || { echo "error: base ref not found: $base" >&2; exit 1; }

# GNU coreutils (Linux, Homebrew gnubin) reads `stat -f` as file system status
# and `date -r` as a file, so pick the stat and date flags once.
if stat -c %Y / >/dev/null 2>&1; then
	stat_fmt=(-c '%Y %n'); fmt_day() { date -d "@$1" '+%Y-%m-%d'; }
else
	stat_fmt=(-f '%m %N'); fmt_day() { date -r "$1" '+%Y-%m-%d'; }
fi

# PR state by branch, fetched once as [{number, state, head, head_oid}] with a
# lowercase state. Origin when its CLI can read this repo's PRs, otherwise gh.
# Empty when neither can. Held in memory, so the audit writes no scratch file.
prs=""
if command -v origin >/dev/null 2>&1 \
	&& raw=$(origin pr list --author "@me" --state all --limit 1000 \
		--json number,status,headRef 2>/dev/null); then
	prs=$(printf '%s' "$raw" | jq -c '[.[] | {number, state: (.status // "" | ascii_downcase), head: .headRef, head_oid: ""}]' 2>/dev/null)
elif raw=$(gh pr list --author "@me" --state all --limit 1000 \
	--json number,state,headRefName,headRefOid 2>/dev/null); then
	prs=$(printf '%s' "$raw" | jq -c '[.[] | {number, state: (.state // "" | ascii_downcase), head: .headRefName, head_oid: (.headRefOid // "")}]' 2>/dev/null)
fi
[ -n "$prs" ] || prs="[]"

# omp's session store, resolved the way omp resolves it. An explicit
# PI_CODING_AGENT_SESSION_DIR is the transcript directory itself, with no cwd
# bucket under it. Otherwise the root is the profile's (OMP_PROFILE, else
# PI_PROFILE) under ~/${PI_CONFIG_DIR:-.omp}, PI_CODING_AGENT_DIR when no
# profile is set, or an existing XDG_DATA_HOME/omp when the agent dir is the
# default, and it holds one bucket per canonical cwd. Only the buckets of this
# repo's worktrees and their subdirectories are scanned; walking every bucket
# would scale with total session history. A store that cannot be read makes
# LAST_CHAT "?" and holds the row at verify-recent-chat instead of reading as
# no chat at all.
# omp also fills each unset variable from the .env in the cwd it launched in,
# then the agent dir's, the config root's and home's, reading an OMP_ key there
# as its PI_ alias, while the profile comes from the environment alone. The
# audit does not replay that loader. A store key in any of those files counts
# as a store it cannot read. An explicit session directory is exempt, since the
# environment outranks every .env.
canon() { (CDPATH='' cd -- "$1" 2>/dev/null && pwd -P) || printf '%s\n' "$1"; }
dash() { printf '%s' "$1" | tr '/\\:' '---'; }
# Path of $2 relative to $1, failing when $2 is outside it. Like omp, a
# relative path starting with ".." counts as outside.
rel_under() {
	local root="${1%/}"
	case "$2" in
	"$root") return 0 ;;
	"$root"/*) case "${2#"$root"/}" in ..*) return 1 ;; esac; printf '%s' "${2#"$root"/}" ;;
	*) return 1 ;;
	esac
}
# omp's bucket name for a canonical cwd. The temp root is checked before home.
bucket_name() {
	local rel
	if rel=$(rel_under "$temp_root" "$1"); then printf '%s' "-tmp${rel:+-$(dash "$rel")}"
	elif rel=$(rel_under "$home_root" "$1"); then printf '%s' "-$(dash "$rel")"
	else printf '%s' "--$(dash "${1#/}")--"; fi
}
session_dirs=()
dotenvs=()
config_root="$HOME/${PI_CONFIG_DIR:-.omp}"
if [ -n "${PI_CODING_AGENT_SESSION_DIR:-}" ]; then
	sessions=$PI_CODING_AGENT_SESSION_DIR
	session_dirs=("$sessions/")
else
	profile=$(printf '%s' "${OMP_PROFILE-${PI_PROFILE-}}" | sed 's/^[[:space:]]*//; s/[[:space:]]*$//')
	[ "$profile" = default ] && profile=""
	config="$config_root${profile:+/profiles/$profile}"
	agent="$config/agent"
	[ -z "$profile" ] && [ -n "${PI_CODING_AGENT_DIR:-}" ] && agent=$PI_CODING_AGENT_DIR
	data=$agent
	xdg="${XDG_DATA_HOME:-}/omp${profile:+/profiles/$profile}"
	[ "$agent" = "$config/agent" ] && [ -n "${XDG_DATA_HOME:-}" ] && [ -e "$xdg" ] && data=$xdg
	sessions="$data/sessions"
	dotenvs=("$agent/.env" "$config/.env" "$HOME/.env")
fi
# A session launched with --profile, --session-dir or another environment is
# not in that store. Every store under the config root and the XDG roots counts
# too, and each one's custom-session-files lists the absolute path of every
# transcript omp wrote outside the bucket store. Precedence does not matter
# for these, since a transcript only counts when it names the worktree.
home_root=$(canon "$HOME")
temp_root=$(canon "${TMPDIR:-${TMP:-${TEMP:-/tmp}}}")
roots=("$config_root/agent" "$config_root"/profiles/*/agent)
for x in "${XDG_DATA_HOME:-}" "${XDG_STATE_HOME:-}"; do
	[ -n "$x" ] && roots+=("$x/omp" "$x"/omp/profiles/*)
done
[ -n "${PI_CODING_AGENT_DIR:-}" ] && roots+=("$PI_CODING_AGENT_DIR")
indexes=()
stores=$'\n'
for root in "${roots[@]}"; do
	[ -d "$root/custom-session-files" ] && indexes+=("$root/custom-session-files")
	[ -d "$root/sessions" ] && stores+="$(canon "$root/sessions")"$'\n'
done
while IFS= read -r path; do
	cpath=$(canon "$path")
	own=$(bucket_name "$cpath")
	# A session started in a subdirectory has that subdirectory's bucket, the
	# worktree's name plus "-<rest>" ahead of any closing "--". A transcript
	# still has to name the worktree path, so a bucket that only shares the
	# prefix costs time, never a match. The main worktree is skipped, since a
	# repo at $HOME would make this the whole store.
	sub=$(bucket_name "$cpath/*")
	for root in "${roots[@]}"; do
		[ -d "$root/sessions/$own" ] && session_dirs+=("$root/sessions/$own/")
		[ "$path" = "$main_wt" ] && continue
		for dir in "$root/sessions/${sub%\**}"*"${sub##*\*}"; do
			[ -d "$dir" ] && session_dirs+=("$dir/")
		done
	done
	dotenvs+=("$path/.env")
done < <(printf '%s\n' "$worktree_records" | awk '/^worktree /{sub(/^worktree /, ""); print}')
# Under a symlinked home omp lists every bucket transcript too, and the bucket
# scan already covers those. They share one parent, so it is canonicalized
# once rather than once per transcript. Any other listed transcript that is
# gone holds no chat, but one behind a directory the audit cannot search may
# still exist. Its subagents sit in the directory named after it.
listed=$([ "${#indexes[@]}" -eq 0 ] || grep -rhs '' -- "${indexes[@]}")
index_status=$?
seen="" store="" closed=""
while IFS= read -r f; do
	[ "${f%/*/*}" = "$seen" ] || { seen=${f%/*/*}; store=$(canon "$seen"); }
	case "$stores" in *$'\n'"$store"$'\n'*) continue ;; esac
	if [ ! -f "$f" ]; then
		dir=${f%/*}
		while [ ! -e "$dir" ] && [ "$dir" != "${dir%/*}" ]; do dir=${dir%/*}; done
		[ -d "$dir" ] && [ ! -x "$dir" ] && closed=$dir
		continue
	fi
	session_dirs+=("$f")
	[ -d "${f%.jsonl}" ] && session_dirs+=("${f%.jsonl}/")
done <<<"$listed"
moved=""
[ -n "${PI_CODING_AGENT_SESSION_DIR:-}" ] ||
	moved=$(grep -lsE '^[[:space:]]*(export[[:space:]]+)?((PI|OMP)_(CODING_AGENT_SESSION_DIR|CODING_AGENT_DIR|CONFIG_DIR)|XDG_DATA_HOME)[[:space:]]*[=:]' \
		-- "${dotenvs[@]}")
chat_lookup=ok
if [ -n "$moved" ]; then
	chat_lookup=failed
	sed 's/^/warn: /; s/$/ can move the omp session store; LAST_CHAT is ? and rows hold at verify-recent-chat/' <<<"$moved" >&2
elif [ ! -d "$sessions" ]; then
	chat_lookup=failed
	echo "warn: no omp session store at $sessions; LAST_CHAT is ? and rows hold at verify-recent-chat" >&2
elif [ "$index_status" -gt 1 ]; then
	chat_lookup=failed
	echo "warn: cannot read an omp custom-session-files index; LAST_CHAT is ? and rows hold at verify-recent-chat" >&2
elif [ -n "$closed" ]; then
	chat_lookup=failed
	echo "warn: cannot search $closed for a listed omp transcript; LAST_CHAT is ? and rows hold at verify-recent-chat" >&2
fi
now=$(date +%s)

echo "# base: $base"
printf "SIZE\tAGE\tMERGED\tDIRTY\tLOCKED\tINSPECT\tREMOTE\tPR\tLAST_CHAT\tBUCKET\tWORKTREE\n"

printf '%s\n' "$worktree_records" | awk '
	/^worktree / { if (wt != "") print wt "\t" lock; wt = substr($0, 10); lock = "-" }
	/^locked/ { lock = substr($0, 8); if (lock == "") lock = "yes" }
	END { if (wt != "") print wt "\t" lock }' | while IFS=$'\t' read -r wt lock; do
	[ "$wt" = "$main_wt" ] && continue

	inspect=ok
	size=$(du -sh "$wt" 2>/dev/null | awk '{print $1}')
	if ! head=$(git -C "$wt" rev-parse HEAD 2>/dev/null); then
		head=""
		inspect="head-error"
	fi
	head_ts=$(git -C "$wt" log -1 --format='%ct' HEAD 2>/dev/null || echo 0)
	age=$([ "$head_ts" -gt 0 ] 2>/dev/null && echo "$(( (now - head_ts) / 86400 ))d" || echo "?")

	# Squash-merged branches are not ancestors of the base, so PR state is the
	# real signal; merge-base only catches fast-forward/rebase merges.
	git merge-base --is-ancestor "$head" "$base" 2>/dev/null && merged=YES || merged=no

	# Treat tracked, untracked, and ignored paths as work that must be held.
	if ! porcelain=$(git -C "$wt" status --porcelain --untracked-files=all --ignored=matching 2>/dev/null); then
		dirty=error
		inspect="status-error"
	elif [ -z "$porcelain" ]; then dirty=clean
	else dirty="wip:$(printf '%s\n' "$porcelain" | wc -l | tr -d '[:space:]')"; fi

	branch=$(git -C "$wt" symbolic-ref --quiet --short HEAD 2>/dev/null || echo "")
	if [ -z "$branch" ]; then remote=detached
	elif git -C "$wt" show-ref --verify --quiet "refs/remotes/origin/$branch"; then
		[ "$(git -C "$wt" rev-parse "origin/$branch" 2>/dev/null)" = "$head" ] \
			&& remote=pushed \
			|| remote="ahead$(git -C "$wt" rev-list --count "origin/$branch..HEAD" 2>/dev/null)"
		[ "$remote" = ahead0 ] && remote=behind
	else remote=no-remote; fi

	# Several PRs can share a branch name; prefer the one whose head is HEAD.
	pr_record=$([ -n "$branch" ] && printf '%s' "$prs" | jq -r --arg b "$branch" --arg h "$head" \
		'[.[] | select(.head==$b)] | (map(select(.head_oid==$h)) + .)[0]
		| select(.) | "#\(.number)/\(.state)\t\(.head_oid // "")"' 2>/dev/null)
	pr=${pr_record%%$'\t'*}
	pr_head=${pr_record#*$'\t'}
	[ -z "$pr" ] && pr="-"

	# Most recent chat whose transcript operated in this worktree, under the
	# path git lists or its canonical spelling. Match path followed by "/" or a
	# quote so glint-482 does not match glint-482-r37.
	last="-"; last_ts=0; chat=$chat_lookup
	if [ "$chat" = ok ] && [ "${#session_dirs[@]}" -gt 0 ]; then
		cwt=$(canon "$wt")
		matched=$(grep -RlsF --include='*.jsonl' -e "${wt}/" -e "${wt}\"" -e "${cwt}/" -e "${cwt}\"" \
			-- "${session_dirs[@]}")
		[ $? -le 1 ] || chat=failed
		while IFS= read -r f; do
			[ -n "$f" ] || continue
			ts=$(stat "${stat_fmt[@]}" "$f") || { chat=failed; break; }
			ts=${ts%% *}
			[ "$ts" -gt "$last_ts" ] && last_ts=$ts
		done <<<"$matched"
	fi
	if [ "$chat" != ok ]; then last="?"
	elif [ "$last_ts" -gt 0 ]; then last=$(fmt_day "$last_ts" 2>/dev/null) || last="?"; fi
	recent=$([ "$last_ts" -gt 0 ] 2>/dev/null && [ $(( (now - last_ts) / 86400 )) -le 4 ] && echo yes || echo no)

	# An exact PR head proves the commits were pushed even if origin has no
	# branch (deleted after merging, or hosted on a fork). A closed PR still
	# proves nothing about whether those commits were merged.
	case "$pr" in */merged) pr_merged=yes ;; *) pr_merged=no ;; esac
	case "$remote" in ahead*|no-remote|detached) unpushed=yes ;; *) unpushed=no ;; esac
	[ "$merged" = YES ] && unpushed=no
	[ -n "$pr_head" ] && [ "$head" = "$pr_head" ] && unpushed=no

	case "$dirty" in wip:*) bucket=hold-wip ;; *)
		case "$pr" in */open|*/draft) bucket=hold-open-pr ;; *)
			if [ "$unpushed" = yes ]; then bucket=hold-unpushed
			elif [ "$recent" = yes ] || [ "$chat" != ok ]; then bucket=verify-recent-chat
			elif [ "$merged" = YES ] || [ "$pr_merged" = yes ]; then bucket=safe
			else bucket=review; fi ;;
		esac ;;
	esac
	# A locked or unreadable worktree is never a candidate, whatever else holds.
	[ "$lock" != "-" ] && bucket=hold-locked
	[ "$inspect" != ok ] && bucket=hold-error

	printf "%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n" \
		"$size" "$age" "$merged" "$dirty" "$lock" "$inspect" "$remote" "$pr" "$last" "$bucket" "$wt"
done | sort -t$'\t' -k1,1 -rh
