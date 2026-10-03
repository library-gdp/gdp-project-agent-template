#!/usr/bin/env bash
#
# .agent (정본) -> 각 도구가 요구하는 고정 경로로 링크를 건다.
# Linux/macOS 용. Windows 는 script/setup-agent-links.ps1 을 쓴다.
#
# 반복 실행해도 안전하다(idempotent).
#   - source 가 없으면            [SKIP]
#   - 올바른 링크가 이미 있으면   [OK]
#   - 링크가 잘못됐거나 끊겼으면  제거 후 재생성 [FIX]
#   - target 이 실제 파일/디렉터리면 건드리지 않고 [ERROR] (종료코드 1)
#
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd -P)"
PROJECT_ROOT="$(cd -- "${SCRIPT_DIR}/.." >/dev/null 2>&1 && pwd -P)"

# "source|target|kind" — 경로는 project root 기준 상대경로, kind 는 dir 또는 file.
# 항목을 추가하려면 이 배열에만 한 줄 넣으면 된다(ps1 의 $Links 와 같이 맞출 것).
LINKS=(
  ".agent/skills|.claude/skills|dir"
  ".agent/rules|.claude/rules|dir"
  ".agent/agents|.claude/agents|dir"
  # MCP: Claude Code 의 공식 project-scoped 설정 위치는 프로젝트 root 의 .mcp.json 이다.
  # (.claude/mcp 같은 경로는 존재하지 않는다.) 정본을 .agent/mcp.json 에 두면 여기에 연결된다.
  ".agent/mcp.json|.mcp.json|file"
)

had_error=0

# 심링크를 따라가 절대 물리경로로 바꾼다. (macOS 의 BSD readlink 에는 -f 가 없을 수 있어 직접 구현)
resolve_path() {
  local path="$1" target hops=0
  while [ -L "$path" ] && [ "$hops" -lt 40 ]; do
    target="$(readlink -- "$path")"
    case "$target" in
      /*) path="$target" ;;
      *)  path="$(dirname -- "$path")/$target" ;;
    esac
    hops=$((hops + 1))
  done
  if [ -d "$path" ]; then
    (cd -- "$path" >/dev/null 2>&1 && pwd -P)
  else
    printf '%s/%s\n' "$(cd -- "$(dirname -- "$path")" >/dev/null 2>&1 && pwd -P)" "$(basename -- "$path")"
  fi
}

# target 의 부모 디렉터리에서 project root 로 거슬러 올라가는 접두사. ".claude/skills" -> "../"
rel_prefix() {
  local dir prefix="" segment
  dir="$(dirname -- "$1")"
  [ "$dir" = "." ] && { printf ''; return; }
  local IFS='/'
  for segment in $dir; do
    prefix="${prefix}../"
  done
  printf '%s' "$prefix"
}

report() { printf '%-7s %s\n' "$1" "$2"; }

link_one() {
  local src_rel="$1" target_rel="$2" kind="$3"
  local src_abs="${PROJECT_ROOT}/${src_rel}" target_abs="${PROJECT_ROOT}/${target_rel}"
  local link_value="$(rel_prefix "$target_rel")${src_rel}"

  if [ ! -e "$src_abs" ]; then
    report "[SKIP]" "${src_rel} 없음 -> ${target_rel} 건너뜀"
    return 0
  fi
  if [ "$kind" = "dir" ] && [ ! -d "$src_abs" ]; then
    report "[ERROR]" "${src_rel} 이 디렉터리가 아니다"
    had_error=1
    return 0
  fi

  mkdir -p -- "$(dirname -- "$target_abs")"

  if [ -L "$target_abs" ]; then
    if [ -e "$target_abs" ] && [ "$(resolve_path "$target_abs")" = "$(resolve_path "$src_abs")" ]; then
      report "[OK]" "${target_rel} -> ${link_value}"
      return 0
    fi
    rm -- "$target_abs"
    ln -s -- "$link_value" "$target_abs"
    report "[FIX]" "${target_rel} -> ${link_value} (잘못된 링크 재생성)"
    return 0
  fi

  if [ -e "$target_abs" ]; then
    report "[ERROR]" "${target_rel} 이 실제 파일/디렉터리다. 직접 확인 후 옮기거나 지운 뒤 다시 실행할 것"
    had_error=1
    return 0
  fi

  ln -s -- "$link_value" "$target_abs"
  report "[LINK]" "${target_rel} -> ${link_value}"
}

main() {
  printf 'project root: %s\n\n' "$PROJECT_ROOT"
  local entry src target kind
  for entry in "${LINKS[@]}"; do
    IFS='|' read -r src target kind <<< "$entry"
    link_one "$src" "$target" "$kind"
  done
  printf '\n'
  if [ "$had_error" -ne 0 ]; then
    printf '실패한 항목이 있다. 위 [ERROR] 를 확인할 것.\n' >&2
    return 1
  fi
  printf '완료.\n'
}

main "$@"
