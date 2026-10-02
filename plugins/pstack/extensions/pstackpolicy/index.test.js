import { describe, expect, test } from "bun:test";
import policy, { DENY_REASONS } from "./index.js";

// The handler is the whole backstop, so it is tested against commands that must be refused and
// commands that must not be. A rule set that blocks nothing is indistinguishable from no
// backstop at all until something tries to merge. Every call awaits: the handler is async, and
// comparing a Promise against undefined would pass for the wrong reason.
async function call(toolName, input, env) {
  const saved = {};
  for (const [k, v] of Object.entries(env ?? {})) {
    saved[k] = process.env[k];
    if (v === undefined) delete process.env[k];
    else process.env[k] = v;
  }
  let handler;
  policy({ on: (_event, fn) => { handler = fn; } });
  try {
    return await handler({ toolName, input });
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

const MUST_BLOCK = [
  // A refspec this port cannot read is not a refspec. `git push origin HEAD` and a bare
  // `git push` land on whatever the checkout is on, which from a trunk checkout is trunk, and a
  // quoted refspec hid the destination from the colon split.
  "git push origin HEAD",
  "git push",
  "git push origin",
  "git push --force origin",
  "git push origin 'HEAD:main'",
  "gh pr edit 12 \\\n  --base main",
  "gh pr merge 12 \\\n  --auto",
  "gh --repo o/r pr merge 12 \\\n  --squash",
  // The forms that defeated the first version of this file.
  "gh --repo o/r pr merge 12 --squash",
  "gh --repo o/r pr edit 12 --base main",
  "gh --repo o/r pr review 12 --approve",
  "gh --repo o/r issue close 5",
  "git push origin HEAD:main",
  "git push origin main:main",
  "git push origin HEAD:refs/heads/main",
  "git push origin +main",
  "git push origin :feature/x",
  "git push --mirror git@github.com:o/r.git",
  "git update-ref refs/heads/main abc123",
  'gh api graphql -f query=\'mutation{mergePullRequest(input:{pullRequestId:"x"}){clientMutationId}}\'',
  "gh api -X PATCH repos/o/r/pulls/12 -f state=closed",
  "gh api -X DELETE /repos/o/r/git/refs/heads/main",
  // The forms it always caught.
  "gh pr merge 12 --squash --delete-branch",
  "gh pr merge 12 --squash --auto",
  "gh pr edit 12 --base main",
  "gh pr close 12",
  "gh pr review 12 --approve",
  "git push --force origin main",
  "git push origin main --force-with-lease",
  "git push origin --delete feature/x",
  "git branch -D feature/x",
  "gh api repos/o/r/pulls/12/merge -X POST",
  "gt submit --stack",
  "if [ -z \"$x\" ]; then gh pr merge 3; fi",
  "cd /tmp && gh pr merge 9 --squash",
  // git's global options between the binary and the subcommand. A push scan keyed on two
  // adjacent raw tokens of exactly `git` then `push` found none of these; the first of them was
  // executed against a real bare remote and created refs/heads/trunk there.
  "git -C /tmp/bypass/work push -q origin HEAD:trunk",
  "git -c user.name=bot push origin HEAD:main",
  "git --git-dir=/tmp/repo/.git push origin main",
  "git --work-tree=/tmp/wt push origin HEAD:refs/heads/main",
  "git --namespace=refs/ns push origin master",
  "git --exec-path=/usr/lib/git-core push origin develop",
  "/usr/bin/git push origin HEAD:main",
  "/usr/bin/git -C /tmp/work push origin HEAD",
  "git --git-dir=/tmp/repo/.git push",
  "git -c core.hooksPath=/dev/null push origin release",
  "git --bare push origin HEAD:trunk",
  "git -C /tmp/repo push -q origin :feature/x",
  "git -C /tmp/repo push -q --mirror origin",
  // The same gap defeated the local-history rules.
  "git -C /tmp/repo branch -D feat",
  "git --git-dir=/tmp/repo/.git update-ref refs/heads/main abc123",
  "git -C /tmp/repo reflog expire --expire=now --all",
  "git --work-tree=/tmp/wt reset --hard origin/main",
  // The gh verbs the enumeration never listed.
  "gh repo delete o/r --yes",
  "gh --repo o/r repo delete --yes",
  "gh release create v1.2.3",
  "gh release delete v1.2.3",
  "gh secret set DEPLOY_TOKEN",
  "gh variable set FLAG",
  "gh workflow run deploy.yml --ref main",
  "gh workflow run deploy.yml --ref=trunk",
  // A quoted subcommand is the same token to gh once the shell strips it.
  'gh "pr" merge 12',
  "gh 'pr' merge 12 --squash",
  'gh "repo" delete o/r --yes',
  'gh "workflow" run deploy.yml --ref main',
  // curl reaches the same endpoints with the token already in the environment.
  "curl -sS -X PUT https://api.github.com/repos/o/r/pulls/1/merge -d '{}'",
  "curl --request POST -H 'Authorization: token x' https://api.github.com/repos/o/r/pulls/1/merge",
  "curl -X PATCH https://api.github.com/repos/o/r/pulls/1 -d state=closed",
  "curl -X DELETE https://api.github.com/repos/o/r/git/refs/heads/main",
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
  "git commit -m \"merge main into feature\"",
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
];

describe("pstackpolicy", () => {
  test("refuses every forge mutation when no grant is set", async () => {
    for (const command of MUST_BLOCK) {
      const result = await run(command, { PSTACK_LANDING_GRANT: undefined });
      expect(result?.block, `should block: ${command}`).toBe(true);
      expect(result?.reason, `should explain: ${command}`).toContain("PSTACK_LANDING_GRANT");
    }
  });

  test("allows reads and ordinary pushes to pass through", async () => {
    for (const command of MUST_PASS) {
      expect(await run(command, { PSTACK_LANDING_GRANT: undefined }), `should pass: ${command}`)
        .toBeUndefined();
    }
  });

  test("an operator grant lifts every rule", async () => {
    for (const command of MUST_BLOCK) {
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

  test("an eval cell is gated the same way a bash call is", async () => {
    // omp://approval-mode.md: eval declares the exec tier and can spawn a shell, so a rule that
    // only read bash's `command` field was not a rule about the command.
    for (const code of [
      'await Bun.$`gh pr merge 12 --squash`',
      'subprocess.run(["git", "push", "origin", "HEAD:main"])',
      'await tool.bash({ command: "gh repo delete o/r --yes" })',
    ]) {
      const result = await call("eval", { language: "js", code }, { PSTACK_LANDING_GRANT: undefined });
      expect(result?.block, `should block: ${code}`).toBe(true);
      expect(result?.reason, `should explain: ${code}`).toContain("PSTACK_LANDING_GRANT");
    }
  });

  test("an eval cell with no forge mutation still passes", async () => {
    const ok = await call(
      "eval",
      { language: "py", code: 'print("git push origin feature/x")' },
      { PSTACK_LANDING_GRANT: undefined }
    );
    expect(ok?.block).toBeUndefined();
  });

  test("ignores tools that carry no command", async () => {
    let handler;
    policy({ on: (_e, fn) => { handler = fn; } });
    expect(await handler({ toolName: "read", input: { command: "gh pr merge 12" } })).toBeUndefined();
    expect(await handler({ toolName: "bash", input: {} })).toBeUndefined();
    expect(await handler({ toolName: "eval", input: {} })).toBeUndefined();
  });

  test("every rule carries a reason the port can assert on", () => {
    expect(DENY_REASONS.length).toBeGreaterThan(0);
    for (const why of DENY_REASONS) expect(typeof why).toBe("string");
  });
});