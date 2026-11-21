#!/usr/bin/env python3
"""Claude Code PreToolUse guard.

Blocks, for every agent session in this project:

  1. direct pushes to protected branches (main, prod, qa, stg, dev, develop, release)
  2. merging pull requests (gh pr merge, REST/GraphQL merge endpoints)
  3. amend commits and force pushes
  4. any modification of agent setting files (settings.json, settings.local.json,
     this hooks directory)

Permission deny rules in .agent/settings.json cover the common spellings, but
Bash prefix rules are easy to sidestep (`git -C . push`, `HEAD:main`, `+ref`,
...). This hook parses the command instead and is the authoritative check.

Exit code 2 blocks the tool call and shows stderr to the agent.
"""

import json
import os
import re
import shlex
import subprocess
import sys

PROTECTED_BRANCHES = {"main", "prod", "qa", "stg", "dev", "develop", "release"}

# File names that count as agent setting files when they live in a .claude or
# .agent directory (project or user level).
SETTING_FILE_NAMES = {"settings.json", "settings.local.json"}
SETTING_DIR_NAMES = {".claude", ".agent"}

# Text that marks a Bash command as touching a setting file.
SETTING_MARKERS = ("settings.json", "settings.local.json", ".agent/hooks", ".agent\\hooks")

# Commands that only read, allowed to mention setting files.
READ_ONLY_COMMANDS = {
    "cat", "head", "tail", "less", "more", "grep", "egrep", "fgrep", "rg",
    "wc", "diff", "jq", "ls", "stat", "file", "readlink", "realpath", "test",
    "[", "echo", "printf", "bat", "md5sum", "sha256sum", "cmp",
}
READ_ONLY_GIT = {"diff", "log", "show", "status", "blame", "add", "commit", "ls-files", "grep", "check-ignore"}

GIT_GLOBAL_OPTS_WITH_VALUE = {"-C", "-c", "--git-dir", "--work-tree", "--namespace", "--exec-path"}


def block(reason):
    sys.stderr.write("Blocked by project guard (.agent/hooks/guard.py): " + reason + "\n")
    sys.exit(2)


# ---------------------------------------------------------------------------
# Setting files
# ---------------------------------------------------------------------------

def is_setting_path(path, cwd):
    if not path:
        return False
    if not os.path.isabs(path):
        path = os.path.join(cwd, path)
    candidates = {os.path.normpath(path), os.path.realpath(path)}
    for p in candidates:
        parts = p.replace("\\", "/").split("/")
        name = parts[-1]
        parent = parts[-2] if len(parts) > 1 else ""
        if name in SETTING_FILE_NAMES and parent in SETTING_DIR_NAMES:
            return True
        for i in range(len(parts) - 1):
            if parts[i] == ".agent" and parts[i + 1] == "hooks":
                return True
    return False


def check_file_tool(tool_input, cwd):
    path = tool_input.get("file_path") or tool_input.get("notebook_path") or ""
    if is_setting_path(path, cwd):
        block("setting files (%s) are read-only for agents." % path)


# ---------------------------------------------------------------------------
# Bash
# ---------------------------------------------------------------------------

def split_segments(command):
    # Split on command separators; good enough for guarding purposes.
    return [s.strip() for s in re.split(r"&&|\|\||[;|\n]|\$\(|`", command) if s.strip()]


def tokenize(segment):
    try:
        return shlex.split(segment, posix=True)
    except ValueError:
        return segment.split()


def strip_prefix(tokens):
    """Drop env assignments and wrappers such as sudo/env/command."""
    i = 0
    while i < len(tokens):
        t = tokens[i]
        if re.match(r"^[A-Za-z_][A-Za-z0-9_]*=", t):
            i += 1
        elif t in ("sudo", "env", "command", "exec", "nohup", "time", "xargs"):
            i += 1
        else:
            break
    return tokens[i:]


def git_subcommand(tokens):
    """Return (subcommand, args) for a git invocation, else (None, [])."""
    if not tokens or os.path.basename(tokens[0]) not in ("git", "git.exe"):
        return None, []
    i = 1
    while i < len(tokens):
        t = tokens[i]
        if t in GIT_GLOBAL_OPTS_WITH_VALUE:
            i += 2
        elif t.startswith("-"):
            i += 1
        else:
            return t, tokens[i + 1:]
    return None, []


def git_output(args, cwd):
    try:
        return subprocess.run(
            ["git"] + args, cwd=cwd, capture_output=True, text=True, timeout=5
        ).stdout.strip()
    except Exception:
        return ""


def branch_name(ref):
    for prefix in ("refs/heads/", "refs/remotes/origin/", "origin/"):
        if ref.startswith(prefix):
            return ref[len(prefix):]
    return ref


def check_git_push(args, cwd):
    positionals = []
    i = 0
    while i < len(args):
        a = args[i]
        if a == "--":
            positionals.extend(args[i + 1:])
            break
        if a in ("-f", "--force", "--force-if-includes") or a.startswith("--force-with-lease"):
            block("force push is not allowed.")
        if re.match(r"^-[a-zA-Z]*f[a-zA-Z]*$", a):
            block("force push is not allowed.")
        if a in ("--mirror", "--all", "--branches"):
            block("git push %s would push protected branches." % a)
        if a in ("--repo", "-o", "--push-option", "--receive-pack", "--exec"):
            i += 2
            continue
        if not a.startswith("-"):
            positionals.append(a)
        i += 1

    refspecs = positionals[1:]  # first positional is the remote
    current = git_output(["rev-parse", "--abbrev-ref", "HEAD"], cwd)

    if not refspecs:
        upstream = git_output(["rev-parse", "--abbrev-ref", "--symbolic-full-name", "@{u}"], cwd)
        upstream_branch = upstream.split("/", 1)[1] if "/" in upstream else upstream
        if current in PROTECTED_BRANCHES or upstream_branch in PROTECTED_BRANCHES:
            block("direct push to protected branch '%s' is not allowed." % (current or upstream_branch))
        return

    for spec in refspecs:
        if spec.startswith("+"):
            block("force push ('+' refspec) is not allowed.")
        src, _, dst = spec.partition(":")
        target = dst if dst else src
        if target in ("HEAD", "@"):
            target = current
        target = branch_name(target)
        if target in PROTECTED_BRANCHES:
            block("direct push to protected branch '%s' is not allowed." % target)


def check_settings_in_segment(segment, tokens):
    if not any(m in segment for m in SETTING_MARKERS):
        return
    # Any redirection other than to /dev/null or fd duplication counts as a write.
    for m in re.finditer(r"(\d?)>>?\s*(&?\S+)", segment):
        if m.group(2) not in ("/dev/null",) and not m.group(2).startswith("&"):
            block("writing to setting files is not allowed.")
    if not tokens:
        return
    cmd = os.path.basename(tokens[0])
    if cmd == "git":
        sub, _ = git_subcommand(tokens)
        if sub in READ_ONLY_GIT:
            return
    elif cmd == "sed":
        if not any(t.startswith("-i") or t.startswith("--in-place") for t in tokens[1:]):
            return
    elif cmd in READ_ONLY_COMMANDS:
        return
    block("setting files are read-only for agents (command: %s)." % cmd)


def check_bash(command, cwd):
    lowered = command.lower()
    if "mergepullrequest" in lowered:
        block("merging pull requests is not allowed.")
    if re.search(r"/pulls/[^/\s]+/merge\b", command):
        block("merging pull requests is not allowed.")

    for segment in split_segments(command):
        tokens = strip_prefix(tokenize(segment))
        check_settings_in_segment(segment, tokens)
        if not tokens:
            continue
        name = os.path.basename(tokens[0])

        if name in ("gh", "gh.exe"):
            rest = [t for t in tokens[1:] if not t.startswith("-")]
            if rest[:2] == ["pr", "merge"]:
                block("merging pull requests is not allowed.")
            continue

        sub, args = git_subcommand(tokens)
        if sub == "push":
            check_git_push(args, cwd)
        elif sub == "commit":
            if any(a.startswith("--am") for a in args):
                block("amend commits are not allowed.")


def main():
    try:
        data = json.load(sys.stdin)
    except Exception:
        return 0
    tool = data.get("tool_name", "")
    tool_input = data.get("tool_input") or {}
    cwd = data.get("cwd") or os.getcwd()

    if tool in ("Edit", "Write", "MultiEdit", "NotebookEdit"):
        check_file_tool(tool_input, cwd)
    elif tool == "Bash":
        check_bash(tool_input.get("command", ""), cwd)
    return 0


if __name__ == "__main__":
    sys.exit(main())
