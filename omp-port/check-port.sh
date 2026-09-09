#!/usr/bin/env bash
# Gate for the omp port of pstack. Port-only file, never upstream.
# Usage: bash omp-port/check-port.sh [canonical-checkout]
set -uo pipefail
cd "$(dirname "$0")/../plugins/pstack"
CANON="${1:-/tmp/cursor-plugins/pstack}"
fail=0
report() { printf '%-28s %s\n' "$1" "$2"; }
violate() { fail=1; printf '  %s\n' "$1"; }

SCOPE=(skills agents)
ALLOW=../../omp-port/slug-allowlist.txt

# An audited exception is `path:line<TAB>reason`. Illustrative prose only, never a
# real prescription. Anything not listed here must pass on its own merits.
allowed() { [ -f "$ALLOW" ] && cut -f1 "$ALLOW" | grep -qxF "$1"; }
# One source per gate pattern. scan() enforces them and the allowlist check below
# proves every audited exception still trips one of them.
PAT_SLUG='\b(claude-[a-z0-9.-]+|gpt-[0-9][a-z0-9.-]*|grok-[a-z0-9.-]+|gemini-[a-z0-9.-]+|opus-[a-z0-9.-]+)\b'
PAT_CAPS='omp (has no|does not support|cannot|lacks) [a-z`_.:-]+'
PAT_RESIDUE='cursor-team-kit|/deslop|run_in_background|<agent-transcripts>|~/\.cursor/|AskQuestion|cloud_base_branch|~/\.omp/skills/|environment: "cloud"'

scan() {
	local pat="$1" label="$2" bad=""
	while IFS= read -r line; do
		allowed "${line%%:*}:$(cut -d: -f2 <<<"$line")" || bad="$bad$line"$'\n'
	done < <(grep -rIn -E "$pat" --include='*.md' --include='*.mjs' --include='*.ts' --include='*.sh' "${SCOPE[@]}" 2>/dev/null | cut -d: -f1,2)
	if [ -n "$bad" ]; then
		report "$label" "FAIL"
		while read -r b; do [ -n "$b" ] && violate "$b"; done <<<"$bad"
	else
		local n=0
		[ -f "$ALLOW" ] && n=$(grep -cv '^#' "$ALLOW")
		report "$label" "PASS  clean, $n audited exception(s)"
	fi
}

scan "$PAT_SLUG" "model-agnostic"

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
for f in skills/interrogate/SKILL.md skills/arena/SKILL.md skills/reflect/SKILL.md; do
	grep -qiE 'different (model )?(family|provider)|separate model family' "$f" ||
		{ fail=1; violate "no model-diversity property stated in $f"; }
done
[ "$fail" -eq 0 ] && report "review diversity" "PASS  stated as a property"

# A capability claim pinned to a version rots on the next upgrade, exactly like a
# hardcoded model slug. Depend on a probe or a conditional instead.
ver=$(grep -rIn -oE 'omp[/ ]?1[0-9]+\.[0-9]+(\.[0-9]+)?' --include='*.md' "${SCOPE[@]}" 2>/dev/null)
if [ -n "$ver" ]; then
	report "version-agnostic" "FAIL"
	while read -r v; do violate "version-pinned: $v"; done <<<"$ver"
else
	report "version-agnostic" "PASS  no version-pinned capability claim"
fi

scan "$PAT_CAPS" "capability claims"

scan "$PAT_RESIDUE" "cursor residue"

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
	local label="$1" a="$2" b="$3" fmt_a="$4" fmt_b="$5" only_a only_b
	only_a=$(comm -23 <(printf '%s\n' "$a") <(printf '%s\n' "$b"))
	only_b=$(comm -13 <(printf '%s\n' "$a") <(printf '%s\n' "$b"))
	if [ -n "$only_a$only_b" ]; then
		report "$label" "FAIL"
		while read -r x; do [ -n "$x" ] && violate "$(printf "$fmt_a" "$x")"; done <<<"$only_a"
		while read -r x; do [ -n "$x" ] && violate "$(printf "$fmt_b" "$x")"; done <<<"$only_b"
	else
		report "$label" "PASS  $(printf '%s\n' "$a" | grep -c .) names, index and tree agree"
	fi
}

ROUTER=skills/poteto-mode/SKILL.md
parity "principle parity" \
	"$(grep -ohE 'principle-[a-z-]+' "$ROUTER" | sort -u)" \
	"$(for d in skills/principle-*/; do basename "$d"; done | sort -u)" \
	'index names %s, no leaf' \
	'leaf %s not in the Principles index'

parity "playbook parity" \
	"$(grep -ohE 'playbooks/[a-z-]+\.md' "$ROUTER" | sed 's|playbooks/||; s|\.md$||' | sort -u)" \
	"$(for f in skills/poteto-mode/playbooks/*.md; do basename "$f" .md; done | sort -u)" \
	'index names playbook %s, no file' \
	'playbook %s not named in the Playbooks index'

# An exception whose line no longer trips any gate pattern is a standing skip for a
# violation that is gone, and it silently covers whatever that line says next.
if [ -f "$ALLOW" ]; then
	stale_allow=""
	while IFS=$'\t' read -r entry _ || [ -n "$entry" ]; do
		case "$entry" in '' | '#'*) continue ;; esac
		line=$(sed -n "${entry##*:}p" "${entry%:*}" 2>/dev/null)
		[ -n "$line" ] && printf '%s\n' "$line" | grep -qE "$PAT_SLUG|$PAT_CAPS|$PAT_RESIDUE" ||
			stale_allow="$stale_allow $entry"
	done <"$ALLOW"
	if [ -n "$stale_allow" ]; then
		report "allowlist" "FAIL"
		for s in $stale_allow; do violate "stale allowlist entry $s"; done
	else
		report "allowlist" "PASS  $(grep -cv '^#' "$ALLOW") entries still match a gate pattern"
	fi
fi

# Claims the published guide makes about pstack, verified as present.
for s in create-verification-skill maintain-verification-skill swarm poteto-mode; do
	[ -f "skills/$s/SKILL.md" ] || { fail=1; violate "guide names /$s, not installed"; }
done
grep -qi 'features' skills/create-verification-skill/SKILL.md ||
	{ fail=1; violate "create-verification-skill must build the Feature Map (references/features)"; }
grep -q 'mode: true' skills/poteto-mode/SKILL.md ||
	{ fail=1; violate "poteto-mode must carry the Custom Mode pin frontmatter"; }
[ "$fail" -eq 0 ] && report "guide claims" "PASS  verification skill, Feature Map, swarm, pin"

bad=""
for d in skills/*/; do
	n=$(basename "$d")
	fm=$(sed -n 's/^name: *//p' "$d/SKILL.md" 2>/dev/null | head -1 | tr -d '"' | tr -d "'")
	[ -n "$fm" ] || bad="$bad $n(noname)"
done
[ -n "$bad" ] && { fail=1; violate "frontmatter name missing:$bad"; }
markers=$(grep -rIl -E '^(<{7} |\|{7}|={7}$|>{7} )' "${SCOPE[@]}" 2>/dev/null || true)
if [ -n "$markers" ]; then
	report "conflict markers" "FAIL"
	while read -r m; do [ -n "$m" ] && violate "unresolved merge: $m"; done <<<"$markers"
else
	report "conflict markers" "PASS  no unresolved merge left"
fi

# The counts are generated by omp-port/sync-upstream.sh into marketplace.json. The two READMEs
# carry them by hand, so they rot silently unless the live tree is the judge.
nskills=$(ls -1d skills/*/ | wc -l)
nplays=$(find skills/poteto-mode/playbooks -name '*.md' -type f | wc -l)
nprinc=$(ls -1d skills/principle-*/ | wc -l)
MARKET=../../.omp-plugin/marketplace.json
stale=""
for f in ../../README.md README.md "$MARKET"; do
	grep -qF "$nskills skills" "$f" 2>/dev/null || stale="$stale $f:$nskills-skills"
done
grep -qF "$nplays playbooks" "$MARKET" 2>/dev/null || stale="$stale $MARKET:$nplays-playbooks"
grep -qF "$nprinc principles" "$MARKET" 2>/dev/null || stale="$stale $MARKET:$nprinc-principles"
if [ -n "$stale" ]; then
	report "counts" "FAIL"
	for s in $stale; do violate "missing live count ${s#*:} in ${s%:*}"; done
else
	report "counts" "PASS  $nskills skills, $nplays playbooks, $nprinc principles"
fi

if [ -d "$CANON" ]; then
	drift=$(for d in "${SCOPE[@]}"; do diff -rq "$CANON/$d" "$d" -x node_modules 2>/dev/null; done | wc -l)
	report "canonical delta" "$drift files differ from $CANON"
else
	report "canonical delta" "SKIP  no canonical checkout at $CANON"
fi

echo
if [ "$fail" -eq 0 ]; then echo "check-port: PASS"; else echo "check-port: FAIL"; fi
exit "$fail"
