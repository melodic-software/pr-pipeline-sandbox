// Prints one probe line: the judge step's outcome, the verdict enum from the
// final result's structured output, and counts of write or bwrap errors in
// the leg log. It prints no model or tool text.
import fs from "node:fs";

const env = process.env;
const read = (p) => {
  try {
    return p ? fs.readFileSync(p, "utf8") : "";
  } catch {
    return "";
  }
};
let messages = [];
try {
  messages = JSON.parse(read(env.EXECUTION_FILE));
} catch {
  // An unreadable file leaves the verdict unset.
}
const final = messages.findLast?.((m) => m?.type === "result");
const verdict = final?.structured_output?.verdict;
const valid = ["pass", "pass-notes", "fail"].includes(verdict);
const log = read(env.LOG_FILE);
const count = (re) => (log.match(re) ?? []).length;
const writeErrors = count(/EACCES|EROFS|EPERM|read-only file system|permission denied/giu);
const bwrapErrors = count(/bwrap:/giu);
const pass = env.OUTCOME === "success" && valid && writeErrors === 0 && bwrapErrors === 0;
console.log(
  [
    `probe=pr-verify-v053 result=${pass ? "pass" : "fail"}`,
    `run=${env.RUN_URL}`,
    `outcome=${env.OUTCOME || "none"}`,
    `lane-class=${env.LANE_CLASS || "none"}`,
    `credential=${env.CREDENTIAL || "none"}`,
    `cli=${env.CLI_VERSION || "?"}`,
    `verdict=${valid ? verdict : "none"}`,
    `turns=${final?.num_turns ?? "?"}`,
    `denials=${Array.isArray(final?.permission_denials) ? final.permission_denials.length : "?"}`,
    `log-lines=${log ? log.trim().split("\n").length : 0}`,
    `log-write-errors=${writeErrors}`,
    `log-bwrap-errors=${bwrapErrors}`,
  ].join(" "),
);
