import { describe, expect, test } from "bun:test";
import policy from "./index.js";

// The handler is the whole backstop, so it is tested against commands that must be refused and
// commands that must not be. A rule set that blocks nothing is indistinguishable from no
// backstop at all until something tries to merge. Every call awaits: the handler is async, and
// comparing a Promise against undefined would pass for the wrong reason.
//
// omp vetoes only from `tool_call`, so the handler is looked up under that name. A fake host that
// ignored the event name passed every test with the backstop registered on `tool_result`.
const handlers = new Map();
policy({ on: (event, fn) => handlers.set(event, fn) });
const toolCall = handlers.get("tool_call");

async function call(toolName, input, env) {
  const saved = {};
  for (const [k, v] of Object.entries(env ?? {})) {
    saved[k] = process.env[k];
    if (v === undefined) delete process.env[k];
    else process.env[k] = v;
  }
  try {
    return await toolCall({ toolName, input });
  } finally {
    for (const [k, v] of Object.entries(saved)) {
      if (v === undefined) delete process.env[k];
      else process.env[k] = v;
    }
  }
}

async function run(command, env) {
  return call("bash", { command }, env);
}

// Each command with a fragment of the reason its own rule gives, so a command refused by the
// wrong rule fails and a rule another rule shadows cannot hide.
const MUST_BLOCK = [
  // A refspec this port cannot read is not a refspec. `git push origin HEAD` and a bare
  // `git push` land on whatever the checkout is on, which from a trunk checkout is trunk, and a
  // quoted refspec hid the destination from the colon split.
  ["git push origin HEAD", "current branch"],
  ["git push", "explicit refspec"],
  ["git push origin", "explicit refspec"],
  ["git push --force origin", "explicit refspec"],
  ["git push origin 'HEAD:main'", "pushing to trunk"],
  ["gh pr edit 12 \\\n  --base main", "retargeting"],
  ["gh pr merge 12 \\\n  --auto", "merge-when-ready"],
  ["gh --repo o/r pr merge 12 \\\n  --squash", "merging a pull request"],
  // The forms that defeated the first version of this file.
  ["gh --repo o/r pr merge 12 --squash", "merging a pull request"],
  ["gh --repo o/r pr edit 12 --base main", "retargeting"],
  ["gh --repo o/r pr review 12 --approve", "posting a review"],
  ["gh --repo o/r issue close 5", "closing, reopening"],
  ["git push origin HEAD:main", "pushing to trunk"],
  ["git push origin main:main", "pushing to trunk"],
  ["git push origin HEAD:refs/heads/main", "pushing to trunk"],
  ["git push origin +main", "pushing to trunk"],
  ["git push origin :feature/x", "deleting a branch on the forge"],
  ["git push --mirror git@github.com:o/r.git", "mirroring"],
  ["git update-ref refs/heads/main abc123", "local history"],
  [
    'gh api graphql -f query=\'mutation{mergePullRequest(input:{pullRequestId:"x"}){clientMutationId}}\'',
    "merging through the API",
  ],
  ["gh api -X PATCH repos/o/r/pulls/12 -f state=closed", "closing, reopening"],
  ["gh api -X DELETE /repos/o/r/git/refs/heads/main", "closing, reopening"],
  // The forms it always caught.
  ["gh pr merge 12 --squash --delete-branch", "merging a pull request"],
  ["gh pr merge 12 --squash --auto", "merge-when-ready"],
  ["gh pr edit 12 --base main", "retargeting"],
  ["gh pr close 12", "closing, reopening"],
  ["gh pr review 12 --approve", "posting a review"],
  ["git push --force origin main", "rewriting history"],
  ["git push origin main --force-with-lease", "rewriting history"],
  ["git push origin --delete feature/x", "deleting a branch on the forge"],
  ["git branch -D feature/x", "local history"],
  ["gh api repos/o/r/pulls/12/merge -X PUT", "merging through the API"],
  ["gt submit --stack", "merging through Graphite"],
  ['if [ -z "$x" ]; then gh pr merge 3; fi', "merging a pull request"],
  ["cd /tmp && gh pr merge 9 --squash", "merging a pull request"],
  // git's global options between the binary and the subcommand. A push scan keyed on two
  // adjacent raw tokens of exactly `git` then `push` found none of these; the first of them was
  // executed against a real bare remote and created refs/heads/trunk there.
  ["git -C /tmp/bypass/work push -q origin HEAD:trunk", "pushing to trunk"],
  ["git -c user.name=bot push origin HEAD:main", "pushing to trunk"],
  ["git --git-dir=/tmp/repo/.git push origin main", "pushing to trunk"],
  ["git --work-tree=/tmp/wt push origin HEAD:refs/heads/main", "pushing to trunk"],
  ["git --namespace=refs/ns push origin master", "pushing to trunk"],
  ["git --exec-path=/usr/lib/git-core push origin develop", "pushing to trunk"],
  ["/usr/bin/git push origin HEAD:main", "pushing to trunk"],
  ["/usr/bin/git -C /tmp/work push origin HEAD", "current branch"],
  ["git --git-dir=/tmp/repo/.git push", "explicit refspec"],
  ["git -c core.hooksPath=/dev/null push origin release", "pushing to trunk"],
  ["git --bare push origin HEAD:trunk", "pushing to trunk"],
  ["git -C /tmp/repo push -q origin :feature/x", "deleting a branch on the forge"],
  ["git -C /tmp/repo push -q --mirror origin", "mirroring"],
  // The same gap defeated the local-history rules.
  ["git -C /tmp/repo branch -D feat", "local history"],
  ["git --git-dir=/tmp/repo/.git update-ref refs/heads/main abc123", "local history"],
  ["git -C /tmp/repo reflog expire --expire=now --all", "local history"],
  ["git --work-tree=/tmp/wt reset --hard origin/main", "local history"],
  // The gh verbs the enumeration never listed.
  ["gh repo delete o/r --yes", "deleting the repository"],
  ["gh --repo o/r repo delete --yes", "deleting the repository"],
  ["gh release create v1.2.3", "a release"],
  ["gh release delete v1.2.3", "a release"],
  ["gh secret set DEPLOY_TOKEN", "a secret"],
  ["gh variable set FLAG", "a secret"],
  ["gh workflow run deploy.yml --ref main", "running a workflow"],
  ["gh workflow run deploy.yml --ref=trunk", "running a workflow"],
  // A quoted subcommand is the same token to gh once the shell strips it.
  ['gh "pr" merge 12', "merging a pull request"],
  ["gh 'pr' merge 12 --squash", "merging a pull request"],
  ['gh "repo" delete o/r --yes', "deleting the repository"],
  ['gh "workflow" run deploy.yml --ref main', "running a workflow"],
  // curl reaches the same endpoints with the token already in the environment.
  ["curl -sS -X PUT https://api.github.com/repos/o/r/pulls/1/merge -d '{}'", "with curl"],
  [
    "curl --request POST -H 'Authorization: token x' https://api.github.com/repos/o/r/pulls/1/merge",
    "with curl",
  ],
  ["curl -X PATCH https://api.github.com/repos/o/r/pulls/1 -d state=closed", "with curl"],
  ["curl -X DELETE https://api.github.com/repos/o/r/git/refs/heads/main", "with curl"],
  // gh reads flags between the command group and its verb as well, so each of these is the
  // same call as its `gh -R o/r <group> <verb>` spelling above.
  ["gh pr -R o/r merge 12", "merging a pull request"],
  ["gh pr --repo o/r merge 12 --squash", "merging a pull request"],
  ["gh pr -R o/r merge 12 --auto", "merge-when-ready"],
  ["gh pr -R o/r edit 12 --base main", "retargeting"],
  ["gh pr --repo=o/r close 12", "closing, reopening"],
  ["gh pr -R o/r review 12 --approve", "posting a review"],
  ["gh issue -R o/r close 5", "closing, reopening"],
  ["gh release -R o/r create v1.2.3", "a release"],
  ["gh secret -R o/r set DEPLOY_TOKEN", "a secret"],
  ["gh workflow -R o/r run deploy.yml --ref main", "running a workflow"],
  // Merges the API rule never named, and trunk moved without a push.
  ["gh api repos/o/r/merges -f base=main -f head=feature/x", "merging through the API"],
  [
    'gh api graphql -f query=\'mutation{mergeBranch(input:{repositoryId:"r",base:"main",head:"x"}){clientMutationId}}\'',
    "merging through the API",
  ],
  [
    'gh api graphql -f query=\'mutation{enablePullRequestAutoMerge(input:{pullRequestId:"x"}){clientMutationId}}\'',
    "merge-when-ready",
  ],
  ["gh api -X PATCH repos/o/r/git/refs/heads/main -f sha=abc -F force=true", "moving a trunk branch"],
  ["gh api --method=PATCH repos/o/r/git/refs/heads/release -f sha=abc", "moving a trunk branch"],
  [
    `curl -X POST https://api.github.com/repos/o/r/merges -d '{"base":"main","head":"x"}'`,
    "with curl",
  ],
  ["gt merge", "merging through Graphite"],
  // Cutting a command line into simple commands must not open a hole. A redirection is not a
  // separator, a substitution belongs to the push it feeds, and a heredoc body can be run.
  ["git push origin 2>&1 HEAD:main", "pushing to trunk"],
  ["git push 2>&1", "explicit refspec"],
  ["git push origin $(echo feature; echo main)", "pushing to trunk"],
  ["bash <<'EOF'\ngit push origin HEAD:main\nEOF", "pushing to trunk"],
  ["cat > land.sh <<'EOF'\ngh pr merge 12 --squash\nEOF", "merging a pull request"],
  // A separator glued to a refspec is not part of it. Both of these were allowed as a push of
  // `main;`, which is not trunk.
  ["git push origin main; echo done", "pushing to trunk"],
  ["(git push origin main; true)", "pushing to trunk"],
  // A subshell still ends its commands, and a substitution inside one still feeds its push.
  ["(cd x && git push origin main)", "pushing to trunk"],
  ["(git push origin $(echo feature; echo main))", "pushing to trunk"],
  // GraphQL names a ref by node ID or inside an input list, so any ref mutation may be trunk.
  [
    'gh api graphql -f query=\'mutation{updateRef(input:{refId:"r",oid:"abc",force:true}){clientMutationId}}\'',
    "through the GraphQL API",
  ],
  [
    'gh api graphql -f query=\'mutation{updateRefs(input:{repositoryId:"r",refUpdates:[{name:"refs/heads/main",afterOid:"abc",force:true}]}){clientMutationId}}\'',
    "through the GraphQL API",
  ],
  [
    'gh api graphql -f query=\'mutation{deleteRef(input:{refId:"r"}){clientMutationId}}\'',
    "through the GraphQL API",
  ],
  [
    `curl https://api.github.com/graphql -d '{"query":"mutation{updateRef(input:{refId:\\"r\\",oid:\\"abc\\"}){clientMutationId}}"}'`,
    "through the GraphQL API",
  ],
  // A refspec the shell or git expands is only known when it runs, and it may be trunk.
  ["git push origin $(git branch --show-current)", "resolves only when it runs"],
  ["git push origin `git branch --show-current`", "resolves only when it runs"],
  ['git push origin "${BRANCH}"', "resolves only when it runs"],
  ['git push -u origin "$BRANCH"', "resolves only when it runs"],
  ['git push origin HEAD:"$(git branch --show-current)"', "resolves only when it runs"],
  ["git push origin 'refs/heads/*:refs/heads/*'", "resolves only when it runs"],
  // A backtick substitution runs the command inside it, the same as `$(...)`.
  ["echo `git push origin main`", "pushing to trunk"],
  // A comment ends at its newline whatever quotes it holds, and `$#` is a parameter, not a comment.
  ["# don't push trunk from here\ngit push origin main", "pushing to trunk"],
  ["git status # it's clean\ngit push origin HEAD:main", "pushing to trunk"],
  ["echo $#; git push origin main", "pushing to trunk"],
];

const MUST_PASS = [
  "gh pr view 12",
  "gh pr list --state open",
  "gh pr diff 12",
  "git push origin feature/x",
  "git push --force-with-lease origin feature/x",
  "git status --porcelain",
  "bun run test",
  "git push --force-with-lease origin main-menu",
  "git push --force origin feature/main-menu",
  'git commit -m "merge main into feature"',
  "gh pr list --search main",
  "git log main..HEAD",
  // The global-option tolerance must not cost the feature-branch push.
  "git -C /tmp/work push origin feature/x",
  "git --git-dir=/tmp/repo/.git push --force-with-lease origin feature/x",
  "/usr/bin/git push origin feature/x",
  "git -C /tmp/wt push --dry-run origin HEAD:main",
  "git -c user.name=bot push origin feature/head",
  "git --work-tree=/tmp/wt push -q origin feature/main-menu",
  "git -C /tmp/repo branch -d feat",
  "git update-ref -d refs/heads/feature/x",
  "git reflog expire --expire=now --all-older-than=1wk",
  "gh repo view o/r",
  "gh release list",
  "gh release view v1.2.3",
  "gh secret list",
  "gh workflow list",
  "gh workflow run deploy.yml --ref feature/x",
  "gh 'workflow' run ci.yml --ref feature/x",
  "curl -sSL https://api.github.com/repos/o/r/pulls/1",
  "curl -X GET https://api.github.com/repos/o/r",
  "gh api repos/o/r/pulls/12",
  "gh api -X GET repos/o/r/branches/main",
  // Flags after the command group must not turn a read into a mutation.
  "gh pr -R o/r view 12",
  "gh pr -R o/r list --search merge",
  // Reading a trunk ref, or moving a feature ref, is not moving trunk.
  "gh api repos/o/r/git/refs/heads/main",
  "gh api -X GET repos/o/r/git/refs/heads/main --jq .object.sha",
  "gh api -X PATCH repos/o/r/git/refs/heads/feature/main-menu -f sha=abc -F force=true",
  // A later command's arguments are not the push's refspecs.
  "git push origin feature && git rev-parse HEAD",
  "git push origin feature || git rev-parse HEAD",
  "git push origin feature; git checkout main",
  "git push origin feature | grep main",
  "git push origin feature\ngit log -1 HEAD",
  "git push origin feature 2>&1 && git rev-parse HEAD",
  "cat > notes.md <<'EOF'\nPush with git push origin feature.\nEOF\ngit rev-parse HEAD",
  // A subshell or brace group cuts the same as the commands written without it.
  "(cd x && git push origin feature && git rev-parse HEAD)",
  "{ git push origin feature; git rev-parse HEAD; }",
  // A comment is not an argument, and a redirection target is not a refspec.
  "git push origin feature # never main",
  'git push origin feature > "$LOG" 2>&1',
  // Reading a ref through GraphQL is not moving it.
  "gh api graphql -f query='query{repository(owner:\"o\",name:\"r\"){ref(qualifiedName:\"main\"){target{oid}}}}'",
];

describe("pstackpolicy", () => {
  test.each(MUST_BLOCK)("refuses %p as %p without a grant", async (command, rule) => {
    const result = await run(command, { PSTACK_LANDING_GRANT: undefined });
    expect(result?.block).toBe(true);
    expect(result?.reason).toContain(rule);
    expect(result?.reason).toContain("PSTACK_LANDING_GRANT");
  });

  test.each(MUST_PASS)("allows %p", async (command) => {
    expect(await run(command, { PSTACK_LANDING_GRANT: undefined })).toBeUndefined();
  });

  test("an operator grant lifts every rule", async () => {
    for (const [command] of MUST_BLOCK) {
      expect(await run(command, { PSTACK_LANDING_GRANT: "1" }), `granted: ${command}`)
        .toBeUndefined();
    }
  });

  test("only an explicit affirmative counts as a grant", async () => {
    for (const value of ["0", "false", "", "yes", "no"]) {
      const result = await run("gh pr merge 12 --squash", { PSTACK_LANDING_GRANT: value });
      expect(result?.block, `not a grant: ${JSON.stringify(value)}`).toBe(true);
    }
    const ok = await run("gh pr merge 12 --squash", { PSTACK_LANDING_GRANT: "true" });
    expect(ok?.block).toBeUndefined();
  });

  // omp://approval-mode.md: eval declares the exec tier and can spawn a shell, so a rule that
  // only read bash's `command` field was not a rule about the command.
  test.each([
    ["await Bun.$`gh pr merge 12 --squash`", "merging a pull request"],
    ['subprocess.run(["git", "push", "origin", "HEAD:main"])', "pushing to trunk"],
    ['await tool.bash({ command: "gh repo delete o/r --yes" })', "deleting the repository"],
    // A list literal broken over lines is still one command, and a comment inside it does not
    // open a quote that hides the rest.
    ['subprocess.run([\n    "git", "push", "origin", "feature",\n    "HEAD:main",\n])', "pushing to trunk"],
    ['subprocess.run([\n    "git", "push", "origin",  # don\'t\n    "HEAD:main",\n])', "pushing to trunk"],
    ["await Bun.$`git push origin HEAD:main`", "pushing to trunk"],
  ])("refuses the eval cell %p as %p", async (code, rule) => {
    const result = await call("eval", { language: "py", code }, { PSTACK_LANDING_GRANT: undefined });
    expect(result?.block).toBe(true);
    expect(result?.reason).toContain(rule);
  });

  test.each([
    'print("git push origin feature/x")',
    'subprocess.run(["git", "push", "origin", "feature"])\nsubprocess.run(["git", "rev-parse", "HEAD"])',
    "await Bun.$`git push origin feature`",
  ])("allows the eval cell %p", async (code) => {
    expect(await call("eval", { language: "py", code }, { PSTACK_LANDING_GRANT: undefined }))
      .toBeUndefined();
  });

  test("ignores tools that carry no command", async () => {
    expect(await toolCall({ toolName: "read", input: { command: "gh pr merge 12" } })).toBeUndefined();
    expect(await toolCall({ toolName: "bash", input: {} })).toBeUndefined();
    expect(await toolCall({ toolName: "eval", input: {} })).toBeUndefined();
  });
});
