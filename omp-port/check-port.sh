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

# The rule ledgers are `left-hand-fragment<TAB>...` rows. The fragment is matched as a literal
# substring of the rule's own line, never as a line number: a line number moves the moment anyone
# edits a rule above it, and a row that silently stops applying is worse than none, because the
# gate then goes red for a reason nobody can reconstruct. A fragment survives every edit that does
# not change the rule it names.
#   stale-exempt.tsv   `fragment<TAB>reason`, a rule that matches no upstream text, kept on purpose.
#   shadow-exempt.tsv  `fragment<TAB>reason`, a rule earlier rules starve, kept on purpose.
#   swallow.tsv        `fragment<TAB>sha256<TAB>reason`, a rule with `.*` or `.+`, the hash of every
#                      raw upstream span its left side matches, and why dropping them is right.
STALE_ALLOW="${STALE_EXEMPT:-$PORT_DIR/stale-exempt.tsv}"
SHADOW_ALLOW="${SHADOW_EXEMPT:-$PORT_DIR/shadow-exempt.tsv}"
SWALLOW_LEDGER="${SWALLOW:-$PORT_DIR/swallow.tsv}"
# Resolves each row of ledger <file> to the one rule it names, printing
# `ok<TAB><rules.sed line><TAB><file>:<row line><TAB><rest of the row>` or `bad<TAB><why>`, so the lint
# and the probe read one answer. Only a fragment that names exactly one rule counts. A blank or short
# fragment is found by index() in almost any rule, and a fragment that matches two rules lets the one
# it was not written for go stale in silence: a `run_in_background: true` fragment once hid a swarm
# Phase B rule that way. Only a genuinely empty line is not a row; a line holding whitespace is one,
# and fails.
ledger_resolve() {
	[ -f "$1" ] || return 0
	awk -F'\t' -v name="$(basename "$1")" '
		FILENAME == ARGV[1] {
			n++; at[n] = substr($0, 1, index($0, "\t") - 1); rule[n] = substr($0, index($0, "\t") + 1)
			next
		}
		$0 !~ /^#/ && $0 != "" {
			f = $1
			gsub(/^[[:space:]]+|[[:space:]]+$/, "", f)
			if (f !~ /[^[:space:]]/ || length(f) < 20) {
				printf "bad\t%s:%d fragment is blank or under 20 chars: [%s]\n", name, FNR, f
				next
			}
			c = 0; hits = ""
			for (i = 1; i <= n; i++) if (index(rule[i], f)) hits = hits (c++ ? ", " : "") at[i]
			if (c == 1) printf "ok\t%s\t%s:%d\t%s\n", hits, name, FNR, substr($0, length($1) + 2)
			else if (c == 0) printf "bad\t%s:%d fragment matches no rule: [%s]\n", name, FNR, f
			else printf "bad\t%s:%d fragment matches %d rules, rules.sed lines %s: [%s]\n", name, FNR, c, hits, f
		}
	' <(rule_records) "$1"
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

# Review diversity is no longer asserted here. These three checks pinned exact sentences inside
# upstream's skills, which made a reworded upstream sentence a gate failure rather than a
# cosmetic diff. The substance survives as token rules in rules.sed: any slug that reaches the tree
# is already model-agnostic, so a reviewer can only be told a family that does not exist.

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
bad_ro=$(printf '%s\n' "$ro" | awk '{ s = tolower($0); if (s !~ /readonly/) next; if (s ~ /readonly __brand|readonly string|readonly \[|readonly</) next; if (s ~ /(^|[^a-z])(no|not|never|without)[^a-z][^.;]{0,80}readonly/) next; print }')
if [ -n "$bad_ro" ]; then
	report "readonly posture" "FAIL"
	while read -r r; do [ -n "$r" ] && violate "unsupported readonly directive: $r"; done <<<"$bad_ro"
else
	report "readonly posture" "PASS  no readonly task field or prose directive"
fi

runtime_contract() {
	local bad label pattern
	for label in per-call-model pstack-rule-file task-environment unscoped-cleanup history-layout; do
		case "$label" in
		per-call-model) pattern='subagent_type|run_in_background|generalPurpose|`model`:\s*[^f]|Set `model`|set `model` to|with `model` from|omit `model` so' ;;
		pstack-rule-file) pattern='pstack-models\.mdc' ;;
		task-environment) pattern='environment:[[:space:]]*"?((local)|(cloud))\b|cloud_base_branch' ;;
		# `omp cleanse` detects AND fixes with parallel subagents, and `--all` runs every checker
		# repo-wide, so recommending it as a precommit diagnostic edits files outside the diff.
		unscoped-cleanup) pattern='omp[[:space:]]+cleanse[[:space:]]+(--all|-a)([[:space:]]|`|$)' ;;
		# Cursor's per-project transcript directory and its three layouts. omp writes one layout,
		# described in omp-mechanics/references/session-store-on-omp.md.
		history-layout) pattern='agent-transcripts|/subagents/|read the first JSONL line|legacy flat|message\.content\[0\]' ;;
		esac
		bad=$(grep -rInE "$pattern" --include='*.md' --include='*.mjs' --include='*.ts' --include='*.sh' "${SCOPE[@]}" 2>/dev/null || true)
		if [ -n "$bad" ]; then
			report "runtime $label" "FAIL"
			while read -r line; do violate "$line"; done <<<"$bad"
		else
			report "runtime $label" "PASS"
		fi
	done

	retired='swarm workers|architect runners|arena runners|arena cross-judge pool|interrogate reviewers|reflect judgment, divergent, synthesizer|reflect tooling|why investigators|why synthesizer|how explorer|how explainer|feature, refactoring|<swarm workers model>|`drive` inside a phase agent'
	bad=$(grep -rInE "$retired" --include='*.md' --include='*.mjs' --include='*.ts' --include='*.sh' "${SCOPE[@]}" 2>/dev/null || true)
	if [ -n "$bad" ]; then
		report "retired runtime labels" "FAIL"
		while read -r line; do violate "$line"; done <<<"$bad"
	else
		report "retired runtime labels" "PASS  no abstract role labels, placeholders, or stale process wording"
	fi

	# There is no `hub` tool. omp's own builtin tool list, packages/coding-agent/src/tools/builtin-names.ts
	# inside the binary, carries `wait` and no `hub`; the binary's only other `hub` is the `/hub`
	# slash command that opens Agent Hub, a human-facing TUI. The probe is in PORTING.md under
	# "Sibling coordination". An earlier tree claimed a `hub` tool with list/send/inbox/wait/cancel/
	# jobs/start/logs/stop ops, read off a stale pi-coding-agent 17.x package, and this assertion
	# enforced that claim. A sentence that names `hub` as a tool sends an agent to a primitive that
	# is not there; `wait`, `proc://`, `write agent://<id>`, and named `bash` services are.
	hub_claim='`hub`|\bhub[` ]+(tool|tools|op|ops|operation|operations)\b'
	bad=$(grep -rInE "$hub_claim" --include='*.md' --include='*.mjs' --include='*.ts' --include='*.sh' "${SCOPE[@]}" 2>/dev/null || true)
	if [ -n "$bad" ]; then
		report "agent hub api" "FAIL"
		while read -r line; do violate "claims a hub tool omp does not ship: $line"; done <<<"$bad"
	else
		report "agent hub api" "PASS  no hub tool claimed; coordination names wait, proc://, and agent://"
	fi

	# One install root. A path under any other agent store resolves to nothing on this machine,
	# and the playbook that names it cannot run its own binary.
	install=$(grep -rInE '~/\.(agents|claude|cursor)/' --include='*.md' --include='*.mjs' --include='*.ts' --include='*.sh' --include='*.js' \
		"${SCOPE[@]}" "$REPO_ROOT/PORTING.md" "$REPO_ROOT/README.md" README.md extensions 2>/dev/null |
		grep -vE 'claude-plugins|~/.claude/plugins' || true)
	if [ -n "$install" ]; then
		report "install root" "FAIL"
		while read -r line; do violate "$line"; done <<<"$install"
	else
		report "install root" "PASS  every install path resolves under ~/.omp"
	fi

	# Prose-presence checks are gone. This gate used to assert that port-authored sentences sat
	# inside upstream's playbooks, which is the opposite of mirroring upstream: upstream rewords
	# those sentences constantly, so every assertion was a rule that went stale and a sync that
	# broke. The port is lean by rule now, so a playbook says what upstream says and the omp
	# deltas live in rules.sed and the owned skills. What remains below is residue detection, which
	# is the part that can catch a defect rather than assert a preference.
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

	# omp's tools are lowercase. A capitalised `Task` names Cursor's spawn tool, and in a reviewer
	# template it makes the lens grep a transcript for a tool that was never called.
	bad=$(grep -rInE '`(Read|Grep|Glob|Shell)` (tool calls|prompts|response body|of)|`Task`|\bTask (tool|subagent|spawn|call|schema)s?\b|[Tt]ool calls? \(Shell,|Use Glob to find|Use Read, Grep|Subagents inherit it' --include='*.md' "${SCOPE[@]}" 2>/dev/null || true)
	if [ -n "$bad" ]; then
		report "cursor tool names" "FAIL"
		while read -r line; do violate "$line"; done <<<"$bad"
	else
		report "cursor tool names" "PASS  no Cursor tool name, capitalised Task included"
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
	grep -Fq 'APPLY=$(realpath skill://setup-pstack)/scripts/apply-models.mjs' "$setup_skill" && grep -Fq -- '--dry-run' "$setup_skill" && [ -f skills/setup-pstack/scripts/apply-models.mjs ] || bad="$bad"'setup does not plan and write through scripts/apply-models.mjs'$'\n'
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
		report "setup config contract" "PASS  ownership, aliases, model efforts, suffix, base selector, and the apply-models lever"
	fi
}
runtime_contract

# Claims the published guide (Pt.1 and Pt.2) makes about pstack, verified as present. Tree-local,
# so it runs before the contracts-only exit and the fixture mutations can reach it. The playbook
# count the guide states is asserted by `playbook parity`, from the index, not restated here.
unclaimed=""
guide_skills=(create-verification-skill maintain-verification-skill swarm poteto-mode teach how why recall technical-writing unslop architect)
guide_files=(skills/poteto-mode/playbooks/prototype.md skills/poteto-mode/playbooks/multi-phase-plan.md skills/poteto-mode/scripts/check-plan.mjs)
for s in "${guide_skills[@]}"; do
	[ -f "skills/$s/SKILL.md" ] || unclaimed="$unclaimed""guide names /$s, not installed"$'\n'
done
for f in "${guide_files[@]}"; do
	[ -f "$f" ] || unclaimed="$unclaimed""guide names $f, not shipped"$'\n'
done
grep -qi 'feature map' skills/create-verification-skill/SKILL.md 2>/dev/null ||
	unclaimed="$unclaimed""create-verification-skill must seed the feature map"$'\n'
# Upstream removed `mode: true` on purpose (b93e811) and omp never modelled it, so asserting that
# key only asserted a deleted line. The extension is what registers the command.
grep -q 'registerCommand("poteto-mode"' extensions/potetomode/index.js 2>/dev/null ||
	unclaimed="$unclaimed""the potetomode extension must register /poteto-mode"$'\n'
if [ -n "$unclaimed" ]; then
	report "guide claims" "FAIL"
	while read -r c; do [ -n "$c" ] && violate "$c"; done <<<"$unclaimed"
else
	report "guide claims" "PASS  ${#guide_skills[@]} skills, prototype and multi-phase-plan playbooks, check-plan.mjs, feature map, /poteto-mode command"
fi

# rules.sed read as data rather than run, so these need no clone and run before the contracts-only
# exit, where the fixture mutations reach them. Each is a shape that once shipped with every other
# check green.
rules_table=$(rule_table)

# A bare `&` in a replacement is the whole match. A replacement that quotes `git fetch && git
# reset` spliced the matched sentence in twice, and the tree still built.
amp=$(awk -F'\t' '$4 == 1 { print "rules.sed:" $1 ": " $7 }' <<<"$rules_table")
if [ -n "$amp" ]; then
	report "rule replacement &" "FAIL"
	while read -r l; do violate "$l"; done <<<"$amp"
	violate "a bare & in a replacement inserts the whole match; write \\& for a literal ampersand, or capture the text and use \\1"
else
	report "rule replacement &" "PASS  no replacement splices its match back in"
fi

# Under -E an unescaped `(` opens a group. A left side that wraps upstream's literal parentheses in a
# group consumes nothing of them, and a replacement that writes `(` back without a backreference
# then doubles them: three rules shipped `((force-push ...))` that way.
paren=$(awk -F'\t' '$5 == 1 { print "rules.sed:" $1 ": " $7 }' <<<"$rules_table")
if [ -n "$paren" ]; then
	report "rule paren groups" "FAIL"
	while read -r l; do violate "$l"; done <<<"$paren"
	violate "the left side groups text it never references and the replacement adds a literal (; escape upstream's parentheses as \\( and \\), or reference the group"
else
	report "rule paren groups" "PASS  no left side wraps literal parentheses in a group the replacement doubles"
fi

# Each ledger is resolved on every run, so a bad row fails the day it is written whether or not the
# rule it names is in trouble yet.
ledger_bad() { awk -F'\t' '$1 == "bad" { print $2 }' <<<"$1"; }
ledger_rules() { awk -F'\t' '$1 == "ok" { print $2 }' <<<"$1"; }
row_rule="a row must name exactly one rules.sed rule by a fragment of 20 or more characters, and any other fragment counts for nothing; starting it with the rule's s# opener keeps it off other rules' replacement text"
lint_ledger() {
	local bad
	bad=$(ledger_bad "$2")
	if [ -n "$bad" ]; then
		report "$1" "FAIL"
		while read -r l; do [ -n "$l" ] && violate "$l"; done <<<"$bad"
		violate "$row_rule"
	else
		report "$1" "PASS  $(ledger_rules "$2" | grep -c .) row(s), each naming exactly one rule"
	fi
}
stale_rows=$(ledger_resolve "$STALE_ALLOW")
shadow_rows=$(ledger_resolve "$SHADOW_ALLOW")
lint_ledger "stale exemptions" "$stale_rows"
lint_ledger "shadow exemptions" "$shadow_rows"

# A `.*` that is followed by more pattern, in a left side not anchored at `$`, ends its match at the
# last place that pattern occurs on the line, so it swallows every sentence in between. Rule 34 once
# ended `(\b.*)?\.` and deleted two sentences after the one it was written for. Such a rule needs a
# reviewed swallow.tsv row before it lands, clone or no clone. The probe below holds every wildcard
# rule to its row.
swallow_rows=$(ledger_resolve "$SWALLOW_LEDGER")
wild_bad=$(ledger_bad "$swallow_rows")
wild_bad="$wild_bad"$'\n'$(awk -F'\t' 'FILENAME == ARGV[1] { if ($1 == "ok") row[$2] = $3; next }
	$3 == "mid" && !($1 in row) { print "rules.sed:" $1 " ends a `.*` mid-line with no `$` anchor and has no swallow.tsv row: " $7 }
	$3 == "-" { plain[$1] = 1 }
	END { for (n in row) if (n in plain) print row[n] " names rules.sed:" n ", which has no `.*` or `.+`" }' \
	<(printf '%s\n' "$swallow_rows") <(printf '%s\n' "$rules_table"))
if [ -n "$(tr -d '[:space:]' <<<"$wild_bad")" ]; then
	report "rule wildcards" "FAIL"
	while read -r l; do [ -n "$l" ] && violate "$l"; done <<<"$wild_bad"
	violate "$row_rule; a row records the sha256 of the spans the wildcard swallows and why dropping them is right"
else
	report "rule wildcards" "PASS  every mid-line wildcard has a swallow.tsv row, and every row names a wildcard rule"
fi

if [ "${CHECK_PORT_CONTRACTS_ONLY:-}" = 1 ]; then
	echo
	if [ "$fail" -eq 0 ]; then echo "check-port contracts: PASS"; else echo "check-port contracts: FAIL"; fi
	exit "$fail"
fi

# The mutation harness runs this gate past the contracts-only exit to reach the upstream probes, and
# the harness is itself a step of this gate, so a nested run has to skip it or the two call each
# other forever. A nested run skips the worktree audit too: it is there for one probe, and the outer
# run has already run both suites.
if [ "${CHECK_PORT_NESTED:-}" = 1 ]; then
	report "gate mutations" "SKIP  nested run inside the mutation harness"
	report "worktree audit" "SKIP  nested run inside the mutation harness"
else
	mutation_log=$(mktemp)
	if CANON="$CANON" bash "$PORT_DIR/test-gate-mutations.sh" >"$mutation_log" 2>&1; then
		report "gate mutations" "PASS  $(grep -c 'rejected$' "$mutation_log") mutations rejected, each by its own check"
	else
		report "gate mutations" "FAIL"
		while read -r line; do [ -n "$line" ] && violate "$line"; done <"$mutation_log"
	fi
	rm -f "$mutation_log"
	# The patched worktree-audit.sh is a script, so its behaviour needs a run, not a grep. Its test
	# lives beside this gate and is cwd-independent.
	if [ -f "$PORT_DIR/test-worktree-audit.sh" ]; then
		audit_log=$(mktemp)
		if bash "$PORT_DIR/test-worktree-audit.sh" >"$audit_log" 2>&1; then
			report "worktree audit" "PASS  omp-port/test-worktree-audit.sh"
		else
			report "worktree audit" "FAIL"
			while read -r line; do [ -n "$line" ] && violate "$line"; done <"$audit_log"
		fi
		rm -f "$audit_log"
	else
		report "worktree audit" "SKIP  omp-port/test-worktree-audit.sh not present"
	fi
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

# The index names a leaf two ways and its preamble states both: an entry gives its own name in
# parentheses or names its file, and otherwise its title kebab-cases to the leaf. Upstream dropped
# the literal per-entry slug in favor of that rule, so a check that greps for the slug reads every
# entry as unnamed. Deriving the name is what the router tells the agent to do, so it is also the
# only reading that survives the next rewording. Prints one bare leaf name per index entry.
index_names() {
	awk -v section="$1" '
		$0 == "## " section { inside = 1; next }
		/^## / { inside = 0 }
		!inside || !/^- \*\*/ { next }
		{
			# An explicit name wins over the title: (**principle-x**) or File: `playbooks/x.md`.
			name = ""
			if (match($0, "[*][*][a-z-]+[*][*]")) {
				name = substr($0, RSTART + 2, RLENGTH - 4)
				gsub(/[()]/, "", name)
			} else if (match($0, "[`]playbooks/[a-z-]+[.]md[`]")) {
				name = substr($0, RSTART + 11, RLENGTH - 15)
			}
			if (name == "") {
				title = $0
				sub(/^- \*\*/, "", title)
				sub(/\*\*.*/, "", title)
				gsub(/[^A-Za-z0-9 -]/, "", title)
				title = tolower(title)
				gsub(/ /, "-", title)
				name = title
			}
			sub(/^principle-/, "", name)
			print name
		}
	' "$ROUTER" | grep .
}

ROUTER=skills/poteto-mode/SKILL.md
parity "principle parity" \
	"$(index_names Principles | sed 's/^/principle-/' | sort -u)" \
	"$(for d in skills/principle-*/; do basename "$d"; done | sort -u)" \
	'index names ' ', no leaf' \
	'leaf ' ' not in the Principles index'

parity "playbook parity" \
	"$(index_names Playbooks | sort -u)" \
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

bad=""
nfm=0
for d in skills/*/; do
	n=$(basename "$d")
	nfm=$((nfm + 1))
	fm=$(sed -n 's/^name: *//p' "$d/SKILL.md" 2>/dev/null | head -1 | tr -d '"' | tr -d "'")
	[ -n "$fm" ] || bad="$bad $n"
done
if [ -n "$bad" ]; then
	report "frontmatter name" "FAIL"
	for n in $bad; do violate "skills/$n/SKILL.md has no frontmatter name"; done
else
	report "frontmatter name" "PASS  $nfm skills, each SKILL.md names itself"
fi
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

# omp's agent-plugins provider claims a package with plugin.json at its root, checks skill
# frontmatter against a closed field set, and skips every skill that carries
# disable-model-invocation, icon, color, or globs.
if [ -e plugin.json ]; then
	report "plugin manifest" "FAIL"
	violate "plugins/pstack/plugin.json present; omp's agent-plugins provider skips every skill with an omp-only frontmatter field"
else
	report "plugin manifest" "PASS  no Agent Plugins manifest, so omp-plugins loads every skill"
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
# the checked-in tree, so it follows the pin and nothing else. The assertions after it are
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

# Same rule as the probes below: the probe's exit status is part of the result. untiered_slugs
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

# Ownership discards the built copy of an owned path, so an upstream edit to one reaches nobody
# unless the gate holds the path to the upstream object a maintainer last read. A commit count
# since the pin cannot do it: once the pin moves past the commit the count is zero again, and that
# is how ab1f702's edit to setup-pstack went unread.
if git -C "$CANON" cat-file -e "${TARGET_SHA}^{commit}" 2>/dev/null; then
	drift=$(owned_drift "$TARGET_SHA")
	if [ -n "$drift" ]; then
		report "owned drift" "FAIL"
		while IFS=$'\t' read -r p reviewed now; do
			if [ "$reviewed" = - ]; then
				violate "$p: upstream now carries pstack/$p at ${TARGET_SHA:0:7} as $now, and owned.txt says it has none"
			elif [ "$now" = - ]; then
				violate "$p: upstream no longer carries pstack/$p at ${TARGET_SHA:0:7}; owned.txt reviewed $reviewed"
			else
				violate "$p: upstream moved at ${TARGET_SHA:0:7}, reviewed $reviewed, now $now; read git -C $CANON diff $reviewed $now"
			fi
		done <<<"$drift"
		violate "carry what the owned copy needs, then record the object you read in omp-port/owned.txt"
	else
		report "owned drift" "PASS  $(owned_paths | grep -c .) owned path(s) match the upstream object last reviewed, at ${TARGET_SHA:0:7}"
	fi
else
	report "owned drift" "SKIP  needs the clone at $CANON"
fi

# The probe's own status is part of each assertion below. A probe that cannot run prints nothing,
# and reading only its stdout turns a probe that could not run into the strongest green this gate
# can print. An unknown result is a failure, not a clean one.
probes=skip
dead=""
causes=""
if [ "$canon_ok" = yes ]; then
	probes=failed
	if ! dead=$(dead_rules "$TARGET_SHA" 2>/dev/null); then
		report "rule liveness" "FAIL"
		violate "the marked build failed, so liveness is unknown; an empty result here is not a clean one"
	elif ! causes=$(dead_rule_causes "$TARGET_SHA" "$dead"); then
		report "rule liveness" "FAIL"
		violate "a rule failed to run on its own against upstream, so why rules fire nothing is unknown"
	elif [ -z "$dead" ]; then
		probes=ok
		report "rule liveness" "PASS  every rule fired at ${TARGET_SHA:0:7}"
	else
		probes=ok
		report "rule liveness" "REPORT  $(grep -c . <<<"$dead") rule(s) fired nothing at ${TARGET_SHA:0:7}: $(cut -f2 <<<"$causes" | sort | uniq -c | awk '{ printf "%s%s %s", (NR > 1 ? ", " : ""), $1, $2 }')"
	fi
else
	report "rule liveness" "SKIP  needs the clone at $CANON"
fi
probe_unknown() {
	if [ "$probes" = skip ]; then
		report "$1" "SKIP  needs the clone at $CANON"
	else
		report "$1" "FAIL"
		violate "rule liveness could not run, so this is unknown"
	fi
}

# Has upstream moved past a rule? A rule whose left side matches nothing in raw upstream can never
# fire again, so the translation it was written for is not being applied, and sed exiting 0 is the
# only thing that kept that quiet. An exemption is a reviewed decision about one stale rule, so an
# exemption whose rule is not stale is a decision about something that no longer exists, and it
# keeps that rule from being reviewed again the day it does go stale.
if [ "$probes" = ok ]; then
	bad=""
	stale_set=$(awk -F'\t' '$2 == "stale" { print $1 }' <<<"$causes")
	exempted=$(ledger_rules "$stale_rows")
	while IFS=$'\t' read -r n rule; do
		[ -n "$n" ] || continue
		grep -qxF "$n" <<<"$stale_set" || continue
		grep -qxF "$n" <<<"$exempted" || bad="${bad}rules.sed:${n}: ${rule}"$'\n'
	done <<<"$dead"
	while IFS=$'\t' read -r _ n at _; do
		[ -n "$n" ] || continue
		grep -qxF "$n" <<<"$stale_set" && continue
		cause=$(awk -F'\t' -v n="$n" '$1 == n { print "it fires nothing, cause " $2 }' <<<"$causes")
		bad="${bad}${at} exempts rules.sed:${n}, which matches upstream text at ${TARGET_SHA:0:7}; ${cause:-it fires in the build}"$'\n'
	done < <(awk -F'\t' '$1 == "ok"' <<<"$stale_rows")
	if [ -n "$bad" ]; then
		report "rule staleness" "FAIL"
		while read -r l; do [ -n "$l" ] && violate "$l"; done <<<"$bad"
		violate "a rule matching no upstream text can never fire again; fix its left side or exempt it in omp-port/stale-exempt.tsv, and delete an exemption whose rule matches upstream"
	else
		report "rule staleness" "PASS  $(grep -c . <<<"$stale_set") stale rule(s) at ${TARGET_SHA:0:7}, each exempted, and no exemption on a live rule"
	fi
else
	probe_unknown "rule staleness"
fi

# A rule whose own raw match an earlier rule rewrites never fires while that order stands: a
# duplicate, or a narrower rule placed above a broader one. That is how rule 228 shipped its
# translation dead behind rule 227. A token net that only loses the sentence around its match is
# not this; it is the healthy `consumed` population.
if [ "$probes" = ok ]; then
	bad=""
	shadow_set=$(awk -F'\t' '$2 == "shadowed" { print $1 }' <<<"$causes")
	recorded=$(ledger_rules "$shadow_rows")
	while IFS=$'\t' read -r n _ by span; do
		grep -qxF "$n" <<<"$recorded" ||
			bad="${bad}rules.sed:${n} never fires: ${by} rewrite its own match first, e.g. ${span}"$'\n'
	done < <(awk -F'\t' '$2 == "shadowed"' <<<"$causes")
	while IFS=$'\t' read -r _ n at _; do
		[ -n "$n" ] || continue
		grep -qxF "$n" <<<"$shadow_set" ||
			bad="${bad}${at} records rules.sed:${n} as shadowed, and at ${TARGET_SHA:0:7} it is not"$'\n'
	done < <(awk -F'\t' '$1 == "ok"' <<<"$shadow_rows")
	if [ -n "$bad" ]; then
		report "rule shadowing" "FAIL"
		while read -r l; do [ -n "$l" ] && violate "$l"; done <<<"$bad"
		violate "move the rule above the one that starves it, delete it if it duplicates that rule, or record why it stays in omp-port/shadow-exempt.tsv"
	else
		report "rule shadowing" "PASS  $(grep -c . <<<"$shadow_set") shadowed rule(s) at ${TARGET_SHA:0:7}, each recorded"
	fi
else
	probe_unknown "rule shadowing"
fi

# A `.*` or `.+` swallows whatever upstream writes inside its span, so a sentence upstream adds
# there is dropped with no rule changing and no probe above noticing. Rule 89 dropped a new clause
# about steering a running agent that way, and rule 35 six new sentences. Each wildcard rule's row
# holds the hash of every raw upstream span it matched when someone last read them, so new text
# inside a span fails here until someone reads it.
if [ "$canon_ok" = yes ]; then
	if spans=$(wildcard_spans "$TARGET_SHA"); then
		bad=""
		pin_spans=""
		nwild=0
		while IFS=$'\t' read -r n _ wild _ _ _ rule; do
			[ "$wild" != - ] || continue
			nwild=$((nwild + 1))
			mine=$(awk -F'\t' -v n="$n" '$1 == n { print substr($0, index($0, "\t") + 1) }' <<<"$spans")
			hash=$(if [ -n "$mine" ]; then printf '%s\n' "$mine"; fi | sha256sum | cut -d' ' -f1)
			at=$(awk -F'\t' -v n="$n" '$1 == "ok" && $2 == n { print $3 }' <<<"$swallow_rows")
			reviewed=$(awk -F'\t' -v n="$n" '$1 == "ok" && $2 == n { print $4 }' <<<"$swallow_rows")
			if [ -z "$at" ]; then
				bad="${bad}rules.sed:${n} has no swallow.tsv row; its spans hash to ${hash}: ${rule}"$'\n'
				continue
			fi
			[ "$reviewed" != "$hash" ] || continue
			bad="${bad}${at} rules.sed:${n} swallows different text at ${TARGET_SHA:0:7}: reviewed ${reviewed:0:12}, now ${hash}"$'\n'
			changed=""
			if [ "$TARGET_SHA" != "$pin" ]; then
				[ -n "$pin_spans" ] || pin_spans=$(wildcard_spans "$pin") || pin_spans=""
				was=$(awk -F'\t' -v n="$n" '$1 == n { print substr($0, index($0, "\t") + 1) }' <<<"$pin_spans")
				changed=$(diff <(printf '%s\n' "$was") <(printf '%s\n' "$mine") | sed -n 's/^< /  - at the pin: /p; s/^> /  + at the target: /p')
			fi
			[ -n "$changed" ] || changed=$(printf '%s\n' "$mine" | sed 's/^/  now: /')
			bad="${bad}${changed}"$'\n'
		done <<<"$rules_table"
		if [ -n "$bad" ]; then
			report "swallow ledger" "FAIL"
			while IFS= read -r l; do [ -n "$l" ] && violate "$l"; done <<<"$bad"
			violate "read what the wildcard now swallows; then narrow the rule, or record the new hash in omp-port/swallow.tsv with why dropping that text is right"
		else
			report "swallow ledger" "PASS  $nwild wildcard rule(s) swallow exactly the spans last reviewed, at ${TARGET_SHA:0:7}"
		fi
	else
		report "swallow ledger" "FAIL"
		violate "the upstream extract failed, so what the wildcards swallow is unknown"
	fi
else
	report "swallow ledger" "SKIP  needs the clone at $CANON"
fi

rm -rf "$scratch" "$buildlog"

echo
if [ "$fail" -eq 0 ]; then echo "check-port: PASS"; else echo "check-port: FAIL"; fi
exit "$fail"
