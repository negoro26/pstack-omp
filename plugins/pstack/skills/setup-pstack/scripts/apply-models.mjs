#!/usr/bin/env node
// Applies setup-pstack's model choices to omp config, checked against `omp models --json` first.
// `omp config set` stores any string, so an unknown selector or alias otherwise fails only at spawn.
//
// Data shape.
//   OWNED_ALIASES are the only modelRoles keys this script writes.
//   A Selection is { alias, base, effort }: base is a `selector` from the catalog, effort is null or
//   an EFFORTS member that the model's `thinking` list names. It is written as base or base:effort.
//   A task.agentModelOverrides entry is pstack-owned only when its key is an exact agent name and
//   its value is one of OWNED_VALUES. Every other entry in both records keeps its key, value, and order.
import { spawnSync } from "node:child_process";

const OWNED_ALIASES = ["pstack_fast_code", "pstack_judgment", "pstack_instruction"];
const OWNED_VALUES = OWNED_ALIASES.map((alias) => `@${alias}`);
const EFFORTS = ["max", "xhigh", "high", "medium", "low", "minimal"];
const RECORDS = { roles: "modelRoles", overrides: "task.agentModelOverrides" };
const USAGE = `usage: apply-models.mjs --show
       apply-models.mjs [--dry-run] [--alias <pstack alias>=<provider/model>[:effort]]...
                        [--agent <exact agent name>=@<pstack alias>]... [--unset-agent <exact agent name>]...`;

const fail = (message) => {
	throw new Error(message);
};

function omp(...args) {
	const run = spawnSync("omp", args, { encoding: "utf8" });
	if (run.error) fail(`cannot run omp: ${run.error.message}`);
	if (run.status !== 0) fail(`omp ${args.slice(0, 3).join(" ")} exited ${run.status}: ${(run.stderr || run.stdout).trim()}`);
	return run.stdout;
}

function parseArgs(argv) {
	const request = { show: false, dryRun: false, aliases: new Map(), agents: new Map() };
	const add = (map, key, value) => (map.has(key) ? fail(`${key} is given twice`) : map.set(key, value));
	for (let i = 0; i < argv.length; i++) {
		const flag = argv[i];
		const value = () => {
			const next = argv[++i];
			return next && !next.startsWith("--") ? next : fail(`${flag} needs a value\n${USAGE}`);
		};
		const pair = () => {
			const next = value();
			const eq = next.indexOf("=");
			return eq > 0 && eq < next.length - 1 ? [next.slice(0, eq), next.slice(eq + 1)] : fail(`${flag} expects <key>=<value>, got "${next}"`);
		};
		if (flag === "--show") request.show = true;
		else if (flag === "--dry-run") request.dryRun = true;
		else if (flag === "--alias") add(request.aliases, ...pair());
		else if (flag === "--agent") add(request.agents, ...pair());
		else if (flag === "--unset-agent") add(request.agents, value(), null);
		else fail(`unknown argument "${flag}"\n${USAGE}`);
	}
	const edits = request.aliases.size + request.agents.size;
	if (request.show && (edits || request.dryRun)) fail("--show takes no other argument");
	if (!request.show && !edits) fail(`nothing to do\n${USAGE}`);
	return request;
}

function readCatalog() {
	const { models } = JSON.parse(omp("models", "--json"));
	return new Map(models.map((model) => [model.selector, Array.isArray(model.thinking) ? model.thinking : []]));
}

// A value that is itself a selector wins, so a colon inside a selector is never read as an effort.
// Otherwise only a known effort suffix is split off; any other colon fragment stays part of the base.
function parseSelection(alias, value, catalog) {
	if (!OWNED_ALIASES.includes(alias)) fail(`--alias ${alias}: not a pstack alias, use one of ${OWNED_ALIASES.join(", ")}`);
	if (catalog.has(value)) return { alias, base: value, effort: null };
	const cut = value.lastIndexOf(":");
	const base = value.slice(0, cut);
	const effort = value.slice(cut + 1);
	const suffixed = cut > 0 && EFFORTS.includes(effort);
	if (!suffixed || !catalog.has(base)) fail(`--alias ${alias}=${value}: ${suffixed ? base : value} is not a selector in \`omp models --json\``);
	const supported = catalog.get(base);
	if (!supported.includes(effort)) fail(`--alias ${alias}=${value}: ${base} supports ${supported.join(", ") || "no effort suffix"}, not ${effort}`);
	return { alias, base, effort };
}

function plan(current, request, catalog) {
	const roles = { ...current.roles };
	for (const [alias, value] of request.aliases) {
		const { base, effort } = parseSelection(alias, value, catalog);
		roles[alias] = effort ? `${base}:${effort}` : base;
	}
	const overrides = { ...current.overrides };
	for (const [agent, value] of request.agents) {
		const held = overrides[agent];
		if (held !== undefined && !OWNED_VALUES.includes(held)) fail(`${agent} maps to ${JSON.stringify(held)}, which pstack does not own; change it with \`omp config\` yourself`);
		if (value === null) {
			delete overrides[agent];
			continue;
		}
		if (agent.startsWith("pstack_")) fail(`--agent ${agent}: a pstack alias is not an agent name`);
		if (!OWNED_VALUES.includes(value)) fail(`--agent ${agent}=${value}: use one of ${OWNED_VALUES.join(", ")}`);
		const alias = value.slice(1);
		if (!Object.hasOwn(roles, alias)) fail(`--agent ${agent}=${value}: modelRoles has no ${alias}, add --alias ${alias}=<selector>`);
		overrides[agent] = value;
	}
	return { roles, overrides };
}

function describe({ roles, overrides }) {
	const lines = OWNED_ALIASES.map((alias) => `${alias} = ${roles[alias] ?? "(unset)"}`);
	for (const [agent, value] of Object.entries(overrides)) {
		if (OWNED_VALUES.includes(value)) lines.push(`${agent} -> ${value} -> ${roles[value.slice(1)] ?? "(unset)"}`);
	}
	const families = new Set(OWNED_ALIASES.filter((alias) => roles[alias]).map((alias) => String(roles[alias]).split("/")[0]));
	lines.push(`model families: ${families.size}${families.size === 1 ? ", weaker diversity: one family" : ""}`);
	return lines.join("\n");
}

function changes(before, after, record) {
	return [...new Set([...Object.keys(before), ...Object.keys(after)])]
		.filter((key) => before[key] !== after[key])
		.map((key) => `  ${record}.${key}: ${before[key] ?? "(unset)"} -> ${after[key] ?? "(removed)"}`);
}

function main(argv) {
	const request = parseArgs(argv);
	const current = {};
	for (const [field, record] of Object.entries(RECORDS)) current[field] = JSON.parse(omp("config", "get", record, "--json")).value;
	if (request.show) return console.log(describe(current));
	const next = plan(current, request, request.aliases.size ? readCatalog() : new Map());
	const stale = Object.keys(RECORDS).filter((field) => JSON.stringify(current[field]) !== JSON.stringify(next[field]));
	if (!stale.length) return console.log(`no change: config already matches\n${describe(next)}`);
	const diff = stale.flatMap((field) => changes(current[field], next[field], RECORDS[field]));
	console.log([request.dryRun ? "planned changes:" : "changes:", ...diff, describe(next)].join("\n"));
	if (request.dryRun) return console.log("dry run: nothing written");
	// modelRoles goes first, so an override never lands pointing at an alias that is not written yet.
	for (const [i, field] of stale.entries()) {
		try {
			omp("config", "set", RECORDS[field], JSON.stringify(next[field]));
		} catch (error) {
			const landed = stale.slice(0, i).map((done) => RECORDS[done]);
			const recovery = landed.length
				? `${landed.join(", ")} was written and ${RECORDS[field]} was not. Rerun the same command to finish; it writes only what still differs.`
				: "nothing was written";
			console.error(`apply-models: ${error.message}\n${recovery}`);
			process.exit(1);
		}
	}
	console.log(`written: ${stale.map((field) => RECORDS[field]).join(", ")}`);
}

try {
	main(process.argv.slice(2));
} catch (error) {
	console.error(`apply-models: refused: ${error.message}\nnothing was written`);
	process.exit(1);
}
