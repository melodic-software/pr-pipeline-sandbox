// Probe 0b re-run report: reads run-claude-cli's execution file and prints one
// probe line of booleans and counts. It prints no tool result text.
// Usage: node report.mjs <execution-file> <lane-class> <run-url>
import fs from "node:fs";

const [file, laneClass, runUrl] = process.argv.slice(2);
const MARKER = "PROBE-0B-V053-MARKER-91C2";
let messages = [];
try {
  messages = JSON.parse(fs.readFileSync(file, "utf8"));
} catch {
  // An unreadable file leaves every check false.
}

const init = messages.find((m) => m?.type === "system" && m?.subtype === "init") ?? {};
const skills = Array.isArray(init.skills) ? init.skills : [];
const plugins = Array.isArray(init.plugins) ? init.plugins : [];
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
  (t) => t.name === "Read" && String(t.input?.file_path ?? "").endsWith("reference/x.md"),
);
const readResult = readUse ? results.get(readUse.id) : undefined;
const readOk = Boolean(readResult) && readResult.is_error !== true && text(readResult).includes(MARKER);
const final = messages.findLast((m) => m?.type === "result");
const replied = typeof final?.result === "string" && final.result.includes(MARKER);
const denials = Array.isArray(final?.permission_denials) ? final.permission_denials.length : 0;

const pass = skillOk && readOk;
console.log(
  [
    `probe=b-release result=${pass ? "pass" : "fail"}`,
    `run=${runUrl}`,
    `lane-class=${laneClass || "none"}`,
    `plugin-listed=${plugins.some((p) => String(p?.name ?? p).includes("probe-plugin"))}`,
    `skill-listed=${skills.some((s) => String(s).includes("probe-skill"))}`,
    `skill-invoked=${skillOk}`,
    `read-reference=${readOk}`,
    `read-denied=${readResult?.is_error === true}`,
    `permission-denials=${denials}`,
    `replied-marker=${replied}`,
    `tools-used=${[...new Set(toolUses.map((t) => t.name))].join(",") || "none"}`,
    `turns=${final?.num_turns ?? "?"}`,
  ].join(" "),
);
