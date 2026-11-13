# AGENTS.md

이 저장소에서 작업하는 모든 코딩 에이전트(Claude Code, Codex, OpenCode 등)에 공통으로 적용되는 규칙.

## Git guardrails

`.agent/guardrails/protected-branches`에 나열된 브랜치(기본: dev, qa, prod, main, release)에는
직접 push하지 않고, PR을 merge하지 않는다. 이 규칙은 각 에이전트의 permission deny rule로
강제되며, 차단된 명령을 다른 형태로 우회하려 하지 않는다.

- push는 대상을 명시한다: `git push -u origin <feature-branch>`.
  `git push`, `git push origin`, `git push origin HEAD`처럼 대상 브랜치가 명령에 드러나지 않는
  push는 차단된다.
- 작업 결과는 PR로 올리고, merge는 사람이 한다.
