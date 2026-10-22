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
	# PATCH_DIR is overridable for the same reason RULES is: the mutation harness has to be able to
	# feed the build a patch set that does not apply without editing the repository to do it.
	local work="$1" p
	for p in "${PATCH_DIR:-$PORT_DIR/patches}"/*.patch; do
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

# Owned paths that upstream also carries, and how many upstream commits have touched each between
# the pin and <target>, as "<owned-path>\t<count>".
#
# Ownership is deliberate and the build is right to discard the built copy, but that is exactly what
# makes an upstream edit to an owned path disappear with no conflict, no patch failure and no gate
# failure. install_tree restores the checked-in copy over whatever the build produced; reproducible
# copies owned paths out of the live tree before diffing, so it cannot see the difference; and the
# resulting tree is byte-identical to the build by construction. Proven end to end on the base
# branch: an upstream commit adding a section to setup-pstack/SKILL.md, the pin moved to it, real
# build and install, section gone, `owned PASS` and `reproducible PASS`.
#
# This only means anything when the target differs from the pin. Compared to itself the count is
# always zero, which is why it lives here rather than on the branch that introduced ownership: that
# branch had no target to compare against.
owned_upstream_drift() {
	local target="$1" base="$2" rel up n
	[ -d "$CANON/.git" ] || return 0
	while IFS= read -r rel; do
		up="pstack/$rel"
		git -C "$CANON" cat-file -e "$target:$up" 2>/dev/null || continue
		n=$(git -C "$CANON" rev-list --count "$base..$target" -- "$up" 2>/dev/null) || n=""
		printf '%s\t%s\n' "$rel" "${n:-?}"
	done < <(owned_paths)
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

# One rule per line as "<line-number>\t<rule>", comments and blanks dropped and a trailing
# backslash continuation joined onto the rule it belongs to, so every record is something sed can
# parse on its own. Both probes below read rules through this, and a rule split across lines would
# otherwise be handed to sed as a fragment, which fails, which is indistinguishable from a rule
# that matched nothing.
rule_records() {
	awk '
		function flush() { if (buf != "") { printf "%d\t%s\n", start, buf; buf = "" } }
		{
			if (buf != "") {
				buf = buf "\n" $0
				if ($0 !~ /\\[[:space:]]*$/) flush()
				next
			}
			if ($0 ~ /^[[:space:]]*#/ || $0 ~ /^[[:space:]]*$/) next
			start = NR; buf = $0
			if ($0 !~ /\\[[:space:]]*$/) flush()
		}
		END { flush() }
	' "$RULES"
}

# Substitution rules that fire against the upstream text at <sha>, as "<line-number>\t<rule>".
# A rule whose left-hand side no longer matches changes nothing and sed still exits 0, so without
# this the build cannot distinguish a rule that substituted from one upstream has outrun. Each
# rule's replacement is rewritten to carry its own line number as a marker, so one marked build
# answers for all of them: a marker with no occurrence in the tree is a rule that matched nothing.
# Most of what this reports is healthy. The token rules sit under the whole-sentence rules and fire
# nothing precisely because an earlier rule already consumed their input, and that redundancy is
# the safety net for when a whole-sentence rule misses.
dead_rules() {
	local sha="$1" work marked st=0
	work=$(mktemp -d)
	marked=$(mktemp)
	awk '
		{
			s = $0
			if (s !~ /^s./) { print s; next }
			d = substr(s, 2, 1)
			rest = substr(s, 3)
			k = index(rest, d)
			if (k == 0) { print s; next }
			body = substr(rest, k + 1)
			j = index(body, d)
			if (j == 0) { print s; next }
			printf "s%s%s%s@%d@%s%s\n", d, substr(rest, 1, k - 1), d, NR, substr(body, 1, j - 1), substr(body, j)
		}' "$RULES" >"$marked"
	if extract_upstream "$sha" "$work" && apply_rules "$work" "$marked"; then
		while IFS=$'\t' read -r n rule; do
			case "$rule" in s?*) ;; *) continue ;; esac
			grep -rqF "@$n@" "$work" 2>/dev/null || printf '%s\t%s\n' "$n" "$rule"
		done < <(rule_records)
	else
		st=1
	fi
	rm -rf "$work" "$marked"
	return "$st"
}

# Rules that can never fire again, as "<line-number>\t<rule>", which is the intersection of two
# questions and neither one alone.
#
# dead_rules asks which rules substituted nothing in a full marked build. That list is mostly
# healthy: the token rules sit under the whole-sentence rules and fire nothing precisely because an
# earlier rule already consumed their input, which is what makes them the net that catches a
# whole-sentence rule when it misses. But it cannot say why a rule produced nothing, so a rule
# upstream has outrun prints identically to a redundant one and nobody triages either.
#
# This applies each rule on its own to upstream as it stands, with the same sed and the same -E the
# build uses, so the engine is never reimplemented and a pattern cannot mean one thing to the probe
# and another to the build. A rule that changes nothing in isolation may still be fed by an earlier
# rule's output, so intersecting with dead_rules is what separates the two: dead in isolation and
# dead in the build is stale, dead only in the build is a net doing its job, and dead only in
# isolation is ordinary and needs nothing. The intersection is why this gate needs no exemption for
# the fed-by-earlier rules, which is most of them.
#
# A rule sed cannot parse exits non-zero, and treating that as "changed" would report a broken rule
# as a healthy one, so a parse failure fails the probe rather than producing a result.
#
# Exits 1, printing nothing, when the extract or any rule fails to parse, so a caller cannot read an
# empty result as "nothing is stale".
stale_rules() {
	# The dead-rule set is the other half of the intersection, and the caller has just computed it
	# for the assertion above. Passing it in halves the gate's wall time; recomputing it here when
	# absent costs one extra marked build and keeps this function usable on its own.
	local sha="$1" deadset="${2-}" work blob rule n st=0 out
	work=$(mktemp -d)
	blob=$(mktemp)
	out=$(mktemp)
	if extract_upstream "$sha" "$work"; then
		find "$work" -type f -print0 | xargs -0 cat >"$blob" 2>/dev/null || :
		[ -n "$deadset" ] || deadset=$(dead_rules "$sha") || deadset=''
		while IFS=$'\t' read -r n rule; do
			printf '%s\n' "$rule" >"$work/rule.sed"
			if ! sed -E -f "$work/rule.sed" "$blob" >"$work/out" 2>/dev/null; then
				st=1
				break
			fi
			cmp -s "$work/out" "$blob" || continue
			# Unchanged in isolation. Still only a candidate: it is stale only if it also produced
			# nothing in the real build, which is how a rule fed by an earlier rule is excluded.
			printf '%s\t' "$n" | grep -qxF "$n" <(cut -f1 <<<"$deadset") || continue
			printf '%s\t%s\n' "$n" "$rule" >>"$out"
		done < <(rule_records)
	else
		st=1
	fi
	if [ "$st" -eq 0 ]; then cat "$out"; fi
	rm -rf "$work" "$blob" "$out"
	return "$st"
}
