// potetomode: reproduces Cursor's "Custom Mode" pin for pstack's /poteto-mode.
//
// Cursor pins a skill via `mode: true` + `reminder:` in SKILL.md frontmatter, so the agent gets
// re-reminded on every new turn. omp does not model either key (grep of src/capability/skill.ts and
// src/extensibility/skills.ts: no hits), so the pin is the ONE mechanically missing piece of pstack
// on omp. Everything else in pstack is portable prose, installed by symlink into
// ~/.omp/agent/skills/ (verified: skill://<name> resolves with no --plugin-dir).
//
// Pattern copied from the working reference ~/.omp/agent/extensions/ponytail/index.js:
//   pi.appendEntry(...)                persist across turns without spending context
//   session_start + getBranch()        restore the pin when a session resumes
//   before_agent_start -> systemPrompt inject the reminder every run
//   pi.registerCommand(...)            /poteto-mode as a slash command
//   c.ui.setStatus(...)                live status bar pill/indicator

const ENTRY = "poteto-mode";

// Mirrors the `reminder:` field in pstack's skills/poteto-mode/SKILL.md frontmatter.
const REMINDER =
  "poteto-mode is PINNED for this session.\n" +
  "Before acting on a new task: read `skill://poteto-mode` in full (including its Principles index), " +
  "then read `skill://omp-mechanics` for the omp-specific levers every pstack skill assumes, " +
  "match the request against its playbook table, and copy the matched playbook's steps verbatim into " +
  "your todo list as the first items. A step you skip stays listed with `skip: <reason>`.\n" +
  "Spawn code-writing delegates with the `task` tool using `agent: poteto-agent`. " +
  "Casual turns, or an explicit opt-out, do not need the playbook.";

export default function potetomode(pi) {
  let pinned = false;
  let isActive = false;

  const syncStatus = (c) => {
    if (!c?.ui?.setStatus) return;
    let theme;
    try {
      theme = c.ui.theme;
      if (!theme?.fg) return;
    } catch {
      return;
    }

    if (!pinned) {
      c.ui.setStatus("poteto-mode", "");
      return;
    }

    // Indicator matches ponytail's style: ● active, ○ idle
    const indicator = isActive ? theme.fg("accent", "●") : theme.fg("dim", "○");
    // 🥔 / 👑 poteto: PINNED
    const pill =
      indicator +
      " 🥔 " +
      theme.fg("muted", "poteto: ") +
      theme.fg("warning", "👑 PINNED");

    c.ui.setStatus("poteto-mode", pill);
  };

  const restore = (entries) => {
    // Latest entry wins; scan backwards so an unpin later in the session sticks.
    for (let i = entries.length - 1; i >= 0; i--) {
      const e = entries[i];
      // appendEntry persists {type:"custom",customType,data}; same predicate omp
      // uses to replay its own pins (src/session/mode-skills.ts:42).
      if (e?.type === "custom" && e?.customType === ENTRY) return Boolean(e.data?.pinned);
    }
    return false;
  };

  const setPinned = (next, ctx) => {
    pinned = Boolean(next);
    pi.appendEntry(ENTRY, { pinned });
    syncStatus(ctx);
    ctx?.ui?.notify?.(
      pinned ? "poteto-mode pinned for this session." : "poteto-mode unpinned.",
      "info"
    );
  };

  pi.registerCommand("poteto-mode", {
    description: "Pin pstack's poteto-mode router for this session (on|off|status; default: toggle on)",
    handler: async (args, ctx) => {
      const arg = String(args || "").trim().toLowerCase();
      if (arg === "status") {
        syncStatus(ctx);
        ctx?.ui?.notify?.(`poteto-mode: ${pinned ? "pinned" : "not pinned"}`, "info");
        return;
      }
      if (arg === "off" || arg === "unpin") return setPinned(false, ctx);
      setPinned(true, ctx);
      // A bare `/poteto-mode <task>` should also start the work, matching Cursor's ergonomics.
      const rest = String(args || "").trim();
      if (rest && !["on", "off", "pin", "unpin", "status"].includes(rest.toLowerCase())) {
        pi.sendUserMessage(rest, ctx?.isIdle?.() === false ? { deliverAs: "followUp" } : undefined);
      }
    },
  });

  // Print mode (`-p`) has no slash dispatch, so the flag is the only way a
  // headless run or subagent can start pinned.
  pi.registerFlag("poteto", {
    description: "Pin pstack's poteto-mode for this run (works in -p print mode)",
    type: "boolean",
  });

  // alt+shift+t is free in omp's keybinding registry (src/config/keybindings.ts,
  // packages/tui/src/keybindings.ts) and not in runner.ts's reserved list.
  pi.registerShortcut("alt+shift+t", {
    description: "Toggle poteto-mode pin",
    handler: (ctx) => setPinned(!pinned, ctx),
  });

  pi.on("session_start", async (_event, ctx) => {
    const entries = ctx?.sessionManager?.getBranch?.() || ctx?.sessionManager?.getEntries?.() || [];
    pinned = restore(entries);
    syncStatus(ctx);
  });

  pi.on("agent_start", async (_event, ctx) => {
    isActive = true;
    syncStatus(ctx);
  });

  pi.on("agent_end", async (_event, ctx) => {
    isActive = false;
    syncStatus(ctx);
  });

  pi.on("before_agent_start", async (event) => {
    if (!pinned && pi.getFlag?.("poteto") !== true) return;
    // systemPrompt is an ordered block list; interpolating it comma-joins the
    // blocks and collapses the provider's cache segmentation.
    const raw = event?.systemPrompt;
    const blocks = Array.isArray(raw) ? raw : raw ? [raw] : [];
    return { systemPrompt: [...blocks, REMINDER] };
  });
}
