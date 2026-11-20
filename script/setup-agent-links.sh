#!/usr/bin/env bash
#
# Link the agent resources in .agent/ into the vendor-specific locations that
# Claude Code, Codex and opencode read.
#
# .agent/ is the source of truth. The vendor directories only ever receive
# symbolic links; this script never copies, moves or deletes real data.
#
# Run in a terminal, the script first shows a checklist of the agents to set
# up, and any number of them can be selected. Without a terminal, or with
# --agents / --all, the checklist is skipped.
#
# Usage: script/setup-agent-links.sh [--agents LIST | --all]
#        (runnable from any working directory; see --help)
#
# Compatible with bash 3.2, the version macOS ships.

set -euo pipefail

# ---------------------------------------------------------------------------
# Agents
#
# The checklist lists the agents in this order. Ids are what --agents accepts
# and what the agents field of the mappings below refers to.
# ---------------------------------------------------------------------------

agent_ids=(claude codex opencode)
agent_labels=('Claude Code' 'Codex' 'OpenCode')
agent_hints=(
  '.claude/, .mcp.json, CLAUDE.md'
  '.agents/skills, .codex/rules'
  '.agents/skills, .opencode/commands, opencode.json'
)

# ---------------------------------------------------------------------------
# Resource mapping
#
# To support a new resource, add one line. Fields are name|agents|source|target:
# agents is a comma-separated list of agent ids, and the link is created when
# at least one of them is selected. Paths are relative to the project root.
# ---------------------------------------------------------------------------

directory_links() {
  cat <<'MAP'
skills|claude|.agent/skills|.claude/skills
skills|codex,opencode|.agent/skills|.agents/skills
rules|claude|.agent/rules|.claude/rules
agents|claude|.agent/agents|.claude/agents
commands|claude|.agent/commands|.claude/commands
commands|opencode|.agent/commands|.opencode/commands
MAP
}

# Single files cannot be directory junctions on Windows, so they are tracked
# separately. Both sources stay vendor-neutral:
#
#   .mcp.json  Claude Code reads project-scoped MCP servers from this one file
#              at the project root, in {"mcpServers": {...}} form. There is no
#              .claude/mcp directory, so the source is the single file
#              .agent/mcp.json rather than a directory.
#   CLAUDE.md  Claude Code v2.1.277+ reads AGENTS.md directly, but older
#              versions need a CLAUDE.md. Linking the two keeps one source.
#   guardrails Permission deny rules rendered by script/generate-guardrails.sh
#              from .agent/guardrails/protected-branches, one file per agent.
file_links() {
  cat <<'MAP'
mcp|claude|.agent/mcp.json|.mcp.json
instructions|claude|AGENTS.md|CLAUDE.md
guardrails|claude|.agent/guardrails/claude-settings.json|.claude/settings.json
guardrails|opencode|.agent/guardrails/opencode.json|opencode.json
guardrails|codex|.agent/guardrails/codex.rules|.codex/rules/guardrails.rules
MAP
}

usage() {
  cat <<'USAGE'
Usage: script/setup-agent-links.sh [--agents LIST | --all]

Link the agent resources in .agent/ into the paths each coding agent reads.

Without an option, a checklist of agents opens in the terminal. Select any
number of them:
  Up/Down, k/j  move          Space  toggle        a  select all / none
  Enter         confirm       q, Esc cancel
When stdin or stderr is not a terminal (CI, a pipe, most coding agents'
shells), or TERM is unset or dumb, the checklist is skipped and every agent is
set up. Automation that does run in a terminal should pass --all or --agents.

Options:
  -a, --agents LIST  Set up only these agents, skipping the checklist.
                     Comma-separated: claude, codex, opencode. May be repeated.
      --all          Set up every agent, skipping the checklist
  -h, --help         Show this help

Example:
  script/setup-agent-links.sh --agents claude,codex
USAGE
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

usage_error() {
  printf '[ERROR] %s\n' "$1" >&2
  printf "        Run '%s --help' for usage.\n" "$0" >&2
  exit 2
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
# Agent selection
#
# The selection is kept as a space-separated list of agent ids in checklist
# order, since bash 3.2 has no associative arrays.
# ---------------------------------------------------------------------------

selected_agents=''

# Agent id for a name given on the command line, or nothing when unknown.
agent_id_for() {
  local name
  name="$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]')"
  case "$name" in
    claude | claude-code | claudecode) printf 'claude' ;;
    codex) printf 'codex' ;;
    opencode | open-code) printf 'opencode' ;;
  esac
}

agent_selected() {
  case " $selected_agents " in
    *" $1 "*) return 0 ;;
  esac
  return 1
}

# True when at least one agent of a comma-separated list is selected.
any_agent_selected() {
  local rest="$1," item
  while [ -n "$rest" ]; do
    item="${rest%%,*}"
    rest="${rest#*,}"
    if agent_selected "$item"; then
      return 0
    fi
  done
  return 1
}

# Sets selected_agents from a comma-separated --agents value.
select_agents_from_list() {
  local rest="$1," item id wanted=' ' i
  while [ -n "$rest" ]; do
    item="${rest%%,*}"
    rest="${rest#*,}"
    # Trim the ends only, so the error shows the name as typed.
    item="${item#"${item%%[![:space:]]*}"}"
    item="${item%"${item##*[![:space:]]}"}"
    [ -n "$item" ] || continue
    id="$(agent_id_for "$item")"
    if [ -z "$id" ]; then
      usage_error "unknown agent '$item' in --agents; expected claude, codex or opencode"
    fi
    wanted="$wanted$id "
  done
  if [ "$wanted" = ' ' ]; then
    usage_error '--agents needs at least one of claude, codex, opencode'
  fi

  selected_agents=''
  for i in "${!agent_ids[@]}"; do
    case "$wanted" in
      *" ${agent_ids[$i]} "*) selected_agents="$selected_agents ${agent_ids[$i]}" ;;
    esac
  done
  selected_agents="${selected_agents# }"
}

select_all_agents() {
  selected_agents="${agent_ids[*]}"
}

selected_agent_labels() {
  local i out=''
  for i in "${!agent_ids[@]}"; do
    if agent_selected "${agent_ids[$i]}"; then
      out="$out, ${agent_labels[$i]}"
    fi
  done
  printf '%s' "${out#, }"
}

# ---------------------------------------------------------------------------
# Checklist (TUI)
#
# Drawn on stderr and read from stdin, so stdout keeps only the setup report.
# Every line is cut to the terminal width, so the drawing never wraps and can
# be redrawn in place by moving the cursor back up over it.
# ---------------------------------------------------------------------------

tui_checked=()
tui_cursor=0
tui_message=''
tui_lines=0
tui_width=80
tui_buffer=''
tui_key=''
tui_stty=''
tui_active=0
tui_cancelled=0

if [ -n "${NO_COLOR:-}" ]; then
  tui_reverse=''
  tui_reset=''
else
  tui_reverse=$'\033[7m'
  tui_reset=$'\033[0m'
fi

# bash 3.2 accepts whole seconds only for read -t; a lone Esc then takes a
# second to register, while arrow keys still arrive at once.
if [ "${BASH_VERSINFO[0]}" -ge 4 ]; then
  tui_escape_timeout=0.1
else
  tui_escape_timeout=1
fi

tui_available() {
  [ -t 0 ] && [ -t 2 ] && [ "${TERM:-dumb}" != dumb ]
}

tui_terminal_width() {
  local size cols
  size="$(stty size 2>/dev/null || true)"
  cols="${size##* }"
  # A terminal without a window size (a bare pty, a serial line) reports 0.
  case "$cols" in
    '' | *[!0-9]* | 0) cols="${COLUMNS:-80}" ;;
  esac
  case "$cols" in
    '' | *[!0-9]* | 0) cols=80 ;;
  esac
  # One column short of the edge: some terminals wrap when the last column is
  # written.
  if [ "$cols" -gt 1 ]; then
    cols=$((cols - 1))
  fi
  tui_width="$cols"
}

# tui_put <text> [highlight]
tui_put() {
  local text="${1:0:$tui_width}"
  if [ "${2:-0}" -eq 1 ]; then
    tui_buffer="$tui_buffer"$'\r\033[2K'"$tui_reverse$text$tui_reset"$'\n'
  else
    tui_buffer="$tui_buffer"$'\r\033[2K'"$text"$'\n'
  fi
  tui_lines=$((tui_lines + 1))
}

tui_draw() {
  local i mark pointer highlight label
  tui_terminal_width
  tui_buffer=''
  if [ "$tui_lines" -gt 0 ]; then
    tui_buffer=$'\033['"$tui_lines"'A'
  fi
  tui_lines=0

  tui_put 'Select the agents to set up (any number):'
  tui_put '  Up/Down move  Space toggle  a all/none  Enter confirm  q cancel'
  tui_put ''
  for i in "${!agent_ids[@]}"; do
    mark=' '
    pointer=' '
    highlight=0
    if [ "${tui_checked[$i]}" -eq 1 ]; then
      mark='x'
    fi
    if [ "$i" -eq "$tui_cursor" ]; then
      pointer='>'
      highlight=1
    fi
    label="${agent_labels[$i]}            "
    tui_put "  $pointer [$mark] ${label:0:12}  ${agent_hints[$i]}" "$highlight"
  done
  tui_put ''
  tui_put "  $tui_message"

  printf '%s' "$tui_buffer" >&2
}

# Erases the checklist and leaves the cursor where its first line was.
tui_erase() {
  if [ "$tui_lines" -gt 0 ]; then
    printf '\033[%dA\r\033[J' "$tui_lines" >&2
    tui_lines=0
  fi
}

tui_restore() {
  [ "$tui_active" -eq 1 ] || return 0
  tui_active=0
  tui_erase
  printf '\033[?25h' >&2
  if [ -n "$tui_stty" ]; then
    stty "$tui_stty" 2>/dev/null || true
  fi
  if [ "$tui_cancelled" -eq 1 ]; then
    printf 'Cancelled. Nothing was changed.\n' >&2
  fi
}

# Reads one key press into tui_key: up, down, toggle, all, enter, cancel or
# other.
#
# NUL is the read delimiter, so Enter arrives as a newline of its own. With the
# default newline delimiter, bash 3.2 returns the same empty string for Enter
# and for a NUL byte (Ctrl-Space), and Ctrl-Space would confirm.
tui_read_key() {
  local key='' rest=''
  if ! IFS= read -rsn1 -d '' key; then
    if [ -z "$key" ]; then
      tui_key=cancel # end of input
    else
      tui_key=other
    fi
    return 0
  fi
  case "$key" in
    $'\004') tui_key=cancel ;; # Ctrl-D: read -n takes it as a plain byte
    $'\033')
      IFS= read -rsn1 -d '' -t "$tui_escape_timeout" rest || true
      if [ "$rest" = $'\033' ]; then
        # Alt sent as an Esc prefix (PuTTY, urxvt: Alt+Up is ESC ESC [ A), or
        # Esc pressed twice. The sequence after it is read to the end below,
        # so none of it is left over for the shell after the script exits.
        rest=''
        IFS= read -rsn1 -d '' -t "$tui_escape_timeout" rest || true
      fi
      case "$rest" in
        '[' | O)
          # Consume the whole CSI / SS3 sequence up to its final byte, so no
          # byte of it is taken as a key of its own: Shift+Up sends
          # ESC [ 1 ; 2 A, and a stray A would toggle every agent. Parameter
          # bytes are 0-9 : ; < = > ?, and the final byte decides the key.
          rest=''
          IFS= read -rsn1 -d '' -t "$tui_escape_timeout" rest || true
          if [ "$rest" = '[' ]; then
            # Linux console F1-F5: ESC [ [ A-E.
            IFS= read -rsn1 -d '' -t "$tui_escape_timeout" rest || true
            rest=''
          fi
          while :; do
            case "$rest" in
              [0-9:\;\<=\>?]) ;;
              *) break ;;
            esac
            rest=''
            IFS= read -rsn1 -d '' -t "$tui_escape_timeout" rest || true
          done
          case "$rest" in
            A) tui_key=up ;;
            B) tui_key=down ;;
            *) tui_key=other ;;
          esac
          ;;
        # A lone Esc, or Esc followed by another key before the timeout ran
        # out. bash 3.2 waits a whole second, and a second Esc or a q pressed
        # meanwhile must not swallow the cancel.
        *) tui_key=cancel ;;
      esac
      ;;
    $'\n' | $'\r') tui_key=enter ;;
    ' ') tui_key=toggle ;;
    k | K) tui_key=up ;;
    j | J) tui_key=down ;;
    a | A) tui_key=all ;;
    q | Q) tui_key=cancel ;;
    *) tui_key=other ;;
  esac
}

# Runs the checklist and sets selected_agents. Exits on cancel.
select_agents_with_tui() {
  local i count all_checked
  count="${#agent_ids[@]}"
  for i in "${!agent_ids[@]}"; do
    tui_checked[$i]=1
  done
  tui_cursor=0
  tui_message=''

  tui_stty="$(stty -g 2>/dev/null || true)"
  tui_active=1
  # The terminal is restored in the EXIT trap, never in the signal traps: when
  # Ctrl-C interrupts `read -s`, bash puts back the terminal settings read had
  # saved after the INT trap has run, which would undo the restore, but before
  # the EXIT trap runs.
  trap 'tui_restore' EXIT
  trap 'tui_cancelled=1; exit 130' INT
  trap 'tui_cancelled=1; exit 143' TERM
  # Ctrl-Z is ignored while the checklist is open: a suspended checklist would
  # leave the shell prompt with a hidden cursor, and resume with echo back on.
  trap '' TSTP
  # Keys typed while the checklist redraws must not be echoed into it.
  stty -echo 2>/dev/null || true
  printf '\033[?25l' >&2

  while :; do
    tui_draw
    tui_read_key
    tui_message=''
    case "$tui_key" in
      up) tui_cursor=$(((tui_cursor + count - 1) % count)) ;;
      down) tui_cursor=$(((tui_cursor + 1) % count)) ;;
      toggle) tui_checked[$tui_cursor]=$((1 - tui_checked[tui_cursor])) ;;
      all)
        all_checked=1
        for i in "${!agent_ids[@]}"; do
          [ "${tui_checked[$i]}" -eq 1 ] || all_checked=0
        done
        for i in "${!agent_ids[@]}"; do
          tui_checked[$i]=$((1 - all_checked))
        done
        ;;
      enter)
        selected_agents=''
        for i in "${!agent_ids[@]}"; do
          if [ "${tui_checked[$i]}" -eq 1 ]; then
            selected_agents="$selected_agents ${agent_ids[$i]}"
          fi
        done
        selected_agents="${selected_agents# }"
        if [ -n "$selected_agents" ]; then
          break
        fi
        tui_message='Select at least one agent with Space, or press q to cancel.'
        ;;
      cancel)
        tui_cancelled=1
        exit 1
        ;;
    esac
  done

  tui_restore
  trap - EXIT INT TERM TSTP
}

# ---------------------------------------------------------------------------
# Options
# ---------------------------------------------------------------------------

agents_option=''
all_option=0

while [ "$#" -gt 0 ]; do
  case "$1" in
    -h | --help)
      usage
      exit 0
      ;;
    -a | --agents)
      [ "$#" -ge 2 ] && [ -n "$2" ] || usage_error "$1 needs a value, e.g. $1 claude,codex"
      # Repeating the option adds to the list.
      agents_option="${agents_option:+$agents_option,}$2"
      shift 2
      ;;
    --agents=*)
      [ -n "${1#--agents=}" ] || usage_error '--agents needs a value, e.g. --agents=claude,codex'
      agents_option="${agents_option:+$agents_option,}${1#--agents=}"
      shift
      ;;
    --all)
      all_option=1
      shift
      ;;
    *)
      usage_error "unknown option: $1"
      ;;
  esac
done

if [ -n "$agents_option" ] && [ "$all_option" -eq 1 ]; then
  usage_error '--agents and --all cannot be used together'
fi

# ---------------------------------------------------------------------------
# Run
# ---------------------------------------------------------------------------

if [ ! -d "$project_root/.agent" ]; then
  printf '[ERROR] .agent does not exist at %s\n' "$project_root" >&2
  printf '        .agent is the source of truth for agent resources and must be present.\n' >&2
  exit 1
fi

selection_note=''
if [ -n "$agents_option" ]; then
  select_agents_from_list "$agents_option"
elif [ "$all_option" -eq 1 ]; then
  select_all_agents
elif tui_available; then
  select_agents_with_tui
else
  select_all_agents
  selection_note='no usable terminal for the checklist, so every agent is set up; choose with --agents'
fi

printf 'Agent resource setup\n'
printf '  project root: %s\n' "$project_root"
printf '  agents:       %s\n' "$(selected_agent_labels)"
if [ -n "$selection_note" ]; then
  printf '                (%s)\n' "$selection_note"
fi
printf '\n'

# Created when absent; any existing contents are left untouched.
if agent_selected claude; then
  mkdir -p -- "$project_root/.claude"
fi

while IFS='|' read -r name agents source_rel target_rel; do
  [ -n "$name" ] || continue
  any_agent_selected "$agents" || continue
  ensure_link "$name" "$source_rel" "$target_rel" dir
done <<EOF
$(directory_links)
EOF

while IFS='|' read -r name agents source_rel target_rel; do
  [ -n "$name" ] || continue
  any_agent_selected "$agents" || continue
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
