#!/usr/bin/env bash
set -uo pipefail

PORT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)
REPO_ROOT=$(cd "$PORT_DIR/.." && pwd -P)
FIXTURE=$(mktemp -d)
trap 'rm -rf "$FIXTURE"' EXIT
fail=0

reset_fixture() {
	rm -rf "$FIXTURE"
	mkdir -p "$FIXTURE"
	cp -a "$REPO_ROOT/plugins/pstack/." "$FIXTURE/"
}

run_contracts() {
	CHECK_PORT_ROOT="$FIXTURE" CHECK_PORT_CONTRACTS_ONLY=1 bash "$PORT_DIR/check-port.sh"
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

expect_failure 'unrelated ownership' 'setup config contract' mutate_preserve_ownership
expect_failure 'per-agent ownership' 'setup config contract' mutate_override_ownership
expect_failure 'alias shape' 'setup config contract' mutate_alias_shape
expect_failure 'supported suffix list' 'setup config contract' mutate_supported_suffixes
expect_failure 'base selector validation' 'setup config contract' mutate_base_selector
expect_failure 'setup model lever' 'omp model levers' mutate_setup_lever
expect_failure 'router model lever' 'omp model levers' mutate_router_lever

if [ "$fail" -ne 0 ]; then
	printf 'mutation tests: FAIL\n'
	exit 1
fi
printf 'mutation tests: PASS\n'
