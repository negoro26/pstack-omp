#!/usr/bin/env bash
# Sync the omp port of pstack to an upstream cursor/plugins commit. Port-only file, never upstream.
#
# The sync is a function of two inputs, the pinned sha in omp-port/UPSTREAM and a target sha. It
# writes the merged plugins/pstack tree, the version fields derived from upstream, and then the new
# pin. The pin lands last, so an interrupted run reruns cleanly instead of latching.
#
# Usage
#   bash omp-port/sync-upstream.sh check
#       Lists upstream commits touching pstack/ since the pin, newest first, one per line as
#       "<short-sha>\t<date>\t<subject>". Empty stdout and exit 0 mean no drift. The resolved
#       target head sha is written to stderr as "target <full-sha>", and also to the file named
#       by SYNC_TARGET_OUT when that variable is set, which is how CI captures it.
#   bash omp-port/sync-upstream.sh [<target-sha>]
#       Merges upstream into plugins/pstack. <target-sha> must be a full 40-hex sha that touched
#       pstack/. Default is the newest upstream commit that touched pstack/.
#
# Exit 0 clean, 2 conflict, 1 failure. Markers are zdiff3, so a conflicted hunk shows base, ours,
# and theirs, and the resolver can see what upstream actually changed.
# Override the canonical checkout location with CANON=/path.
set -euo pipefail
. "$(dirname "$0")/lib.sh"
cd "$(dirname "$0")/.."
REPO=$(pwd -P)

CANON="${CANON:-/tmp/cursor-plugins}"
PIN_FILE=omp-port/UPSTREAM
UPSTREAM_URL=https://github.com/cursor/plugins

die() { printf 'sync-upstream: %s\n' "$*" >&2; exit 1; }

read_pin() {
	[ -f "$PIN_FILE" ] ||
		die "no pin at $PIN_FILE, create it holding the full 40-hex upstream sha this port was built from"
	local p
	p=$(tr -d '[:space:]' <"$PIN_FILE")
	[[ $p =~ ^[0-9a-f]{40}$ ]] || die "$PIN_FILE must hold one full 40-hex sha, got '$p'"
	printf '%s\n' "$p"
}

# The path-filtered history is the only history that matters here. A monorepo head that never
# touched pstack/ is not a syncable target and the next run could not find it as a pin.
pstack_log() {
	gh api "repos/cursor/plugins/commits?path=pstack&sha=main&per_page=100" \
		--jq '.[] | [.sha, .sha[0:7], (.commit.author.date|split("T")[0]), (.commit.message|split("\n")[0])] | @tsv'
}

upstream_head() { gh api 'repos/cursor/plugins/commits?path=pstack&sha=main&per_page=1' --jq '.[0].sha'; }

commits_since() {
	local pin="$1" log out st=0
	log=$(pstack_log)
	out=$(printf '%s\n' "$log" |
		awk -F'\t' -v pin="$pin" '$1==pin { seen=1; exit } { print $2"\t"$3"\t"$4 } END { if (!seen) exit 3 }') || st=$?
	[ "$st" -eq 0 ] ||
		die "pin $pin is not among the last 100 upstream pstack commits, widen the query in pstack_log"
	[ -z "$out" ] || printf '%s\n' "$out"
}

ensure_canon() {
	if [ ! -d "$CANON/.git" ]; then
		git clone --depth 1 --filter=blob:none --sparse "$UPSTREAM_URL" "$CANON"
		git -C "$CANON" sparse-checkout set pstack
	fi
	local s
	for s in "$@"; do
		git -C "$CANON" cat-file -e "$s^{commit}" 2>/dev/null ||
			git -C "$CANON" fetch --depth 1 --filter=blob:none origin "$s"
	done
}

# A synthetic tree holding only plugins/pstack/{skills,agents} at the given upstream sha. Paths the
# port owns are absent from it, so merge-tree sees them as ours-only and leaves them alone.
tree_of() {
	local sha="$1" work idx tree=""
	work=$(mktemp -d)
	idx=$(mktemp -u)
	mkdir -p "$work/plugins/pstack"
	git -C "$CANON" archive "$sha" pstack/skills pstack/agents |
		tar -x --strip-components=1 -C "$work/plugins/pstack"
	# set -e does not reach a failing pipeline inside a command substitution, and an empty
	# extraction would read as "upstream deleted everything". Print nothing instead.
	if [ -d "$work/plugins/pstack/skills" ] && [ -d "$work/plugins/pstack/agents" ]; then
		tree=$(cd "$work" &&
			GIT_INDEX_FILE="$idx" git --git-dir="$REPO/.git" --work-tree="$work" add -Af . >/dev/null &&
			GIT_INDEX_FILE="$idx" git --git-dir="$REPO/.git" write-tree)
	fi
	rm -rf "$work" "$idx"
	printf '%s\n' "$tree"
}

write_json() {
	local path="$1"
	shift
	local tmp
	tmp=$(mktemp "$path.XXXXXX")
	jq --indent 2 "$@" "$path" >"$tmp"
	chmod --reference="$path" "$tmp"
	mv "$tmp" "$path"
}

cmd_sync() {
	local target="${1:-}" pin base_tree target_tree merged conflicts touched version st=0
	pin=$(read_pin)
	[ -n "$target" ] || target=$(upstream_head)
	[[ $target =~ ^[0-9a-f]{40}$ ]] || die "target must be a full 40-hex sha, got '$target'"
	touched=$(pstack_log | cut -f1)
	grep -qxF "$target" <<<"$touched" ||
		die "target $target does not touch pstack/, the pin must be a commit that touched pstack/"
	if [ "$pin" = "$target" ]; then
		printf 'sync-upstream: already at %s, nothing to do\n' "$target"
		return 0
	fi
	[ -z "$(git status --porcelain -- plugins/pstack)" ] ||
		die "uncommitted changes under plugins/pstack, commit or stash them first"

	ensure_canon "$pin" "$target"
	# Read before the worktree changes, so a lazy blob fetch that fails cannot strand a
	# rewritten tree next to an unwritten version.
	version=$(git -C "$CANON" show "$target:pstack/.cursor-plugin/plugin.json" | jq -r .version)
	base_tree=$(tree_of "$pin")
	target_tree=$(tree_of "$target")
	[[ $base_tree =~ ^[0-9a-f]{40}$ && $target_tree =~ ^[0-9a-f]{40}$ ]] ||
		die "could not build the synthetic upstream trees from $CANON at $pin and $target"

	local mt mt_conflicts
	mt=$(git -c merge.conflictStyle=zdiff3 merge-tree --write-tree --merge-base="$base_tree" HEAD "$target_tree") || st=$?
	[ "$st" -le 1 ] || die "git merge-tree failed"
	merged=${mt%%$'\n'*}
	# merge-tree reports modify/delete and rename/delete conflicts here and nowhere else. They
	# leave no markers in the tree, so the marker grep alone would call them clean.
	mt_conflicts=$(printf '%s\n' "$mt" | tail -n +2 | grep '^CONFLICT' || true)
	git restore --source="$merged" --staged --worktree -- plugins/pstack
	git ls-files -z -- plugins/pstack | while IFS= read -r -d '' f; do
		git cat-file -e "$merged:$f" 2>/dev/null || git rm -qf --ignore-unmatch -- "$f"
	done

	conflicts=$(grep -rIl -E "$PAT_MARKER" plugins/pstack/skills plugins/pstack/agents || true)

	local n p k
	read -r n p k < <(port_counts plugins/pstack)

	write_json plugins/pstack/package.json --arg v "$version" '.version = $v'
	write_json .omp-plugin/marketplace.json --arg v "$version" \
		--arg d "$n skills, $p playbooks, $k principles, the poteto-mode pin, and two agents. Upstream cursor/plugins pstack at ${target:0:7}." \
		'.metadata.version = $v
		 | (.plugins[] | select(.name == "pstack")) |= (.version = $v | .description = $d)'
	printf '%s\n' "$target" >"$PIN_FILE"
	git add -- "$PIN_FILE" plugins/pstack/package.json .omp-plugin/marketplace.json

	printf '\npin      %s -> %s\nversion  %s\ncounts   %s skills, %s playbooks, %s principles\nchanged  %s files under plugins/pstack\n' \
		"${pin:0:7}" "${target:0:7}" "$version" "$n" "$p" "$k" \
		"$(git status --porcelain -- plugins/pstack | wc -l)"
	if [ "$st" -eq 1 ] || [ -n "$mt_conflicts" ] || [ -n "$conflicts" ]; then
		printf 'conflicts merge-tree exit %s\n' "$st"
		if [ -n "$mt_conflicts" ]; then
			printf 'merge-tree\n'
			printf '%s\n' "$mt_conflicts" | sed 's/^/  /'
		fi
		if [ -n "$conflicts" ]; then
			printf 'markers  %s files\n' "$(printf '%s\n' "$conflicts" | wc -l)"
			printf '%s\n' "$conflicts" | sed 's/^/  /'
		fi
		return 2
	fi
	printf 'conflicts none\n'
}

case "${1:-}" in
check)
	pin=$(read_pin)
	target=$(upstream_head)
	printf 'target %s\n' "$target" >&2
	[ -z "${SYNC_TARGET_OUT:-}" ] || printf '%s\n' "$target" >"$SYNC_TARGET_OUT"
	commits_since "$pin"
	;;
-h | --help) sed -n '2,20p' "$0" ;;
*) cmd_sync "${1:-}" ;;
esac
