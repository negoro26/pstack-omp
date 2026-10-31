#!/usr/bin/env bash
# Each case breaks one thing in its own copy of the tree and the port files, runs check-port.sh on
# that copy, and expects one named check to FAIL on it. A case that passes, or fails some other
# check, fails the harness. Cases run in parallel, one directory each.
set -uo pipefail

PORT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)
. "$PORT_DIR/lib.sh"
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT
JOBS=$(getconf _NPROCESSORS_ONLN 2>/dev/null || echo 2)
PIN=$(tr -d '[:space:]' <"$PORT_DIR/UPSTREAM")
# An earlier pin. `target builds` only runs when the target differs from the pin, and any upstream
# sha whose text differs from the pin's will do.
OLD_TARGET=519d36aa98955bf680db01bcde5fdfba686dc901
export CANON
fail=0
ncase=0

# Runs the gate on case directory <dir>, the way the outer gate would but nested, so it skips this
# harness and the worktree audit. A contracts run reads the case's copy of the tree; a full run
# reads the real tree, because the counts and the docs it checks sit outside the plugin root.
run_gate() {
	local mode=$1 dir=$2 only="" root="" patches="$PORT_DIR/patches"
	shift 2
	[ "$mode" = contracts ] && only=1 root="$dir/plugin"
	[ -d "$dir/patches" ] && patches="$dir/patches"
	CHECK_PORT_ROOT="$root" RULES="$dir/port/rules.sed" STALE_EXEMPT="$dir/port/stale-exempt.tsv" \
		SHADOW_EXEMPT="$dir/port/shadow-exempt.tsv" SWALLOW="$dir/port/swallow.tsv" OWNED="$dir/port/owned.txt" \
		EXCLUDED="$dir/port/excluded.txt" \
		PATCH_DIR="$patches" CHECK_PORT_CONTRACTS_ONLY="$only" CHECK_PORT_NESTED=1 \
		bash "$PORT_DIR/check-port.sh" "$@"
}

# Sets up a case, applies <mutation> to it, and starts it in the background.
#   <name>      what the mutation breaks.
#   <label>     the check that must report FAIL. Unused by a `terminal` case.
#   <needle>    text one of that check's violation lines must contain, or empty for any. A
#               `terminal` case needs it anywhere in its output.
#   <mode>      `contracts` or `full` runs the gate. `terminal` runs the pin's build alone with
#               its output on a pseudo-terminal and a deadline, the way `sync-upstream.sh` prints
#               it, which is the one place a prompt reaches a person; the gate sends the build's
#               output to a file, and patch answers its own prompts there.
#   <mutation>  a function editing $FIXTURE (the tree, contracts only), $PORT_FIXTURE (the port
#               files), or $PATCH_FIXTURE (a patch directory that replaces omp-port/patches).
#   [args]      passed to check-port.sh.
start_case() {
	local name=$1 label=$2 needle=$3 mode=$4 mutation=$5 dir
	shift 5
	dir="$WORK/$((++ncase))"
	mkdir -p "$dir/port"
	[ "$mode" != contracts ] || cp -a "$PORT_DIR/../plugins/pstack" "$dir/plugin"
	cp "$PORT_DIR"/{rules.sed,stale-exempt.tsv,shadow-exempt.tsv,swallow.tsv,owned.txt,excluded.txt} "$dir/port/"
	FIXTURE="$dir/plugin" PORT_FIXTURE="$dir/port" PATCH_FIXTURE="$dir/patches"
	"$mutation"
	printf '%s\037%s\037%s\037%s\037%s\n' "$name" "$mode" "$label" "$needle" "$dir" >>"$WORK/cases"
	while [ "$(jobs -rp | wc -l)" -ge "$JOBS" ]; do wait -n; done
	if [ "$mode" = terminal ]; then
		mkdir -p "$dir/build"
		printf '. %q\nPATCH_DIR=%q build_tree %q %q\n' "$PORT_DIR/lib.sh" "$dir/patches" "$PIN" "$dir/build" >"$dir/run.sh"
		(
			SHELL=/bin/bash timeout 120 script -qec "bash $dir/run.sh" /dev/null </dev/null >"$dir/out" 2>&1
			echo $? >"$dir/status"
		) &
	else
		(
			run_gate "$mode" "$dir" "$@" >"$dir/out" 2>&1
			echo $? >"$dir/status"
		) &
	fi
}

# 0 when <label> printed FAIL and, given a <needle>, one of its violation lines contains it. Every
# label prints on a PASS run too, so a bare substring match would accept a mutation some other
# check had rejected.
failed_on() {
	tr -d '\r' <"$1" | awk -v m="$2" -v needle="$3" '
		/^  / { if (in_label && (needle == "" || index($0, needle))) hit = 1; next }
		{ in_label = (substr($0, 1, length(m)) == m && $NF == "FAIL"); if (in_label && needle == "") hit = 1 }
		END { exit !hit }'
}

# Swaps the one rule containing <fragment> for <rule>, verbatim.
replace_rule() {
	F=$1 R=$2 awk 'index($0, ENVIRON["F"]) && !done { print ENVIRON["R"]; done = 1; next } { print }' \
		"$PORT_FIXTURE/rules.sed" >"$PORT_FIXTURE/rules.new" && mv "$PORT_FIXTURE/rules.new" "$PORT_FIXTURE/rules.sed"
}

nothing() { :; }

# Appends <line> to <file> as a line of its own. stale-exempt.tsv once had no final newline, so an
# append edited its last row instead, and two cases were the baseline twice.
append() {
	[ -z "$(tail -c1 "$1")" ] || printf '\n' >>"$1"
	printf '%s\n' "$2" >>"$1"
}

# The build deletes an excluded path, so it reaches the tree only by hand or through owned.txt.
mutate_excluded_path() {
	mkdir -p "$FIXTURE/skills/setup-pstack"
	printf -- '---\nname: setup-pstack\n---\n' >"$FIXTURE/skills/setup-pstack/SKILL.md"
}

# A poteto-help line this port shipped before it excluded setup-pstack.
mutate_excluded_reference() {
	printf '\n- Now: give them `/skill:setup-pstack` to type, and answer their question too.\n' >>"$FIXTURE/skills/poteto-help/SKILL.md"
}

mutate_router_lever() {
	sed -i 's/task\.agentModelOverrides/task.model/g' "$FIXTURE/skills/poteto-mode/SKILL.md"
}

# The claim an earlier tree shipped. omp has no `hub` tool, so naming one must fail on its own check,
# not only on the retired `op:` wording.
mutate_hub_api() {
	printf '\n`hub` is a real built-in tool on this harness, with ops `list`, `send`, and `wait`.\n' >>"$FIXTURE/skills/pstack-omp/SKILL.md"
}

mutate_install_root() {
	sed -i 's#~/\.omp/plugins/node_modules/pstack/skills#~/.agents/skills#' "$FIXTURE/skills/poteto-mode/playbooks/multi-phase-plan.md"
}

# negoro26/pstack-omp#20: `omp cleanse --all` detects and fixes repo-wide, so it is no diagnostic.
mutate_unscoped_cleanup() {
	printf '\nRun `omp cleanse --all` before commit.\n' >>"$FIXTURE/skills/poteto-mode/SKILL.md"
}

mutate_general_purpose() {
	printf '\nSpawn every explorer as a `generalPurpose` worker.\n' >>"$FIXTURE/skills/how/SKILL.md"
}

# Restores the upstream wording rules.sed rewrites in the reflect reviewer templates.
mutate_task_tool() {
	sed -i 's/a `task` item whose brief names its path/a `Task` prompt naming its path/' "$FIXTURE/skills/reflect/references/judgment-reviewer.md"
}

mutate_transcript_layout() {
	printf '\nFind this conversation in the `agent-transcripts/` directory the system prompt names.\n' >>"$FIXTURE/skills/reflect/SKILL.md"
}

mutate_guide_playbook() {
	rm "$FIXTURE/skills/poteto-mode/playbooks/prototype.md"
}

# `features` matched "Sub-features" and nothing about the map the guide promises.
mutate_guide_feature_map() {
	sed -i 's/Seed the feature map/Seed the inventory/' "$FIXTURE/skills/create-verification-skill/SKILL.md"
}

# "another" holds "no", which once excused the directive as a negation.
mutate_readonly_another() {
	printf '\nSpawn another readonly reviewer.\n' >>"$FIXTURE/skills/how/SKILL.md"
}

mutate_bare_skill_command() {
	printf '\nRun `/how` first, then `/skill:how`.\n' >>"$FIXTURE/skills/no-comments/SKILL.md"
}

mutate_required_item_field() {
	sed -i 's/solutionSpace/spaceField/g' "$FIXTURE/skills/pstack-omp/SKILL.md"
}

mutate_veto_provenance() {
	sed -i 's/ships no `session_stop` veto/ships a session_stop veto/' "$FIXTURE/README.md"
}

# A fragment written for one stale rule once matched a second rule too and kept it from failing the
# gate. Copying the rule the first exemption names gives that fragment two rules to match.
mutate_shared_fragment() {
	local frag rule
	frag=$(awk -F'\t' '$0 !~ /^#/ && $0 != "" { print $1; exit }' "$PORT_FIXTURE/stale-exempt.tsv")
	rule=$(grep -m1 -F -- "$frag" "$PORT_FIXTURE/rules.sed")
	append "$PORT_FIXTURE/rules.sed" "$rule"
}

# index() finds a run of spaces in almost any rule, so a whitespace row would exempt everything.
mutate_whitespace_exemption() {
	append "$PORT_FIXTURE/stale-exempt.tsv" $' \t                     '
}

mutate_shadow_row_no_rule() {
	append "$PORT_FIXTURE/shadow-exempt.tsv" $'s#a left side no rule has ever had#\tkept on purpose'
}

# 73f30d9 rule 512: its replacement quoted `git fetch && git reset`, and each & spliced the matched
# sentence back in, three copies on one line of opening-a-pr.md.
mutate_bare_ampersand() {
	replace_rule 'git fetch && git reset --hard origin/<branch>` between them' \
		's#or `git fetch && git reset --hard origin/<branch>` between them\.#or `git fetch && git reset --hard origin/<branch>` between them -- and only after `git status --porcelain` comes back empty, since the next clause is what you do when it does not.#'
}

# 73f30d9 rule 551: an ERE group around upstream's literal parentheses, and a replacement that
# added them again, so session-pickup.md shipped `((`.
mutate_paren_group() {
	replace_rule 's#the system prompt names (the|this) path#' \
		's#(the system prompt names the path)#(`history://<id>` is the documented surface)#'
}

# 4275556 rule 34: `(\b.*)?\.` ran to the last period on the line and deleted two sentences after
# the one it was written for.
mutate_greedy_wildcard() {
	replace_rule "s#Pick each subagent's reasoning level and fast or standard speed for the job, per the Subagents section" \
		"s#Pick each subagent's reasoning level and fast or standard speed for the job, per the Subagents section(\\b.*)?\\.#Use the reasoning and speed already selected by agent frontmatter or exact \`task.agentModelOverrides\` entries. Do not change operator configuration to satisfy a skill example.#g"
}

mutate_swallow_row_plain_rule() {
	append "$PORT_FIXTURE/swallow.tsv" "s#which each get their own machine#"$'\t'"$(printf '' | sha256sum | cut -d' ' -f1)"$'\tnot a wildcard rule'
}

mutate_unmatched_rule() {
	append "$PORT_FIXTURE/rules.sed" 's#a sentence upstream has never contained#a replacement nobody sees#'
}

# rules.sed:109 deleted a line upstream stopped writing, and only `s` rules were probed, so nobody
# was told.
mutate_unmatched_delete() {
	append "$PORT_FIXTURE/rules.sed" '/^a line upstream has never contained$/d'
}

mutate_exemption_on_live_rule() {
	append "$PORT_FIXTURE/stale-exempt.tsv" $'s#Typing `/principle-<name>` still loads\tforward-compat net'
}

# 4275556 rule 228 sat behind rule 227, which rewrote the same token first, so its translation never
# reached orchestrate.md. A copy of a live rule further down is the same shape.
mutate_shadowed_rule() {
	append "$PORT_FIXTURE/rules.sed" 's#which each get their own machine#which share one machine#g'
}

mutate_swallow_hash() {
	sed -i '/^s#^\\\*\\\*Match the model to the job/s/\t[0-9a-f]\{64\}\t/\t0000000000000000000000000000000000000000000000000000000000000000\t/' "$PORT_FIXTURE/swallow.tsv"
}

mutate_swallow_row_missing() {
	sed -i '/^s#^- Enter on `\/poteto-mode` attaches/d' "$PORT_FIXTURE/swallow.tsv"
}

# poteto-mode's upstream tree at the old target, recorded as the object last reviewed. Upstream has
# changed it since, which is what owned.txt says when nobody read an upstream edit to an owned path.
mutate_owned_drift() {
	append "$PORT_FIXTURE/owned.txt" "skills/poteto-mode"$'\t'"$(git -C "$CANON" rev-parse "$OLD_TARGET:pstack/skills/poteto-mode")"
}

# A real patch applied a second time. Its hunks are already in, so plain patch asks on the terminal
# whether to reverse them and waits, and --batch answers yes and reverts the first copy.
mutate_patch_fails() {
	mkdir -p "$PATCH_FIXTURE"
	cp "$PORT_DIR"/patches/*.patch "$PATCH_FIXTURE/"
	cp "$PORT_DIR/patches/zzz-script-typecheck.patch" "$PATCH_FIXTURE/zzzz-applied-twice.patch"
}

# A patch for a line the pin has and the old target lacks, so the pin builds and the target cannot.
mutate_target_only_patch() {
	local tmp f line n
	tmp=$(mktemp -d)
	mkdir -p "$tmp/pin" "$tmp/old" "$PATCH_FIXTURE"
	cp "$PORT_DIR"/patches/*.patch "$PATCH_FIXTURE/"
	if build_tree "$PIN" "$tmp/pin" >/dev/null 2>&1 && build_tree "$OLD_TARGET" "$tmp/old" >/dev/null 2>&1; then
		while read -r f; do
			[ -f "$tmp/old/$f" ] || continue
			n=$(awk 'FILENAME == ARGV[1] { old[$0] = 1; next } length($0) > 20 && !($0 in old) { print FNR; exit }' "$tmp/old/$f" "$tmp/pin/$f")
			[ -n "$n" ] || continue
			line=$(sed -n "${n}p" "$tmp/pin/$f")
			printf -- '--- a/%s\n+++ b/%s\n@@ -%s,1 +%s,1 @@\n-%s\n+%s (only at the pin)\n' "$f" "$f" "$n" "$n" "$line" "$line" \
				>"$PATCH_FIXTURE/zzzz-target-only.patch"
			break
		done < <(cd "$tmp/pin" && grep -rlI '' skills | sort)
	fi
	rm -rf "$tmp"
}

start_case 'baseline' '' '' contracts nothing
start_case 'excluded path in the tree' 'excluded paths' 'skills/setup-pstack is in the tree' contracts mutate_excluded_path
start_case 'line naming an excluded path' 'excluded paths' '/skill:setup-pstack' contracts mutate_excluded_reference
start_case 'router model lever' 'omp model levers' '' contracts mutate_router_lever
start_case 'agent hub api' 'agent hub api' '' contracts mutate_hub_api
start_case 'install root' 'install root' '' contracts mutate_install_root
start_case 'unscoped cleanup' 'runtime unscoped-cleanup' '' contracts mutate_unscoped_cleanup
start_case 'generalPurpose agent' 'runtime per-call-model' '' contracts mutate_general_purpose
start_case 'capitalised Task tool' 'cursor tool names' '' contracts mutate_task_tool
start_case 'cursor transcript layout' 'runtime history-layout' '' contracts mutate_transcript_layout
start_case 'guide prototype playbook' 'guide claims' '' contracts mutate_guide_playbook
start_case 'guide feature map' 'guide claims' 'feature map' contracts mutate_guide_feature_map
start_case 'readonly after another' 'readonly posture' 'another readonly' contracts mutate_readonly_another
start_case 'bare skill command' 'skill command form' '`/how`' contracts mutate_bare_skill_command
start_case 'required item field' 'runtime contract fields' 'solutionSpace' contracts mutate_required_item_field
# The README half only: PORTING.md lives outside the plugin root, so no fixture reaches it.
start_case 'external veto provenance' 'external capability provenance' '' contracts mutate_veto_provenance
start_case 'shared exemption fragment' 'stale exemptions' 'matches 2 rules' contracts mutate_shared_fragment
start_case 'whitespace exemption row' 'stale exemptions' 'blank' contracts mutate_whitespace_exemption
start_case 'shadow row naming no rule' 'shadow exemptions' 'matches no rule' contracts mutate_shadow_row_no_rule
start_case 'bare & in a replacement' 'rule replacement &' 'git fetch &&' contracts mutate_bare_ampersand
start_case 'parentheses as a group' 'rule paren groups' '(the system prompt names the path)' contracts mutate_paren_group
start_case 'greedy mid-line wildcard' 'rule wildcards' 'Pick each subagent' contracts mutate_greedy_wildcard
start_case 'swallow row on a plain rule' 'rule wildcards' 'which has no' contracts mutate_swallow_row_plain_rule

# The upstream probes answer a question about rules.sed and the ledgers against upstream text, so
# these cases run the whole gate and need the clone. The clone is fetched here, one sha at a time,
# before any case starts: the cases run in parallel and two fetches into one clone collide.
if ensure_canon "$PIN" "$OLD_TARGET" >/dev/null 2>&1; then
	start_case 'rule matching no upstream text' 'rule staleness' 'a sentence upstream has never contained' full mutate_unmatched_rule
	start_case 'delete rule matching no line' 'rule staleness' 'a line upstream has never contained' full mutate_unmatched_delete
	start_case 'exemption on a live rule' 'rule staleness' 'which matches upstream text' full mutate_exemption_on_live_rule
	start_case 'rule behind its own duplicate' 'rule shadowing' 'which each get their own machine' full mutate_shadowed_rule
	start_case 'swallowed text changed' 'swallow ledger' 'now: **Match the model to the job.**' full mutate_swallow_hash
	start_case 'wildcard rule with no row' 'swallow ledger' 'has no swallow.tsv row' full mutate_swallow_row_missing
	start_case 'owned path moved upstream' 'owned drift' 'skills/poteto-mode: upstream moved' full mutate_owned_drift
	start_case 'patch that no longer applies' 'reproducible' 'failed, rules or a patch' full mutate_patch_fails
	if command -v script >/dev/null; then
		start_case 'patch prompt on a terminal' '' 'hunk FAILED' terminal mutate_patch_fails
	else
		printf 'mutation tests: SKIP patch prompt on a terminal, no script(1) for a pseudo-terminal\n'
	fi
	start_case 'target that no longer builds' 'target builds' "the build fails at ${OLD_TARGET:0:7}" full mutate_target_only_patch "$CANON" "$OLD_TARGET"
else
	printf 'mutation tests: SKIP upstream cases, no cursor/plugins clone at %s\n' "$CANON"
fi

wait

while IFS=$'\037' read -r name mode label needle dir; do
	status=$(cat "$dir/status" 2>/dev/null || echo '?')
	if [ "$name" = baseline ]; then
		if [ "$status" != 0 ]; then
			printf 'mutation tests: baseline FAIL\n'
			cat "$dir/out"
			exit 1
		fi
		printf 'mutation tests: baseline PASS\n'
	elif [ "$status" = 124 ]; then
		printf 'mutation tests: %s hung until the deadline, a prompt is waiting for an answer\n' "$name"
		fail=1
	elif [ "$status" = 0 ]; then
		printf 'mutation tests: %s unexpectedly passed\n' "$name"
		fail=1
	elif { [ "$mode" = terminal ] && ! tr -d '\r' <"$dir/out" | grep -qF -- "$needle"; } ||
		{ [ "$mode" != terminal ] && ! failed_on "$dir/out" "$label" "$needle"; }; then
		printf 'mutation tests: %s failed for the wrong reason\n' "$name"
		tr -d '\r' <"$dir/out"
		fail=1
	else
		printf 'mutation tests: %s rejected\n' "$name"
	fi
done <"$WORK/cases"

if [ "$fail" -ne 0 ]; then
	printf 'mutation tests: FAIL\n'
	exit 1
fi
printf 'mutation tests: PASS\n'
