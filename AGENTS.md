# AGENTS.md

이 저장소에서 작업하는 모든 코딩 에이전트(Claude Code, Codex, OpenCode 등)에 공통으로 적용되는 규칙.

## Git / 설정 Guardrail

- 보호 브랜치(`main`, `prod`, `qa`, `stg`, `dev`, `develop`, `release`)에 직접 push하지 않는다.
  작업 브랜치에 push하고 PR을 연다.
- PR은 어느 브랜치든 merge하지 않는다. merge는 사람이 한다.
- `git commit --amend`와 force push(`-f`, `--force`, `--force-with-lease`, `+refspec`)를 쓰지 않는다.
- setting 파일(`.claude/settings*.json`, `.agent/settings.json`, `.agent/hooks/`)은 수정하지 않는다.
- 위 항목 외의 commit·push(`.agent/` 이하 포함)는 허용한다.

Claude Code에서는 `.agent/settings.json`과 `.agent/hooks/guard.mjs`가 이를 강제한다.
