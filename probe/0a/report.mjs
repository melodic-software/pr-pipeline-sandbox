// Phase 0a probe report: reads run-claude-cli's JSONL log (credential-scanned
// by the action) and prints one probe line naming the leg and its models.
// Usage: node report.mjs <leg-name> <log-file> <lane-class> <lane-models> <run-url>
import fs from "node:fs";

const [leg, logFile, laneClass, laneModels, runUrl] = process.argv.slice(2);
let records = [];
try {
  records = fs
    .readFileSync(logFile, "utf8")
    .split("\n")
    .filter(Boolean)
    .map((line) => JSON.parse(line));
} catch {
  // No log: the line reports what the outputs say.
}
const last = records.at(-1) ?? {};
const models = Object.keys(last.models_used ?? {});
const clean = (v) => String(v ?? "").replace(/[^\w.,:@[\]-]/gu, "");
const pass = (laneClass ?? "") === "" && models.length > 0;
console.log(
  [
    `probe=a-${leg} result=${pass ? "pass" : "fail"}`,
    `run=${runUrl}`,
    `requested=${clean(last.model) || "default"}`,
    `models=${clean(models.join(",")) || clean(laneModels) || "none"}`,
    `credential=${clean(last.credential) || "none"}`,
    `class=${clean(laneClass) || "none"}`,
    `legs=${records.length}`,
    `turns=${clean(last.num_turns)}`,
    `cli=${clean(last.cli_version)}`,
  ].join(" "),
);
