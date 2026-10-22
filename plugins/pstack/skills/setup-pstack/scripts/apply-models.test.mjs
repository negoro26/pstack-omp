import { afterAll, expect, test } from "bun:test";
import { spawnSync } from "node:child_process";
import { chmodSync, mkdtempSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";

const SCRIPT = join(import.meta.dir, "apply-models.mjs");
const BIN = mkdtempSync(join(tmpdir(), "apply-models-"));
const STATE = join(BIN, "state.json");
const ROLES = "modelRoles";
const OVERRIDES = "task.agentModelOverrides";
const MODELS = [
	{ selector: "acme/model-a", thinking: ["low", "medium", "high", "xhigh", "max"] },
	{ selector: "acme/model-b", thinking: ["low", "medium", "high"] },
	{ selector: "acme/model-plain", thinking: null },
	{ selector: "relay/acme/model-a:batch", thinking: ["minimal", "low", "high"] },
	{ selector: "other/model-c", thinking: ["high"] },
	{ selector: "acme/model-odd", thinking: ["high", "turbo"] },
];

// A stand-in for omp's CLI surface the script uses, backed by one JSON file the tests read back.
writeFileSync(
	join(BIN, "omp-stub.mjs"),
	`import { readFileSync, writeFileSync } from "node:fs";
const state = JSON.parse(readFileSync(process.env.OMP_STUB_STATE, "utf8"));
const [command, action, key, value] = process.argv.slice(2);
if (command === "models") process.stdout.write(JSON.stringify({ models: state.models }));
else if (command === "config" && action === "get") process.stdout.write(JSON.stringify({ key, value: state.config[key], type: "record" }));
else if (command === "config" && action === "set" && state.failSet !== key) {
	state.config[key] = JSON.parse(value);
	state.sets += 1;
	writeFileSync(process.env.OMP_STUB_STATE, JSON.stringify(state));
} else {
	process.stderr.write("Error: simulated failure");
	process.exit(1);
}
`,
);
writeFileSync(join(BIN, "omp"), `#!/bin/sh\nexec "${process.execPath}" "${join(BIN, "omp-stub.mjs")}" "$@"\n`);
chmodSync(join(BIN, "omp"), 0o755);
afterAll(() => rmSync(BIN, { recursive: true, force: true }));

function setup(config = {}, extra = {}) {
	writeFileSync(STATE, JSON.stringify({ models: MODELS, config: { [ROLES]: {}, [OVERRIDES]: {}, ...config }, sets: 0, ...extra }));
}
const state = () => JSON.parse(readFileSync(STATE, "utf8"));
const ordered = (record) => JSON.stringify(state().config[record]);
function run(...args) {
	const env = { ...process.env, PATH: `${BIN}:${process.env.PATH}`, OMP_STUB_STATE: STATE };
	const result = spawnSync(process.execPath, [SCRIPT, ...args], { encoding: "utf8", env });
	return { code: result.status, out: result.stdout, err: result.stderr };
}
const OPERATOR = {
	[ROLES]: { default: "acme/model-b", pstack_judgment: "acme/model-b:low", smol: "@default" },
	[OVERRIDES]: { explore: "acme/model-b", reviewer: "@pstack_judgment", helper: "@smol" },
};

test("writes owned entries and keeps every unrelated key, value, and order", () => {
	setup(OPERATOR);
	const result = run(
		"--alias", "pstack_judgment=acme/model-a:max",
		"--alias", "pstack_fast_code=relay/acme/model-a:batch:minimal",
		"--alias", "pstack_instruction=relay/acme/model-a:batch",
		"--agent", "task=@pstack_fast_code",
		"--unset-agent", "reviewer",
	);
	expect(result.code).toBe(0);
	expect(ordered(ROLES)).toBe(
		JSON.stringify({
			default: "acme/model-b",
			pstack_judgment: "acme/model-a:max",
			smol: "@default",
			pstack_fast_code: "relay/acme/model-a:batch:minimal",
			pstack_instruction: "relay/acme/model-a:batch",
		}),
	);
	expect(ordered(OVERRIDES)).toBe(JSON.stringify({ explore: "acme/model-b", helper: "@smol", task: "@pstack_fast_code" }));
});

test("refuses a base that is not a catalog selector and writes neither record", () => {
	for (const bad of ["acme/model-z:high", "acme/model-z", "acme/model-a:batch", "acme/model-a:"]) {
		setup(OPERATOR);
		const result = run("--alias", "pstack_fast_code=acme/model-a:high", "--alias", `pstack_judgment=${bad}`, "--agent", "task=@pstack_fast_code");
		expect(result.code).not.toBe(0);
		expect(state().config).toEqual(OPERATOR);
	}
});

test("refuses an effort off the ladder or missing from the selected model's list", () => {
	for (const bad of ["acme/model-b:max", "acme/model-plain:low", "other/model-c:minimal", "acme/model-odd:turbo"]) {
		setup(OPERATOR);
		expect(run("--alias", `pstack_judgment=${bad}`).code).not.toBe(0);
		expect(state().config).toEqual(OPERATOR);
	}
	expect(run("--alias", "pstack_judgment=acme/model-b:high").code).toBe(0);
	expect(state().config[ROLES].pstack_judgment).toBe("acme/model-b:high");
});

test("refuses an agent value that is not a defined pstack alias, before any write", () => {
	for (const bad of ["@pstack_bogus", "@default", "acme/model-a", "@pstack_instruction"]) {
		setup(OPERATOR);
		const result = run("--alias", "pstack_fast_code=acme/model-a", "--agent", `task=${bad}`);
		expect(result.code).not.toBe(0);
		expect(state().config).toEqual(OPERATOR);
	}
});

test("refuses to change or remove an agent entry pstack does not own", () => {
	for (const args of [["--unset-agent", "explore"], ["--agent", "explore=@pstack_judgment"], ["--agent", "helper=@pstack_judgment"]]) {
		setup(OPERATOR);
		expect(run(...args).code).not.toBe(0);
		expect(state().config).toEqual(OPERATOR);
	}
});

test("a second identical run writes nothing and says so", () => {
	setup(OPERATOR);
	const args = ["--alias", "pstack_judgment=acme/model-a:high", "--agent", "task=@pstack_judgment", "--unset-agent", "reviewer"];
	expect(run(...args).code).toBe(0);
	const after = state();
	expect(after.sets).toBeGreaterThan(0);
	const again = run(...args);
	expect(again.code).toBe(0);
	expect(again.out).toContain("no change");
	expect(state()).toEqual(after);
});

test("a failed second write is reported with the rerun that finishes it", () => {
	setup(OPERATOR, { failSet: OVERRIDES });
	const args = ["--alias", "pstack_judgment=acme/model-a:high", "--agent", "task=@pstack_judgment"];
	const failed = run(...args);
	expect(failed.code).not.toBe(0);
	expect(state().config[ROLES].pstack_judgment).toBe("acme/model-a:high");
	expect(state().config[OVERRIDES]).toEqual(OPERATOR[OVERRIDES]);
	expect(failed.err).toContain(`${ROLES} was written and ${OVERRIDES} was not`);
	expect(failed.err).toContain("Rerun the same command");
	writeFileSync(STATE, JSON.stringify({ ...state(), failSet: null }));
	expect(run(...args).code).toBe(0);
	expect(state().config[OVERRIDES]).toEqual({ ...OPERATOR[OVERRIDES], task: "@pstack_judgment" });
});

test("one model family is reported as information, never refused", () => {
	setup();
	const one = run("--alias", "pstack_fast_code=acme/model-b:low", "--alias", "pstack_judgment=acme/model-a:max", "--alias", "pstack_instruction=acme/model-a");
	expect(one.code).toBe(0);
	expect(state().config[ROLES]).toEqual({ pstack_fast_code: "acme/model-b:low", pstack_judgment: "acme/model-a:max", pstack_instruction: "acme/model-a" });
	expect(one.out).toContain("model families: 1, weaker diversity: one family");
	const two = run("--alias", "pstack_judgment=other/model-c:high");
	expect(two.code).toBe(0);
	expect(two.out).toContain("model families: 2");
	expect(two.out).not.toContain("weaker diversity");
});

test("--show lists each pstack-owned agent with the model it resolves to", () => {
	setup(OPERATOR);
	const shown = run("--show");
	expect(shown.code).toBe(0);
	expect(shown.out).toMatch(/^reviewer -> @pstack_judgment -> acme\/model-b:low$/m);
	expect(shown.out).not.toContain("explore");
	expect(shown.out).not.toContain("helper");
	expect(state().sets).toBe(0);
});

test("--dry-run prints the planned change and writes nothing", () => {
	setup(OPERATOR);
	const planned = run("--dry-run", "--alias", "pstack_judgment=acme/model-a:high", "--agent", "task=@pstack_judgment");
	expect(planned.code).toBe(0);
	expect(planned.out).toContain(`${ROLES}.pstack_judgment: acme/model-b:low -> acme/model-a:high`);
	expect(planned.out).toContain(`${OVERRIDES}.task: (unset) -> @pstack_judgment`);
	expect(state().config).toEqual(OPERATOR);
	expect(state().sets).toBe(0);
});

test("refuses unknown or malformed arguments", () => {
	setup(OPERATOR);
	const cases = [
		[],
		["--model", "acme/model-a", "--alias", "pstack_judgment=acme/model-a"],
		["--alias", "pstack_judgment"],
		["--alias", "pstack_other=acme/model-a"],
		["--alias", "pstack_judgment=acme/model-a", "--alias", "pstack_judgment=acme/model-b"],
		["--agent", "pstack_judgment=@pstack_judgment", "--alias", "pstack_judgment=acme/model-a"],
		["--unset-agent", "--dry-run"],
		["--show", "--alias", "pstack_judgment=acme/model-a"],
	];
	for (const args of cases) expect(run(...args).code).not.toBe(0);
	expect(state().config).toEqual(OPERATOR);
	expect(state().sets).toBe(0);
});
