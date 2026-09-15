#!/usr/bin/env bash
# Gate for the omp port of pstack. Port-only file, never upstream.
# Usage: bash omp-port/check-port.sh [canonical-clone]
# The argument, or CANON, is the cursor/plugins clone the reproducible check builds from.
set -uo pipefail
. "$(dirname "$0")/lib.sh"
cd "$(dirname "$0")/../plugins/pstack"
CANON="${1:-$CANON}"
fail=0
report() { printf '%-28s %s\n' "$1" "$2"; }
violate() { fail=1; printf '  %s\n' "$1"; }

SCOPE=(skills agents)
ALLOW=../../omp-port/slug-allowlist.txt

# An audited exception is `path:line<TAB>pattern<TAB>reason`, where pattern is one of slug, caps,
# or residue. An exception covers that one pattern on that one line, nothing else. Illustrative
# prose only, never a real prescription. Anything not listed here passes on its own merits.
allowed() {
	[ -f "$ALLOW" ] || return 1
	awk -F'\t' -v k="$1" -v p="$2" '$1 == k && $2 == p { hit = 1 } END { exit !hit }' "$ALLOW"
}
allow_count() { awk -F'\t' -v p="$2" '$0 !~ /^#/ && $2 == p' "$1" | wc -l; }
# The gate patterns live in omp-port/lib.sh, one source shared with the sync script.
pattern_for() {
	case "$1" in
	slug) printf '%s\n' "$PAT_SLUG" ;;
	caps) printf '%s\n' "$PAT_CAPS" ;;
	residue) printf '%s\n' "$PAT_RESIDUE" ;;
	esac
}

scan() {
	local pat="$1" label="$2" name="$3" bad=""
	while IFS= read -r line; do
		allowed "$line" "$name" || bad="$bad$line"$'\n'
	done < <(grep -rIn -E "$pat" --include='*.md' --include='*.mjs' --include='*.ts' --include='*.sh' "${SCOPE[@]}" 2>/dev/null | cut -d: -f1,2)
	if [ -n "$bad" ]; then
		report "$label" "FAIL"
		while read -r b; do [ -n "$b" ] && violate "$b"; done <<<"$bad"
	else
		local n=0
		[ -f "$ALLOW" ] && n=$(allow_count "$ALLOW" "$name")
		report "$label" "PASS  clean, $n audited $name exception(s)"
	fi
}

scan "$PAT_SLUG" "model-agnostic" slug

# Role instructions must name an omp lever. /model sets the chat model,
# task.agentModelOverrides sets a per-agent model.
if grep -rIlq 'task.agentModelOverrides' skills/setup-pstack/SKILL.md skills/poteto-mode/SKILL.md 2>/dev/null; then
	report "omp model levers" "PASS  task.agentModelOverrides named"
else
	report "omp model levers" "FAIL"
	violate "setup-pstack and poteto-mode must name task.agentModelOverrides"
fi
if grep -rIlq '/model' skills/setup-pstack/SKILL.md 2>/dev/null; then
	report "chat-model lever" "PASS  /model named in setup-pstack"
else
	report "chat-model lever" "FAIL"
	violate "setup-pstack must tell the user to pick the chat model with /model"
fi

# A diverse-model review is a property of the reviewer, not a named slug.
undiverse=""
for f in skills/interrogate/SKILL.md skills/arena/SKILL.md skills/reflect/SKILL.md; do
	grep -qiE 'different (model )?(family|provider)|separate model family' "$f" ||
		undiverse="$undiverse $f"
done
if [ -n "$undiverse" ]; then
	report "review diversity" "FAIL"
	for f in $undiverse; do violate "no model-diversity property stated in $f"; done
else
	report "review diversity" "PASS  stated as a property"
fi

# A capability claim pinned to a version rots on the next upgrade, exactly like a
# hardcoded model slug. Depend on a probe or a conditional instead.
ver=$(grep -rIn -oE 'omp[/ ]?1[0-9]+\.[0-9]+(\.[0-9]+)?' --include='*.md' "${SCOPE[@]}" 2>/dev/null)
if [ -n "$ver" ]; then
	report "version-agnostic" "FAIL"
	while read -r v; do violate "version-pinned: $v"; done <<<"$ver"
else
	report "version-agnostic" "PASS  no version-pinned capability claim"
fi

scan "$PAT_CAPS" "capability claims" caps

scan "$PAT_RESIDUE" "cursor residue" residue

# omp's task wire has no readonly field, so a bare `readonly: true` task parameter
# is silently ignored. Read-only posture must be a brief-level tool grant plus a
# write ban, with the skill stating omp cannot enforce it.
ro=$(grep -rIn -E '`readonly`:\s*`?true`?|readonly:\s*true' --include='*.md' "${SCOPE[@]}" 2>/dev/null)
if [ -n "$ro" ]; then
	report "readonly posture" "FAIL"
	while read -r r; do violate "unenforceable readonly: $r"; done <<<"$ro"
else
	report "readonly posture" "PASS  read-only stated as brief posture"
fi

missing=""
while read -r p; do
	[ -e "skills/poteto-mode/$p" ] || missing="$missing $p"
done < <(grep -rohE 'playbooks/[a-z-]+\.md|references/[a-z-]+\.md' skills/poteto-mode --include='*.md' | sort -u)
if [ -n "$missing" ]; then
	report "internal links" "FAIL"
	for m in $missing; do violate "dangling: $m"; done
else
	report "internal links" "PASS  every playbook and reference resolves"
fi

# The router prose and the tree must name the same set. A name in the index with no
# leaf misroutes the agent, a leaf the index never names is unreachable.
parity() {
	local label="$1" a="$2" b="$3" pre_a="$4" suf_a="$5" pre_b="$6" suf_b="$7" only_a only_b
	only_a=$(comm -23 <(printf '%s\n' "$a" | grep .) <(printf '%s\n' "$b" | grep .))
	only_b=$(comm -13 <(printf '%s\n' "$a" | grep .) <(printf '%s\n' "$b" | grep .))
	if [ -n "$only_a$only_b" ]; then
		report "$label" "FAIL"
		while read -r x; do [ -n "$x" ] && violate "$pre_a$x$suf_a"; done <<<"$only_a"
		while read -r x; do [ -n "$x" ] && violate "$pre_b$x$suf_b"; done <<<"$only_b"
	else
		report "$label" "PASS  $(printf '%s\n' "$a" | grep -c .) names, index and tree agree"
	fi
}

ROUTER=skills/poteto-mode/SKILL.md
parity "principle parity" \
	"$(grep -ohE 'principle-[a-z-]+' "$ROUTER" | sort -u)" \
	"$(for d in skills/principle-*/; do basename "$d"; done | sort -u)" \
	'index names ' ', no leaf' \
	'leaf ' ' not in the Principles index'

parity "playbook parity" \
	"$(grep -ohE 'playbooks/[a-z-]+\.md' "$ROUTER" | sed 's|playbooks/||; s|\.md$||' | sort -u)" \
	"$(for f in skills/poteto-mode/playbooks/*.md; do basename "$f" .md; done | sort -u)" \
	'index names playbook ' ', no file' \
	'playbook ' ' not named in the Playbooks index'

# An exception whose line no longer trips the pattern it was audited for is a standing skip for a
# violation that is gone, and it silently covers whatever that line says next.
if [ -f "$ALLOW" ]; then
	stale_allow=""
	bad_allow=""
	while IFS=$'\t' read -r entry name _ || [ -n "$entry" ]; do
		case "$entry" in '' | '#'*) continue ;; esac
		pat=$(pattern_for "$name")
		lineno=${entry##*:}
		if [ -z "$pat" ] || ! [[ $lineno =~ ^[0-9]+$ ]]; then
			bad_allow="$bad_allow $entry"
			continue
		fi
		printf '%s\n' "$(sed -n "${lineno}p" "${entry%:*}")" | grep -qE "$pat" ||
			stale_allow="$stale_allow $entry"
	done <"$ALLOW"
	if [ -n "$stale_allow$bad_allow" ]; then
		report "allowlist" "FAIL"
		for s in $bad_allow; do violate "malformed allowlist entry $s"; done
		for s in $stale_allow; do violate "stale allowlist entry $s"; done
	else
		report "allowlist" "PASS  $(grep -cv '^#' "$ALLOW") entries still match their own pattern"
	fi
fi

# Claims the published guide makes about pstack, verified as present.
unclaimed=""
for s in create-verification-skill maintain-verification-skill swarm poteto-mode; do
	[ -f "skills/$s/SKILL.md" ] || unclaimed="$unclaimed""guide names /$s, not installed"$'\n'
done
grep -qi 'features' skills/create-verification-skill/SKILL.md ||
	unclaimed="$unclaimed""create-verification-skill must build the Feature Map (references/features)"$'\n'
grep -q 'mode: true' skills/poteto-mode/SKILL.md ||
	unclaimed="$unclaimed""poteto-mode must carry the Custom Mode pin frontmatter"$'\n'
if [ -n "$unclaimed" ]; then
	report "guide claims" "FAIL"
	while read -r c; do [ -n "$c" ] && violate "$c"; done <<<"$unclaimed"
else
	report "guide claims" "PASS  verification skill, Feature Map, swarm, pin"
fi

bad=""
for d in skills/*/; do
	n=$(basename "$d")
	fm=$(sed -n 's/^name: *//p' "$d/SKILL.md" 2>/dev/null | head -1 | tr -d '"' | tr -d "'")
	[ -n "$fm" ] || bad="$bad $n(noname)"
done
[ -n "$bad" ] && { fail=1; violate "frontmatter name missing:$bad"; }
markers=$(grep -rIl -E "$PAT_MARKER" "${SCOPE[@]}" 2>/dev/null || true)
if [ -n "$markers" ]; then
	report "conflict markers" "FAIL"
	while read -r m; do [ -n "$m" ] && violate "unresolved merge: $m"; done <<<"$markers"
else
	report "conflict markers" "PASS  no unresolved merge left"
fi

# The counts are generated by omp-port/sync-upstream.sh into marketplace.json. The two READMEs
# carry them by hand, so they rot silently unless the live tree is the judge. "principle" with no
# trailing s so it matches both "principles" and "principle leaves".
read -r nskills nplays nprinc < <(port_counts .)
MARKET=../../.omp-plugin/marketplace.json
pin7=$(cut -c1-7 ../../omp-port/UPSTREAM)
stale=""
for f in ../../README.md README.md "$MARKET"; do
	grep -qF "$nskills skills" "$f" 2>/dev/null || stale="$stale$f wants \"$nskills skills\""$'\n'
	grep -qF "$nplays playbooks" "$f" 2>/dev/null || stale="$stale$f wants \"$nplays playbooks\""$'\n'
	grep -qF "$nprinc principle" "$f" 2>/dev/null || stale="$stale$f wants \"$nprinc principle\""$'\n'
done
grep -qF "pstack at $pin7." "$MARKET" 2>/dev/null ||
	stale="$stale$MARKET wants the pinned sha \"pstack at $pin7.\""$'\n'
if [ -n "$stale" ]; then
	report "counts" "FAIL"
	while read -r s; do [ -n "$s" ] && violate "$s"; done <<<"$stale"
else
	report "counts" "PASS  $nskills skills, $nplays playbooks, $nprinc principles, pin $pin7"
fi

# The port-owned paths are the one exception to "the build owns this tree", so their absence is
# the build silently dropping port behavior.
ownmissing=""
ownn=0
while IFS= read -r p; do
	ownn=$((ownn + 1))
	[ -e "$p" ] || ownmissing="$ownmissing$p missing"$'\n'
done < <(owned_paths)
[ "$ownn" -gt 0 ] || ownmissing="no omp-port/owned.txt entries, the build has nothing to carry"$'\n'
if [ -n "$ownmissing" ]; then
	report "owned" "FAIL"
	while read -r o; do [ -n "$o" ] && violate "$o"; done <<<"$ownmissing"
else
	report "owned" "PASS  $ownn owned path(s) present"
fi

# Every pstack skill assumes the Cursor mechanics. omp-mechanics is where the omp ones live, and
# the injected reminder is the only thing that makes an agent read it.
nomech=""
[ -f skills/omp-mechanics/SKILL.md ] || nomech="${nomech}skills/omp-mechanics/SKILL.md missing"$'\n'
grep -qF 'skill://omp-mechanics' extensions/potetomode/index.js 2>/dev/null ||
	nomech="${nomech}extensions/potetomode/index.js must point the reminder at skill://omp-mechanics"$'\n'
if [ -n "$nomech" ]; then
	report "mechanics" "FAIL"
	while read -r m; do [ -n "$m" ] && violate "$m"; done <<<"$nomech"
else
	report "mechanics" "PASS  omp-mechanics installed and named in the reminder"
fi

# The tree is build output. Rebuilding the pin has to reproduce it byte for byte outside the
# owned paths, otherwise someone hand-edited a file the next sync will overwrite.
pin=$(tr -d '[:space:]' <"$PORT_DIR/UPSTREAM")
scratch=$(mktemp -d)
buildlog=$(mktemp)
canon_ok=no
if ! ensure_canon "$pin" >"$buildlog" 2>&1; then
	# A skipped reproduction on a developer box is a nuisance. In CI it would hide the one
	# invariant this gate exists to prove behind a green check.
	if [ -n "${CI:-}" ]; then
		report "reproducible" "FAIL"
		violate "no clone at $CANON and cloning $UPSTREAM_URL failed, CI cannot skip this"
	else
		report "reproducible" "SKIP  no clone at $CANON and cloning $UPSTREAM_URL failed"
	fi
elif ! build_tree "$pin" "$scratch" >>"$buildlog" 2>&1; then
	report "reproducible" "FAIL"
	violate "build at ${pin:0:7} failed, rules or a patch no longer applies"
	while read -r l; do [ -n "$l" ] && violate "$l"; done < <(tail -n 5 "$buildlog")
else
	canon_ok=yes
	# Owned content is the port's, so the build is judged on everything else.
	while IFS= read -r p; do
		[ -e "$p" ] || continue
		rm -rf "$scratch/$p"
		mkdir -p "$(dirname "$scratch/$p")"
		cp -a "$p" "$scratch/$p"
	done < <(owned_paths)
	delta=$(for d in "${SCOPE[@]}"; do diff -rq "$scratch/$d" "$d" -x node_modules; done)
	if [ -n "$delta" ]; then
		report "reproducible" "FAIL"
		while read -r l; do [ -n "$l" ] && violate "$l"; done <<<"$delta"
	else
		report "reproducible" "PASS  tree equals the build at ${pin:0:7}"
	fi
fi

if [ "$canon_ok" = yes ]; then
	untiered=$(untiered_slugs "$pin" | sed 's/^/  /')
	if [ -n "$untiered" ]; then
		report "untiered slugs" "REPORT  $(printf '%s\n' "$untiered" | wc -l) slug(s) only the catch-all rewrote"
		printf '%s\n' "$untiered"
	else
		report "untiered slugs" "REPORT  none, every slug has a tiered rule"
	fi
else
	report "untiered slugs" "SKIP  needs the clone at $CANON"
fi
rm -rf "$scratch" "$buildlog"

echo
if [ "$fail" -eq 0 ]; then echo "check-port: PASS"; else echo "check-port: FAIL"; fi
exit "$fail"
