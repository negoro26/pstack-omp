// pstackpolicy: a veto for the two actions pstack's pause list names and a command can show.
//
// poteto-mode says "Always pause for irreversible writes: force-push to shared branches, deploys,
// data deletion, customer messages." On this harness that sentence has nothing behind it:
//
//   - `omp://approval-mode.md`: yolo auto-approves the `read`, `write`, AND `exec` tiers.
//   - same file, Subagents: they run headless yolo, and the parent `task` approval is the
//     authorization boundary. Every pstack owner is a subagent.
//
// So this refuses exactly two things, in front of execution through `tool_call`:
//
//   - a force-push to the repository's default branch or to main, master, or trunk
//   - deleting the repository
//
// Everything else passes: merging, closing, reviews, retargeting, branch deletion and plain
// pushes are the playbooks' own work, and the operator's prompt is the permission for them.
// Deploys, data deletion and customer messages have no command shape this file could read, so
// they stay with the prose.
//
// Two tools carry a shell command into the process and both are inspected: `bash` through
// `event.input.command`, and `eval` through `event.input.code`, because the `eval` tool declares
// the exec tier too. This is a backstop, not a sandbox. `omp://hooks.md` records that the
// `browser` and `computer` preludes emit no `tool_call`, and a command assembled from string
// concatenation inside a cell matches no rule here.
//
// Git is read as tokens, not substrings. `git -C <dir> push ...` and `/usr/bin/git push ...` are
// the same push, so the scan skips git's global options to find the subcommand, and a refspec is
// judged by its destination: `git push -f origin HEAD:main` forces trunk with no `main` token
// next to the flag, while `feature/main-menu` is not trunk.

import { execFileSync } from "node:child_process";
import { resolve } from "node:path";

const TRUNK = new Set(["main", "master", "trunk"]);

// gh accepts flags before the command group and between the group and its verb, including
// `--repo owner/name`, which the port uses constantly.
const GH_FLAGS = String.raw`(?:\s+(?:-[A-Za-z]|[-]{2}[A-Za-z][\w-]*)(?:[= ]\S+)?)*`;

const gh = (group, verbs) =>
  String.raw`\bgh\b${GH_FLAGS}\s+(?:${group})${GH_FLAGS}\s+(?:${verbs})\b`;

const REPO_DELETE = new RegExp(gh("repo", "delete"));

// Quotes are syntax once the shell or the host language has read them, so `gh "repo" delete` is
// `gh repo delete` and `'HEAD:main'` is one refspec. A quoted piece joins the text beside it as
// the shell joins it, so `"HEAD":main`, `"ma"in` and `m""ain` stay one word and quotes never
// split one. Inside an `eval` cell the command is usually a list literal,
// `subprocess.run(["git", "push", "origin", "HEAD:main"])`, where a comma and a bracket separate
// what separated nothing in a shell line. Both become a space. A backslash-newline is a line
// continuation the shell deletes. Only the loose direction is taken: an unpaired quote is left
// alone. A backtick substitution becomes `$` and its command, the text a `$(...)` leaves once its
// brackets go, so a refspec built from one reads as a value the shell fills in when it runs.
const normalize = (command) =>
  command
    .replace(/\\\n/g, "")
    .replace(/(["'])([^"'\n]*)\1(\s*,)?/g, (_, _quote, body, comma) => (comma ? `${body} ` : body))
    .replace(/`([^`]*)`/g, "$$ $1 ")
    .replace(/[()[\]{},]/g, " ");

// `;`, `|` and `&` end a shell word and the simple command it is in, except inside a redirection:
// the `&` of `2>&1`, `<&` or `&>`, and the `|` of `>|`.
function separates(text, i) {
  const ch = text[i];
  if (ch === ";") return true;
  if (ch === "|") return text[i - 1] !== ">";
  if (ch === "&") return !/[<>]/.test(text[i - 1] ?? "") && text[i + 1] !== ">";
  return false;
}

/**
 * Shell-shaped tokeniser: whitespace and the separators above end a word, single and double
 * quotes group, a backslash escapes the next character and a backslash-newline disappears. Quotes
 * are stripped, because `'HEAD:main'` and `HEAD:main` are one refspec to git and the strip is what
 * lets the refspec rules see the colon. A glued `;` is not part of the word, so
 * `(git push origin main; true)` pushes `main`, not `main;`.
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
    if (/\s/.test(ch) || separates(command, i)) {
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

/**
 * The simple commands in a command line, cut where the shell ends one: `&&`, `||`, `;`, `|`, `&`
 * and newline. A push's refspecs end with its own command, so `git push origin feature && git
 * rev-parse HEAD` is a feature push and a read, not a push of HEAD. A subshell or brace group cuts
 * the same way, so `(cd x && git push origin feature && git rev-parse HEAD)` reads the same.
 *
 * Every miss leaves text joined, which fails closed. Nothing inside quotes, backticks, a
 * substitution or a list literal is cut, so the `;` in `$(echo; echo main)` and the newlines of a
 * list literal stay with the push they feed, and the `&` of `2>&1` or `&>` is a redirection, not a
 * separator. A comment is dropped up to its newline, quotes and all, so the apostrophe in
 * `# don't` opens nothing. A heredoc body gets no exception: each line is scanned as its own
 * command, because `bash <<EOF` runs it.
 */
function simpleCommands(command) {
  const out = [];
  let kept = "";
  let start = 0;
  let quote = null;
  // One entry per open bracket. A subshell or brace group is true, because the shell still
  // separates the commands inside it. A substitution or list literal is false, because its text
  // feeds one command.
  const brackets = [];
  const cut = (at) => {
    out.push(kept + command.slice(start, at));
    kept = "";
    start = at + 1;
  };
  for (let i = 0; i < command.length; i += 1) {
    const ch = command[i];
    if (quote === "'") {
      if (ch === "'") quote = null;
    } else if (ch === "\\") {
      i += 1;
    } else if (quote) {
      if (ch === quote) quote = null;
    } else if (ch === "'" || ch === '"' || ch === "`") {
      quote = ch;
    } else if (ch === "#" && /^$|[\s;&|()]/.test(command[i - 1] ?? "")) {
      kept += command.slice(start, i);
      start = command.indexOf("\n", i);
      if (start < 0) start = command.length;
      i = start - 1;
    } else if ("([{".includes(ch)) {
      brackets.push(ch !== "[" && /^[\s({]*$/.test(kept + command.slice(start, i)));
    } else if (")]}".includes(ch)) {
      brackets.pop();
    } else if (brackets.every(Boolean) && (ch === "\n" || separates(command, i))) {
      cut(i);
    }
  }
  out.push(kept + command.slice(start));
  return out;
}

// git, or git under any path: an absolute binary is the same program with the same global
// options in front of the subcommand.
const BASENAME = (name) => (token) => new RegExp(`(?:^|[/\\\\])${name}(?:\\.exe)?$`).test(token);
const isGit = BASENAME("git");
const isGh = BASENAME("gh");

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
 * `git -C /tmp/work push ...`, `git -c foo=bar push ...` and `/usr/bin/git push ...` all resolve
 * to `push` here.
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

/** The directory `git` runs in: the tool call's directory, moved by each `-C <dir>` in turn. */
function gitDirectory(tokens, start, at, base) {
  let dir = base;
  for (let i = start + 1; i < at; i += 1) {
    if (tokens[i] === "-C" && i + 1 < at) {
      dir = resolve(dir, tokens[i + 1]);
      i += 1;
    } else if (GIT_VALUE_OPTIONS.has(tokens[i])) i += 1;
  }
  return dir;
}

/** Every `git <subcommand>` in the command, with the arguments its own simple command gives it. */
function eachGitCommand(command, base, visit) {
  for (const simple of simpleCommands(command)) {
    const tokens = shellTokens(normalize(simple));
    for (let i = 0; i < tokens.length; i += 1) {
      if (!isGit(tokens[i])) continue;
      const at = gitSubcommand(tokens, i);
      if (at < 0) continue;
      visit(tokens[at], tokens.slice(at + 1), gitDirectory(tokens, i, at, base));
    }
  }
}

function probe(dir, args) {
  try {
    return execFileSync("git", ["-C", dir, ...args], {
      encoding: "utf8",
      stdio: ["ignore", "pipe", "ignore"],
      timeout: 3000,
    }).trim();
  } catch {
    return null;
  }
}

/** The branch the remote's HEAD names, or null when the checkout never recorded one. */
function defaultBranch(dir, remote) {
  const ref = probe(dir, ["symbolic-ref", "--short", `refs/remotes/${remote}/HEAD`]);
  return ref?.startsWith(`${remote}/`) ? ref.slice(remote.length + 1) : null;
}

const currentBranch = (dir) => probe(dir, ["symbolic-ref", "--short", "HEAD"]);

// A redirection with its target glued on, and an operator alone, whose target is the next token.
// The target names a file, not a refspec.
const REDIRECTION = /^(?:\d+|&)?[<>]/;
const REDIRECTION_ALONE = /^(?:\d+|&)?[<>]+[&|]?$/;

const REASON_TRUNK = "force-pushing a default or trunk branch";
const REASON_SHELL_NAMED = `${REASON_TRUNK} that the shell names at run time`;

/**
 * Why this `git push` is a force-push to the default branch or to main, master, or trunk, or
 * null. A push is forced by `--force`, `--force-with-lease`, `-f`, or a `+` on the refspec, and
 * `--mirror` always is. Where the destination is `HEAD` or absent, git pushes the checked-out
 * branch, so that branch is read. A forced destination the shell fills in, such as `$BRANCH` or
 * `$(git branch --show-current)`, can be trunk and the command cannot show it is not, so it is
 * refused; writing the branch name out lets it through. A delete refspec is not a force-push.
 */
function pushRefuse(argv, dir) {
  const args = argv.filter(
    (token, i) => !REDIRECTION.test(token) && !REDIRECTION_ALONE.test(argv[i - 1] ?? "")
  );
  const has = (token) => args.includes(token);
  if (has("--dry-run") || has("-n") || has("--delete")) return null;
  if (has("--mirror")) {
    return "mirroring the repository, which force-updates every ref including the default branch";
  }
  const forced = args.some((t) => /^--force/.test(t) || /^-[A-Za-z]*f[A-Za-z]*$/.test(t));
  if (forced && has("--all")) return "force-pushing every branch, including the default branch";
  let sawRefspec = false;
  // The first bare, colon-free, non-HEAD token is the remote name, not a refspec.
  const bare = args.filter((t) => !t.startsWith("-"));
  let remote = "origin";
  let remoteSeen = bare.length === 0 || bare[0].includes(":") || bare[0] === "HEAD";
  const onTrunk = (branch, name) => branch && (TRUNK.has(branch) || branch === defaultBranch(dir, name));
  for (const token of args) {
    if (token.startsWith("-")) continue;
    if (!remoteSeen && !token.includes(":")) {
      remoteSeen = true;
      remote = token;
      continue;
    }
    sawRefspec = true;
    if (token.startsWith(":")) continue;
    if (!forced && !token.startsWith("+")) continue;
    const dest = token
      .slice(token.lastIndexOf(":") + 1)
      .replace(/^\+/, "")
      .replace(/^refs\/heads\//, "");
    if (dest.startsWith("$")) return REASON_SHELL_NAMED;
    if (dest === "*") return "force-pushing every branch, including the default branch";
    if (dest === "HEAD") {
      if (onTrunk(currentBranch(dir), remote)) return `${REASON_TRUNK} through HEAD`;
      continue;
    }
    if (onTrunk(dest, remote)) return REASON_TRUNK;
  }
  if (forced && !sawRefspec && onTrunk(currentBranch(dir), remote)) {
    return `${REASON_TRUNK} through the checked-out branch`;
  }
  return null;
}

function pushOffence(command, base) {
  let why = null;
  eachGitCommand(command, base, (subcommand, args, dir) => {
    if (subcommand === "push" && !why) why = pushRefuse(args, dir);
  });
  return why;
}

// gh api flags that consume the next token, so the endpoint is the first token that is not one.
const GH_API_VALUE_FLAGS = new Set([
  "-X",
  "--method",
  "-f",
  "-F",
  "--field",
  "--raw-field",
  "-H",
  "--header",
  "--input",
  "-q",
  "--jq",
  "-t",
  "--template",
  "--cache",
  "--hostname",
  "-p",
  "--preview",
]);

/** `gh [flags] api <args>` calls, as the method, the endpoint and the field tokens each carries. */
function eachGhApi(command, visit) {
  for (const simple of simpleCommands(command)) {
    for (const text of [simple, normalize(simple)]) {
      const tokens = shellTokens(text);
      for (let i = 0; i < tokens.length; i += 1) {
        if (!isGh(tokens[i])) continue;
        let at = i + 1;
        while (at < tokens.length && tokens[at].startsWith("-")) {
          at += tokens[at] === "-R" || tokens[at] === "--repo" || tokens[at] === "--hostname" ? 2 : 1;
        }
        if (tokens[at] !== "api") continue;
        let method = "GET";
        let endpoint = null;
        const fields = [];
        for (let j = at + 1; j < tokens.length; j += 1) {
          const token = tokens[j];
          const long = /^(?:--method|-X)=?(.+)$/.exec(token);
          if (long && token !== "--method" && token !== "-X") method = long[1].toUpperCase();
          else if (token === "-X" || token === "--method") method = (tokens[(j += 1)] ?? "").toUpperCase();
          else if (GH_API_VALUE_FLAGS.has(token)) fields.push(tokens[(j += 1)] ?? "");
          else if (token.startsWith("-")) fields.push(token);
          else endpoint ??= token;
        }
        visit(method, endpoint?.split("?")[0] ?? "", fields);
      }
    }
  }
}

const API_ORIGIN = String.raw`(?:https://api\.github\.com)?`;
const REPO_ENDPOINT = new RegExp(String.raw`^${API_ORIGIN}/?repos/[^/\s]+/[^/\s]+/?$`);
const HEADS_ENDPOINT = new RegExp(
  String.raw`^${API_ORIGIN}/?repos/[^/\s]+/[^/\s]+/git/refs/heads/(.+)$`
);
const FORCE_FIELD = /(?:^|[=:])force=true$/i;

/** Why this `gh api` call is repository deletion or a forced update of a trunk ref, or null. */
function apiOffence(command) {
  let why = null;
  eachGhApi(command, (method, endpoint, fields) => {
    if (why) return;
    if (method === "DELETE" && REPO_ENDPOINT.test(endpoint)) {
      why = "deleting the repository through the API";
      return;
    }
    const heads = HEADS_ENDPOINT.exec(endpoint);
    if (heads && method !== "GET" && fields.some((f) => FORCE_FIELD.test(f.replace(/^-[fF]/, "")))) {
      const branch = heads[1].replace(/\/$/, "");
      if (TRUNK.has(branch)) why = `${REASON_TRUNK} through the API`;
    }
  });
  return why;
}

function repoDeletion(command) {
  for (const simple of simpleCommands(command)) {
    if (REPO_DELETE.test(normalize(simple))) return "deleting the repository";
  }
  return null;
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

/**
 * The directory the call runs in. bash runs in the session's cwd, which `ctx.cwd` carries and
 * which differs from the omp launch directory for an isolated owner in a worktree, and a call
 * can pass its own `cwd`. A `cd x && git push` inside the command line is not tracked.
 */
const baseDirectory = (event, ctx) =>
  resolve(ctx.cwd, typeof event.input?.cwd === "string" ? event.input.cwd : "");

const STOP = "Stop here and return this step to the operator, saying what is blocked.";
const HANDOFF =
  "Ask them to confirm it and run it themselves. A different command for the same push or delete " +
  "is the same blocked action.";

export default function pstackpolicy(pi) {
  pi.on("tool_call", async (event, ctx) => {
    const command = subject(event);
    if (!command) return;

    const why =
      pushOffence(command, baseDirectory(event, ctx)) ?? repoDeletion(command) ?? apiOffence(command);
    if (!why) return;
    if (why === REASON_SHELL_NAMED) {
      return {
        block: true,
        reason:
          `pstackpolicy: refused ${why}. The command does not show which branch it forces. ` +
          `If the branch is not the default branch, write its name out literally and retry. ` +
          `If it is the default branch, pstack's pause list says to always pause for that. ${STOP}`,
      };
    }
    return {
      block: true,
      reason:
        `pstackpolicy: refused ${why}. pstack's pause list says to always pause for ` +
        `irreversible writes, and a force-push to the default branch and repository deletion ` +
        `are two of them. ${STOP} ${HANDOFF}`,
    };
  });
}
