#!/usr/bin/env bash
# Gate for the omp port of pstack. Port-only file, never upstream.
# Usage: bash omp-port/check-port.sh [canonical-clone]
# The argument, or CANON, is the cursor/plugins clone the reproducible check builds from.
set -uo pipefail
. "$(dirname "$0")/lib.sh"
PLUGIN_ROOT=${CHECK_PORT_ROOT:-"$(dirname "$0")/../plugins/pstack"}
cd "$PLUGIN_ROOT"
CANON="${1:-$CANON}"
fail=0
report() { printf '%-28s %s\n' "$1" "$2"; }
violate() { fail=1; printf '  %s\n' "$1"; }

SCOPE=(skills agents)
ALLOW="$PORT_DIR/slug-allowlist.txt"

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

# Role instructions must name the omp lever in each intended file. /model sets the chat model,
# task.agentModelOverrides sets a per-agent model.
model_levers=""
for f in skills/setup-pstack/SKILL.md skills/poteto-mode/SKILL.md; do
	grep -Fq 'task.agentModelOverrides' "$f" || model_levers="$model_levers $f"
done
if [ -n "$model_levers" ]; then
	report "omp model levers" "FAIL"
	for f in $model_levers; do violate "$f must name task.agentModelOverrides"; done
else
	report "omp model levers" "PASS  setup-pstack and poteto-mode name task.agentModelOverrides"
fi
if grep -rIlq '/model' skills/setup-pstack/SKILL.md 2>/dev/null; then
	report "chat-model lever" "PASS  /model named in setup-pstack"
else
	report "chat-model lever" "FAIL"
	violate "setup-pstack must tell the user to pick the chat model with /model"
fi

# Require each review workflow's own affirmative diversity sentence. Generic "different models"
# prose can be negated or incidental and must not satisfy the gate.
undiversity=""
grep -qF 'report when the live roster cannot provide the requested model-family diversity' skills/interrogate/SKILL.md || undiversity="$undiversity skills/interrogate/SKILL.md"
grep -qF 'Prefer distinct configured model families when the roster supplies them' skills/arena/SKILL.md || undiversity="$undiversity skills/arena/SKILL.md"
grep -qF 'Run the three lenses on three different configured model families where available' skills/reflect/SKILL.md || undiversity="$undiversity skills/reflect/SKILL.md"
if [ -n "$undiversity" ]; then
	report "review diversity" "FAIL"
	for f in $undiversity; do violate "$f lacks its affirmative model-family diversity rule"; done
else
	report "review diversity" "PASS  interrogate, arena, and reflect state exact diversity requirements"
fi

# A capability claim pinned to a version rots on the next upgrade.
ver=$(grep -rIni -oE '(^|[^0-9])(omp|since)[[:space:]]+v?[0-9]+\.[0-9]+(\.[0-9]+)?' --include='*.md' "${SCOPE[@]}" 2>/dev/null || true)
if [ -n "$ver" ]; then
	report "version-agnostic" "FAIL"
	while read -r v; do violate "version-pinned: $v"; done <<<"$ver"
else
	report "version-agnostic" "PASS  no version-pinned capability claim"
fi

scan "$PAT_CAPS" "capability claims" caps

scan "$PAT_RESIDUE" "cursor residue" residue

# Reject positive standalone readonly prose and task fields. Type syntax and explicit no-field
# contracts are not runtime directives.
ro=$(grep -riIn -E '\breadonly\b' --include='*.md' "${SCOPE[@]}" 2>/dev/null || true)
bad_ro=$(printf '%s\n' "$ro" | awk '{ s = tolower($0); if (s !~ /readonly/) next; if (s ~ /readonly __brand|readonly string|readonly \[|readonly</) next; if (s ~ /(no|not|never|without)[^.;]{0,80}readonly/) next; print }')
if [ -n "$bad_ro" ]; then
	report "readonly posture" "FAIL"
	while read -r r; do [ -n "$r" ] && violate "unsupported readonly directive: $r"; done <<<"$bad_ro"
else
	report "readonly posture" "PASS  no readonly task field or prose directive"
fi

# OMP's task batch requires shared context, has no per-call model or Cursor environment fields,
# and keys model overrides by exact loaded agent names. Check every generated text surface.
runtime_contract() {
	local bad label pattern
	for label in per-call-model pstack-rule-file task-environment; do
		case "$label" in
		per-call-model) pattern='subagent_type|run_in_background|`model`:\s*[^f]|Set `model`|set `model` to|with `model` from|omit `model` so' ;;
		pstack-rule-file) pattern='pstack-models\.mdc' ;;
		task-environment) pattern='environment:[[:space:]]*"?((local)|(cloud))\b|cloud_base_branch' ;;
		esac
		bad=$(grep -rInE "$pattern" --include='*.md' --include='*.mjs' --include='*.ts' --include='*.sh' "${SCOPE[@]}" 2>/dev/null || true)
		if [ -n "$bad" ]; then
			report "runtime $label" "FAIL"
			while read -r line; do violate "$line"; done <<<"$bad"
		else
			report "runtime $label" "PASS"
		fi
	done

	retired='swarm workers|architect runners|arena runners|arena cross-judge pool|interrogate reviewers|reflect judgment, divergent, synthesizer|reflect tooling|why investigators|why synthesizer|how explorer|how explainer|feature, refactoring|<swarm workers model>|your configured [a-z-]+ model|default your fast code model|`hub` process ops|`hub` process op|Blocking on `drive`|`drive` inside a phase agent|`hub` `op: "(list|jobs|send|wait)"'
	bad=$(grep -rInE "$retired" --include='*.md' --include='*.mjs' --include='*.ts' --include='*.sh' "${SCOPE[@]}" 2>/dev/null || true)
	if [ -n "$bad" ]; then
		report "retired runtime labels" "FAIL"
		while read -r line; do violate "$line"; done <<<"$bad"
	else
		report "retired runtime labels" "PASS  no abstract role labels, placeholders, or stale process wording"
	fi
	bad=""
	for f in skills/poteto-mode/playbooks/autopilot-full.md skills/poteto-mode/playbooks/autopilot-stack.md; do
		grep -qF 'exact discovered owner agent' "$f" && grep -qF 'default worker with the owner role' "$f" || bad="$bad$f lacks exact owner fallback"$'\n'
	done
	grep -qF 'exact discovered watcher agent' skills/poteto-mode/playbooks/autonomous-run.md && grep -qF 'default worker with the watcher role' skills/poteto-mode/playbooks/autonomous-run.md || bad="$bad"$'skills/poteto-mode/playbooks/autonomous-run.md lacks exact watcher fallback'$'\n'
	grep -qF '`<plugin-root>/agents/comment-sicko.md`' skills/no-comments/SKILL.md && grep -qF 'omit `agent` for the default worker' skills/no-comments/SKILL.md || bad="$bad"$'skills/no-comments/SKILL.md lacks exact absolute fallback instructions'$'\n'
	grep -qF 'This investigation is read-only: do not write files, change git state, commit, push, open pull requests, or mutate any external system.' skills/why/references/investigator-prompt.md || bad="$bad"$'skills/why investigator template lacks the explicit no-mutation posture'$'\n'
	grep -qF 'forbids file writes, git state changes, commits, pushes, pull requests, and external mutations' skills/why/SKILL.md || bad="$bad"$'skills/why investigator briefs lack the explicit no-mutation posture'$'\n'
	if [ -n "$bad" ]; then
		report "canonical role fallback" "FAIL"
		while read -r line; do [ -n "$line" ] && violate "$line"; done <<<"$bad"
	else
		report "canonical role fallback" "PASS"
	fi


	bad=""
	for f in skills/arena/SKILL.md skills/swarm/SKILL.md skills/reflect/SKILL.md skills/interrogate/SKILL.md; do
		grep -q 'tasks\[\]' "$f" && ! grep -q 'required shared `context`' "$f" && bad="$bad$f lacks required shared context"$'\n'
	done
	if [ -n "$bad" ]; then
		report "runtime batch context" "FAIL"
		while read -r line; do violate "$line"; done <<<"$bad"
	else
		report "runtime batch context" "PASS  arena, swarm, reflect, and interrogate name context"
	fi

	bad=$(grep -riEn '(start|spawn|launch|run|use|gets?) (one|a single) [^.]*(subagent|worker|judge|synthesizer|explainer|investigator|reviewer|owner|watcher|comment review)|(^|[.!?] )one [^.]{0,40}subagent per |gets? (a|an) (owner|watcher) subagent|one item in `tasks\[\]`' --include='*.md' "${SCOPE[@]}" 2>/dev/null | grep -vE '^skills/(pstack-omp|omp-mechanics)/' | awk '{ s = tolower($0); if (s ~ /all items in `tasks\[\]`/ || s ~ /one item per [^.]* in `tasks\[\]`/) next; if (s !~ /one `task` call with one item in `tasks\[\]`,? (and |)(one|the) required shared `context`/) print }' || true)
	for required in \
		'full-access worker for every MCP-backed lane' \
		'A repository-only lane may use `scout` only when its file-only grant covers the evidence' \
		'full-access worker for citation spot-checks that call MCP'; do
		grep -qF "$required" skills/why/SKILL.md || bad="$bad"'skills/why/SKILL.md lacks required investigator routing'$'\n'
	done
	if [ -n "$bad" ]; then
		report "one-item role routing" "FAIL"
		while read -r line; do [ -n "$line" ] && violate "$line"; done <<<"$bad"
	else
		report "one-item role routing" "PASS  every explicit single-spawn line has one-item context"
	fi

	bad=""
	setup_skill=skills/setup-pstack/SKILL.md
	setup_ref=skills/omp-mechanics/references/setup-pstack-config.md
	expected_aliases=$'pstack_fast_code\npstack_instruction\npstack_judgment'
	actual_aliases=$(grep -hoE '^[[:space:]]{2,}pstack_[a-z0-9_]+:' "$setup_ref" 2>/dev/null | sed 's/^[[:space:]]*//; s/:$//' | sort -u || true)
	[ "$actual_aliases" = "$expected_aliases" ] || bad="unexpected pstack-owned modelRoles alias set"$'\n'
	expected_alias_shapes=$'  pstack_fast_code: "<detected-selector>:<effort>"\n  pstack_instruction: "<detected-selector>:<effort>"\n  pstack_judgment: "<detected-selector>:<effort>"'
	actual_alias_shapes=$(awk '/^modelRoles:/{roles=1; next} roles && /^task:/{exit} roles && /^  pstack_/{print}' "$setup_ref" | sort || true)
	[ "$actual_alias_shapes" = "$expected_alias_shapes" ] || bad="$bad"'unexpected pstack alias shape'$'\n'
	grep -q '^task:$' "$setup_ref" && grep -q '^  agentModelOverrides:$' "$setup_ref" && grep -qF '    <exact discovered agent name>: "@pstack_fast_code"' "$setup_ref" || bad="$bad"'task.agentModelOverrides YAML shape is missing'$'\n'
	for alias in pstack_fast_code pstack_judgment pstack_instruction; do grep -qF "$alias" "$setup_skill" || bad="$bad$alias is missing from setup-pstack"$'\n'; done
	setup_keys=$(grep -nE '^[[:space:]]{4,}pstack_[a-z0-9_]+:' "$setup_skill" "$setup_ref" 2>/dev/null || true)
	[ -z "$setup_keys" ] || bad="$bad$setup_keys"$'\n'
	old_setup=$(grep -nE '^([[:space:]]{4,})?(feature, refactoring|arena runners|arena cross-judge pool|architect runners|swarm workers|interrogate reviewers|reflect judgment, divergent, synthesizer):|For panel roles .* value is a list' "$setup_skill" 2>/dev/null || true)
	[ -z "$old_setup" ] || bad="$bad$old_setup"$'\n'
	grep -Fxq 'A `task.agentModelOverrides` entry is pstack-owned only when its exact key is a discovered agent and its value is one of `@pstack_fast_code`, `@pstack_judgment`, or `@pstack_instruction`.' "$setup_skill" || bad="$bad"'per-agent setup ownership is missing'$'\n'
	grep -Fxq 'Preserve every unrelated entry in both maps.' "$setup_skill" || bad="$bad"'unrelated setup ownership preservation is missing'$'\n'
	grep -Fq 'capability, exact discovered agent name' "$setup_skill" || bad="$bad"'setup capability mapping is missing'$'\n'
	grep -Fq 'The effort ladder is `max > xhigh > high > medium > low > minimal`.' "$setup_skill" || bad="$bad"'setup effort ladder is missing minimal or ordering'$'\n'
	grep -Fq 'Strip only that supported suffix and require the remaining base to equal a selector from `omp models --json`.' "$setup_skill" || bad="$bad"'setup suffix or base-selector validation is missing'$'\n'
	grep -Fq 'Never strip an arbitrary colon fragment.' "$setup_skill" || bad="$bad"'setup allows arbitrary suffix stripping'$'\n'
	grep -Fq '`:low`, or `:minimal` suffix' "$setup_skill" || bad="$bad"'setup supported suffix list is missing minimal'$'\n'
	grep -Fq 'selected model' "$setup_skill" && grep -Fq '`thinking.efforts`' "$setup_skill" || bad="$bad"'setup does not validate supported model efforts'$'\n'
	grep -Fq 'An omitted override uses the discovered agent' "$setup_skill" && grep -Fq "frontmatter model first, then the parent session's active or default model" "$setup_skill" || bad="$bad"'setup omission precedence is missing'$'\n'
	grep -Fq 'Family diversity is optional' "$setup_skill" || bad="$bad"'setup family fallback is missing'$'\n'
	bad_alias_choices=$(grep -nE 'offer(s|ing).*`(inherit-parent|auto)`| `(inherit-parent|auto)` always pass|omission for parent inheritance|Omit an override to inherit the parent model' "$setup_skill" 2>/dev/null || true)
	[ -z "$bad_alias_choices" ] || bad="$bad$bad_alias_choices"$'\n'
	grep -Fq 'exactly one supported effort suffix from `max`, `xhigh`, `high`, `medium`, `low`, and `minimal`' "$setup_ref" || bad="$bad"'setup reference suffix list is missing minimal'$'\n'
	grep -Fq 'remaining base to equal a selector from `omp models --json`' "$setup_ref" || bad="$bad"'setup reference base-selector validation is missing'$'\n'
	grep -Fq 'selected model' "$setup_ref" && grep -Fq '`thinking.efforts`' "$setup_ref" || bad="$bad"'setup reference does not validate model efforts'$'\n'
	if [ -n "$bad" ]; then
		report "setup config contract" "FAIL"
		while read -r line; do [ -n "$line" ] && violate "$line"; done <<<"$bad"
	else
		report "setup config contract" "PASS  ownership, aliases, model efforts, suffix, and base selector"
	fi
}
runtime_contract

if [ "${CHECK_PORT_CONTRACTS_ONLY:-}" = 1 ]; then
	echo
	if [ "$fail" -eq 0 ]; then echo "check-port contracts: PASS"; else echo "check-port contracts: FAIL"; fi
	exit "$fail"
fi

mutation_log=$(mktemp)
if bash "$PORT_DIR/test-gate-mutations.sh" >"$mutation_log" 2>&1; then
	report "gate mutations" "PASS  ownership, alias, effort, and per-file lever mutations rejected"
else
	report "gate mutations" "FAIL"
	while read -r line; do [ -n "$line" ] && violate "$line"; done <"$mutation_log"
fi
rm -f "$mutation_log"

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
