#!/usr/bin/env bash
set -uo pipefail

PORT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)
REPO_ROOT=$(cd "$PORT_DIR/.." && pwd -P)
FIXTURE=$(mktemp -d)
FIXTURE_DOCS=$(mktemp -d)
trap 'rm -rf "$FIXTURE" "$FIXTURE_DOCS"' EXIT
fail=0

reset_fixture() {
	rm -rf "$FIXTURE"
	mkdir -p "$FIXTURE"
	cp -a "$REPO_ROOT/plugins/pstack/." "$FIXTURE/"
	cp -a "$REPO_ROOT/PORTING.md" "$FIXTURE_DOCS/PORTING.md"
	[ -f "$REPO_ROOT/README.md" ] && cp -a "$REPO_ROOT/README.md" "$FIXTURE_DOCS/README.md"
	return 0
}

run_contracts() {
	CHECK_PORT_ROOT="$FIXTURE" CHECK_PORT_DOCS_ROOT="$FIXTURE_DOCS" CHECK_PORT_CONTRACTS_ONLY=1 bash "$PORT_DIR/check-port.sh"
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
	elif ! printf '%s\n' "$output" | grep -qF "$marker"; then
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
	sed -i 's/`:low`, or `:minimal`/`:low`/' "$FIXTURE/skills/setup-pstack/SKILL.md"
	sed -i 's/, and `minimal`//' "$FIXTURE/skills/omp-mechanics/references/setup-pstack-config.md"
}

mutate_base_selector() {
	sed -i 's/require the remaining base to equal a selector from `omp models --json`/accept any remaining base/' "$FIXTURE/skills/setup-pstack/SKILL.md"
}

mutate_setup_lever() {
	sed -i 's/task\.agentModelOverrides/task.model/g' "$FIXTURE/skills/setup-pstack/SKILL.md"
}

mutate_router_lever() {
	sed -i 's/task\.agentModelOverrides/task.model/g' "$FIXTURE/skills/poteto-mode/SKILL.md"
}

mutate_batch_shape_abandoned() {
	sed -i 's/tasks\[\]/items[]/g; s/the required shared `context`/the shared brief/g' "$FIXTURE/skills/arena/SKILL.md"
}

mutate_yield_line_dropped() {
	sed -i '/^\*\*Yield first\.\*\*/d' "$FIXTURE/skills/pstack-omp/SKILL.md"
}

mutate_yield_account_dropped() {
	sed -i 's/A child that ends without the call costs three reminder prompts, then a system warning and no structured output\. //' "$FIXTURE/skills/pstack-omp/SKILL.md"
}

mutate_required_item_field() {
	sed -i 's/solutionSpace/spaceField/g' "$FIXTURE/skills/pstack-omp/SKILL.md"
}

mutate_gate_setting_dropped() {
	sed -i 's/task\.softRequestBudget/task.softBudget/g' "$FIXTURE/skills/pstack-omp/SKILL.md"
}

mutate_tool_class_renamed() {
	sed -i 's/kernel-defined/eval-defined/g' "$FIXTURE/skills/pstack-omp/SKILL.md"
}

mutate_hub_api() {
	printf '\nUse `hub` `op: "list"` to enumerate workers.\n' >>"$FIXTURE/skills/pstack-omp/SKILL.md"
}

mutate_install_root() {
	sed -i 's#~/\.omp/plugins/node_modules/pstack/skills#~/.agents/skills#' "$FIXTURE/skills/poteto-mode/playbooks/multi-phase-plan.md"
}

mutate_hub_prescribed_after_denial() {
	printf 'There is no `agent://all` in the live schema, and `hub` `op: "list"` is the fallback.\n' >>"$FIXTURE/skills/pstack-omp/SKILL.md"
}

mutate_install_root_in_docs() {
	printf 'Install to ~/.agents/skills/pstack now.\n' >>"$FIXTURE_DOCS/PORTING.md"
}

mutate_cursor_tool_name() {
	printf '\n- `Read` tool calls against any `SKILL.md` file in the repo\n' >>"$FIXTURE/skills/reflect/references/judgment-reviewer.md"
}

mutate_bare_skill_command() {
	printf '\nRun `/how` first, then `/skill:how`.\n' >>"$FIXTURE/skills/no-comments/SKILL.md"
}

expect_failure 'unrelated ownership' 'setup config contract' mutate_preserve_ownership
expect_failure 'per-agent ownership' 'setup config contract' mutate_override_ownership
expect_failure 'alias shape' 'setup config contract' mutate_alias_shape
expect_failure 'supported suffix list' 'setup config contract' mutate_supported_suffixes
expect_failure 'base selector validation' 'setup config contract' mutate_base_selector
expect_failure 'setup model lever' 'omp model levers' mutate_setup_lever
expect_failure 'router model lever' 'omp model levers' mutate_router_lever
expect_failure 'batch shape abandoned' 'runtime batch context' mutate_batch_shape_abandoned
expect_failure 'yield line dropped' 'runtime contract fields' mutate_yield_line_dropped
expect_failure 'yield account dropped' 'runtime contract fields' mutate_yield_account_dropped
expect_failure 'required item field' 'runtime contract fields' mutate_required_item_field
expect_failure 'gate setting dropped' 'runtime contract fields' mutate_gate_setting_dropped
expect_failure 'tool class renamed' 'runtime contract fields' mutate_tool_class_renamed
expect_failure 'agent hub api' 'agent hub api' mutate_hub_api
expect_failure 'install root' 'install root' mutate_install_root
expect_failure 'hub prescribed after a denial' 'agent hub api' mutate_hub_prescribed_after_denial
expect_failure 'install root in the port docs' 'install root' mutate_install_root_in_docs
expect_failure 'cursor tool name' 'cursor tool names' mutate_cursor_tool_name
expect_failure 'bare skill command' 'skill command form' mutate_bare_skill_command

mutate_typed_verdict() {
	sed -i '/^Pass this explicit `outputSchema` so the scores arrive typed/d' "$FIXTURE/skills/arena/SKILL.md"
}

mutate_checkpoint_claim() {
	printf '\nCheckpoint snapshots the working tree and filesystem before pausing.\n' >>"$FIXTURE/skills/poteto-mode/playbooks/pause-safely.md"
}

expect_failure 'typed verdict' 'capability wiring' mutate_typed_verdict
expect_failure 'checkpoint filesystem claim' 'capability wiring' mutate_checkpoint_claim

mutate_veto_provenance() {
	sed -i 's/ships no `session_stop` veto/ships a session_stop veto/' "$FIXTURE/README.md"
}

expect_failure 'external veto provenance' 'external capability provenance' mutate_veto_provenance

mutate_babysit_device() {
	sed -i '/^   Reading a thread is a separate surface/d' "$FIXTURE/skills/poteto-mode/playbooks/babysit.md"
}

expect_failure 'babysit device read surface' 'capability wiring' mutate_babysit_device

if [ "$fail" -ne 0 ]; then
	printf 'mutation tests: FAIL\n'
	exit 1
fi
printf 'mutation tests: PASS\n'
