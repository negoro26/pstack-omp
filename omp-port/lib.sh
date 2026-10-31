#!/usr/bin/env bash
# The build pipeline, gate patterns, and live-tree counts shared by sync-upstream.sh and
# check-port.sh. Port-only file, never upstream. Paths resolve from this file's own location, so
# sourcing it before or after a cd makes no difference.

PORT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)
REPO_ROOT=$(cd "$PORT_DIR/.." && pwd -P)
CANON="${CANON:-/tmp/cursor-plugins}"
RULES="${RULES:-$PORT_DIR/rules.sed}"
UPSTREAM_URL=https://github.com/cursor/plugins

PAT_SLUG='\b(claude-[a-z0-9.-]+|gpt-[0-9][a-z0-9.-]*|grok-[a-z0-9.-]+|gemini-[a-z0-9.-]+|opus-[a-z0-9.-]+)\b'
PAT_CAPS='omp (has no|does not support|cannot|lacks) [A-Za-z`_.:-]+'
PAT_RESIDUE='cursor-team-kit|/deslop|run_in_background|<agent-transcripts>|~/\.cursor/|AskQuestion|cloud_base_branch|~/\.omp/skills/|~/\.omp/pstack/|environment: "cloud"'
# Every conflict git writes is bracketed by <<<<<<< and >>>>>>>, so a bare ======= needs no
# branch of its own and a seven-character setext underline stops being a false positive.
PAT_MARKER='^(<{7} |\|{7}( |$)|>{7} )'
# The last model-slug rule in rules.sed is a catch-all, so an upstream slug nobody wrote a tiered
# rule for still comes out model-agnostic. What it rewrote is reported, never silently accepted,
# and it is found by rebuilding without it and grepping for what it would have matched. Its
# replacement text is how the line is identified, so it has to stay unique in rules.sed, and its
# left side is read off that line rather than restated here where the two could drift apart.
CATCHALL_REPL='your configured model for this role'
catchall_pat() {
	grep -F "$CATCHALL_REPL" "$RULES" 2>/dev/null | head -n1 |
		sed -E "s@^s(.)(.*)\1${CATCHALL_REPL}\1g?\$@\2@"
}

# Skills, playbooks, and principle leaves under a plugin root, printed as one line. The
# generator and the gate call this, so they cannot disagree on what counts as a skill.
port_counts() {
	local root="$1" n p k
	n=$(find "$root/skills" -mindepth 1 -maxdepth 1 -type d | wc -l)
	p=$(find "$root/skills/poteto-mode/playbooks" -mindepth 1 -maxdepth 1 -type f -name '*.md' | wc -l)
	k=$(find "$root/skills" -mindepth 1 -maxdepth 1 -type d -name 'principle-*' | wc -l)
	printf '%s %s %s\n' "$n" "$p" "$k"
}

# The port is a build, not a maintained tree. plugins/pstack/{skills,agents} is build_tree(pin)
# plus the paths in owned.txt, so upstream text can never conflict with port text. rules.sed
# rewrites mechanics, patches/ carries port-only code, owned.txt carries port-only files.

ensure_canon() {
	if [ ! -d "$CANON/.git" ]; then
		git clone --depth 1 --filter=blob:none --sparse "$UPSTREAM_URL" "$CANON" || return 1
		git -C "$CANON" sparse-checkout set pstack || return 1
	fi
	local s
	for s in "$@"; do
		git -C "$CANON" cat-file -e "$s^{commit}" 2>/dev/null ||
			git -C "$CANON" fetch --depth 1 --filter=blob:none origin "$s" || return 1
	done
}

# Step 1, upstream text as it is, with pstack/ stripped so skills and agents land at the root.
extract_upstream() {
	local sha="$1" work="$2"
	git -C "$CANON" archive "$sha" pstack/skills pstack/agents |
		tar -x --strip-components=1 -C "$work" || return 1
	[ -d "$work/skills" ] && [ -d "$work/agents" ]
}

# Step 2, the substitution table. Binary files are skipped rather than corrupted, which is what
# grep -I reports when the empty pattern does not match. One sed takes a batch of files, and -i
# implies -s, so each file is still its own stream and a range address ends with its file.
apply_rules() {
	local work="$1" rules="$2"
	grep -rIlZ '' "$work" |
		xargs -0 -r -n 64 -P "$(getconf _NPROCESSORS_ONLN 2>/dev/null || echo 2)" sed -E -i -f "$rules"
}

# Step 3, the port's own code. A patch that no longer applies is a hard stop, because the
# alternative is shipping a tree that silently lost the port's behavior. --force keeps patch from
# asking on the terminal: without it a missing file waits at `File to patch:` and a hunk that looks
# reversed waits at `Assume -R?`. --batch is not the same thing, because it answers that second
# question yes and applies the hunk backwards.
apply_patches() {
	# PATCH_DIR is overridable for the same reason RULES is: the mutation harness has to be able to
	# feed the build a patch set that does not apply without editing the repository to do it.
	local work="$1" p
	for p in "${PATCH_DIR:-$PORT_DIR/patches}"/*.patch; do
		[ -e "$p" ] || continue
		patch -p1 -d "$work" --force --fuzz=0 --no-backup-if-mismatch --reject-file=- -i "$p" || return 1
	done
}

build_tree() {
	local sha="$1" work="$2"
	extract_upstream "$sha" "$work" &&
		apply_rules "$work" "$RULES" &&
		apply_patches "$work"
}

# owned.txt is `<path><TAB><reviewed upstream object>`, one owned path per line relative to
# plugins/pstack. The object is the upstream tree or blob sha a maintainer last read for that
# path, or `-` when upstream has no such path. Comments and blanks are the file's, not the
# caller's problem.
OWNED_FILE="${OWNED:-$PORT_DIR/owned.txt}"
owned_reviewed() {
	[ -f "$OWNED_FILE" ] || return 0
	awk -F'\t' '{ sub(/#.*/, ""); gsub(/^[[:space:]]+|[[:space:]]+$/, "", $1); gsub(/[[:space:]]/, "", $2) }
		$1 != "" { print $1 "\t" ($2 == "" ? "?" : $2) }' "$OWNED_FILE"
}
owned_paths() { owned_reviewed | cut -f1; }

# Owned paths whose upstream object at <target> is not the one recorded as reviewed, as
# "<owned-path>\t<reviewed>\t<now>".
#
# Ownership is deliberate and the build is right to discard the built copy, but that is exactly what
# makes an upstream edit to an owned path disappear with no conflict, no patch failure and no gate
# failure. install_tree restores the checked-in copy over whatever the build produced; reproducible
# copies owned paths out of the live tree before diffing, so it cannot see the difference; and the
# resulting tree is byte-identical to the build by construction. A commit count between the pin and
# the target cannot see it either once the pin has moved past the commit, which is how ab1f702's
# edit to setup-pstack went unreviewed. The reviewed object does not move with the pin.
owned_drift() {
	local target="$1" rel reviewed now
	while IFS=$'\t' read -r rel reviewed; do
		now=$(git -C "$CANON" rev-parse --verify -q "$target:pstack/$rel" 2>/dev/null) || now=-
		[ "$now" = "$reviewed" ] || printf '%s\t%s\t%s\n' "$rel" "$reviewed" "$now"
	done < <(owned_reviewed)
}

# Step 4. The rm is what makes the build authoritative: a file upstream deleted, or one a
# maintainer hand-added, is gone before the new tree lands. The owned paths are carried across it
# from the worktree, so an owned file that is not committed yet survives its first build. Only a
# path missing from the worktree falls back to HEAD, and one missing from both is a broken
# owned.txt and stops the build.
install_tree() {
	local work="$1" keep p src
	keep=$(mktemp -d)
	while IFS= read -r p; do
		src="$REPO_ROOT/plugins/pstack/$p"
		[ -e "$src" ] || continue
		mkdir -p "$keep/$(dirname "$p")"
		cp -a "$src" "$keep/$p" || return 1
	done < <(owned_paths)
	rm -rf "$REPO_ROOT/plugins/pstack/skills" "$REPO_ROOT/plugins/pstack/agents" || return 1
	mv "$work/skills" "$work/agents" "$REPO_ROOT/plugins/pstack/" || return 1
	while IFS= read -r p; do
		src="$REPO_ROOT/plugins/pstack/$p"
		if [ -e "$keep/$p" ]; then
			rm -rf "$src"
			mkdir -p "$(dirname "$src")"
			cp -a "$keep/$p" "$src" || return 1
		else
			git -C "$REPO_ROOT" checkout HEAD -- "plugins/pstack/$p" || return 1
		fi
	done < <(owned_paths)
	rm -rf "$keep"
}

# Distinct slugs the catch-all rewrote at <sha>, one per line.
untiered_slugs() {
	local sha="$1" rules work pat st=0
	pat=$(catchall_pat)
	[ -n "$pat" ] || return 0
	rules=$(mktemp)
	work=$(mktemp -d)
	grep -vF "$CATCHALL_REPL" "$RULES" >"$rules" || true
	if extract_upstream "$sha" "$work" && apply_rules "$work" "$rules"; then
		{ grep -rohIE "$pat" "$work" || true; } | sort -u
	else
		st=1
	fi
	rm -rf "$work" "$rules"
	return "$st"
}

# One rule per line as "<line-number>\t<rule>", comments and blanks dropped and a trailing
# backslash continuation joined onto the rule it belongs to, so every record is something sed can
# parse on its own. The join is RULE_NL rather than a newline, so a multi-line `a\` record stays one
# line here; a caller handing the record to sed turns RULE_NL back into a newline first.
RULE_NL=$'\036'
rule_records() {
	awk '
		function flush() { if (buf != "") { printf "%d\t%s\n", start, buf; buf = "" } }
		{
			if (buf != "") {
				buf = buf "\036" $0
				if ($0 !~ /\\[[:space:]]*$/) flush()
				next
			}
			if ($0 ~ /^[[:space:]]*#/ || $0 ~ /^[[:space:]]*$/) next
			start = NR; buf = $0
			if ($0 !~ /\\[[:space:]]*$/) flush()
		}
		END { flush() }
	' "$RULES"
}

# One sed command split into its parts. parse(r) sets P_addr (the address, verbatim, possibly
# empty), P_cmd, and for `s` P_delim, P_lhs, P_rhs and P_flags, each verbatim with its escapes,
# and returns 0 when the record is not a command it can split. lhs_shape and rhs_shape read the
# parts the way sed -E does: a backslash takes the next character with it, and a bracket
# expression is one atom whatever it holds.
RULE_AWK='
function upto(s, i, d,   c) {
	while (i <= length(s)) {
		c = substr(s, i, 1)
		if (c == "\\") { i += 2; continue }
		if (c == d) return i
		i++
	}
	return 0
}
function parse(r,   i, j, k, d, c) {
	P_addr = P_cmd = P_delim = P_lhs = P_rhs = P_flags = ""
	i = 1
	while (1) {
		c = substr(r, i, 1)
		if (c == "/") { d = "/"; j = upto(r, i + 1, d) }
		else if (c == "\\") { d = substr(r, i + 1, 1); j = upto(r, i + 2, d) }
		else break
		if (!j) return 0
		i = j + 1
		if (substr(r, i, 1) != ",") break
		i++
	}
	P_addr = substr(r, 1, i - 1)
	P_cmd = substr(r, i, 1)
	if (P_cmd != "s") return P_cmd != ""
	d = substr(r, i + 1, 1)
	j = upto(r, i + 2, d); if (!j) return 0
	k = upto(r, j + 1, d); if (!k) return 0
	P_delim = d
	P_lhs = substr(r, i + 2, j - i - 2)
	P_rhs = substr(r, j + 1, k - j - 1)
	P_flags = substr(r, k + 1)
	return 1
}
function bracket_end(s, i,   j, k) {
	j = i + 1
	if (substr(s, j, 1) == "^") j++
	if (substr(s, j, 1) == "]") j++
	while (j <= length(s)) {
		if (substr(s, j, 1) == "[" && index(":.=", substr(s, j + 1, 1))) {
			k = index(substr(s, j + 2), substr(s, j + 1, 1) "]")
			if (k) { j += k + 3; continue }
		}
		if (substr(s, j, 1) == "]") return j
		j++
	}
	return length(s)
}
# L_wild is "" with no `.*` or `.+`, "eol" when every one runs to the end of the line, and "mid"
# when one is followed by more pattern and the left side does not end in `$`, so the match stops at
# the last place that pattern occurs on the line. L_bare is 1 when a group holds no alternation and
# carries no quantifier, which makes its parentheses a group that groups nothing.
function lhs_shape(s,   i, n, c, depth, alt, after) {
	L_wild = ""; L_bare = 0; depth = 0
	n = length(s); i = 1
	while (i <= n) {
		c = substr(s, i, 1)
		if (c == "\\") { i += 2; continue }
		if (c == "[") { i = bracket_end(s, i) + 1; continue }
		if (c == "(") { alt[++depth] = 0; i++; continue }
		if (c == "|") { if (depth) alt[depth] = 1; i++; continue }
		if (c == ")") {
			if (depth && !alt[depth] && substr(s, i + 1, 1) !~ /^[*+?{]$/) L_bare = 1
			if (depth) depth--
			i++; continue
		}
		if (c == "." && substr(s, i + 1, 1) ~ /^[*+]$/) {
			after = substr(s, i + 2)
			sub(/^[)?*+]+/, "", after)
			if (after == "" || after == "$" || substr(s, n, 1) == "$" && substr(s, n - 1, 1) != "\\") {
				if (L_wild == "") L_wild = "eol"
			} else L_wild = "mid"
			i += 2; continue
		}
		i++
	}
}
function rhs_shape(s,   i, c) {
	R_amp = R_backref = R_paren = 0
	i = 1
	while (i <= length(s)) {
		c = substr(s, i, 1)
		if (c == "\\") { if (substr(s, i + 1, 1) ~ /^[0-9]$/) R_backref = 1; i += 2; continue }
		if (c == "&") R_amp = 1
		if (c == "(") R_paren = 1
		i++
	}
}
'

# The rule table, one record per line as
# "<line>\t<cmd>\t<wild>\t<amp>\t<paren>\t<span-program>\t<rule>":
#   wild          `-`, `eol`, or `mid`, from lhs_shape.
#   amp           1 when the replacement holds a bare `&`, which splices the whole match back in.
#   paren         1 when the left side has a group that groups nothing, the replacement adds a
#                 literal `(`, and no backreference carries the group: a literal parenthesis
#                 written as an ERE group, which the replacement then doubles.
#   span-program  a sed -n script printing what this rule's own left side matches, each match
#                 between \x01 and \x02, or `-` when the record has no address and is not `s`.
rule_table() {
	rule_records | awk "$RULE_AWK"'
		{
			n = substr($0, 1, index($0, "\t") - 1)
			r = substr($0, index($0, "\t") + 1)
			wild = "-"; amp = paren = 0; prog = "-"
			if (parse(r) && P_cmd == "s") {
				lhs_shape(P_lhs); rhs_shape(P_rhs)
				if (L_wild != "") wild = L_wild
				amp = R_amp
				paren = L_bare && R_paren && !R_backref
				prog = P_addr "s" P_delim P_lhs P_delim "\\x01&\\x02" P_delim P_flags "p"
			} else if (P_addr != "") prog = P_addr "s/^.*$/\\x01&\\x02/p"
			printf "%s\t%s\t%s\t%d\t%d\t%s\t%s\n", n, P_cmd, wild, amp, paren, prog, r
		}'
}

# The rules with every command marked by its own line number: a substitution writes `@<line>@`
# ahead of its replacement, `a` and `i` ahead of their text, and `d` and `c` write it as their
# text. Appended and changed text never reaches a later rule, so marking those cannot change what
# any other rule sees. Line for line with RULES, so `head -n` of it is the same prefix of rules.
mark_rules() {
	awk "$RULE_AWK"'
		cont { if (pending != "") { $0 = pending $0; pending = "" } cont = ($0 ~ /\\[[:space:]]*$/); print; next }
		/^[[:space:]]*(#|$)/ { print; next }
		{
			cont = ($0 ~ /\\[[:space:]]*$/)
			if (!parse($0)) { print; next }
			m = "@" NR "@"
			rest = substr($0, length(P_addr) + 2)
			if (P_cmd == "s") print P_addr "s" P_delim P_lhs P_delim m P_rhs P_delim P_flags
			else if (P_cmd == "d") print P_addr "c " m
			else if (P_cmd ~ /^[aic]$/ && rest ~ /^\\[[:space:]]*$/) { pending = m; print }
			else if (P_cmd ~ /^[aic]$/) { sub(/^[[:space:]]*/, "", rest); print P_addr P_cmd " " m rest }
			else print
		}' "$RULES"
}

# Every text file of an extract, each newline-terminated so no file joins its last line to the
# next file's first. The isolation probes read this one stream rather than every file.
text_blob() {
	grep -rIlZ '' "$1" | xargs -0 -r awk 1
}

# What a span program printed, one match per line.
spans_of() {
	awk 'BEGIN { FS = "\001" } { for (i = 2; i <= NF; i++) { j = index($i, "\002"); print (j ? substr($i, 1, j - 1) : $i) } }'
}

# Rules that fire nothing in a marked build of the upstream text at <sha>, as
# "<line-number>\t<rule>". A rule whose left-hand side no longer matches changes nothing and sed
# still exits 0, so without this the build cannot distinguish a rule that substituted from one
# upstream has outrun. One marked build answers for every rule: a marker with no occurrence in the
# tree is a rule that matched nothing. Why it matched nothing is dead_rule_causes' question.
dead_rules() {
	local sha="$1" work marked fired st=0
	work=$(mktemp -d)
	marked=$(mktemp)
	mark_rules >"$marked"
	if extract_upstream "$sha" "$work" && apply_rules "$work" "$marked"; then
		fired=$(grep -rhoE '@[0-9]+@' "$work" | sort -u)
		while IFS=$'\t' read -r n rule; do
			grep -qxF "@$n@" <<<"$fired" || printf '%s\t%s\n' "$n" "$rule"
		done < <(rule_records)
	else
		st=1
	fi
	rm -rf "$work" "$marked"
	return "$st"
}

# Why each dead rule fired nothing at <sha>, as "<line>\t<cause>\t<by>\t<span>". <dead> is
# dead_rules' output. Every dead rule gets exactly one cause, decided on the raw upstream text with
# the same sed and -E the build uses, so a pattern cannot mean one thing here and another there:
#   stale      the rule changes nothing in raw upstream, so it can never fire again.
#   catch-all  the model-slug catch-all, which the tiered slug rules above it starve by design.
#   shadowed   earlier rules rewrite this rule's own match: its raw matches, fed alone through every
#              rule above it, come out changed. <by> names the rules that changed them and <span>
#              is one raw match they changed. A duplicate rule, or a narrower rule placed above a
#              broader one, lands here, and it never fires while that order stands.
#   consumed   earlier rules rewrite the sentence around its match but leave the match itself
#              alone. These are the token nets under the whole-sentence rules, healthy by design:
#              they fire when a sentence rule misses.
# Exits 1, printing nothing, when the extract or any rule fails to parse, so a caller cannot read
# an empty result as "nothing is stale".
dead_rule_causes() {
	local sha="$1" dead="$2" work catchall n rule prog by span st=0
	[ -n "$dead" ] || return 0
	work=$(mktemp -d)
	if ! mkdir "$work/up" || ! extract_upstream "$sha" "$work/up"; then
		rm -rf "$work"
		return 1
	fi
	text_blob "$work/up" >"$work/blob"
	mark_rules >"$work/marked"
	catchall=$(grep -nF "$CATCHALL_REPL" "$RULES" | head -n1 | cut -d: -f1)
	declare -A progs
	while IFS=$'\t' read -r n _ _ _ _ prog _; do progs[$n]=$prog; done < <(rule_table)
	while IFS=$'\t' read -r n rule; do
		[ -n "$n" ] || continue
		printf '%s\n' "${rule//$RULE_NL/$'\n'}" >"$work/rule.sed"
		if ! sed -E -f "$work/rule.sed" "$work/blob" >"$work/out" 2>/dev/null; then
			st=1
			break
		fi
		if cmp -s "$work/out" "$work/blob"; then
			printf '%s\tstale\t-\t-\n' "$n" >>"$work/causes"
			continue
		fi
		if [ "$n" = "$catchall" ]; then
			printf '%s\tcatch-all\t-\t-\n' "$n" >>"$work/causes"
			continue
		fi
		prog=${progs[$n]:--}
		if [ "$prog" != - ]; then
			sed -nE "$prog" "$work/blob" | spans_of | LC_ALL=C sort -u >"$work/spans"
			head -n "$((n - 1))" "$RULES" >"$work/prefix.sed"
			sed -E -f "$work/prefix.sed" "$work/spans" >"$work/after"
			if ! cmp -s "$work/spans" "$work/after"; then
				head -n "$((n - 1))" "$work/marked" >"$work/prefix.sed"
				by=$(sed -E -f "$work/prefix.sed" "$work/spans" | grep -oE '@[0-9]+@' | tr -d @ |
					sort -nu | sed 's/^/rules.sed:/' | paste -sd ' ' -)
				span=$(paste "$work/spans" "$work/after" | awk -F'\t' '$1 != $2 { print $1; exit }')
				printf '%s\tshadowed\t%s\t%s\n' "$n" "$by" "$span" >>"$work/causes"
				continue
			fi
		fi
		printf '%s\tconsumed\t-\t-\n' "$n" >>"$work/causes"
	done <<<"$dead"
	[ "$st" -ne 0 ] || cat "$work/causes" 2>/dev/null
	rm -rf "$work"
	return "$st"
}

# What each wildcard rule's own left side matches in the raw upstream text at <sha>, as
# "<line>\t<span>", sorted. A `.*` or `.+` swallows whatever upstream writes inside it, so a
# sentence upstream adds there is dropped with no rule changing and no probe above noticing. These
# spans are what the swallow ledger hashes.
wildcard_spans() {
	local sha="$1" work n prog
	work=$(mktemp -d)
	if ! mkdir "$work/up" || ! extract_upstream "$sha" "$work/up"; then
		rm -rf "$work"
		return 1
	fi
	text_blob "$work/up" >"$work/blob"
	while IFS=$'\t' read -r n _ wild _ _ prog _; do
		[ "$wild" != - ] || continue
		sed -nE "$prog" "$work/blob" | spans_of | LC_ALL=C sort | sed "s/^/$n\t/"
	done < <(rule_table)
	rm -rf "$work"
}
