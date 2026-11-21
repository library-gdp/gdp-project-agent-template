/**
 * Shared helpers for the PreToolUse guard hooks in .agent/hooks/.
 *
 * Only Node.js built-ins are used; there are no npm dependencies.
 */

import { execFileSync } from "node:child_process";
import fs from "node:fs";

const GIT_GLOBAL_OPTS_WITH_VALUE = new Set([
  "-C", "-c", "--git-dir", "--work-tree", "--namespace", "--exec-path",
]);

const COMMAND_WRAPPERS = new Set(["sudo", "env", "command", "exec", "nohup", "time", "xargs"]);

export const FILE_TOOLS = new Set(["Edit", "Write", "MultiEdit", "NotebookEdit"]);

// Exit code 2 blocks the tool call and shows stderr to the agent.
export function makeBlocker(hookFile) {
  return (reason) => {
    process.stderr.write(`Blocked by project guard (.agent/hooks/${hookFile}): ${reason}\n`);
    process.exit(2);
  };
}

// Read the PreToolUse payload from stdin. Returns null when it cannot be parsed.
export function readHookInput() {
  let data;
  try {
    data = JSON.parse(fs.readFileSync(0, "utf8"));
  } catch {
    return null;
  }
  return {
    tool: data.tool_name || "",
    toolInput: data.tool_input || {},
    cwd: data.cwd || process.cwd(),
  };
}

export function basename(p) {
  return p.replace(/\\/g, "/").split("/").pop();
}

export function splitSegments(command) {
  // Split on command separators; good enough for guarding purposes.
  return command
    .split(/&&|\|\||[;|\n]|\$\(|`/)
    .map((s) => s.trim())
    .filter(Boolean);
}

// POSIX-like word splitting: single quotes, double quotes and backslash escapes.
export function tokenize(segment) {
  const tokens = [];
  let cur = "";
  let inToken = false;
  let quote = null;
  for (let i = 0; i < segment.length; i++) {
    const ch = segment[i];
    if (quote === "'") {
      if (ch === "'") quote = null;
      else cur += ch;
    } else if (quote === '"') {
      if (ch === '"') quote = null;
      else if (ch === "\\" && i + 1 < segment.length && '"\\$`'.includes(segment[i + 1])) cur += segment[++i];
      else cur += ch;
    } else if (ch === "'" || ch === '"') {
      quote = ch;
      inToken = true;
    } else if (ch === "\\" && i + 1 < segment.length) {
      cur += segment[++i];
      inToken = true;
    } else if (/\s/.test(ch)) {
      if (inToken) tokens.push(cur);
      cur = "";
      inToken = false;
    } else {
      cur += ch;
      inToken = true;
    }
  }
  if (inToken) tokens.push(cur);
  return tokens;
}

// Drop env assignments and wrappers such as sudo/env/command.
export function stripPrefix(tokens) {
  let i = 0;
  while (i < tokens.length) {
    const t = tokens[i];
    if (/^[A-Za-z_][A-Za-z0-9_]*=/.test(t) || COMMAND_WRAPPERS.has(t)) i++;
    else break;
  }
  return tokens.slice(i);
}

// Segment-wise iteration: yields { segment, tokens } with wrappers stripped.
export function* commandSegments(command) {
  for (const segment of splitSegments(command)) {
    yield { segment, tokens: stripPrefix(tokenize(segment)) };
  }
}

// Return [subcommand, args] for a git invocation, else [null, []].
export function gitSubcommand(tokens) {
  if (!tokens.length || !["git", "git.exe"].includes(basename(tokens[0]))) return [null, []];
  let i = 1;
  while (i < tokens.length) {
    const t = tokens[i];
    if (GIT_GLOBAL_OPTS_WITH_VALUE.has(t)) i += 2;
    else if (t.startsWith("-")) i++;
    else return [t, tokens.slice(i + 1)];
  }
  return [null, []];
}

export function gitOutput(args, cwd) {
  try {
    return execFileSync("git", args, {
      cwd,
      encoding: "utf8",
      timeout: 5000,
      stdio: ["ignore", "pipe", "ignore"],
    }).trim();
  } catch {
    return "";
  }
}
