# gdp-project-agent-template

코딩 에이전트(Claude Code, Codex, OpenCode 등)에 공통으로 적용할 규칙을 담은 프로젝트 템플릿.

## 구조

```
AGENTS.md                                 # 모든 에이전트 공통 진입점 (CLAUDE.md는 이 파일의 symlink)
skills/
  project-documentation/
    SKILL.md                              # 문서화 Rule 정본
    references/document-types.md          # 문서 9종별 판정 기준
.claude/skills/project-documentation   -> skills/project-documentation
.opencode/skill/project-documentation  -> skills/project-documentation
.claude/commands/doc-sync.md              # /doc-sync (Claude Code)
.codex/prompts/doc-sync.md                # /doc-sync (Codex)
.opencode/command/doc-sync.md             # /doc-sync (OpenCode)
```

규칙의 정본은 `skills/` 아래에 있고, 에이전트별 디렉터리는 symlink 또는 얇은 진입점이다.
규칙을 고칠 때는 정본 한 곳만 수정한다.

## 수록된 규칙

### 문서화 Rule (`skills/project-documentation`)

프로젝트 문서 9종(PRD, Requirements, ADR, System/Application/Data Architecture, Tech stacks,
Wireframe, Storyboard)에 대해 현재 형상 기준으로 새 문서 작성 / 최신화 / Deprecation 필요 여부를
판정하고 작업을 trigger한다. 정보가 부족한 문서는 작성하지 않는다.

문서 저장 위치와 각 문서의 작성 방법은 이 규칙의 범위가 아니다.
