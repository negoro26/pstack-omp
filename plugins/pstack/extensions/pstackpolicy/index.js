// pstackpolicy: the machine backstop for the one gate the port has no prose answer for.
//
// pstack's playbooks say "only under an operator landing grant", "never merge without an
// explicit request", "stop where the human's call begins". Those are instructions, and an
// instruction is not enforcement. On this harness they cannot be, either:
//
//   - `omp://approval-mode.md`: yolo auto-approves the `read`, `write`, AND `exec` tiers, so
//     `gh pr merge` inside a bash call runs with no prompt.
//   - same file, Subagents: "Subagents run headless with `tools.approvalMode: yolo`... The
//     parent `task` approval is the authorization boundary." Every pstack owner is a subagent.
//   - same file: bash's built-in critical patterns cover `rm -rf /`, fork bombs,
//     remote-fetch-then-execute, `/etc/passwd`, and host shutdown. A merge is not on that list.
//
// So an agent that reads a playbook step in isolation has licence to land the stack. This
// closes that with `tool_call`, the one native veto point that sits in front of execution.
//
// What it reaches, and what it does not. Two tools carry a shell command into the process and
// both are inspected: `bash` through `event.input.command`, and `eval` through
// `event.input.code`, because the `eval` tool declares the `exec` tier too
// (`omp://approval-mode.md`) and a `Bun.$` or `subprocess.run` inside a cell is the same
// execution a bash rule would have been caught for. Stated rather than implied, because this
// is a backstop for a port that mostly drives git and gh through `bash`, not a sandbox:
// `omp://hooks.md` records that the `browser` and `computer` preludes are host bridge calls
// that emit no `tool_call`, so they are out of reach here, and a command assembled from string
// concatenation inside a cell (`["gh", "pr", "merge"].join(" ")`) matches no string rule.
//
// The grant is deliberately an environment variable rather than a flag or a command, because a
// flag the agent can pass is not a grant the operator made. The operator arms it; a subagent
// cannot set its own process environment.
//
//   PSTACK_LANDING_GRANT=1   allow the forge mutations below for this process
//
// Three shapes of rule, because no one shape covers the ground. The `gh` rules are regexes, so
// they have to tolerate global flags between the binary and the subcommand -- `gh --repo o/r pr
// merge` is the documented way to target a non-default repo and the port uses it constantly,
// and anchoring on `gh pr` alone let every one of them through. The `git push` and
// `git branch -D` rules are token scans, because "does this push land on trunk" is a question
// about refspecs, not a substring: `git push origin HEAD:main` moves trunk with no force flag
// at all, which a force-token regex cannot see, and a naive trunk-word lookahead then blocks
// `feature/main-menu`. And both of those token scans have to read past git's global options,
// because `git -C <dir> push ...` and `/usr/bin/git push ...` are the same push; a scan keyed on
// two adjacent raw tokens of exactly `git` then `push` was proven to let
// `git -C /tmp/bypass/work push -q origin HEAD:trunk` create a branch on a real remote.

const GRANT = "PSTACK_LANDING_GRANT";

const TRUNK = new Set(["main", "master", "trunk", "develop", "release"]);

// Regexes cannot read a Set, and two rules have to name trunk inside a pattern.
const TRUNK_ALT = [...TRUNK].join("|");

// gh accepts global flags before the subcommand. Each rule permits any number of them, including
// `--repo owner/name`, which is the form the port actually uses.
const GH_FLAGS = String.raw`(?:\s+(?:-[A-Za-z]|[-]{2}[A-Za-z][\w-]*)(?:[= ]\S+)?)*`;

// Any run of characters that is not a newline, except a backslash immediately followed by one. A
// plain `[^\n]*` let `gh pr edit 12 \` + newline + `--base main` past every flag rule, because
// the flag it gates sits on the far side of the continuation.
const CONT = String.raw`(?:[^\n\\]|\\\n)*`;

// Two normalisations, because these rules match text and the text is not always a shell line.
//
// Quotes are syntax once the shell or the host language has read them, so `gh "pr" merge 12` is
// `gh pr merge 12` and `'HEAD:main'` is one refspec. And inside an `eval` cell the command is
// usually a list literal -- `subprocess.run(["git", "push", "origin", "HEAD:main"])`, or
// `tool.bash({ command: "gh repo delete o/r --yes" })` -- where a comma and a bracket separate
// what separated nothing in a shell line. Both are rewritten to a space. Only the loose direction
// is taken: an unpaired quote is left alone, and a comma between two branch names becomes two
// branch names, which this scan already treats as two refspecs.
const normalize = (command) =>
  command
    .replace(/(["'])([^"'\n]*)\1\s*,?/g, "$2 ")
    .replace(/[()[\]{},]/g, " ");

const FORBIDDEN = [
  [
    "merging a pull request",
    new RegExp(String.raw`\bgh\b${GH_FLAGS}\s+pr\s+merge\b`),
  ],
  [
    "merging a pull request through the API",
    new RegExp(
      String.raw`\bgh\b${GH_FLAGS}\s+api\b${CONT}(?:\/pulls\/\d+\/merge|mergePullRequest|\/merge\b)`
    ),
  ],
  [
    "closing, reopening, or deleting a pull request, issue, or thread",
    new RegExp(
      String.raw`\bgh\b${GH_FLAGS}\s+(pr|issue)\s+(close|reopen|delete)\b|\bgh\b${GH_FLAGS}\s+api\b${CONT}(?:-X\s*DELETE[^\n]*\/(issues|pulls|git\/refs)|state\s*=\s*closed|closePullRequest|closeIssue)`
    ),
  ],
  [
    "retargeting a pull request base, which rewrites the whole stack under it",
    new RegExp(String.raw`\bgh\b${GH_FLAGS}\s+pr\s+edit\b${CONT}--base\b`),
  ],
  [
    "posting a review or resolving a review thread",
    new RegExp(
      String.raw`\bgh\b${GH_FLAGS}\s+pr\s+review\b|\bgh\b${GH_FLAGS}\s+api\b${CONT}(?:-X\s*POST[^\n]*(?:\/reviews|pulls\/\d+\/(comments|reviews))|resolveReviewThread|addPullRequestReview)`
    ),
  ],
  [
    "armoring merge-when-ready",
    new RegExp(String.raw`\bgh\b${GH_FLAGS}\s+pr\s+merge\b${CONT}--(?:auto|auto-merge)\b`),
  ],
  // The enumeration below used to stop at the verbs the port happened to use, so every other
  // forge mutation gh ships was a clean pass: `gh repo delete` destroys the repository the whole
  // stack lives in, and a release publish or a secret write is not undoable from a later step.
  [
    "deleting the repository",
    new RegExp(String.raw`\bgh\b${GH_FLAGS}\s+repo\s+(delete|remove|rm)\b`),
  ],
  [
    "publishing, replacing, or deleting a release",
    new RegExp(String.raw`\bgh\b${GH_FLAGS}\s+release\s+(create|delete|upload)\b`),
  ],
  [
    "writing a secret or a deployment variable on the forge",
    new RegExp(String.raw`\bgh\b${GH_FLAGS}\s+(secret|variable)\s+(set|delete)\b`),
  ],
  [
    "running a workflow against a trunk branch",
    // `--ref` is the trigger, and the ref is what decides: `gh workflow run ci.yml --ref
    // feature/x` is the port's own CI path and stays allowed.
    new RegExp(
      String.raw`\bgh\b${GH_FLAGS}\s+workflow\s+run\b${CONT}(?:--ref|-r)(?![A-Za-z0-9-])[= ]+["']?(?:${TRUNK_ALT})(?![\w-])`
    ),
  ],
  [
    "merging, closing, or deleting forge state with curl, which no gh rule can see",
    // Same request as the `gh api` rules above, and equally available with the token already in
    // the environment. The trigger is the method or a request body, since curl POSTs by default.
    new RegExp(
      String.raw`\bcurl\b${CONT}(?:(?:-X|--request)\s*[A-Za-z]+|--data[\s=])${CONT}(?:\/pulls\/\d+\/merge|\/merge\b|mergePullRequest|state\s*=\s*closed|\/git\/refs)`,
      "i"
    ),
  ],
  [
    "merging through Graphite",
    new RegExp(String.raw`\bgt\s+(submit|rebase|restack)\b`),
  ],
];

/**
 * Shell-shaped tokeniser: whitespace separates, single and double quotes group, a backslash
 * escapes the next character and a backslash-newline disappears. Quotes are stripped, because
 * `'HEAD:main'` and `HEAD:main` are one refspec to git and the strip is what lets the refspec
 * rules see the colon.
 */
function shellTokens(command) {
  const out = [];
  let current = "";
  let open = false;
  let quote = null;
  for (let i = 0; i < command.length; i += 1) {
    const ch = command[i];
    if (quote === "'") {
      if (ch === "'") quote = null;
      else current += ch;
      continue;
    }
    if (ch === "\\" && command[i + 1] === "\n") {
      i += 1;
      continue;
    }
    if (quote === '"') {
      if (ch === '"') quote = null;
      else if (ch === "\\" && command[i + 1] !== undefined) {
        i += 1;
        current += command[i];
      } else current += ch;
      continue;
    }
    if (ch === "'" || ch === '"') {
      quote = ch;
      open = true;
      continue;
    }
    if (ch === "\\" && command[i + 1] !== undefined) {
      i += 1;
      current += command[i];
      open = true;
      continue;
    }
    if (/\s/.test(ch)) {
      if (open) out.push(current);
      current = "";
      open = false;
      continue;
    }
    current += ch;
    open = true;
  }
  if (open) out.push(current);
  return out;
}

// git, or git under any path: an absolute binary is the same program with the same global
// options in front of the subcommand.
const GIT_BASENAME = /(?:^|[/\\])git(?:\.exe)?$/;

/**
 * The git global options that take a separate value token. `--git-dir=<x>` needs no entry
 * because the `=` form is consumed as one token by the `startsWith("-")` branch below.
 */
const GIT_VALUE_OPTIONS = new Set([
  "-c",
  "-C",
  "--git-dir",
  "--work-tree",
  "--namespace",
  "--exec-path",
  "--attr-source",
  "--super-prefix",
  "--config-env",
]);

/**
 * Index of the subcommand token after the git binary at `start`, skipping global options, or -1.
 *
 * This is the fix for the proven bypass: `git -C /tmp/bypass/work push ...`, `git -c foo=bar
 * push ...`, `git --git-dir=... push ...` and `/usr/bin/git push ...` all resolve to `push`
 * here, where a scan for two adjacent tokens of exactly `git` then `push` found nothing.
 */
function gitSubcommand(tokens, start) {
  for (let i = start + 1; i < tokens.length; i += 1) {
    const token = tokens[i];
    if (token === "--") return i + 1 < tokens.length ? i + 1 : -1;
    if (!token.startsWith("-")) return i;
    if (GIT_VALUE_OPTIONS.has(token)) i += 1;
  }
  return -1;
}

/** Every `git <subcommand>` in the command, with its arguments and no global options. */
function eachGitCommand(command, visit) {
  const tokens = shellTokens(command);
  for (let i = 0; i < tokens.length; i += 1) {
    if (!GIT_BASENAME.test(tokens[i])) continue;
    const at = gitSubcommand(tokens, i);
    if (at < 0) continue;
    visit(tokens[at], tokens.slice(at + 1));
  }
}

/**
 * Why this `git push` is refused, or null.
 *
 * Deliberately blocks every push whose refspec lands on a trunk branch, not only forced ones:
 * the port's own pause list now names "pushing to trunk" as irreversible, and a plain
 * `git push origin HEAD:main` does that with no force flag to key on. A push to a feature branch
 * is the port's normal rebase flow and stays allowed.
 */
function pushRefuse(args) {
  const has = (token) => args.includes(token);
  if (has("--dry-run") || has("-n")) return null;
  if (has("--mirror") || has("--all") || has("--tags")) {
    return "pushing every ref, or mirroring the whole repository, at the remote";
  }
  if (has("--delete")) return "deleting a branch on the forge";
  const forced = args.some((t) => /^--force/.test(t) || t === "-f");
  let sawRefspec = false;
  // The first bare, colon-free, non-HEAD token is the remote name, not a refspec. Counting it as
  // one made `git push origin` look like a push with a destination.
  const bare = args.filter((t) => !t.startsWith("-"));
  let remoteSeen = bare.length === 0 || bare[0].includes(":") || bare[0] === "HEAD";
  for (const token of args) {
    // `:branch` is git's refspec delete form; it carries no --delete flag.
    if (token.startsWith(":")) return "deleting a branch on the forge";
    if (token.startsWith("-")) continue;
    if (!token.includes(":")) {
      if (!remoteSeen) {
        remoteSeen = true;
        continue;
      }
      // A bare destination, or HEAD, is whatever this checkout is on. From a trunk checkout that
      // is trunk, and there is nothing in the command to tell, so it is treated as trunk-risky
      // rather than allowed. `git push origin HEAD` is the idiom an agent actually writes.
      sawRefspec = true;
      // A leading `+` is git's own force spelling, and the destination can still be trunk.
      const bareDest = token.replace(/^\+/, "").replace(/^refs\/heads\//, "");
      if (bareDest === "HEAD") return "pushing the current branch, which may be trunk";
      if (TRUNK.has(bareDest)) {
        return forced ? "rewriting history on a trunk branch" : "pushing to trunk";
      }
      continue;
    }
    sawRefspec = true;
    const afterColon = token.slice(token.lastIndexOf(":") + 1);
    const clean = afterColon.replace(/^\+/, "").replace(/^refs\/heads\//, "");
    if (TRUNK.has(clean)) {
      return forced ? "rewriting history on a trunk branch" : "pushing to trunk";
    }
  }
  // No refspec at all: `git push` with only flags, or `git push origin`. Same reasoning.
  if (!sawRefspec) return "pushing without an explicit refspec, which may be trunk";
  return null;
}

function pushOffence(command) {
  let why = null;
  eachGitCommand(command, (subcommand, args) => {
    if (subcommand === "push" && !why) why = pushRefuse(args);
  });
  return why;
}

/**
 * Why this git command destroys local history, or null.
 *
 * Tokenised for the same reason the push scan is: `git -C /tmp/repo branch -D feat` was proven
 * to pass a regex that required `\bgit\s+branch`. The `update-ref` carve-out is pre-existing and
 * deliberate in shape: a delete is the same class as the `git branch -d` this file allows, while
 * `update-ref <ref> <sha>` moves a ref out from under the worktree with no signal.
 */
function localDestruction(command) {
  let why = null;
  eachGitCommand(command, (subcommand, args) => {
    if (why) return;
    const has = (token) => args.includes(token);
    if (subcommand === "branch" && has("-D")) why = "destroying local history";
    else if (subcommand === "update-ref" && !has("-d") && !has("--delete")) {
      why = "destroying local history";
    } else if (
      subcommand === "reflog" &&
      args[0] === "expire" &&
      args.slice(1).includes("--expire=now") &&
      args.includes("--all")
    ) {
      why = "destroying local history";
    } else if (
      subcommand === "reset" &&
      has("--hard") &&
      args.some((t) => t.startsWith("origin/"))
    ) {
      why = "destroying local history";
    }
  });
  return why;
}

export const DENY_REASONS = FORBIDDEN.map(([why]) => why);

function granted() {
  const raw = process.env[GRANT];
  // Anything but an explicit affirmative is absent. A stray "0" or "false" must not read as
  // consent, and an unset variable must not either.
  return raw === "1" || raw === "true";
}

/**
 * The command the tool is about to run, or null when this tool carries none. `bash` has a
 * `command` field; `eval` has `code`, and the exec-tier cell is the other door into the shell.
 */
function subject(event) {
  if (event?.toolName === "bash") {
    return typeof event.input?.command === "string" ? event.input.command : null;
  }
  if (event?.toolName === "eval") {
    return typeof event.input?.code === "string" ? event.input.code : null;
  }
  return null;
}

export default function pstackpolicy(pi) {
  pi.on("tool_call", async (event) => {
    const command = subject(event);
    if (!command) return;
    if (granted()) return;

    const text = normalize(command);
    const why =
      pushOffence(text) ??
      (FORBIDDEN.find(([, pattern]) => pattern.test(text)) ?? null)?.[0] ??
      localDestruction(text);

    if (why) {
      return {
        block: true,
        reason:
          `pstackpolicy: refused ${why}. pstack's playbooks require an operator landing grant for ` +
          `this and no prose can enforce it: yolo auto-approves the exec tier, subagents run ` +
          `headless yolo, and bash's critical-pattern list does not cover forge mutations. If you ` +
          `are the operator and want it allowed for this run, restart with ${GRANT}=1. Otherwise ` +
          `return the step to the human and say what is blocked.`,
      };
    }
  });
}