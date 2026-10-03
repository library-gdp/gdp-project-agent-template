# AGENTS.md

이 저장소에서 작업하는 모든 코딩 에이전트(Claude Code, Codex, OpenCode 등)에 공통으로 적용되는 규칙.

## 문서화 Rule

프로젝트 문서 9종 — PRD, Requirements, ADR, System Architecture, Application Architecture,
Data Architecture, Tech stacks, Wireframe, Storyboard — 은 현재 형상을 따라가야 한다.

아래 상황 중 하나에 해당하면 **`.agent/skills/project-documentation/SKILL.md`를 읽고 그 절차를 따른다.**

- 사용자가 문서 작성·최신화·점검·정리를 요청했다.
- 설계 결정이 확정되었다.
- 기술 스택, 아키텍처, 데이터 스키마, 화면, 요구사항을 바꾸는 작업을 완료했다.
- 새 프로젝트를 초기화하고 있다.
- 마일스톤이나 PR을 닫기 전이고, 위 항목 중 무엇이든 바뀌었다.

핵심 원칙 세 가지(전체 규칙은 스킬 파일에 있다):

1. 현재 형상에 정보가 부족해 작성할 수 없는 문서는 **억지로 작성하지 않는다.** `NOT_READY`로 판정하고 무엇이 확정되면 작성 가능한지 보고한다.
2. 이 규칙은 **문서 저장 위치를 정의하지 않는다.** 기존 관례를 따르고, 관례가 없으면 사용자에게 묻는다.
3. 이 규칙은 **각 문서의 작성 방법·양식을 정의하지 않는다.** 판단과 trigger만 담당한다.

## 에이전트별 진입점

| 에이전트 | 진입점 |
|---|---|
| 모든 에이전트 | `.agent/skills/project-documentation/SKILL.md` (정본) |
| Claude Code | 스킬 자동 인식 (`.claude/skills/` → `.agent/skills/` 링크), 또는 `/doc-sync` |
| Codex | 이 파일 + `.codex/prompts/doc-sync.md` (`/doc-sync`) |
| OpenCode | 스킬 자동 인식 (`.opencode/skill/` → 정본 symlink), 또는 `/doc-sync` |
| 그 외 | 이 파일을 읽고 정본 경로를 직접 참조 |

`.claude/skills/`와 `.opencode/skill/` 항목은 정본을 가리키는 링크다. 링크를 따르지 않는 환경이라면
`.agent/skills/project-documentation/SKILL.md`를 직접 읽으면 된다.

`.claude/` 쪽 링크(`skills`, `rules`, `agents`)와 root의 `.mcp.json`은 커밋되지 않는다.
체크아웃 후 `./script/setup-agent-links.sh`(Linux/macOS) 또는
`pwsh -File script\setup-agent-links.ps1`(Windows)을 한 번 실행하면 생성된다.
자세한 내용은 README의 "Claude Code 링크 설정"을 본다.
