#!/usr/bin/env bash
# Gate for the omp port of pstack. Port-only file, never upstream.
# Usage: bash omp-port/check-port.sh [canonical-clone] [sha]
# The first argument, or CANON, is the cursor/plugins clone the reproducible check builds from.
# The second is the upstream sha to gate, defaulting to the pin. Pointing it at a sha other than
# the pin is what makes an upstream change reviewable before it is synced: sync-upstream.sh check
# lists the commits, and this asks the question the commit list cannot, which is whether the port
# still builds clean against text nobody has ported yet. Without it the gate can only ever speak
# about a sha that is already merged, so the first moment a rules.sed rule has been outrun is the
# moment after the pin moved and the tree was rewritten.
set -uo pipefail
. "$(dirname "$0")/lib.sh"
PLUGIN_ROOT=${CHECK_PORT_ROOT:-"$(dirname "$0")/../plugins/pstack"}
cd "$PLUGIN_ROOT"
CANON="${1:-$CANON}"
PORT_PIN=$(tr -d '[:space:]' <"$PORT_DIR/UPSTREAM")
TARGET_SHA="${2:-$PORT_PIN}"
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

# A stale-rule exemption is `left-hand-fragment<TAB>reason`. The fragment is matched as a literal
# substring of the rule's own line, never as a line number: a line number moves the moment anyone
# edits a rule above it, and an exemption that silently stops applying is worse than none, because
# the gate then goes red for a reason nobody can reconstruct. A fragment survives every edit that
# does not change the rule it names.
STALE_ALLOW="${STALE_EXEMPT:-$PORT_DIR/stale-exempt.tsv}"
exempt() {
	[ -f "$STALE_ALLOW" ] || return 1
	# The needle travels through the environment rather than -v, because awk applies escape
	# processing to a -v assignment and a rules.sed left-hand side is full of backslashes: it would
	# warn about every one of them and match the stripped text instead of the rule.
	#
	# Three ways a substring match can go wrong are closed here, because each one silently exempts
	# more than the author intended and a wrong exemption turns the gate green, which is the exact
	# failure this assertion exists to prevent:
	#   a whitespace-only fragment, which index() matches against almost any rule, so a stray tab
	#     or a double space in the file would exempt the entire table;
	#   a fragment too short to be distinctive, which a later rule could match by accident;
	#   a fragment that is only a prefix of a longer rule, which exempts that rule wholesale.
	STALE_RULE="$1" awk -F'\t' '
		BEGIN { rule = ENVIRON["STALE_RULE"] }
		$0 !~ /^#/ {
			f = $1
			gsub(/^[[:space:]]+|[[:space:]]+$/, "", f)
			# The length floor alone is not enough: a run of twenty spaces is twenty characters long
			# and index() finds it in almost any rule, so a whitespace-only row exempts the table.
			if (length(f) >= 20 && f ~ /[^[:space:]]/ && index(rule, f)) hit = 1
		}
		END { exit !hit }
	' "$STALE_ALLOW"
}
# Every fragment has to clear the same bar the matcher enforces, so a typo is caught at review time
# rather than discovered as an exemption that quietly stopped applying.
stale_exempt_bad() {
	[ -f "$STALE_ALLOW" ] || return 0
	awk -F'\t' '
		$0 !~ /^#/ {
			# Only a genuinely empty line is not an entry. A line holding whitespace is one, and is
			# caught below: that is the shape index() would match against every rule, so skipping it
			# here would reinstate the exact hole this lint exists to close.
			if ($0 == "") next
			f = $1
			gsub(/^[[:space:]]+|[[:space:]]+$/, "", f)
			if (f !~ /[^[:space:]]/ || length(f) < 20)
				printf "  rules.sed exemption fragment is blank or under 20 chars: [%s]\n", f
		}
	' "$STALE_ALLOW"
}
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

# Mutation tests intentionally treat these exact sentences as the review-diversity gate interface.
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

ver=$(grep -rIni -oE '(^|[^0-9])(omp|since)[[:space:]]+v?[0-9]+\.[0-9]+(\.[0-9]+)?' --include='*.md' "${SCOPE[@]}" 2>/dev/null || true)
if [ -n "$ver" ]; then
	report "version-agnostic" "FAIL"
	while read -r v; do violate "version-pinned: $v"; done <<<"$ver"
else
	report "version-agnostic" "PASS  no version-pinned capability claim"
fi

scan "$PAT_CAPS" "capability claims" caps

scan "$PAT_RESIDUE" "cursor residue" residue

ro=$(grep -riIn -E '\breadonly\b' --include='*.md' "${SCOPE[@]}" 2>/dev/null || true)
bad_ro=$(printf '%s\n' "$ro" | awk '{ s = tolower($0); if (s !~ /readonly/) next; if (s ~ /readonly __brand|readonly string|readonly \[|readonly</) next; if (s ~ /(no|not|never|without)[^.;]{0,80}readonly/) next; print }')
if [ -n "$bad_ro" ]; then
	report "readonly posture" "FAIL"
	while read -r r; do [ -n "$r" ] && violate "unsupported readonly directive: $r"; done <<<"$bad_ro"
else
	report "readonly posture" "PASS  no readonly task field or prose directive"
fi

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

	retired='swarm workers|architect runners|arena runners|arena cross-judge pool|interrogate reviewers|reflect judgment, divergent, synthesizer|reflect tooling|why investigators|why synthesizer|how explorer|how explainer|feature, refactoring|<swarm workers model>|your configured [a-z-]+ model|default your fast code model|`hub` process ops|`hub` process op|Blocking on `drive`|`drive` inside a phase agent|`hub` +`op:|"hub"'
	bad=$(grep -rInE "$retired" --include='*.md' --include='*.mjs' --include='*.ts' --include='*.sh' "${SCOPE[@]}" 2>/dev/null || true)
	if [ -n "$bad" ]; then
		report "retired runtime labels" "FAIL"
		while read -r line; do violate "$line"; done <<<"$bad"
	else
		report "retired runtime labels" "PASS  no abstract role labels, placeholders, or stale process wording"
	fi

	# `hub` IS a real built-in tool on this harness: sibling messaging, settled-job inspection, and
	# supervised services, with ops list/send/inbox/wait/cancel/jobs/start/logs/stop. Verified in the
	# installed package -- it is in pi-coding-agent's canonical tool set, and the binary carries the
	# HubTool string. It is registered only when tool names are not restricted and IRC is enabled.
	#
	# This assertion used to be the opposite: it failed any backticked `hub`, enforcing a denial that
	# was not true, with a mutation pinning the wrong behaviour. A line that claims hub does not
	# exist is now the defect, because that is the sentence that sends an agent away from a live
	# primitive. What is required instead is that where the port routes sibling coordination or a
	# supervised service, it names the surface that is actually there.
	if grep -rqE 'no (programmatic )?`?hub`? tool' --include='*.md' --include='*.mjs' --include='*.ts' \
		--include='*.sh' "${SCOPE[@]}" 2>/dev/null; then
		report "agent hub api" "FAIL"
		while read -r line; do violate "denies a live primitive: $line"; done <<<"$(grep -rnE 'no (programmatic )?`?hub`? tool' --include='*.md' --include='*.mjs' --include='*.ts' --include='*.sh' "${SCOPE[@]}" 2>/dev/null)"
	elif grep -rqF 'hub' --include='*.md' "${SCOPE[@]}" 2>/dev/null; then
		report "agent hub api" "PASS  hub is documented as a real conditional built-in"
	else
		report "agent hub api" "SKIP  no hub reference in the tree to check"
	fi

	# One install root. A path under any other agent store resolves to nothing on this machine,
	# and the playbook that names it cannot run its own binary.
	install=$(grep -rInE '~/\.(agents|claude|cursor)/' --include='*.md' --include='*.mjs' --include='*.ts' --include='*.sh' --include='*.js' \
		"${SCOPE[@]}" "${CHECK_PORT_DOCS_ROOT:-$REPO_ROOT}"/PORTING.md "${CHECK_PORT_DOCS_ROOT:-$REPO_ROOT}"/README.md README.md extensions 2>/dev/null |
		grep -vE 'claude-plugins|~/.claude/plugins' || true)
	if [ -n "$install" ]; then
		report "install root" "FAIL"
		while read -r line; do violate "$line"; done <<<"$install"
	else
		report "install root" "PASS  every install path resolves under ~/.omp"
	fi

	# Harness capabilities the port names but does not wire. Each of these was described in the
	# adapter and unreachable from the playbook that needs it, which is the failure this block
	# exists to make impossible: prose that documents a capability nothing routes to.
	bad=""
	adopt() {
		local f=$1 needle=$2 what=$3
		grep -qF "$needle" "$f" || bad="$bad$f lacks $what"$'\n'
	}
	adopt skills/arena/SKILL.md 'Pass this explicit `outputSchema`' 'a typed cross-judge result'
	adopt skills/arena/SKILL.md 'parsed `data` you index into' 'a typed read of the judge verdict'
	adopt skills/interrogate/SKILL.md 'an explicit `outputSchema` when the live task schema exposes one' 'a typed reviewer finding'
	adopt skills/interrogate/SKILL.md 'parsed `data` you index into' 'a typed read of reviewer findings'
	adopt skills/reflect/SKILL.md '"required":["Accepted","Rejected","Backlog"]' 'the synthesizer output schema'
	adopt skills/poteto-mode/playbooks/shipping.md 'pr://<n>/diff/all' 'the github device read surface'
	adopt skills/poteto-mode/playbooks/shipping.md 'github.enabled' 'the github tool availability gate'
	# The device adoption is only real where the playbooks that read PRs actually use it.
	# Shipping alone left the claim half-true, because babysit is the playbook that reads
	# review threads most.
	adopt skills/poteto-mode/playbooks/babysit.md 'pr://<n>' 'the github device read surface'
	adopt skills/poteto-mode/playbooks/babysit.md 'Keep every *write* on the resolved forge' 'a single writer per mutation'
	# The cross-repo pr:// form is documented, not invented: <owner>/<repo>/ in front of <n> is how
	# the scheme names a repository other than the current one. This used to be a ban on that exact
	# string, so the gate would have failed correct future usage while the playbook that carried it
	# told the agent the form did not exist. Requiring it is the assertion that was wanted: the
	# failure being guarded against is an agent guessing a selector, and a playbook that never
	# learned the real one is how that happens.
	adopt skills/poteto-mode/playbooks/shipping.md 'pr://<owner>/<repo>/<n>' 'the documented cross-repo pr selector'
	adopt skills/poteto-mode/playbooks/shipping.md 'rather than assuming a form is valid because it parses' 'read the surface doc instead of guessing a selector'
	adopt skills/poteto-mode/playbooks/autopilot-stack.md 'proc://<name>/kill' 'the named proc watcher lifecycle'
	adopt skills/poteto-mode/playbooks/orchestrate.md 'A refilling window is what a work pool is for' 'a pool for the refilling window'
	adopt skills/poteto-mode/playbooks/orchestrate.md 'open a todo list with one entry per phase' 'root plan tracking'
	adopt skills/poteto-mode/references/bugbot-triage.md 'exact discovered `security-reviewer`' 'the native security lane'
	adopt skills/poteto-mode/playbooks/pause-safely.md 'collapses *conversation* context' 'checkpoint scoped to what it does'
	# The device summary calls checkpoint git-based and filesystem-saving. It is neither, and a
	# playbook that repeats that claim sends a cold-start handoff through the wrong primitive.
	if grep -qiE 'git-based checkpoint|checkpoint (snapshots|saves) (the |your )?(working tree|filesystem|files|repo|repository)' skills/poteto-mode/playbooks/pause-safely.md; then
		bad="$bad"'skills/poteto-mode/playbooks/pause-safely.md claims checkpoint snapshots the filesystem'$'\n'
	fi
	# Cursor's Babysit named four modes and omp has none of them. An agent told to "run drive"
	# would run nothing, so the playbook now names a watcher invocation instead. Both halves are
	# pinned: the denial, so the explanation cannot quietly disappear, and the absence of the
	# invocations, so a future upstream edit cannot reintroduce a mode name as something to run.
	adopt skills/poteto-mode/playbooks/babysit.md 'name no command on this runtime' 'the denial that the four Cursor modes are not commands'
	adopt skills/poteto-mode/playbooks/babysit.md 'WatchMode "single" | "stack" | "queued-stack"' 'the watcher modes the port actually implements'
	# Word boundaries on BOTH sides, or the pattern is wrong in two directions at once. Without a
	# left boundary "Restart background tasks" matches on the `start` inside `Restart`, so ordinary
	# English trips it; without a right boundary the verb and the name may be separated by filler
	# words, so "Run the drive loop" sails past. The mode name is also required to be bare or
	# backticked, which is how it appeared in every sentence that actually instructed an agent.
	if grep -rqiE '\b(run|invoke|use|stop|start|defaults to|get|pick|choose|select)(\s+the)?\s+`?(drive|background|threads-only)`?\b' skills/poteto-mode/playbooks/babysit.md; then
		bad="$bad"'babysit.md instructs a Cursor mode name to be run; name a watch-pr invocation instead'$'\n'
	fi
	if [ -n "$bad" ]; then
		report "capability wiring" "FAIL"
		while read -r line; do [ -n "$line" ] && violate "$line"; done <<<"$bad"
	else
		report "capability wiring" "PASS  typed verdicts, github reads, named proc, pool, root plan, native security lane"
	fi
	# A capability claim sourced from outside this repository needs its provenance on the same line,
	# or a maintainer reads a local install as a guarantee the plugin ships. PORTING.md and the
	# shipped README are the two places that claim; PORTING.md sits at the repo root, outside SCOPE.
	# PORTING.md lives outside the plugin root, so no fixture can cover it and the mutation
	# harness proves only the README half below. $PWD is the plugin root, which the harness
	# points at the fixture.
	porting="$PORT_DIR/../PORTING.md"
	readme="README.md"
	unbacked=$(grep -nE 'veto is the +enforced backstop' "$porting" 2>/dev/null || true)
	[ -z "$unbacked" ] ||
		unbacked="$unbacked"$'\n'
	grep -q 'neither ships nor requires' "$porting" 2>/dev/null || unbacked="$unbacked"$'PORTING.md must name the external veto extension as unshipped'$'\n'
	grep -q 'ships no `session_stop` veto' "$readme" 2>/dev/null || unbacked="$unbacked"$'plugins/pstack/README.md must disclose that no session_stop veto ships'$'\n'
	# The external veto is inert unless its own env var is set, so naming it without that
	# precondition is the same inaccuracy one level down.
	grep -q 'OMP_PROOF_FILE' "$porting" 2>/dev/null || unbacked="$unbacked"$'PORTING.md must record that the external veto is dormant unless $OMP_PROOF_FILE is set'$'\n'
	if grep -q 'session_stop' skills/poteto-mode/SKILL.md 2>/dev/null; then
		unbacked="$unbacked"$'poteto-mode must not claim a session_stop veto it does not ship'$'\n'
	fi
	if [ -n "$unbacked" ]; then
		report "external capability provenance" "FAIL"
		while read -r c; do [ -n "$c" ] && violate "$c"; done <<<"$unbacked"
	else
		report "external capability provenance" "PASS  the external veto is named and marked unshipped"
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
		grep -q 'tasks\[\]' "$f" && grep -q 'required shared `context`' "$f" || bad="$bad$f lacks the tasks[] batch shape or its required shared context"$'\n'
	done
	if [ -n "$bad" ]; then
		report "runtime batch context" "FAIL"
		while read -r line; do violate "$line"; done <<<"$bad"
	else
		report "runtime batch context" "PASS  arena, swarm, reflect, and interrogate name context"
	fi

	bad=$(grep -rInE '`(Read|Grep|Glob|Shell|Task)` (tool calls|prompts|response body)|Tool calls \(Shell,|Use Glob to find|Use Read, Grep|Subagents inherit it' --include='*.md' "${SCOPE[@]}" 2>/dev/null || true)
	if [ -n "$bad" ]; then
		report "cursor tool names" "FAIL"
		while read -r line; do violate "$line"; done <<<"$bad"
	else
		report "cursor tool names" "PASS  no prompt template names a Cursor tool"
	fi

	# Derived from the tree, not from a list: a hand-kept list of names is a list that forgets.
	bare=""
	while read -r n; do
		hits=$(grep -rInF "\`/$n\`" --include='*.md' "${SCOPE[@]}" 2>/dev/null || true)
		[ -n "$hits" ] && bare="$bare$hits"$'\n'
	done < <(find skills -mindepth 1 -maxdepth 1 -type d -printf '%f\n' | sort)
	if [ -n "$bare" ]; then
		report "skill command form" "FAIL"
		while read -r line; do [ -n "$line" ] && violate "$line"; done <<<"$bare"
	else
		report "skill command form" "PASS  every skill command uses the registered /skill:<name> form"
	fi

	bad=""
	contract=skills/pstack-omp/SKILL.md
	for required in \
		'solutionSpace' \
		'kernel-defined' \
		'eval.tools.enabled' \
		'names the yield tool' \
		'`error` for a failure' \
		'three reminder prompts' \
		'task.isolation.enabled' \
		'task.enableEffort' \
		'task.batch' \
		'task.maxRecursionDepth' \
		'task.softRequestBudget' \
		'task.maxRuntimeMs' \
		'task.maxConcurrency' \
		'task.agentIdleTtlMs'; do
		grep -qF "$required" "$contract" || bad="$bad"'pstack-omp runtime contract lacks '"$required"$'\n'
	done
	if [ -n "$bad" ]; then
		report "runtime contract fields" "FAIL"
		while read -r line; do [ -n "$line" ] && violate "$line"; done <<<"$bad"
	else
		report "runtime contract fields" "PASS  required item fields, the yield call, and the gating settings are named"
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

# The harness runs this gate, so a caller that needs an assertion living past this line has to be
# able to switch this step off or the two call each other forever. CHECK_PORT_CONTRACTS_ONLY above
# serves the fixture mutations, which only need the contract assertions; this serves the staleness
# mutations, which need the upstream probes below and would otherwise re-enter this step.
if [ "${CHECK_PORT_SKIP_MUTATIONS:-}" = 1 ]; then
	report "gate mutations" "SKIP  recursion guard set by the mutation harness"
else
	mutation_log=$(mktemp)
	if bash "$PORT_DIR/test-gate-mutations.sh" >"$mutation_log" 2>&1; then
		report "gate mutations" "PASS  ownership, alias, effort, and per-file lever mutations rejected"
	else
		report "gate mutations" "FAIL"
		while read -r line; do [ -n "$line" ] && violate "$line"; done <"$mutation_log"
	fi
	rm -f "$mutation_log"
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

# Owning a path makes an upstream edit to it vanish silently, so the count is surfaced on every gate
# run instead of being discovered later. A non-zero count is a maintainer decision, not a failure:
# the built copy is discarded by design, which is what owning a path means. It says nothing when the
# target is the pin, because a sha compared to itself has no commits between them.
drift=$(owned_upstream_drift "$TARGET_SHA" "$PORT_PIN")
moved=""
while IFS=$'\t' read -r p n; do
	[ -n "$p" ] || continue
	[ "$n" = 0 ] || moved="${moved}  $p: $n upstream commit(s) since the pin, dropped by ownership"$'\n'
done <<<"$drift"
if [ -n "$moved" ]; then
	report "owned drift" "REPORT"
	printf '%s' "$moved"
else
	report "owned drift" "REPORT  no upstream commit has touched an owned path since the pin"
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

# extensions/ sits outside SCOPE, so nothing else here would notice a control being unregistered.
# That was verified by deleting the pstackpolicy entry from package.json: every test still passed
# and the gate stayed green, because the tests import index.js directly and never read the
# manifest. A backstop that can be switched off without anything noticing is not a backstop.
unreg=""
for ext in potetomode pstackpolicy; do
	grep -qF "./extensions/$ext/index.js" package.json 2>/dev/null ||
		unreg="${unreg}package.json does not register extensions/$ext/index.js"$'\n'
	[ -f "extensions/$ext/index.js" ] ||
		unreg="${unreg}extensions/$ext/index.js is missing"$'\n'
done
grep -qF 'PSTACK_LANDING_GRANT' extensions/pstackpolicy/index.js 2>/dev/null ||
	unreg="${unreg}extensions/pstackpolicy no longer names PSTACK_LANDING_GRANT"$'\n'
if [ -n "$unreg" ]; then
	report "extensions" "FAIL"
	while read -r u; do [ -n "$u" ] && violate "$u"; done <<<"$unreg"
else
	report "extensions" "PASS  both extensions present and registered"
fi

# The tree is build output. Rebuilding the pin has to reproduce it byte for byte outside the owned
# paths, otherwise someone hand-edited a file the next sync will overwrite. That assertion is about
# the checked-in tree, so it follows the pin and nothing else. The three assertions after it are
# about upstream text, so they follow the target, and that split is the whole point of taking a
# target: the tree assertions can only ever speak about a sha already merged, while the upstream
# assertions can be pointed at text nobody has ported yet, which is the only moment a stale
# rules.sed rule is still cheap to learn about.
pin="$PORT_PIN"
scratch=$(mktemp -d)
buildlog=$(mktemp)
canon_ok=no
if ! ensure_canon "$TARGET_SHA" >"$buildlog" 2>&1 || ! ensure_canon "$pin" >>"$buildlog" 2>&1; then
	# A skipped reproduction on a developer box is a nuisance. In CI it would hide the one
	# invariant this gate exists to prove behind a green check.
	if [ -n "${CI:-}" ]; then
		report "reproducible" "FAIL"
		violate "no clone at $CANON and cloning $UPSTREAM_URL failed, CI cannot skip this"
	else
		# Name the cause rather than assuming it was the clone, and treat an unresolvable target as
		# a failure rather than a skip: a sha we could not read is not a sha we cleared.
		if ! git -C "$CANON" cat-file -e "${TARGET_SHA}^{commit}" 2>/dev/null; then
			report "reproducible" "FAIL"
			violate "target sha $TARGET_SHA does not resolve in the clone at $CANON, so nothing about it was checked"
		else
			report "reproducible" "SKIP  no clone at $CANON and cloning $UPSTREAM_URL failed"
		fi
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

# The target has to BUILD, not merely have its rules probed. Every assertion above reads upstream
# text directly and none of them runs omp-port/patches, so an upstream commit that rewords a line a
# patch matches on would otherwise sail through: rule staleness, liveness and the slug tiers would
# all be perfectly happy while the sync could not be applied at all. The patch layer is the one
# part of this build that fails loudly on its own, and this is what makes that loudness reachable
# before the pin moves rather than after. Skipped when the target is the pin, because
# `reproducible` has already built exactly that tree a few lines up.
if [ "$canon_ok" = yes ] && [ "$TARGET_SHA" != "$pin" ]; then
	tscratch=$(mktemp -d)
	if build_tree "$TARGET_SHA" "$tscratch" >"$buildlog" 2>&1; then
		report "target builds" "PASS  rules and patches apply at ${TARGET_SHA:0:7}"
	else
		report "target builds" "FAIL"
		violate "the build fails at ${TARGET_SHA:0:7}: a rule or a patch no longer applies, so this upstream commit cannot be synced yet"
		while read -r l; do [ -n "$l" ] && violate "$l"; done < <(tail -n 5 "$buildlog")
	fi
	rm -rf "$tscratch"
elif [ "$TARGET_SHA" = "$pin" ]; then
	report "target builds" "SKIP  target is the pin, reproducible already built it"
else
	report "target builds" "SKIP  needs the clone at $CANON"
fi

# Same rule as the two probes below: the probe's exit status is part of the result. untiered_slugs
# returns non-zero when its build fails, and an empty list from a failed build is not evidence that
# every slug has a tiered rule.
if [ "$canon_ok" = yes ]; then
	if untiered=$(untiered_slugs "$TARGET_SHA" 2>/dev/null); then
		if [ -n "$untiered" ]; then
			report "untiered slugs" "REPORT  $(printf '%s\n' "$untiered" | wc -l) slug(s) only the catch-all rewrote at ${TARGET_SHA:0:7}"
			printf '%s\n' "$untiered" | sed 's/^/  /'
		else
			report "untiered slugs" "REPORT  none, every slug has a tiered rule at ${TARGET_SHA:0:7}"
		fi
	else
		report "untiered slugs" "FAIL"
		violate "the catch-all probe failed, so coverage is unknown; an empty list here is not a clean one"
	fi
else
	report "untiered slugs" "SKIP  needs the clone at $CANON"
fi

if [ "$canon_ok" = yes ]; then
	# The probe's own status is part of the assertion. dead_rules returns non-zero with nothing on
	# stdout when the marked build fails, so reading only stdout turns a probe that could not run
	# into the strongest green this gate can print. An unknown result is a failure, not a clean one.
	if dead=$(dead_rules "$TARGET_SHA" 2>/dev/null); then
		if [ -n "$dead" ]; then
			report "rule liveness" "REPORT  $(printf '%s\n' "$dead" | wc -l) rule(s) matched nothing at ${TARGET_SHA:0:7}"
			printf '%s\n' "$dead" | sed 's/^/  rules.sed:/'
		else
			report "rule liveness" "PASS  every substitution rule matched at ${TARGET_SHA:0:7}"
		fi
	else
		report "rule liveness" "FAIL"
		violate "the marked build failed, so liveness is unknown; an empty result here is not a clean one"
	fi
else
	report "rule liveness" "SKIP  needs the clone at $CANON"
fi

if [ "$canon_ok" = yes ]; then
	# The assertion that answers the question this gate exists to ask: has upstream moved past a
	# rule? A rule whose left-hand side matches nothing in raw upstream can never fire again, so the
	# translation it was written to perform is not being applied, and sed exiting 0 is the only thing
	# that kept that quiet. Shadowed rules do not land here: a rule fed by an earlier rule's output
	# matches nothing in isolation but still fires in the build, which is why this probe is separate
	# from rule liveness above and why neither alone answers the question.
	if stale=$(stale_rules "$TARGET_SHA" "$dead"); then
		unexempted=""
		while IFS=$'\t' read -r n rule; do
			[ -n "$n" ] || continue
			exempt "$rule" || unexempted="${unexempted}rules.sed:${n}: ${rule}"$'\n'
		done <<<"$stale"
		total=$(grep -c . <<<"$stale" || true)
		if [ -n "$unexempted" ]; then
			report "rule staleness" "FAIL"
			while read -r l; do [ -n "$l" ] && violate "$l"; done <<<"$unexempted"
			violate "a rule matching no upstream text can never fire again; fix its left-hand side, or exempt it in omp-port/stale-exempt.tsv with a reason"
		elif [ "${total:-0}" -gt 0 ]; then
			report "rule staleness" "PASS  $total stale rule(s) at ${TARGET_SHA:0:7}, all exempted"
		else
			report "rule staleness" "PASS  every rule matches upstream text at ${TARGET_SHA:0:7}"
		fi
	else
		report "rule staleness" "FAIL"
		violate "the upstream extract failed, so staleness is unknown; an empty result here is not a clean one"
	fi
else
	report "rule staleness" "SKIP  needs the clone at $CANON"
fi

# A fragment that is blank or shorter than the matcher requires exempts nothing at all, which reads
# like a working exemption and is not one. Linted separately so the mistake surfaces whether or not
# any rule is currently stale.
bad_frag=$(stale_exempt_bad)
if [ -n "$bad_frag" ]; then
	report "stale exemptions" "FAIL"
	while read -r l; do [ -n "$l" ] && violate "$l"; done <<<"$bad_frag"
	violate "an exemption fragment that is blank or under 20 characters exempts nothing, so the rule it was written for will fail for the wrong reason"
else
	report "stale exemptions" "PASS  $(grep -cvE '^[[:space:]]*(#|$)' "$STALE_ALLOW" 2>/dev/null || echo 0) fragment(s), all usable"
fi
rm -rf "$scratch" "$buildlog"

echo
if [ "$fail" -eq 0 ]; then echo "check-port: PASS"; else echo "check-port: FAIL"; fi
exit "$fail"
