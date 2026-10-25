#!/usr/bin/env bash
set -uo pipefail

PORT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)
REPO_ROOT=$(cd "$PORT_DIR/.." && pwd -P)
FIXTURE=$(mktemp -d)
PORT_FIXTURE=$(mktemp -d)
trap 'rm -rf "$FIXTURE" "$PORT_FIXTURE"' EXIT
fail=0

reset_fixture() {
	rm -rf "$FIXTURE"
	mkdir -p "$FIXTURE"
	cp -a "$REPO_ROOT/plugins/pstack/." "$FIXTURE/"
	cp "$PORT_DIR/rules.sed" "$PORT_DIR/stale-exempt.tsv" "$PORT_FIXTURE/"
}

run_contracts() {
	CHECK_PORT_ROOT="$FIXTURE" RULES="$PORT_FIXTURE/rules.sed" STALE_EXEMPT="$PORT_FIXTURE/stale-exempt.tsv" \
		CHECK_PORT_CONTRACTS_ONLY=1 bash "$PORT_DIR/check-port.sh"
}

reset_fixture
if baseline=$(run_contracts 2>&1); then
	printf 'mutation tests: baseline PASS\n'
else
	printf 'mutation tests: baseline FAIL\n%s\n' "$baseline"
	exit 1
fi

expect_failure() {
	local name=$1 marker=$2 mutation=$3 output status
	reset_fixture
	"$mutation"
	if output=$(run_contracts 2>&1); then status=0; else status=$?; fi
	if [ "$status" -eq 0 ]; then
		printf 'mutation tests: %s unexpectedly passed\n' "$name"
		fail=1
	# The marker has to be the label of a line that reports FAIL. Every label prints on a PASS run
	# too, so a bare substring match accepted a mutation that some other check had rejected.
	elif ! printf '%s\n' "$output" | awk -v m="$marker" 'substr($0, 1, length(m)) == m && $NF == "FAIL" { hit = 1 } END { exit !hit }'; then
		printf 'mutation tests: %s failed for the wrong reason\n%s\n' "$name" "$output"
		fail=1
	else
		printf 'mutation tests: %s rejected\n' "$name"
	fi
}

mutate_preserve_ownership() {
	sed -i 's/^Preserve every unrelated entry in both maps\.$/Discard every unrelated entry in both maps./' "$FIXTURE/skills/setup-pstack/SKILL.md"
}

mutate_override_ownership() {
	sed -i 's/^A `task\.agentModelOverrides` entry is pstack-owned only when its exact key is a discovered agent and its value is one of `@pstack_fast_code`, `@pstack_judgment`, or `@pstack_instruction`\.$/A `task.agentModelOverrides` entry is pstack-owned when its key starts with `pstack_`./' "$FIXTURE/skills/setup-pstack/SKILL.md"
}

mutate_alias_shape() {
	sed -i '/^modelRoles:/a\  pstack_extra: "<detected-selector>:<effort>"' "$FIXTURE/skills/omp-mechanics/references/setup-pstack-config.md"
}

mutate_supported_suffixes() {
	sed -i 's/, and `minimal`//' "$FIXTURE/skills/omp-mechanics/references/setup-pstack-config.md"
}

mutate_base_selector() {
	sed -i 's/require the remaining base to equal a selector from `omp models --json`/accept any remaining base/' "$FIXTURE/skills/omp-mechanics/references/setup-pstack-config.md"
}

mutate_setup_apply_script() {
	sed -i '/^APPLY=/d' "$FIXTURE/skills/setup-pstack/SKILL.md"
}

mutate_setup_lever() {
	sed -i 's/task\.agentModelOverrides/task.model/g' "$FIXTURE/skills/setup-pstack/SKILL.md"
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

expect_failure 'unrelated ownership' 'setup config contract' mutate_preserve_ownership
expect_failure 'per-agent ownership' 'setup config contract' mutate_override_ownership
expect_failure 'alias shape' 'setup config contract' mutate_alias_shape
expect_failure 'supported suffix list' 'setup config contract' mutate_supported_suffixes
expect_failure 'base selector validation' 'setup config contract' mutate_base_selector
expect_failure 'setup apply script' 'setup config contract' mutate_setup_apply_script
expect_failure 'setup model lever' 'omp model levers' mutate_setup_lever
expect_failure 'router model lever' 'omp model levers' mutate_router_lever
expect_failure 'agent hub api' 'agent hub api' mutate_hub_api
expect_failure 'install root' 'install root' mutate_install_root
expect_failure 'unscoped cleanup' 'runtime unscoped-cleanup' mutate_unscoped_cleanup
expect_failure 'generalPurpose agent' 'runtime per-call-model' mutate_general_purpose
expect_failure 'capitalised Task tool' 'cursor tool names' mutate_task_tool
expect_failure 'cursor transcript layout' 'runtime history-layout' mutate_transcript_layout
expect_failure 'guide prototype playbook' 'guide claims' mutate_guide_playbook

mutate_veto_provenance() {
	sed -i 's/ships no `session_stop` veto/ships a session_stop veto/' "$FIXTURE/README.md"
}

# The three mutations above targeted `capability wiring`, which asserted that port-authored prose
# sat inside upstream's playbooks. That check is gone: the port mirrors upstream, so a reworded
# upstream sentence must not be a gate failure. There is nothing left here to mutate.

expect_failure 'external veto provenance' 'external capability provenance' mutate_veto_provenance

# A fragment written for one stale rule once matched a second rule too and kept it from failing the
# gate. Copying the rule the first exemption names gives that fragment two rules to match.
mutate_shared_fragment() {
	local frag rule
	frag=$(awk -F'\t' '$0 !~ /^#/ && $0 != "" { print $1; exit }' "$PORT_FIXTURE/stale-exempt.tsv")
	rule=$(grep -m1 -F -- "$frag" "$PORT_FIXTURE/rules.sed")
	printf '%s\n' "$rule" >>"$PORT_FIXTURE/rules.sed"
}

expect_failure 'shared exemption fragment' 'stale exemptions' mutate_shared_fragment


if [ "$fail" -ne 0 ]; then
	printf 'mutation tests: FAIL\n'
	exit 1
fi
printf 'mutation tests: PASS\n'
