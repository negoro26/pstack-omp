#!/usr/bin/env bash
# Sync the omp port of pstack to an upstream cursor/plugins commit. Port-only file, never upstream.
#
# The sync is a function of two inputs, the pinned sha in omp-port/UPSTREAM and a target sha. It
# writes the merged plugins/pstack tree, the new pin, and the version fields derived from upstream.
# The pin file is the only state, which is what makes squash merging a sync PR safe.
#
# Usage
#   bash omp-port/sync-upstream.sh check
#       Lists upstream commits touching pstack/ since the pin, newest first, one per line as
#       "<short-sha>\t<date>\t<subject>". Empty stdout and exit 0 mean no drift. The resolved
#       target head sha is written to stderr as "target <full-sha>".
#   bash omp-port/sync-upstream.sh [<target-sha>]
#       Merges upstream into plugins/pstack. <target-sha> must be a full 40-hex sha. Default is the
#       current upstream main head.
#
# Exit 0 clean, 2 conflict markers left in the tree, 1 failure.
# Override the canonical checkout location with CANON=/path.
set -euo pipefail
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

upstream_head() { gh api repos/cursor/plugins/commits/main --jq .sha; }

commits_since() {
	local pin="$1" log out st=0
	log=$(gh api "repos/cursor/plugins/commits?path=pstack&sha=main&per_page=100" \
		--jq '.[] | [.sha, .sha[0:7], (.commit.author.date|split("T")[0]), (.commit.message|split("\n")[0])] | @tsv')
	out=$(printf '%s\n' "$log" |
		awk -F'\t' -v pin="$pin" '$1==pin { seen=1; exit } { print $2"\t"$3"\t"$4 } END { if (!seen) exit 3 }') || st=$?
	[ "$st" -eq 0 ] ||
		die "pin $pin is not among the last 100 upstream pstack commits, widen the query in commits_since"
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
	local sha="$1" work idx tree
	work=$(mktemp -d)
	idx=$(mktemp -u)
	mkdir -p "$work/plugins/pstack"
	git -C "$CANON" archive "$sha" pstack/skills pstack/agents |
		tar -x --strip-components=1 -C "$work/plugins/pstack"
	tree=$(cd "$work" &&
		GIT_INDEX_FILE="$idx" git --git-dir="$REPO/.git" --work-tree="$work" add -Af . >/dev/null &&
		GIT_INDEX_FILE="$idx" git --git-dir="$REPO/.git" write-tree)
	rm -rf "$work" "$idx"
	printf '%s\n' "$tree"
}

write_json() {
	local path="$1"
	shift
	local tmp
	tmp=$(mktemp)
	jq --indent 2 "$@" "$path" >"$tmp"
	mv "$tmp" "$path"
}

cmd_sync() {
	local target="${1:-}" pin base_tree target_tree merged conflicts st=0
	pin=$(read_pin)
	[ -n "$target" ] || target=$(upstream_head)
	[[ $target =~ ^[0-9a-f]{40}$ ]] || die "target must be a full 40-hex sha, got '$target'"
	if [ "$pin" = "$target" ]; then
		printf 'sync-upstream: already at %s, nothing to do\n' "$target"
		return 0
	fi
	[ -z "$(git status --porcelain -- plugins/pstack)" ] ||
		die "uncommitted changes under plugins/pstack, commit or stash them first"

	ensure_canon "$pin" "$target"
	base_tree=$(tree_of "$pin")
	target_tree=$(tree_of "$target")

	local mt
	mt=$(git merge-tree --write-tree --merge-base="$base_tree" HEAD "$target_tree") || st=$?
	[ "$st" -le 1 ] || die "git merge-tree failed"
	merged=$(printf '%s\n' "$mt" | head -1)
	git restore --source="$merged" --staged --worktree -- plugins/pstack
	git ls-files -z -- plugins/pstack | while IFS= read -r -d '' f; do
		git cat-file -e "$merged:$f" 2>/dev/null || git rm -qf --ignore-unmatch -- "$f"
	done

	conflicts=$(grep -rIl -E '^(<{7} |={7}$|>{7} )' plugins/pstack/skills plugins/pstack/agents || true)

	local version n p k
	version=$(git -C "$CANON" show "$target:pstack/.cursor-plugin/plugin.json" | jq -r .version)
	n=$(find plugins/pstack/skills -mindepth 1 -maxdepth 1 -type d | wc -l)
	p=$(find plugins/pstack/skills/poteto-mode/playbooks -name '*.md' -type f | wc -l)
	k=$(find plugins/pstack/skills -mindepth 1 -maxdepth 1 -type d -name 'principle-*' | wc -l)

	printf '%s\n' "$target" >"$PIN_FILE"
	write_json plugins/pstack/package.json --arg v "$version" '.version = $v'
	write_json .omp-plugin/marketplace.json --arg v "$version" \
		--arg d "$n skills, $p playbooks, $k principles, the poteto-mode pin, and two agents. Upstream cursor/plugins pstack at ${target:0:7}." \
		'.metadata.version = $v
		 | (.plugins[] | select(.name == "pstack")) |= (.version = $v | .description = $d)'

	printf '\npin      %s -> %s\nversion  %s\ncounts   %s skills, %s playbooks, %s principles\nchanged  %s files under plugins/pstack\n' \
		"${pin:0:7}" "${target:0:7}" "$version" "$n" "$p" "$k" \
		"$(git status --porcelain -- plugins/pstack | wc -l)"
	if [ -n "$conflicts" ]; then
		printf 'conflicts %s files carry markers\n' "$(printf '%s\n' "$conflicts" | wc -l)"
		printf '%s\n' "$conflicts" | sed 's/^/  /'
		return 2
	fi
	printf 'conflicts none\n'
}

case "${1:-}" in
check)
	pin=$(read_pin)
	printf 'target %s\n' "$(upstream_head)" >&2
	commits_since "$pin"
	;;
-h | --help) sed -n '2,20p' "$0" ;;
*) cmd_sync "${1:-}" ;;
esac
