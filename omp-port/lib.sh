#!/usr/bin/env bash
# Gate patterns and live-tree counts shared by sync-upstream.sh and check-port.sh.
# Port-only file, never upstream. Source it before any cd, the callers rely on that.

PAT_SLUG='\b(claude-[a-z0-9.-]+|gpt-[0-9][a-z0-9.-]*|grok-[a-z0-9.-]+|gemini-[a-z0-9.-]+|opus-[a-z0-9.-]+)\b'
PAT_CAPS='omp (has no|does not support|cannot|lacks) [A-Za-z`_.:-]+'
PAT_RESIDUE='cursor-team-kit|/deslop|run_in_background|<agent-transcripts>|~/\.cursor/|AskQuestion|cloud_base_branch|~/\.omp/skills/|~/\.omp/pstack/|environment: "cloud"'
# Every conflict git writes is bracketed by <<<<<<< and >>>>>>>, so a bare ======= needs no
# branch of its own and a seven-character setext underline stops being a false positive.
PAT_MARKER='^(<{7} |\|{7}( |$)|>{7} )'

# Skills, playbooks, and principle leaves under a plugin root, printed as one line. The
# generator and the gate call this, so they cannot disagree on what counts as a skill.
port_counts() {
	local root="$1" n p k
	n=$(find "$root/skills" -mindepth 1 -maxdepth 1 -type d | wc -l)
	p=$(find "$root/skills/poteto-mode/playbooks" -mindepth 1 -maxdepth 1 -type f -name '*.md' | wc -l)
	k=$(find "$root/skills" -mindepth 1 -maxdepth 1 -type d -name 'principle-*' | wc -l)
	printf '%s %s %s\n' "$n" "$p" "$k"
}
