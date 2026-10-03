# gdp-project-agent-template

코딩 에이전트(Claude Code, Codex, OpenCode 등)에 공통으로 적용할 규칙을 담은 프로젝트 템플릿.

## 구조

```
AGENTS.md                                 # 모든 에이전트 공통 진입점 (CLAUDE.md는 이 파일의 symlink)
.agent/                                   # 벤더 중립 정본 (source of truth)
  skills/project-documentation/
    SKILL.md                              # 문서화 Rule 정본
    references/document-types.md          # 문서 9종별 판정 기준
  rules/                                  # (선택) 공통 rule
  agents/                                 # (선택) 공통 subagent 정의
  mcp.json                                # (선택) project-scoped MCP 서버 정의
script/
  setup-agent-links.sh                    # .agent -> .claude 링크 생성 (Linux/macOS)
  setup-agent-links.ps1                   # .agent -> .claude 링크 생성 (Windows)
.claude/commands/doc-sync.md              # /doc-sync (Claude Code)
.codex/prompts/doc-sync.md                # /doc-sync (Codex)
.opencode/command/doc-sync.md             # /doc-sync (OpenCode)
.opencode/skill/project-documentation  -> .agent/skills/project-documentation
```

규칙의 정본은 `.agent/` 아래 한 곳에만 둔다. `.claude/`, `.codex/`, `.opencode/`는 각 도구가
요구하는 고정 경로이므로 옮길 수 없고, 그래서 정본을 가리키는 링크 또는 얇은 진입점만 둔다.
규칙을 고칠 때는 `.agent/` 아래 정본만 수정한다.

`.agent/`는 숨은 디렉터리이므로 `grep`, `rg` 같은 도구의 기본 설정에서는 검색되지 않는다.
에이전트는 `AGENTS.md`나 등록된 스킬을 통해 정본 경로를 안내받으므로 문제되지 않지만,
직접 찾을 때는 `rg --hidden`을 쓴다.

## Claude Code 링크 설정

Claude Code가 `.agent/`의 정본을 읽을 수 있도록, 체크아웃 후 한 번 실행한다.

```bash
# Linux / macOS
./script/setup-agent-links.sh
```

```powershell
# Windows (PowerShell 5.1 또는 PowerShell 7+)
pwsh -File script\setup-agent-links.ps1
```

생성되는 링크:

| source (정본) | target (Claude Code가 읽는 경로) |
|---|---|
| `.agent/skills` | `.claude/skills` |
| `.agent/rules` | `.claude/rules` |
| `.agent/agents` | `.claude/agents` |
| `.agent/mcp.json` | `.mcp.json` |

Linux/macOS는 symbolic link, Windows는 디렉터리 junction(관리자 권한 불필요)을 쓴다.
링크 자체는 OS마다 형태가 달라 커밋하지 않고 `.gitignore`에 넣어 두었다. 정본만 커밋된다.

스크립트는 현재 working directory와 무관하게 스크립트 위치 기준으로 project root를 잡고,
몇 번을 다시 실행해도 결과가 같다(idempotent).

| 출력 | 의미 |
|---|---|
| `[LINK]` | 링크를 새로 만들었다 |
| `[OK]` | 올바른 링크가 이미 있다 |
| `[FIX]` | 잘못되거나 끊어진 링크를 지우고 다시 만들었다 |
| `[SKIP]` | `.agent/` 쪽 source가 없어 건너뛰었다 |
| `[ERROR]` | target이 실제 파일/디렉터리다. 지우지 않고 종료코드 1로 끝낸다 |

`.agent/rules`, `.agent/agents`, `.agent/mcp.json`은 이 템플릿에 아직 없으므로 `[SKIP]`으로
나온다. 해당 디렉터리나 파일을 만들고 스크립트를 다시 실행하면 그때 링크가 생긴다.

연결 대상을 추가하려면 두 스크립트의 mapping 테이블(`LINKS` / `$Links`)에 한 줄씩 넣으면 된다.

### MCP

Claude Code의 공식 project-scoped MCP 설정 위치는 **프로젝트 root의 `.mcp.json`** 이다
(`.claude/mcp` 같은 경로는 존재하지 않는다). 그래서 정본을 `.agent/mcp.json`에 두고
root의 `.mcp.json`을 그 링크로 만든다.

```json
{
  "mcpServers": {
    "example": { "type": "http", "url": "https://example.com/mcp" }
  }
}
```

`.mcp.json`이 링크가 아닌 실제 파일로 이미 있으면 스크립트는 **덮어쓰지 않고** `[ERROR]`로
끝낸다. 내용을 `.agent/mcp.json`으로 옮긴 뒤 다시 실행하면 된다. 개인용 서버는 `.agent/`에
넣지 말고 `claude mcp add --scope local`로 `~/.claude.json`에 두면 커밋되지 않는다.

## 수록된 규칙

### 문서화 Rule (`.agent/skills/project-documentation`)

프로젝트 문서 9종(PRD, Requirements, ADR, System/Application/Data Architecture, Tech stacks,
Wireframe, Storyboard)에 대해 현재 형상 기준으로 새 문서 작성 / 최신화 / Deprecation 필요 여부를
판정하고 작업을 trigger한다. 정보가 부족한 문서는 작성하지 않는다.

문서 저장 위치와 각 문서의 작성 방법은 이 규칙의 범위가 아니다.
