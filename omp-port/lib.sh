#!/usr/bin/env bash
# The build pipeline, gate patterns, and live-tree counts shared by sync-upstream.sh and
# check-port.sh. Port-only file, never upstream. Paths resolve from this file's own location, so
# sourcing it before or after a cd makes no difference.

PORT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)
REPO_ROOT=$(cd "$PORT_DIR/.." && pwd -P)
CANON="${CANON:-/tmp/cursor-plugins}"
RULES="${RULES:-$PORT_DIR/rules.sed}"
UPSTREAM_URL=https://github.com/cursor/plugins

PAT_SLUG='\b(claude-[a-z0-9.-]+|gpt-[0-9][a-z0-9.-]*|grok-[a-z0-9.-]+|gemini-[a-z0-9.-]+|opus-[a-z0-9.-]+)\b'
PAT_CAPS='omp (has no|does not support|cannot|lacks) [A-Za-z`_.:-]+'
PAT_RESIDUE='cursor-team-kit|/deslop|run_in_background|<agent-transcripts>|~/\.cursor/|AskQuestion|cloud_base_branch|~/\.omp/skills/|~/\.omp/pstack/|environment: "cloud"'
# Every conflict git writes is bracketed by <<<<<<< and >>>>>>>, so a bare ======= needs no
# branch of its own and a seven-character setext underline stops being a false positive.
PAT_MARKER='^(<{7} |\|{7}( |$)|>{7} )'
# The last model-slug rule in rules.sed is a catch-all, so an upstream slug nobody wrote a tiered
# rule for still comes out model-agnostic. What it rewrote is reported, never silently accepted,
# and it is found by rebuilding without it and grepping for what it would have matched. Its
# replacement text is how the line is identified, so it has to stay unique in rules.sed, and its
# left side is read off that line rather than restated here where the two could drift apart.
CATCHALL_REPL='your configured model for this role'
catchall_pat() {
	grep -F "$CATCHALL_REPL" "$RULES" 2>/dev/null | head -n1 |
		sed -E "s@^s(.)(.*)\1${CATCHALL_REPL}\1g?\$@\2@"
}

# Skills, playbooks, and principle leaves under a plugin root, printed as one line. The
# generator and the gate call this, so they cannot disagree on what counts as a skill.
port_counts() {
	local root="$1" n p k
	n=$(find "$root/skills" -mindepth 1 -maxdepth 1 -type d | wc -l)
	p=$(find "$root/skills/poteto-mode/playbooks" -mindepth 1 -maxdepth 1 -type f -name '*.md' | wc -l)
	k=$(find "$root/skills" -mindepth 1 -maxdepth 1 -type d -name 'principle-*' | wc -l)
	printf '%s %s %s\n' "$n" "$p" "$k"
}

# The port is a build, not a maintained tree. plugins/pstack/{skills,agents} is build_tree(pin)
# plus the paths in owned.txt, so upstream text can never conflict with port text. rules.sed
# rewrites mechanics, patches/ carries port-only code, owned.txt carries port-only files.

ensure_canon() {
	if [ ! -d "$CANON/.git" ]; then
		git clone --depth 1 --filter=blob:none --sparse "$UPSTREAM_URL" "$CANON" || return 1
		git -C "$CANON" sparse-checkout set pstack || return 1
	fi
	local s
	for s in "$@"; do
		git -C "$CANON" cat-file -e "$s^{commit}" 2>/dev/null ||
			git -C "$CANON" fetch --depth 1 --filter=blob:none origin "$s" || return 1
	done
}

# Step 1, upstream text as it is, with pstack/ stripped so skills and agents land at the root.
extract_upstream() {
	local sha="$1" work="$2"
	git -C "$CANON" archive "$sha" pstack/skills pstack/agents |
		tar -x --strip-components=1 -C "$work" || return 1
	[ -d "$work/skills" ] && [ -d "$work/agents" ]
}

# Step 2, the substitution table. Binary files are skipped rather than corrupted, which is what
# grep -I reports when the empty pattern does not match.
apply_rules() {
	local work="$1" rules="$2" f
	while IFS= read -r -d '' f; do
		if grep -Iq '' "$f"; then
			sed -E -i -f "$rules" "$f" || return 1
		fi
	done < <(find "$work" -type f -print0)
}

# Step 3, the port's own code. A patch that no longer applies is a hard stop, because the
# alternative is shipping a tree that silently lost the port's behavior.
apply_patches() {
	local work="$1" p
	for p in "$PORT_DIR"/patches/*.patch; do
		[ -e "$p" ] || continue
		patch -p1 -d "$work" --fuzz=0 --no-backup-if-mismatch <"$p" || return 1
	done
}

build_tree() {
	local sha="$1" work="$2"
	extract_upstream "$sha" "$work" &&
		apply_rules "$work" "$RULES" &&
		apply_patches "$work"
}

# One owned path per line, relative to plugins/pstack. Comments and blanks are the file's, not
# the caller's problem.
owned_paths() {
	[ -f "$PORT_DIR/owned.txt" ] || return 0
	awk '{ sub(/#.*/, ""); gsub(/^[[:space:]]+|[[:space:]]+$/, ""); if ($0 != "") print }' \
		"$PORT_DIR/owned.txt"
}

# Step 4. The rm is what makes the build authoritative: a file upstream deleted, or one a
# maintainer hand-added, is gone before the new tree lands. The owned paths are carried across it
# from the worktree, so an owned file that is not committed yet survives its first build. Only a
# path missing from the worktree falls back to HEAD, and one missing from both is a broken
# owned.txt and stops the build.
install_tree() {
	local work="$1" keep p src
	keep=$(mktemp -d)
	while IFS= read -r p; do
		src="$REPO_ROOT/plugins/pstack/$p"
		[ -e "$src" ] || continue
		mkdir -p "$keep/$(dirname "$p")"
		cp -a "$src" "$keep/$p" || return 1
	done < <(owned_paths)
	rm -rf "$REPO_ROOT/plugins/pstack/skills" "$REPO_ROOT/plugins/pstack/agents" || return 1
	mv "$work/skills" "$work/agents" "$REPO_ROOT/plugins/pstack/" || return 1
	while IFS= read -r p; do
		src="$REPO_ROOT/plugins/pstack/$p"
		if [ -e "$keep/$p" ]; then
			rm -rf "$src"
			mkdir -p "$(dirname "$src")"
			cp -a "$keep/$p" "$src" || return 1
		else
			git -C "$REPO_ROOT" checkout HEAD -- "plugins/pstack/$p" || return 1
		fi
	done < <(owned_paths)
	rm -rf "$keep"
}

# Distinct slugs the catch-all rewrote at <sha>, one per line.
untiered_slugs() {
	local sha="$1" rules work pat st=0
	pat=$(catchall_pat)
	[ -n "$pat" ] || return 0
	rules=$(mktemp)
	work=$(mktemp -d)
	grep -vF "$CATCHALL_REPL" "$RULES" >"$rules" || true
	if extract_upstream "$sha" "$work" && apply_rules "$work" "$rules"; then
		{ grep -rohIE "$pat" "$work" || true; } | sort -u
	else
		st=1
	fi
	rm -rf "$work" "$rules"
	return "$st"
}
