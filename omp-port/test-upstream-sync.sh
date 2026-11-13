#!/usr/bin/env bash
# Runs the `plan` and `build` steps of .github/workflows/upstream-sync.yml the way a Linux runner
# does, under the shell the workflow declares, against stubbed gh, git, and port scripts. Also runs
# `sync-upstream.sh check` against a gh whose upstream moves between calls. No network.
#
# Usage: bash omp-port/test-upstream-sync.sh
set -uo pipefail

PORT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)
WF="$PORT_DIR/../.github/workflows/upstream-sync.yml"
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT
fail=0

sha40() { printf "$1%.0s" $(seq 40); }
PIN=$(sha40 a)
NEW=$(sha40 b)
NEWER=$(sha40 c)
STRAY=$(sha40 e)
BUILT=$(sha40 d)

# The shell table is GitHub's documented command per `shell:` value on Linux runners.
# shellcheck disable=SC2016
EXTRACT='
const [file, job, id, out] = process.argv.slice(1);
const wf = Bun.YAML.parse(await Bun.file(file).text());
const step = (wf.jobs?.[job]?.steps ?? []).find((s) => s.id === id);
if (typeof step?.run !== "string") throw new Error(`no run step ${job}.${id} in ${file}`);
if (step.run.includes("${{")) throw new Error(`${job}.${id} interpolates an expression into run, pass it through env`);
const shell = step.shell ?? wf.jobs[job].defaults?.run?.shell ?? wf.defaults?.run?.shell ?? "";
const cmd = { "": "bash -e", bash: "bash --noprofile --norc -eo pipefail", sh: "sh -e" }[shell];
if (!cmd) throw new Error(`${job}.${id} declares shell ${shell}, which this harness does not run`);
await Bun.write(out, step.run);
console.log(cmd);
'
for id in plan build; do
	bun -e "$EXTRACT" -- "$WF" sync "$id" "$WORK/$id.sh" >"$WORK/$id.shell" ||
		{ echo "FAIL extracting sync.$id from $WF" >&2; exit 1; }
done

mkdir -p "$WORK/bin" "$WORK/port"
cat >"$WORK/bin/gh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "$*" >>"$FIX/gh.log"
calls=$(($(cat "$FIX/gh.calls" 2>/dev/null || echo 0) + 1))
echo "$calls" >"$FIX/gh.calls"
sub="$1 $2"
shift 2
filter=. state=open head=""
while [ $# -gt 0 ]; do
	case $1 in
	--jq) filter=$2 && shift ;;
	--state) state=$2 && shift ;;
	--head) head=$2 && shift ;;
	esac
	shift
done
case $sub in
"pr list")
	jq -c --arg s "$state" --arg h "$head" \
		'[.[] | select($s == "all" or (.state | ascii_downcase) == $s) | select($h == "" or .headRefName == $h)]' \
		"$FIX/prs.json" | jq -r "$filter"
	;;
"pr create")
	if [ -e "$FIX/pr-create-fails" ]; then
		echo "GraphQL: was submitted too quickly (createPullRequest)" >&2
		exit 1
	fi
	if [ -e "$FIX/pr-create-out" ]; then cat "$FIX/pr-create-out"; else echo "https://github.com/negoro26/pstack-omp/pull/99"; fi
	;;
"api repos/cursor/plugins/commits?path=pstack&sha=main&per_page="*)
	snap="$FIX/api.$calls.json"
	[ -e "$snap" ] || snap="$FIX/api.json"
	jq --argjson n "${sub##*per_page=}" '.[0:$n]' "$snap" | jq -r "$filter"
	;;
*)
	echo "gh stub: no answer for $sub" >&2
	exit 1
	;;
esac
EOF
cat >"$WORK/bin/git" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >>"$FIX/git.log"
case $1 in
config | switch | add | commit) ;;
diff) exit 1 ;;
rev-parse) printf '%s\n' "$BUILT" ;;
ls-remote)
	ref=${*: -1}
	if grep -qxF "$ref" "$FIX/remote-refs"; then
		printf '%s\t%s\n' "$BUILT" "$ref"
	elif [[ " $* " == *" --exit-code "* ]]; then
		exit 2
	fi
	;;
push)
	if [ -s "$FIX/remote-refs" ] && [[ " $* " != *" --force "* ]]; then
		echo " ! [rejected]        HEAD -> HEAD (fetch first)" >&2
		exit 1
	fi
	;;
*)
	echo "git stub: unexpected git $*" >&2
	exit 1
	;;
esac
EOF
chmod +x "$WORK/bin/gh" "$WORK/bin/git"
cat >"$WORK/port/sync-upstream.sh" <<'EOF'
[ "$1" != check ] || { cat "$FIX/head" >"$SYNC_TARGET_OUT" && cat "$FIX/commits"; }
EOF
echo 'exit 0' >"$WORK/port/check-port.sh"

# Starts case <name> in $C: upstream at the pin, no PRs, no remote branches.
new_case() {
	C="$WORK/case-$1"
	NAME=$1
	mkdir -p "$C/repo/omp-port" "$C/repo/plugins/pstack" "$C/tmp"
	cp "$WORK/port/"* "$C/repo/omp-port/"
	printf '%s\n' "$PIN" >"$C/repo/omp-port/UPSTREAM"
	printf '{"version": "0.15.36"}\n' >"$C/repo/plugins/pstack/package.json"
	printf '%s\n' "$PIN" >"$C/head"
	: >"$C/commits"
	: >"$C/tmp/commits.txt"
	: >"$C/remote-refs"
	: >"$C/output"
	echo '[]' >"$C/prs.json"
}

# Sets upstream's pstack history after the pin, newest first, and its head to the first sha.
drift() {
	local s
	printf '%s\n' "$1" >"$C/head"
	for s; do printf '%s\t2026-11-08\tupstream %s\n' "${s:0:7}" "${s:0:7}"; done >"$C/commits"
}

# Runs workflow step <id> in case $C with extra env assignments, recording $STATUS.
run_step() {
	local id=$1 shell
	shift
	read -r -a shell <"$WORK/$id.shell"
	(cd "$C/repo" && env PATH="$WORK/bin:$PATH" FIX="$C" BUILT="$BUILT" RUNNER_TEMP="$C/tmp" \
		GITHUB_OUTPUT="$C/output" "$@" "${shell[@]}" "$WORK/$id.sh") >"$C/log" 2>&1
	STATUS=$?
}

expect() {
	local what=$1
	shift
	"$@" && return 0
	printf 'FAIL %s: %s\n' "$NAME" "$what"
	sed 's/^/    /' "$C/log"
	fail=1
}
exited() { [ "$STATUS" -eq "$1" ]; }
failed() { [ "$STATUS" -ne 0 ]; }
output() { grep -qxF "$1" "$C/output"; }
no_output() { ! grep -q "^$1=" "$C/output"; }
logged() { grep -qF "$1" "$C/log"; }

new_case drift-default-target
drift "$NEW"
run_step plan
expect "exit 0" exited 0
expect "go=yes" output go=yes
expect "target is the newest commit" output "target=$NEW"

new_case orphan-branch-plan
drift "$NEW"
echo "refs/heads/sync/upstream-${NEW:0:7}" >"$C/remote-refs"
run_step plan
expect "exit 0" exited 0
expect "a branch with no PR is rebuilt, go=yes" output go=yes

new_case closed-pr-branch
drift "$NEW"
echo "refs/heads/sync/upstream-${NEW:0:7}" >"$C/remote-refs"
printf '[{"number": 12, "headRefName": "sync/upstream-%s", "state": "CLOSED"}]\n' "${NEW:0:7}" >"$C/prs.json"
run_step plan
expect "exit 0" exited 0
expect "no go" no_output go
expect "names the closed PR" logged "#12"

new_case invalid-sha-no-drift
run_step plan SHA_INPUT=invalid
expect "exit 1" exited 1
expect "no go" no_output go

new_case stray-sha-with-drift
drift "$NEW"
run_step plan SHA_INPUT="$STRAY"
expect "exit 1, a target outside the drift list is refused" exited 1
expect "no go" no_output go

new_case pin-sha-no-drift
run_step plan SHA_INPUT="$PIN"
expect "exit 0" exited 0
expect "no go" no_output go
expect "reports the pin it is already at" logged "${PIN:0:7}"

new_case pin-sha-with-drift
drift "$NEW"
run_step plan SHA_INPUT="$PIN"
expect "exit 0" exited 0
expect "no go, the pin is already built" no_output go

new_case older-target-trims-commits
drift "$NEWER" "$NEW"
run_step plan SHA_INPUT="$NEW"
expect "exit 0" exited 0
expect "target=$NEW" output "target=$NEW"
expect "commits.txt starts at the target" [ "$(cut -f1 "$C/tmp/commits.txt")" = "${NEW:0:7}" ]

new_case pr-create-fails
touch "$C/pr-create-fails"
run_step build TARGET="$NEW" SHORT="${NEW:0:7}"
expect "nonzero exit" failed
expect "no sha=" no_output sha

new_case pr-create-prints-nothing
: >"$C/pr-create-out"
run_step build TARGET="$NEW" SHORT="${NEW:0:7}"
expect "nonzero exit" failed
expect "no sha=" no_output sha

new_case orphan-branch-build
echo "refs/heads/sync/upstream-${NEW:0:7}" >"$C/remote-refs"
run_step build TARGET="$NEW" SHORT="${NEW:0:7}"
expect "exit 0" exited 0
expect "pr= is the created PR" output "pr=https://github.com/negoro26/pstack-omp/pull/99"
expect "sha= is the built commit" output "sha=$BUILT"

# upstream moves between gh calls: the first call sees NEW on top of the pin, later ones NEWER too.
new_case check-one-snapshot
pin=$(tr -d '[:space:]' <"$PORT_DIR/UPSTREAM")
snapshot() {
	local s
	for s; do
		jq -n --arg s "$s" '{sha: $s, commit: {author: {date: "2026-11-08T00:00:00Z"}, message: "upstream \($s[0:7])\n\nbody"}}'
	done | jq -s .
}
snapshot "$NEW" "$pin" >"$C/api.1.json"
snapshot "$NEWER" "$NEW" "$pin" >"$C/api.json"
PATH="$WORK/bin:$PATH" FIX="$C" SYNC_TARGET_OUT="$C/target" bash "$PORT_DIR/sync-upstream.sh" check \
	>"$C/stdout" 2>"$C/log"
STATUS=$?
expect "exit 0" exited 0
expect "lists drift" [ -s "$C/stdout" ]
expect "the target is the first commit listed" [ "$(cut -c1-7 "$C/target" 2>/dev/null)" = "$(head -n1 "$C/stdout" | cut -f1)" ]

[ "$fail" -eq 0 ] && echo "PASS upstream-sync workflow steps and check"
exit "$fail"
