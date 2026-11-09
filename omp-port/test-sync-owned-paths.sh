#!/usr/bin/env bash
set -euo pipefail

PORT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT
fail=0

init_repo() {
	git -C "$1" init -q
	git -C "$1" config user.name 'Sync fixture'
	git -C "$1" config user.email sync-fixture@example.invalid
	git -C "$1" config commit.gpgsign false
	git -C "$1" config core.hooksPath /dev/null
	git -C "$1" config core.quotePath true
	git -C "$1" config status.renames true
}

mkdir -p "$WORK/canon/pstack/"{.cursor-plugin,skills/poteto-mode/playbooks,skills/upstream,agents}
printf '{"version":"1.0.0"}\n' >"$WORK/canon/pstack/.cursor-plugin/plugin.json"
printf 'playbook\n' >"$WORK/canon/pstack/skills/poteto-mode/playbooks/example.md"
printf 'rename source\n' >"$WORK/canon/pstack/skills/upstream/rename.txt"
printf 'agent\n' >"$WORK/canon/pstack/agents/example.md"
init_repo "$WORK/canon"
git -C "$WORK/canon" add .
git -C "$WORK/canon" commit -qm 'Fixture pin'
PIN=$(git -C "$WORK/canon" rev-parse HEAD)
printf 'new upstream content\n' >"$WORK/canon/pstack/skills/upstream/target.txt"
git -C "$WORK/canon" add .
git -C "$WORK/canon" commit -qm 'Fixture target'
TARGET=$(git -C "$WORK/canon" rev-parse HEAD)
export TARGET

gh() { printf '%s\t%s\t2026-01-01\tfixture target\n' "$TARGET" "${TARGET:0:7}"; }
export -f gh
git() {
	if [ "${SYNC_FIXTURE_STATUS_FAIL:-}" = 1 ] && [ "${1:-}" = status ]; then
		printf 'fixture status failure\n' >&2
		return 73
	fi
	command git "$@"
}
export -f git

mkdir -p "$WORK/template/"{omp-port/patches,plugins/pstack,.omp-plugin}
cp "$PORT_DIR/"{sync-upstream.sh,lib.sh} "$WORK/template/omp-port/"
git -C "$WORK/canon" archive "$PIN" pstack/skills pstack/agents |
	tar -x --strip-components=1 -C "$WORK/template/plugins/pstack"
for p in skills/pstack-omp skills/omp-mechanics 'skills/local[.]owner'; do
	mkdir -p "$WORK/template/plugins/pstack/$p"
	printf 'owned content\n' >"$WORK/template/plugins/pstack/$p/SKILL.md"
done
printf 'owned file\n' >"$WORK/template/plugins/pstack/skills/local-file"
printf '%s\t-\n' skills/pstack-omp skills/omp-mechanics 'skills/local[.]owner' skills/local-file \
	>"$WORK/template/omp-port/owned.txt"
printf '%s\n' "$PIN" >"$WORK/template/omp-port/UPSTREAM"
cp "$PORT_DIR/rules.sed" "$WORK/template/omp-port/rules.sed"
: >"$WORK/template/omp-port/excluded.txt"
printf '{"version":"1.0.0"}\n' >"$WORK/template/plugins/pstack/package.json"
printf '{"metadata":{"version":"1.0.0"},"plugins":[{"name":"pstack","version":"1.0.0","description":"fixture"}]}\n' \
	>"$WORK/template/.omp-plugin/marketplace.json"
init_repo "$WORK/template"
git -C "$WORK/template" add .
git -C "$WORK/template" commit -qm 'Fixture port'

run_case() {
	local name="$1" expected="$2" mutation="$3" dir="$WORK/$1" status=0 ok=1 p reviewed
	local status_fail=0
	cp -a "$WORK/template" "$dir"
	FIXTURE="$dir"
	"$mutation"
	cp -a "$dir/plugins/pstack" "$dir/before"
	cp "$dir/omp-port/UPSTREAM" "$dir/pin.before"
	CANON="$WORK/canon" RULES="$dir/omp-port/rules.sed" OWNED="$dir/omp-port/owned.txt" \
		EXCLUDED="$dir/omp-port/excluded.txt" PATCH_DIR="$dir/omp-port/patches" SYNC_FIXTURE_STATUS_FAIL="$status_fail" \
		bash "$dir/omp-port/sync-upstream.sh" "$TARGET" >"$dir/out" 2>&1 || status=$?
	if [ "$expected" != allow ]; then
		if [ "$expected" = reject ]; then
			[ "$status" -ne 0 ] || ok=0
			grep -qF 'uncommitted changes the build would destroy' "$dir/out" || ok=0
		else
			[ "$status" -eq 73 ] || ok=0
			grep -qF 'fixture status failure' "$dir/out" || ok=0
		fi
		cmp -s "$dir/pin.before" "$dir/omp-port/UPSTREAM" || ok=0
		diff -r "$dir/before" "$dir/plugins/pstack" >>"$dir/out" 2>&1 || ok=0
	else
		[ "$status" -eq 0 ] || ok=0
		[ "$(cat "$dir/omp-port/UPSTREAM")" = "$TARGET" ] || ok=0
		cmp -s "$WORK/canon/pstack/skills/upstream/target.txt" \
			"$dir/plugins/pstack/skills/upstream/target.txt" || ok=0
		while IFS=$'\t' read -r p reviewed; do
			diff -r "$dir/before/$p" "$dir/plugins/pstack/$p" >>"$dir/out" 2>&1 || ok=0
		done <"$dir/omp-port/owned.txt"
	fi
	if [ "$ok" -eq 1 ]; then
		printf 'sync owned paths: %s PASS\n' "$name"
	else
		printf 'sync owned paths: %s FAIL, expected %s, exit %s\n' "$name" "$expected" "$status"
		cat "$dir/out"
		fail=1
	fi
}

nothing() { :; }

status_failure() { status_fail=1; }

untracked_prefix_sibling() {
	mkdir -p "$FIXTURE/plugins/pstack/skills/pstack-omp-audit"
	printf 'irreplaceable local edit\000\377\n' >"$FIXTURE/plugins/pstack/skills/pstack-omp-audit/local.txt"
}

owned_edit() {
	printf 'local owned edit\n' >>"$FIXTURE/plugins/pstack/skills/pstack-omp/SKILL.md"
}

owned_quoted_name() {
	printf 'local bytes\000\377\n' >"$FIXTURE/plugins/pstack/skills/pstack-omp/"$'quote"\tline\n\377notes.txt'
}

unowned_quoted_name() {
	mkdir -p "$FIXTURE/plugins/pstack/skills/"$'pstack-omp-audit"\tline\n\377'
	printf 'local bytes\000\377\n' >"$FIXTURE/plugins/pstack/skills/"$'pstack-omp-audit"\tline\n\377/local.txt'
}

owned_file_edit() {
	printf 'local file edit\n' >>"$FIXTURE/plugins/pstack/skills/local-file"
}

owned_file_suffix() {
	printf 'not owned\n' >"$FIXTURE/plugins/pstack/skills/local-file.bak"
}

literal_owned_edit() {
	printf 'literal owned edit\n' >>"$FIXTURE/plugins/pstack/skills/local[.]owner/SKILL.md"
}

regex_lookalike() {
	mkdir -p "$FIXTURE/plugins/pstack/skills/local.owner"
	printf 'not owned\n' >"$FIXTURE/plugins/pstack/skills/local.owner/local.txt"
}

rename_out_of_owned() {
	git -C "$FIXTURE" mv plugins/pstack/skills/pstack-omp/SKILL.md plugins/pstack/skills/pstack-omp-audit.md
}

rename_into_owned() {
	git -C "$FIXTURE" mv plugins/pstack/skills/upstream/rename.txt plugins/pstack/skills/pstack-omp/renamed.txt
}

rename_within_owned() {
	git -C "$FIXTURE" mv plugins/pstack/skills/pstack-omp/SKILL.md plugins/pstack/skills/pstack-omp/renamed.md
}

agent_edit() {
	printf 'local agent edit\n' >>"$FIXTURE/plugins/pstack/agents/example.md"
}

run_case baseline allow nothing
run_case untracked-prefix-sibling reject untracked_prefix_sibling
run_case owned-edit allow owned_edit
run_case owned-quoted-name allow owned_quoted_name
run_case unowned-quoted-name reject unowned_quoted_name
run_case owned-file-edit allow owned_file_edit
run_case owned-file-suffix reject owned_file_suffix
run_case literal-owned-edit allow literal_owned_edit
run_case regex-lookalike reject regex_lookalike
run_case rename-out-of-owned reject rename_out_of_owned
run_case rename-into-owned reject rename_into_owned
run_case rename-within-owned allow rename_within_owned
run_case agent-edit reject agent_edit
run_case status-error status-error status_failure

[ "$fail" -eq 0 ] || exit 1
printf 'sync owned paths: PASS\n'
