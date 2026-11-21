#!/usr/bin/env node
/**
 * Claude Code PreToolUse guard.
 *
 * Blocks, for every agent session in this project:
 *
 *   1. direct pushes to protected branches (main, prod, qa, stg, dev, develop, release)
 *   2. merging pull requests (gh pr merge, REST/GraphQL merge endpoints)
 *   3. amend commits and force pushes
 *   4. any modification of agent setting files (settings.json, settings.local.json,
 *      this hooks directory)
 *
 * Permission deny rules in .agent/settings.json cover the common spellings, but
 * Bash prefix rules are easy to sidestep (`git -C . push`, `HEAD:main`, `+ref`,
 * ...). This hook parses the command instead and is the authoritative check.
 *
 * Exit code 2 blocks the tool call and shows stderr to the agent.
 * Only Node.js built-ins are used; there are no npm dependencies.
 */

import { execFileSync } from "node:child_process";
import fs from "node:fs";
import path from "node:path";

const PROTECTED_BRANCHES = new Set(["main", "prod", "qa", "stg", "dev", "develop", "release"]);

// File names that count as agent setting files when they live in a .claude or
// .agent directory (project or user level).
const SETTING_FILE_NAMES = new Set(["settings.json", "settings.local.json"]);
const SETTING_DIR_NAMES = new Set([".claude", ".agent"]);

// Text that marks a Bash command as touching a setting file.
const SETTING_MARKERS = ["settings.json", "settings.local.json", ".agent/hooks", ".agent\\hooks"];

// Commands that only read, allowed to mention setting files.
const READ_ONLY_COMMANDS = new Set([
  "cat", "head", "tail", "less", "more", "grep", "egrep", "fgrep", "rg",
  "wc", "diff", "jq", "ls", "stat", "file", "readlink", "realpath", "test",
  "[", "echo", "printf", "bat", "md5sum", "sha256sum", "cmp",
]);
const READ_ONLY_GIT = new Set([
  "diff", "log", "show", "status", "blame", "add", "commit", "ls-files", "grep", "check-ignore",
]);

const GIT_GLOBAL_OPTS_WITH_VALUE = new Set([
  "-C", "-c", "--git-dir", "--work-tree", "--namespace", "--exec-path",
]);

const COMMAND_WRAPPERS = new Set(["sudo", "env", "command", "exec", "nohup", "time", "xargs"]);

function block(reason) {
  process.stderr.write(`Blocked by project guard (.agent/hooks/guard.mjs): ${reason}\n`);
  process.exit(2);
}

function basename(p) {
  return p.replace(/\\/g, "/").split("/").pop();
}

// ---------------------------------------------------------------------------
// Setting files
// ---------------------------------------------------------------------------

function isSettingPath(p, cwd) {
  if (!p) return false;
  const abs = path.isAbsolute(p) ? p : path.join(cwd, p);
  const candidates = new Set([path.normalize(abs)]);
  try {
    candidates.add(fs.realpathSync(abs));
  } catch {
    // The file may not exist yet (Write creates it); the normalized path still counts.
  }
  for (const c of candidates) {
    const parts = c.replace(/\\/g, "/").split("/");
    const name = parts[parts.length - 1];
    const parent = parts.length > 1 ? parts[parts.length - 2] : "";
    if (SETTING_FILE_NAMES.has(name) && SETTING_DIR_NAMES.has(parent)) return true;
    for (let i = 0; i < parts.length - 1; i++) {
      if (parts[i] === ".agent" && parts[i + 1] === "hooks") return true;
    }
  }
  return false;
}

function checkFileTool(toolInput, cwd) {
  const p = toolInput.file_path || toolInput.notebook_path || "";
  if (isSettingPath(p, cwd)) block(`setting files (${p}) are read-only for agents.`);
}

// ---------------------------------------------------------------------------
// Bash
// ---------------------------------------------------------------------------

function splitSegments(command) {
  // Split on command separators; good enough for guarding purposes.
  return command
    .split(/&&|\|\||[;|\n]|\$\(|`/)
    .map((s) => s.trim())
    .filter(Boolean);
}

// POSIX-like word splitting: single quotes, double quotes and backslash escapes.
function tokenize(segment) {
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
function stripPrefix(tokens) {
  let i = 0;
  while (i < tokens.length) {
    const t = tokens[i];
    if (/^[A-Za-z_][A-Za-z0-9_]*=/.test(t) || COMMAND_WRAPPERS.has(t)) i++;
    else break;
  }
  return tokens.slice(i);
}

// Return [subcommand, args] for a git invocation, else [null, []].
function gitSubcommand(tokens) {
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

function gitOutput(args, cwd) {
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

function branchName(ref) {
  for (const prefix of ["refs/heads/", "refs/remotes/origin/", "origin/"]) {
    if (ref.startsWith(prefix)) return ref.slice(prefix.length);
  }
  return ref;
}

function checkGitPush(args, cwd) {
  const positionals = [];
  for (let i = 0; i < args.length; i++) {
    const a = args[i];
    if (a === "--") {
      positionals.push(...args.slice(i + 1));
      break;
    }
    if (["-f", "--force", "--force-if-includes"].includes(a) || a.startsWith("--force-with-lease")) {
      block("force push is not allowed.");
    }
    if (/^-[a-zA-Z]*f[a-zA-Z]*$/.test(a)) block("force push is not allowed.");
    if (["--mirror", "--all", "--branches"].includes(a)) {
      block(`git push ${a} would push protected branches.`);
    }
    if (["--repo", "-o", "--push-option", "--receive-pack", "--exec"].includes(a)) {
      i++;
      continue;
    }
    if (!a.startsWith("-")) positionals.push(a);
  }

  const refspecs = positionals.slice(1); // first positional is the remote
  const current = gitOutput(["rev-parse", "--abbrev-ref", "HEAD"], cwd);

  if (!refspecs.length) {
    const upstream = gitOutput(["rev-parse", "--abbrev-ref", "--symbolic-full-name", "@{u}"], cwd);
    const slash = upstream.indexOf("/");
    const upstreamBranch = slash >= 0 ? upstream.slice(slash + 1) : upstream;
    if (PROTECTED_BRANCHES.has(current) || PROTECTED_BRANCHES.has(upstreamBranch)) {
      block(`direct push to protected branch '${current || upstreamBranch}' is not allowed.`);
    }
    return;
  }

  for (const spec of refspecs) {
    if (spec.startsWith("+")) block("force push ('+' refspec) is not allowed.");
    const colon = spec.indexOf(":");
    const src = colon >= 0 ? spec.slice(0, colon) : spec;
    const dst = colon >= 0 ? spec.slice(colon + 1) : "";
    let target = dst || src;
    if (target === "HEAD" || target === "@") target = current;
    target = branchName(target);
    if (PROTECTED_BRANCHES.has(target)) {
      block(`direct push to protected branch '${target}' is not allowed.`);
    }
  }
}

function checkSettingsInSegment(segment, tokens) {
  if (!SETTING_MARKERS.some((m) => segment.includes(m))) return;
  // Any redirection other than to /dev/null or fd duplication counts as a write.
  for (const m of segment.matchAll(/(\d?)>>?\s*(&?\S+)/g)) {
    if (m[2] !== "/dev/null" && !m[2].startsWith("&")) {
      block("writing to setting files is not allowed.");
    }
  }
  if (!tokens.length) return;
  const cmd = basename(tokens[0]);
  if (cmd === "git") {
    const [sub] = gitSubcommand(tokens);
    if (READ_ONLY_GIT.has(sub)) return;
  } else if (cmd === "sed") {
    if (!tokens.slice(1).some((t) => t.startsWith("-i") || t.startsWith("--in-place"))) return;
  } else if (READ_ONLY_COMMANDS.has(cmd)) {
    return;
  }
  block(`setting files are read-only for agents (command: ${cmd}).`);
}

function checkBash(command, cwd) {
  if (command.toLowerCase().includes("mergepullrequest")) block("merging pull requests is not allowed.");
  if (/\/pulls\/[^/\s]+\/merge\b/.test(command)) block("merging pull requests is not allowed.");

  for (const segment of splitSegments(command)) {
    const tokens = stripPrefix(tokenize(segment));
    checkSettingsInSegment(segment, tokens);
    if (!tokens.length) continue;
    const name = basename(tokens[0]);

    if (name === "gh" || name === "gh.exe") {
      const rest = tokens.slice(1).filter((t) => !t.startsWith("-"));
      if (rest[0] === "pr" && rest[1] === "merge") block("merging pull requests is not allowed.");
      continue;
    }

    const [sub, args] = gitSubcommand(tokens);
    if (sub === "push") checkGitPush(args, cwd);
    else if (sub === "commit" && args.some((a) => a.startsWith("--am"))) {
      block("amend commits are not allowed.");
    }
  }
}

function main() {
  let data;
  try {
    data = JSON.parse(fs.readFileSync(0, "utf8"));
  } catch {
    return;
  }
  const tool = data.tool_name || "";
  const toolInput = data.tool_input || {};
  const cwd = data.cwd || process.cwd();

  if (["Edit", "Write", "MultiEdit", "NotebookEdit"].includes(tool)) checkFileTool(toolInput, cwd);
  else if (tool === "Bash") checkBash(toolInput.command || "", cwd);
}

main();
