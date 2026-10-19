// Phase 0b probe report: reads run-claude-cli's execution file and prints one
// probe line of booleans and counts. It prints no tool result text.
// Usage: node report.mjs <execution-file> <lane-class> <runner-temp> <run-url>
import fs from "node:fs";

const [file, laneClass, runnerTemp, runUrl] = process.argv.slice(2);
const MARKER = "PROBE-0B-MARKER-7F3A";
let messages = [];
try {
  messages = JSON.parse(fs.readFileSync(file, "utf8"));
} catch {
  // An unreadable file leaves every check false.
}

const init = messages.find((m) => m?.type === "system" && m?.subtype === "init") ?? {};
const skills = Array.isArray(init.skills) ? init.skills : [];
const plugins = Array.isArray(init.plugins) ? init.plugins : [];
const mcp = Array.isArray(init.mcp_servers) ? init.mcp_servers : [];
const toolUses = messages
  .filter((m) => m?.type === "assistant")
  .flatMap((m) => m.message?.content ?? [])
  .filter((c) => c?.type === "tool_use");
const results = new Map(
  messages
    .filter((m) => m?.type === "user")
    .flatMap((m) => (Array.isArray(m.message?.content) ? m.message.content : []))
    .filter((c) => c?.type === "tool_result")
    .map((c) => [c.tool_use_id, c]),
);
const text = (r) =>
  typeof r?.content === "string"
    ? r.content
    : (r?.content ?? []).map((c) => c?.text ?? "").join("");

const skillUse = toolUses.find((t) => t.name === "Skill");
const skillOk = Boolean(skillUse) && results.get(skillUse.id)?.is_error !== true;
const readUse = toolUses.find(
  (t) => t.name === "Read" && String(t.input?.file_path ?? "").endsWith("reference/marker.md"),
);
const readResult = readUse ? results.get(readUse.id) : undefined;
const readOk = Boolean(readResult) && readResult.is_error !== true && text(readResult).includes(MARKER);
const final = messages.findLast((m) => m?.type === "result");
const replied = typeof final?.result === "string" && final.result.includes(MARKER);
const fired = (kind) =>
  [runnerTemp, "/tmp"].some((d) => d && fs.existsSync(`${d}/probe-0b-${kind}-fired`));
const mcpEntry = mcp.find((s) => String(s?.name ?? "").includes("probe-mcp"));
const readDenied = readResult?.is_error === true;
// The denial text for the marker file read only, cut short and reduced to a
// plain character set.
const denial = readDenied
  ? text(readResult).replace(/[^\w ./:'()-]/gu, " ").replace(/\s+/gu, "_").slice(0, 160)
  : "none";
const readPath = String(readUse?.input?.file_path ?? "");
const readUnderStaged = readPath.startsWith(`${runnerTemp}/staged-plugins/`);
const denials = Array.isArray(final?.permission_denials) ? final.permission_denials.length : 0;

const pass = skillOk && readOk;
const fields = [
  `probe=b result=${pass ? "pass" : "fail"}`,
  `run=${runUrl}`,
  `lane-class=${laneClass || "none"}`,
  `plugin-listed=${plugins.some((p) => String(p?.name ?? p).includes("probe-plugin"))}`,
  `skill-listed=${skills.some((s) => String(s).includes("probe-skill"))}`,
  `skill-invoked=${skillOk}`,
  `read-reference=${readOk}`,
  `read-denied=${readDenied}`,
  `read-under-staged-dir=${readUnderStaged}`,
  `permission-denials=${denials}`,
  `denial=${denial}`,
  `replied-marker=${replied}`,
  `hook-fired=${fired("hook")}`,
  `mcp-fired=${fired("mcp")}`,
  `mcp-listed=${mcpEntry ? String(mcpEntry.status ?? "listed").replace(/[^\w-]/gu, "") : "no"}`,
  `tools-used=${[...new Set(toolUses.map((t) => t.name))].join(",") || "none"}`,
  `turns=${final?.num_turns ?? "?"}`,
];
console.log(fields.join(" "));
