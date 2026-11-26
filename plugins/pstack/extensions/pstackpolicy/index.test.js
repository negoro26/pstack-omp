import { afterAll, describe, expect, test } from "bun:test";
import { execFileSync } from "node:child_process";
import { mkdtempSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import policy from "./index.js";

// The handler is the whole backstop, so it is tested against commands that must be refused and
// commands that must not be. A rule set that blocks nothing is indistinguishable from no
// backstop at all until something tries to force-push trunk. Every call awaits: the handler is
// async, and comparing a Promise against undefined would pass for the wrong reason.
//
// omp vetoes only from `tool_call`, so the handler is looked up under that name. A fake host that
// ignored the event name passed every test with the backstop registered on `tool_result`.
const handlers = new Map();
policy({ on: (event, fn) => handlers.set(event, fn) });
const toolCall = handlers.get("tool_call");

const run = (command) => toolCall({ toolName: "bash", input: { command } });
const evalCell = (code) => toolCall({ toolName: "eval", input: { language: "py", code } });

// Checkouts the refusal reads. A command without `-C` would read whatever branch the test runner
// sits on, so every case that depends on a checkout names one. They exist before the case tables
// below are built, because those tables interpolate the paths.
const git = (...args) => execFileSync("git", args, { stdio: "ignore" });
const root = mkdtempSync(join(tmpdir(), "pstackpolicy-"));
const trunk = join(root, "trunk");
const feature = join(root, "feature");
const develop = join(root, "develop");
git("init", "-q", "-b", "main", trunk);
git("init", "-q", "-b", "feature/x", feature);
git("init", "-q", "-b", "develop", develop);
git("-C", develop, "symbolic-ref", "refs/remotes/origin/HEAD", "refs/remotes/origin/develop");
git("-C", feature, "symbolic-ref", "refs/remotes/origin/HEAD", "refs/remotes/origin/develop");

afterAll(() => rmSync(root, { recursive: true, force: true }));

// Each command with a fragment of the reason its own rule gives, so a command refused by the
// wrong rule fails and a rule another rule shadows cannot hide.
const MUST_BLOCK = [
  // A force-push is --force, --force-with-lease, -f, or a `+` on the refspec.
  ["git push --force origin main", "default or trunk"],
  ["git push origin main --force-with-lease", "default or trunk"],
  ["git push --force-with-lease=main:abc123 origin main", "default or trunk"],
  ["git push -f origin master", "default or trunk"],
  ["git push -fu origin trunk", "default or trunk"],
  ["git push origin +main", "default or trunk"],
  ["git push origin +HEAD:refs/heads/main", "default or trunk"],
  ["git push --force-with-lease origin +HEAD:refs/heads/trunk", "default or trunk"],
  ["git push origin +feature/x:main", "default or trunk"],
  ["git push origin '+refs/heads/main'", "default or trunk"],
  ["git push -f origin HEAD:main", "default or trunk"],
  ["git push origin HEAD:refs/heads/master --force", "default or trunk"],
  ["git push --force origin main:main", "default or trunk"],
  ["git push --force origin 'HEAD:main'", "default or trunk"],
  ["git push --force --all origin", "every branch"],
  ["git push --force origin 'refs/heads/*:refs/heads/*'", "every branch"],
  ["git push --mirror git@github.com:o/r.git", "mirroring"],
  ["git -C /tmp/repo push -q --mirror origin", "mirroring"],
  // git's global options between the binary and the subcommand. A push scan keyed on two
  // adjacent raw tokens of exactly `git` then `push` found none of these; the first of them was
  // executed against a real bare remote and created refs/heads/trunk there.
  ["git -C /tmp/bypass/work push -f -q origin HEAD:trunk", "default or trunk"],
  ["git -c user.name=bot push --force origin HEAD:main", "default or trunk"],
  ["git --git-dir=/tmp/repo/.git push -f origin main", "default or trunk"],
  ["git --work-tree=/tmp/wt push -f origin HEAD:refs/heads/main", "default or trunk"],
  ["git --namespace=refs/ns push -f origin master", "default or trunk"],
  ["git --exec-path=/usr/lib/git-core push -f origin trunk", "default or trunk"],
  ["/usr/bin/git push --force origin HEAD:main", "default or trunk"],
  ["git -c core.hooksPath=/dev/null push -f origin main", "default or trunk"],
  ["git --bare push -f origin HEAD:trunk", "default or trunk"],
  // HEAD and a missing refspec push the checked-out branch, which is read from the checkout.
  [`git -C ${trunk} push --force origin HEAD`, "through HEAD"],
  [`git -C ${trunk} push -f`, "checked-out branch"],
  [`git -C ${trunk} push --force-with-lease origin`, "checked-out branch"],
  [`/usr/bin/git -C ${trunk} push -f origin HEAD`, "through HEAD"],
  // The default branch is whatever the remote's HEAD names, which need not be main.
  [`git -C ${feature} push --force origin develop`, "default or trunk"],
  [`git -C ${develop} push -f origin HEAD`, "through HEAD"],
  [`git -C ${develop} push -f`, "checked-out branch"],
  // Cutting a command line into simple commands must not open a hole. A redirection is not a
  // separator, a substitution belongs to the push it feeds, and a heredoc body can be run.
  ["git push -f origin 2>&1 HEAD:main", "default or trunk"],
  ["git push -f origin $(echo feature; echo main)", "default or trunk"],
  ["bash <<'EOF'\ngit push --force origin HEAD:main\nEOF", "default or trunk"],
  // A separator glued to a refspec is not part of it.
  ["git push -f origin main; echo done", "default or trunk"],
  ["(git push -f origin main; true)", "default or trunk"],
  ["(cd x && git push -f origin main)", "default or trunk"],
  ["(git push -f origin $(echo feature; echo main))", "default or trunk"],
  ["cd /tmp && git push --force origin main", "default or trunk"],
  ['if [ -z "$x" ]; then git push -f origin main; fi', "default or trunk"],
  // A forced destination the shell fills in may be trunk, so the command cannot clear it.
  ["git push -f origin $BRANCH", "shell names at run time"],
  ['git push --force origin "$(git branch --show-current)"', "shell names at run time"],
  ["git push origin +${branch}", "shell names at run time"],
  ["git push --force-with-lease origin `git branch --show-current`", "shell names at run time"],
  // A backtick substitution runs the command inside it, the same as `$(...)`.
  ["echo `git push -f origin main`", "default or trunk"],
  // A comment ends at its newline whatever quotes it holds, and `$#` is a parameter, not a comment.
  ["# don't push trunk from here\ngit push -f origin main", "default or trunk"],
  ["git status # it's clean\ngit push -f origin HEAD:main", "default or trunk"],
  ["echo $#; git push -f origin main", "default or trunk"],
  // The same update through the API.
  ["gh api -X PATCH repos/o/r/git/refs/heads/main -f sha=abc -F force=true", "through the API"],
  ["gh api --method=PATCH /repos/o/r/git/refs/heads/master -f sha=abc -f force=true", "through the API"],
  // Repository deletion.
  ["gh repo delete o/r --yes", "deleting the repository"],
  ["gh --repo o/r repo delete --yes", "deleting the repository"],
  ['gh "repo" delete o/r --yes', "deleting the repository"],
  ["gh repo -R o/r delete --yes", "deleting the repository"],
  ["gh api -X DELETE repos/o/r", "deleting the repository through the API"],
  ["gh api --method DELETE /repos/o/r", "deleting the repository through the API"],
  ["gh api repos/o/r -X DELETE", "deleting the repository through the API"],
  ["gh api -XDELETE repos/o/r/", "deleting the repository through the API"],
  ["gh api --method=DELETE 'repos/{owner}/{repo}'", "deleting the repository through the API"],
  ["gh api repos/{owner}/{repo} -X DELETE", "deleting the repository through the API"],
  ["cd /tmp && gh repo delete o/r --yes", "deleting the repository"],
];

// What the operator's prompt authorizes, and what only the shell can fill in. Each of these was
// refused by the earlier gate and is now the playbooks' own work.
const MUST_PASS = [
  "gh pr merge 12 --squash",
  "gh pr merge 12 --squash --delete-branch",
  "gh pr merge 12 --squash --auto",
  "gh --repo o/r pr merge 12 --squash",
  "gh pr -R o/r merge 12",
  "gh pr merge 12 \\\n  --auto",
  'gh "pr" merge 12',
  "gh pr edit 12 --base main",
  "gh pr close 12",
  "gh issue -R o/r close 5",
  "gh pr review 12 --approve",
  "origin pr merge 12",
  "origin pr merge 12 --squash",
  "gh api -X POST repos/o/r/pulls/12/comments/5/replies -f body=done",
  "gh api --method POST repos/o/r/pulls/12/comments/5/replies -f body=done",
  "gh api --method=POST repos/o/r/pulls/12/reviews -f event=APPROVE",
  `gh api graphql -f query='mutation{resolveReviewThread(input:{threadId:"t"}){clientMutationId}}'`,
  "gh api repos/o/r/pulls/12/merge -X PUT",
  "gh api repos/o/r/merges -f base=main -f head=feature/x",
  `gh api graphql -f query='mutation{mergePullRequest(input:{pullRequestId:"x"}){clientMutationId}}'`,
  `gh api graphql -f query='mutation{updateRef(input:{refId:"r",oid:"abc",force:true}){clientMutationId}}'`,
  "gh api -X DELETE repos/o/r/git/refs/heads/feature/x",
  "gh api -X DELETE repos/o/r/issues/comments/5",
  "gh api -X PATCH repos/o/r -f description=docs",
  "gh api -X PATCH repos/o/r/git/refs/heads/main -f sha=abc",
  "gh api -X PATCH repos/o/r/git/refs/heads/feature/main-menu -f sha=abc -F force=true",
  "gh release create v1.2.3",
  "gh secret set DEPLOY_TOKEN",
  "gh workflow run deploy.yml --ref main",
  "curl -sS -X PUT https://api.github.com/repos/o/r/pulls/1/merge -d '{}'",
  "gt submit --stack",
  "gt merge",
  "git push origin HEAD:main",
  "git push origin main",
  "git push",
  "git push origin HEAD",
  "git push -u origin feature/x",
  "git push origin :feature/x",
  "git push origin --delete feature/x",
  "git push --all origin",
  "git branch -D feature/x",
  "git update-ref refs/heads/main abc123",
  "git reflog expire --expire=now --all",
  "git reset --hard origin/main",
  // A force-push to anything that is not the default branch is the port's own rebase flow.
  "git push --force-with-lease origin feature/x",
  "git push -f origin feature/x",
  "git push --force origin feature/main-menu",
  "git push --force-with-lease origin main-menu",
  "git push origin +feature/x",
  "git push --force origin :feature/x",
  "git push --force --delete origin feature/x",
  `git -C ${feature} push --force-with-lease origin HEAD`,
  `git -C ${feature} push -f`,
  `git -C ${feature} push --force-with-lease origin`,
  `git -C ${develop} push -f origin feature/x`,
  "git push origin $BRANCH",
  'git push -u origin "$(git branch --show-current)"',
  "git push -f origin 'refs/heads/feature/*:refs/heads/feature/*'",
  "git push --force-with-lease origin feature/x:feature/x",
  // The global-option tolerance must not cost the feature-branch push.
  "git -C /tmp/work push --force-with-lease origin feature/x",
  "git --git-dir=/tmp/repo/.git push --force-with-lease origin feature/x",
  "/usr/bin/git push -f origin feature/x",
  "git -c user.name=bot push -f origin feature/head",
  "git --work-tree=/tmp/wt push -f -q origin feature/main-menu",
  // A dry run moves nothing.
  "git -C /tmp/wt push --dry-run -f origin HEAD:main",
  "git push -n --force origin main",
  // Reads and unrelated commands.
  "gh pr view 12",
  "gh pr list --state open",
  "gh pr list --search main",
  "gh pr diff 12",
  "gh repo view o/r",
  "gh repo -R o/r view",
  "gh release list",
  "gh api repos/o/r",
  "gh api -X GET repos/o/r",
  "gh api repos/o/r/git/refs/heads/main",
  "gh api -X GET repos/o/r/git/refs/heads/main --jq .object.sha",
  "gh pr -R o/r view 12",
  "git status --porcelain",
  "git log main..HEAD",
  'git commit -m "merge main into feature"',
  "bun run test",
  "curl -sSL https://api.github.com/repos/o/r/pulls/1",
  "curl -X GET https://api.github.com/repos/o/r",
  // A later command's arguments are not the push's refspecs.
  "git push -f origin feature && git rev-parse HEAD",
  "git push -f origin feature || git rev-parse HEAD",
  "git push -f origin feature; git checkout main",
  "git push -f origin feature | grep main",
  "git push -f origin feature\ngit log -1 HEAD",
  "git push -f origin feature 2>&1 && git rev-parse HEAD",
  "cat > notes.md <<'EOF'\nForce-push with git push -f origin feature when told to.\nEOF\ngit rev-parse HEAD",
  // A subshell or brace group cuts the same as the commands written without it.
  "(cd x && git push -f origin feature && git rev-parse HEAD)",
  "{ git push -f origin feature; git rev-parse HEAD; }",
  // A comment is not an argument, and a redirection target is not a refspec.
  "git push -f origin feature # never main",
  'git push -f origin feature > "$LOG" 2>&1',
  // Reading a ref through GraphQL is not moving it.
  "gh api graphql -f query='query{repository(owner:\"o\",name:\"r\"){ref(qualifiedName:\"main\"){target{oid}}}}'",
];

describe("pstackpolicy", () => {
  test.each(MUST_BLOCK)("refuses %p as %p", async (command, rule) => {
    const result = await run(command);
    expect(result?.block).toBe(true);
    expect(result?.reason).toContain(rule);
  });

  test.each(MUST_PASS)("allows %p", async (command) => {
    expect(await run(command)).toBeUndefined();
  });

  test("the refusal tells the agent to stop and return the step to the operator", async () => {
    const result = await run("git push --force origin main");
    expect(result?.reason).toContain("pause list");
    expect(result?.reason).toContain("Stop here and return this step to the operator");
  });

  // omp://approval-mode.md: eval declares the exec tier and can spawn a shell, so a rule that
  // only read bash's `command` field was not a rule about the command.
  test.each([
    ["await Bun.$`git push --force origin HEAD:main`", "default or trunk"],
    ['subprocess.run(["git", "push", "--force", "origin", "HEAD:main"])', "default or trunk"],
    ['await tool.bash({ command: "gh repo delete o/r --yes" })', "deleting the repository"],
    // A list literal broken over lines is still one command, and a comment inside it does not
    // open a quote that hides the rest.
    [
      'subprocess.run([\n    "git", "push", "-f", "origin", "feature",\n    "HEAD:main",\n])',
      "default or trunk",
    ],
    [
      'subprocess.run([\n    "git", "push", "-f", "origin",  # don\'t\n    "HEAD:main",\n])',
      "default or trunk",
    ],
    ['subprocess.run(["gh", "api", "-X", "DELETE", "repos/o/r"])', "deleting the repository"],
  ])("refuses the eval cell %p as %p", async (code, rule) => {
    const result = await evalCell(code);
    expect(result?.block).toBe(true);
    expect(result?.reason).toContain(rule);
  });

  test.each([
    'print("git push -f origin feature/x")',
    'subprocess.run(["git", "push", "--force-with-lease", "origin", "feature"])\nsubprocess.run(["git", "rev-parse", "HEAD"])',
    "await Bun.$`git push origin feature`",
    "await Bun.$`gh pr merge 12 --squash`",
    'subprocess.run(["git", "push", "origin", "HEAD:main"])',
  ])("allows the eval cell %p", async (code) => {
    expect(await evalCell(code)).toBeUndefined();
  });

  test("ignores tools that carry no command", async () => {
    expect(
      await toolCall({ toolName: "read", input: { command: "git push -f origin main" } })
    ).toBeUndefined();
    expect(await toolCall({ toolName: "bash", input: {} })).toBeUndefined();
    expect(await toolCall({ toolName: "eval", input: {} })).toBeUndefined();
  });
});
