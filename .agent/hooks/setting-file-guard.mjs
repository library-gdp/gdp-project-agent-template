#!/usr/bin/env node
/**
 * Claude Code PreToolUse guard: agent setting files.
 *
 * Blocks, for every agent session in this project, any modification of agent
 * setting files (settings.json / settings.local.json under .claude or .agent,
 * and the .agent/hooks directory), via file tools or Bash.
 *
 * Permission deny rules in .agent/settings.json cover Edit/Write on these paths,
 * but not Bash (`sed -i`, redirection, `cp`, ...). This hook is the
 * authoritative check.
 */

import fs from "node:fs";
import path from "node:path";
import {
  FILE_TOOLS,
  basename,
  commandSegments,
  gitSubcommand,
  makeBlocker,
  readHookInput,
} from "./lib/common.mjs";

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

const block = makeBlocker("setting-file-guard.mjs");

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

function checkSegment(segment, tokens) {
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

function checkBash(command) {
  for (const { segment, tokens } of commandSegments(command)) checkSegment(segment, tokens);
}

const input = readHookInput();
if (input) {
  if (FILE_TOOLS.has(input.tool)) checkFileTool(input.toolInput, input.cwd);
  else if (input.tool === "Bash") checkBash(input.toolInput.command || "");
}
