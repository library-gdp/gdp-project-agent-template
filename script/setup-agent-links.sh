#!/usr/bin/env bash
#
# Link the agent resources in .agent/ into the vendor-specific locations that
# Claude Code, Codex and opencode read.
#
# .agent/ is the source of truth. The vendor directories only ever receive
# symbolic links; this script never copies, moves or deletes real data.
#
# Usage: script/setup-agent-links.sh   (runnable from any working directory)

set -euo pipefail

# ---------------------------------------------------------------------------
# Resource mapping
#
# To support a new resource, add one line. Fields are name|source|target,
# both paths relative to the project root.
# ---------------------------------------------------------------------------

directory_links() {
  cat <<'MAP'
skills|.agent/skills|.claude/skills
skills|.agent/skills|.agents/skills
rules|.agent/rules|.claude/rules
agents|.agent/agents|.claude/agents
commands|.agent/commands|.claude/commands
commands|.agent/commands|.opencode/commands
MAP
}

# Single files cannot be directory junctions on Windows, so they are tracked
# separately. Both sources stay vendor-neutral:
#
#   .mcp.json  Claude Code reads project-scoped MCP servers from this one file
#              at the project root, in {"mcpServers": {...}} form. There is no
#              .claude/mcp directory.
#   CLAUDE.md  Claude Code v2.1.277+ reads AGENTS.md directly, but older
#              versions need a CLAUDE.md. Linking the two keeps one source.
file_links() {
  cat <<'MAP'
mcp|.agent/mcp/servers.json|.mcp.json
instructions|AGENTS.md|CLAUDE.md
MAP
}

# ---------------------------------------------------------------------------
# Project root, derived from this file's own location
# ---------------------------------------------------------------------------

script_path="${BASH_SOURCE[0]}"
while [ -L "$script_path" ]; do
  link="$(readlink "$script_path")"
  case "$link" in
    /*) script_path="$link" ;;
    *) script_path="$(dirname -- "$script_path")/$link" ;;
  esac
done
script_dir="$(cd -- "$(dirname -- "$script_path")" && pwd -P)"
project_root="$(cd -- "$script_dir/.." && pwd -P)"

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

failures=0

report() {
  printf '[%s]%s %-12s %s\n' "$1" "$(printf '%*s' $((6 - ${#1})) '')" "$2" "$3"
}

report_error() {
  report ERROR "$1" "$2" >&2
  failures=$((failures + 1))
}

# Number of "../" hops needed to climb from the target back to the project root.
relative_prefix() {
  local slashes="${1//[^\/]/}"
  local prefix="" i=0
  while [ "$i" -lt "${#slashes}" ]; do
    prefix="../$prefix"
    i=$((i + 1))
  done
  printf '%s' "$prefix"
}

# ensure_link <name> <source-rel> <target-rel> <dir|file>
ensure_link() {
  local name="$1" source_rel="$2" target_rel="$3" kind="$4"
  local source="$project_root/$source_rel"
  local target="$project_root/$target_rel"
  local action=OK

  if [ "$kind" = dir ]; then
    if [ ! -d "$source" ]; then
      report SKIP "$name" "$source_rel does not exist"
      return 0
    fi
  else
    if [ ! -f "$source" ]; then
      report SKIP "$name" "$source_rel does not exist"
      return 0
    fi
  fi

  mkdir -p -- "$(dirname -- "$target")"

  if [ -L "$target" ]; then
    if [ "$target" -ef "$source" ]; then
      report OK "$name" "$target_rel already points to $source_rel"
      return 0
    fi
    # Removing a symlink detaches the link only; the data it pointed at stays.
    rm -- "$target"
    action=RELINK
  elif [ -e "$target" ]; then
    report_error "$name" "$target_rel already exists and is not a link; refusing to overwrite existing data"
    return 0
  fi

  ln -s -- "$(relative_prefix "$target_rel")$source_rel" "$target"
  report "$action" "$name" "$target_rel -> $source_rel"
}

# ---------------------------------------------------------------------------
# Run
# ---------------------------------------------------------------------------

printf 'Agent resource setup\n'
printf '  project root: %s\n\n' "$project_root"

if [ ! -d "$project_root/.agent" ]; then
  printf '[ERROR] .agent does not exist at %s\n' "$project_root" >&2
  printf '        .agent is the source of truth for agent resources and must be present.\n' >&2
  exit 1
fi

# Created when absent; any existing contents are left untouched.
mkdir -p -- "$project_root/.claude"

while IFS='|' read -r name source_rel target_rel; do
  [ -n "$name" ] || continue
  ensure_link "$name" "$source_rel" "$target_rel" dir
done <<EOF
$(directory_links)
EOF

while IFS='|' read -r name source_rel target_rel; do
  [ -n "$name" ] || continue
  ensure_link "$name" "$source_rel" "$target_rel" file
done <<EOF
$(file_links)
EOF

printf '\n'
if [ "$failures" -gt 0 ]; then
  printf 'Failed: %d resource(s) could not be linked. See [ERROR] above.\n' "$failures" >&2
  exit 1
fi
printf 'Done.\n'
