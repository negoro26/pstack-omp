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

# The Babysit mode vocabulary. These two cover opposite halves of one assertion: the denial, which
# is the explanation, and the absence of the invocation, which is the thing being prevented. A gate
# that only pinned the denial would pass the moment upstream reintroduced a mode name as something
# to run, and a gate that only banned the name would pass the moment the explanation was deleted and
# left a reader with an unexplained change.
mutate_babysit_mode_invocation() {
	printf '\nRun `drive` to take it to merge-ready.\n' >>"$FIXTURE/skills/poteto-mode/playbooks/babysit.md"
}

mutate_babysit_mode_denial() {
	sed -i 's/ name no command on this runtime:/ ran nothing here:/' "$FIXTURE/skills/poteto-mode/playbooks/babysit.md"
}

expect_failure 'babysit Cursor mode invoked' 'capability wiring' mutate_babysit_mode_invocation
expect_failure 'babysit mode denial removed' 'capability wiring' mutate_babysit_mode_denial

# The upstream probes answer a question about omp-port/rules.sed, not about the generated tree, so
# the fixture harness above cannot reach them: it mutates plugins/pstack and runs the gate with
# CHECK_PORT_CONTRACTS_ONLY, which exits long before any upstream text is read. These two run the
# real gate against a mutated copy of rules.sed instead, which is why they need the clone.
STALE_RULES=$(mktemp)
STALE_EXEMPT_FILE=$(mktemp)
STALE_PATCHES=$(mktemp -d)
# The pin's parent is a real cursor/plugins commit that touched pstack/, so it is a legal sync
# target and differs from the pin, which is what `target builds` needs in order to run at all.
PIN_PARENT=$(git -C "${CANON:-/tmp/cursor-plugins}" rev-parse "$(tr -d '[:space:]' <"$PORT_DIR/UPSTREAM")^" 2>/dev/null || true)
trap 'rm -rf "$FIXTURE" "$FIXTURE_DOCS" "$STALE_RULES" "$STALE_EXEMPT_FILE" "$STALE_PATCHES"' EXIT

expect_stale_failure() {
	local name=$1 output status
	# CHECK_PORT_SKIP_MUTATIONS is not optional here. These two run the gate past the contract-only
	# exit, so they reach the gate's own `gate mutations` step, which runs this harness, which runs
	# them again. Without the guard the two call each other until the process table is gone.
	if output=$(CANON="${CANON:-/tmp/cursor-plugins}" RULES="$STALE_RULES" STALE_EXEMPT="$STALE_EXEMPT_FILE" CHECK_PORT_SKIP_MUTATIONS=1 \
		bash "$PORT_DIR/check-port.sh" 2>&1); then status=0; else status=$?; fi
	if [ "$status" -eq 0 ]; then
		printf 'mutation tests: %s unexpectedly passed\n' "$name"
		fail=1
	elif ! printf '%s\n' "$output" | grep -qF 'rule staleness'; then
		printf 'mutation tests: %s failed for the wrong reason\n%s\n' "$name" "$output"
		fail=1
	else
		printf 'mutation tests: %s rejected\n' "$name"
	fi
}

# `target builds` is skipped when the target is the pin, because `reproducible` has already built
# exactly that tree. Testing it therefore needs a target that differs, so this uses the pin's parent
# on cursor/plugins, which is a real commit that touched pstack/ and so is a legal sync target.
expect_target_failure() {
	local name=$1 output status canon="${CANON:-/tmp/cursor-plugins}"
	# CANON is resolved into a local first: an inline env assignment does not affect how a later
	# "$CANON" on the same line expands, so writing it inline silently passes an empty clone path
	# and every upstream assertion silently skips.
	if output=$(CANON="$canon" RULES="$STALE_RULES" STALE_EXEMPT="$STALE_EXEMPT_FILE" \
		PATCH_DIR="$STALE_PATCHES" CHECK_PORT_SKIP_MUTATIONS=1 \
		bash "$PORT_DIR/check-port.sh" "$canon" "${2:-$PIN_PARENT}" 2>&1); then status=0; else status=$?; fi
	if [ "$status" -eq 0 ]; then
		printf 'mutation tests: %s unexpectedly passed\n' "$name"
		fail=1
	elif ! printf '%s\n' "$output" | grep -qF 'target builds'; then
		printf 'mutation tests: %s failed for the wrong reason\n%s\n' "$name" "$output"
		fail=1
	else
		printf 'mutation tests: %s rejected\n' "$name"
	fi
}

if [ -d "${CANON:-/tmp/cursor-plugins}/.git" ]; then
	# A rule whose left-hand side matches nothing upstream is the exact shape of the failure this
	# gate exists for: sed exits 0, the tree builds, and the translation silently stops happening.
	cp "$PORT_DIR/rules.sed" "$STALE_RULES"
	printf '%s\n' 's#a sentence upstream has never contained#a replacement nobody sees#' >>"$STALE_RULES"
	cp "$PORT_DIR/stale-exempt.tsv" "$STALE_EXEMPT_FILE"
	expect_stale_failure 'rule matching no upstream text'

	# Two rows that used to exempt every rule. index() returns 1 for an empty needle, so a blank
	# row matched everything; and a run of twenty spaces is twenty characters long and index() finds
	# it in almost any rule, so a length floor alone does not save it. The guards are two predicates
	# in a matcher, which is exactly the kind of thing that gets deleted as noise, so both get a
	# test. The fragment here is deliberately long enough to clear the length floor.
	cp "$PORT_DIR/rules.sed" "$STALE_RULES"
	printf '%s\n' 's#a different sentence upstream has never contained#another replacement#' >>"$STALE_RULES"
	cp "$PORT_DIR/stale-exempt.tsv" "$STALE_EXEMPT_FILE"
	printf ' \t                     \n' >>"$STALE_EXEMPT_FILE"
	expect_stale_failure 'whitespace-only exemption row exempting everything'

	# And the same file missing its trailing newline, which made the mutation above a byte-for-byte
	# duplicate of the one before it: the append landed on the end of an unterminated final line and
	# changed nothing. Both rows are live assertions only if the file ends in a newline.
	cp "$PORT_DIR/rules.sed" "$STALE_RULES"
	printf '%s\n' 's#a third sentence upstream has never contained#a third replacement#' >>"$STALE_RULES"
	cp "$PORT_DIR/stale-exempt.tsv" "$STALE_EXEMPT_FILE"
	printf '\n' >>"$STALE_EXEMPT_FILE"
	expect_stale_failure 'blank exemption row exempting everything'

	# The target-build assertion is the one that closes the hole where every upstream probe read
	# text directly and none of them ran omp-port/patches, so an upstream commit reordering a line a
	# patch matches on passed the gate with a sync that could not be applied. The reproducer is a
	# patch whose context line has been reworded, which is what an upstream edit looks like from
	# here.
	cp "$PORT_DIR/rules.sed" "$STALE_RULES"
	cp "$PORT_DIR/patches/zz-live-runtime-routing.patch" "$STALE_PATCHES/zz-live-runtime-routing.patch"
	printf '\n@@ -1,1 +1,1 @@\n-a context line that does not exist upstream\n+b replacement\n' \
		>>"$STALE_PATCHES/zz-live-runtime-routing.patch"
	cp "$PORT_DIR/stale-exempt.tsv" "$STALE_EXEMPT_FILE"
	expect_target_failure 'patch context no longer matches upstream'
else
	printf 'mutation tests: SKIP staleness mutations, no cursor/plugins clone at %s\n' "${CANON:-/tmp/cursor-plugins}"
fi

if [ "$fail" -ne 0 ]; then
	printf 'mutation tests: FAIL\n'
	exit 1
fi
printf 'mutation tests: PASS\n'
