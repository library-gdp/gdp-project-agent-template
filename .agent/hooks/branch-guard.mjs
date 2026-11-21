#!/usr/bin/env node
/**
 * Claude Code PreToolUse guard: git branch operations.
 *
 * Blocks, for every agent session in this project:
 *
 *   1. direct pushes to protected branches (main, prod, qa, stg, dev, develop, release)
 *   2. merging pull requests (gh pr merge, REST/GraphQL merge endpoints)
 *   3. amend commits and force pushes
 *
 * Permission deny rules in .agent/settings.json cover the common spellings, but
 * Bash prefix rules are easy to sidestep (`git -C . push`, `HEAD:main`, `+ref`,
 * ...). This hook parses the command instead and is the authoritative check.
 */

import {
  basename,
  commandSegments,
  gitOutput,
  gitSubcommand,
  makeBlocker,
  readHookInput,
} from "./lib/common.mjs";

const PROTECTED_BRANCHES = new Set(["main", "prod", "qa", "stg", "dev", "develop", "release"]);

const block = makeBlocker("branch-guard.mjs");

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

function checkBash(command, cwd) {
  if (command.toLowerCase().includes("mergepullrequest")) block("merging pull requests is not allowed.");
  if (/\/pulls\/[^/\s]+\/merge\b/.test(command)) block("merging pull requests is not allowed.");

  for (const { tokens } of commandSegments(command)) {
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

const input = readHookInput();
if (input && input.tool === "Bash") checkBash(input.toolInput.command || "", input.cwd);
