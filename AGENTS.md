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

`.agent/`와 이 파일이 source of truth다. 리포지토리에는 특정 에이전트 전용 파일을 두지 않는다.
각 에이전트가 요구하는 경로는 `script/setup-agent-links.sh`(Linux/macOS) 또는
`script/setup-agent-links.ps1`(Windows)이 생성하는 링크이며, Git에서 제외된다.
설정을 수정할 때는 `.agent/` 아래 정본만 고친다.

| 에이전트 | 이 저장소의 규칙을 읽는 경로 |
|---|---|
| 모든 에이전트 | `.agent/skills/project-documentation/SKILL.md` (정본) |
| Claude Code | `AGENTS.md`(v2.1.277+) 또는 `CLAUDE.md` 링크 + `.claude/skills` + `/doc-sync` |
| Codex | `AGENTS.md` + `.agents/skills` |
| opencode | `AGENTS.md` + `.claude/skills`·`.agents/skills` + `/doc-sync` |
| 그 외 | 이 파일을 읽고 정본 경로를 직접 참조 |

Codex는 project-scoped custom prompt를 지원하지 않으므로 `/doc-sync`가 없다. 대신
`.agents/skills`로 등록된 스킬이 이름과 description으로 트리거된다.

링크가 아직 생성되지 않았거나 링크를 따르지 않는 환경이라면
`.agent/skills/project-documentation/SKILL.md`를 직접 읽으면 된다.

전체 mapping과 setup 방법은 `README.md`의 Setup 절에 있다.
