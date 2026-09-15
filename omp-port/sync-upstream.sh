#!/usr/bin/env bash
# Build the omp port of pstack from an upstream cursor/plugins commit. Port-only file, never upstream.
#
# The port is a build, not a maintained tree. plugins/pstack/{skills,agents} is upstream text at
# the pinned sha with omp-port/rules.sed applied, omp-port/patches/*.patch applied on top, and the
# paths in omp-port/owned.txt carried across. Upstream prose can therefore never conflict with
# port prose, because the port never edits upstream files in place.
#
# Usage
#   bash omp-port/sync-upstream.sh check
#       Lists upstream commits touching pstack/ since the pin, newest first, one per line as
#       "<short-sha>\t<date>\t<subject>". Empty stdout and exit 0 mean no drift. The resolved
#       target head sha is written to stderr as "target <full-sha>", and also to the file named
#       by SYNC_TARGET_OUT when that variable is set, which is how CI captures it.
#   bash omp-port/sync-upstream.sh [<target-sha>]
#       Rebuilds plugins/pstack at <target-sha> and moves the pin to it. <target-sha> must be a
#       full 40-hex sha that touched pstack/. Default is the newest such commit. Refuses to run
#       when the built tree carries uncommitted changes, owned paths excepted.
#   bash omp-port/sync-upstream.sh rebuild
#       Rebuilds at the current pin without moving it, which is what a maintainer runs after
#       editing rules.sed, patches/, or owned.txt. Uncommitted build output is what it replaces,
#       so unlike a sync it does not refuse a dirty tree.
#
# Exit 0 clean, 1 failure, including a patch that no longer applies.
# Override the canonical checkout location with CANON=/path.
set -euo pipefail
. "$(dirname "$0")/lib.sh"
cd "$(dirname "$0")/.."

PIN_FILE=omp-port/UPSTREAM

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

write_json() {
	local path="$1"
	shift
	local tmp
	tmp=$(mktemp "$path.XXXXXX")
	jq --indent 2 "$@" "$path" >"$tmp"
	chmod --reference="$path" "$tmp"
	mv "$tmp" "$path"
}

# Build at <sha>, install it, refresh the derived fields, and stage everything. The pin lands
# last and only when <move-pin> is yes, so an interrupted run reruns cleanly instead of latching.
do_build() {
	local sha="$1" pin="$2" move="$3" version work n p k
	ensure_canon "$sha" || die "no canonical checkout at $CANON and cloning $UPSTREAM_URL failed"
	# Read before the worktree changes, so a lazy blob fetch that fails cannot strand a
	# rebuilt tree next to an unwritten version.
	version=$(git -C "$CANON" show "$sha:pstack/.cursor-plugin/plugin.json" | jq -r .version)
	work=$(mktemp -d)
	build_tree "$sha" "$work" || {
		rm -rf "$work"
		die "build at ${sha:0:7} failed, see the output above"
	}
	install_tree "$work" || die "installing the built tree failed"
	rm -rf "$work"

	read -r n p k < <(port_counts plugins/pstack)
	write_json plugins/pstack/package.json --arg v "$version" '.version = $v'
	write_json .omp-plugin/marketplace.json --arg v "$version" \
		--arg d "$n skills, $p playbooks, $k principles, the poteto-mode pin, and two agents. Upstream cursor/plugins pstack at ${sha:0:7}." \
		'.metadata.version = $v
		 | (.plugins[] | select(.name == "pstack")) |= (.version = $v | .description = $d)'
	[ "$move" != yes ] || printf '%s\n' "$sha" >"$PIN_FILE"
	git add -A plugins/pstack "$PIN_FILE" plugins/pstack/package.json .omp-plugin/marketplace.json

	printf '\npin      %s -> %s\nversion  %s\ncounts   %s skills, %s playbooks, %s principles\nchanged  %s files under plugins/pstack\n' \
		"${pin:0:7}" "$(cut -c1-7 "$PIN_FILE")" "$version" "$n" "$p" "$k" \
		"$(git status --porcelain -- plugins/pstack | wc -l)"
	# A slug the tiered rules never named still comes out model-agnostic, but it is worth a
	# tiered rule that names the right capability instead of the generic replacement.
	untiered_slugs "$sha" | sed 's/^/untiered /'
}

cmd_sync() {
	local target="${1:-}" pin touched dirty p
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
	# Only the built tree is destroyed by a sync, and owned paths are carried across it, so an
	# uncommitted owned file or an edit anywhere else is not a reason to refuse.
	dirty=$(git status --porcelain -- plugins/pstack/skills plugins/pstack/agents | sed 's/^...//')
	while IFS= read -r p; do
		dirty=$(printf '%s\n' "$dirty" | grep -v "^plugins/pstack/$p" || true)
	done < <(owned_paths)
	if [ -n "$(printf '%s' "$dirty" | tr -d '[:space:]')" ]; then
		printf '%s\n' "$dirty" >&2
		die "uncommitted changes the build would destroy, commit or stash them first"
	fi
	do_build "$target" "$pin" yes
}

cmd_rebuild() {
	local pin
	pin=$(read_pin)
	do_build "$pin" "$pin" no
}

case "${1:-}" in
check)
	pin=$(read_pin)
	target=$(upstream_head)
	printf 'target %s\n' "$target" >&2
	[ -z "${SYNC_TARGET_OUT:-}" ] || printf '%s\n' "$target" >"$SYNC_TARGET_OUT"
	commits_since "$pin"
	;;
rebuild) cmd_rebuild ;;
-h | --help) sed -n '2,25p' "$0" ;;
*) cmd_sync "${1:-}" ;;
esac
