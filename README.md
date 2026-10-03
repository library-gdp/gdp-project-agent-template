# gdp-project-agent-template

코딩 에이전트(Claude Code, Codex, OpenCode 등)에 공통으로 적용할 규칙을 담은 프로젝트 템플릿.

## 구조

```
AGENTS.md                                 # 모든 에이전트 공통 진입점 (CLAUDE.md는 이 파일의 symlink)
.agent/                                   # 벤더 중립 정본
  skills/project-documentation/
    SKILL.md                              # 문서화 Rule 정본
    references/document-types.md          # 문서 9종별 판정 기준
.claude/skills/project-documentation   -> .agent/skills/project-documentation
.opencode/skill/project-documentation  -> .agent/skills/project-documentation
.claude/commands/doc-sync.md              # /doc-sync (Claude Code)
.codex/prompts/doc-sync.md                # /doc-sync (Codex)
.opencode/command/doc-sync.md             # /doc-sync (OpenCode)
```

규칙의 정본은 `.agent/` 아래 한 곳에만 둔다. `.claude/`, `.codex/`, `.opencode/`는 각 도구가
요구하는 고정 경로이므로 옮길 수 없고, 그래서 정본을 가리키는 symlink 또는 얇은 진입점만 둔다.
규칙을 고칠 때는 `.agent/` 아래 정본만 수정한다.

`.agent/`는 숨은 디렉터리이므로 `grep`, `rg` 같은 도구의 기본 설정에서는 검색되지 않는다.
에이전트는 `AGENTS.md`나 등록된 스킬을 통해 정본 경로를 안내받으므로 문제되지 않지만,
직접 찾을 때는 `rg --hidden`을 쓴다.

## 수록된 규칙

### 문서화 Rule (`.agent/skills/project-documentation`)

프로젝트 문서 9종(PRD, Requirements, ADR, System/Application/Data Architecture, Tech stacks,
Wireframe, Storyboard)에 대해 현재 형상 기준으로 새 문서 작성 / 최신화 / Deprecation 필요 여부를
판정하고 작업을 trigger한다. 정보가 부족한 문서는 작성하지 않는다.

문서 저장 위치와 각 문서의 작성 방법은 이 규칙의 범위가 아니다.
