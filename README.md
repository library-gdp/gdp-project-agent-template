# gdp-project-agent-template

코딩 에이전트(Claude Code, Codex, OpenCode 등)에 공통으로 적용할 규칙을 담은 프로젝트 템플릿.

`.agent/`와 `AGENTS.md`가 에이전트 관련 설정의 **source of truth**다. 리포지토리에는 특정
에이전트 전용 파일을 두지 않고, 각 에이전트가 요구하는 경로는 setup 스크립트가 링크로 생성한다.

## Setup

클론 직후 한 번 실행한다. 어느 디렉터리에서 실행해도 동작한다.

**Linux / macOS**

```bash
chmod +x script/setup-agent-links.sh   # 최초 1회, 실행 권한이 없는 경우
./script/setup-agent-links.sh
```

**Windows PowerShell**

```powershell
.\script\setup-agent-links.ps1
```

출력 예:

```text
Agent resource setup
  project root: /home/you/gdp-project-agent-template

[OK]     skills       .claude/skills -> .agent/skills
[OK]     skills       .agents/skills -> .agent/skills
[SKIP]   rules        .agent/rules does not exist
[SKIP]   agents       .agent/agents does not exist
[OK]     commands     .claude/commands -> .agent/commands
[OK]     commands     .opencode/commands -> .agent/commands
[OK]     mcp          .mcp.json -> .agent/mcp.json
[OK]     instructions CLAUDE.md -> AGENTS.md

Done.
```

몇 번을 실행해도 결과가 같다(idempotent). 두 번째 실행부터는 `already points to`로 보고한다.

### Mapping

| Source | Target | 이 경로를 읽는 에이전트 |
|---|---|---|
| `.agent/skills` | `.claude/skills` | Claude Code, opencode |
| `.agent/skills` | `.agents/skills` | Codex, opencode |
| `.agent/rules` | `.claude/rules` | Claude Code |
| `.agent/agents` | `.claude/agents` | Claude Code (subagents) |
| `.agent/commands` | `.claude/commands` | Claude Code |
| `.agent/commands` | `.opencode/commands` | opencode |
| `.agent/mcp.json` | `.mcp.json` | Claude Code (project MCP) |
| `AGENTS.md` | `CLAUDE.md` | Claude Code v2.1.277 미만 |

리소스를 추가할 때는 두 스크립트의 mapping 테이블에 각각 한 줄만 추가한다
(`directory_links()` / `$DirectoryLinks`).

Target 경로는 각 에이전트의 공식 탐색 경로를 조사해 정한 것이다.

- **Skills** — Claude Code는 `.claude/skills`, Codex는 `.agents/skills`를 스캔한다. opencode는
  `.opencode/skills`, `.claude/skills`, `.agents/skills`를 모두 스캔하므로 별도 링크가 필요 없다.
  세 에이전트 모두 `SKILL.md` + `name`/`description` frontmatter 형식이 같고 symlink를 따른다.
- **Rules / Subagents** — Claude Code 전용 기능이다. `.claude/rules`는 `.md`를 재귀 탐색하며
  `paths` frontmatter로 특정 파일에만 적용할 수 있다. subagent는 `.claude/agents/*.md`다.
- **Commands** — Claude Code는 `.claude/commands`, opencode는 `.opencode/commands`다.
  **Codex는 project-scoped custom prompt를 지원하지 않는다**(user-level `~/.codex/prompts/`만
  지원하며, 해당 기능 자체가 skill로 대체되며 deprecated). 따라서 Codex용 command 링크는 없고,
  Codex에서는 `.agents/skills`로 등록된 스킬이 이름·description으로 트리거된다.
- **CLAUDE.md** — Claude Code v2.1.277부터 `AGENTS.md`를 직접 읽으므로 원래는 불필요하다.
  구버전과 `AGENTS.md`를 읽지 못하는 세션을 위해 링크로만 생성하고 커밋하지 않는다.
  `CLAUDE.md`가 있으면 Claude Code는 그 파일만 읽지만, 링크라 내용이 `AGENTS.md`와 같다.

### MCP 처리

MCP는 다른 리소스와 다르다. Claude Code의 project-scoped MCP 설정은 디렉터리가 아니라
프로젝트 루트의 **단일 파일 `.mcp.json`**이고 형식은 `{"mcpServers": {...}}`다.
`.claude/mcp` 같은 경로는 존재하지 않으므로 만들지 않는다.

정본은 **`.agent/mcp.json`** 단일 파일이고, Claude Code의 `.mcp.json` 형식을 그대로
사용하므로 변환 없이 파일 단위로 링크한다. 서버를 추가할 때는 이 파일만 수정한다.

```json
{
  "mcpServers": {
    "example-http": {
      "type": "http",
      "url": "https://example.com/mcp"
    },
    "example-stdio": {
      "type": "stdio",
      "command": "npx",
      "args": ["-y", "@example/mcp-server"],
      "env": {}
    }
  }
}
```

템플릿에는 서버가 없는 빈 상태(`{"mcpServers": {}}`)로 들어 있다. 유효한 JSON이므로
링크는 항상 생성되며, 서버가 등록될 때까지 Claude Code에 아무 영향이 없다.

`claude mcp add --scope project`로 서버를 추가하면 `.mcp.json`에 쓰는데, 그 경로가 링크라
결과적으로 `.agent/mcp.json`에 기록된다. 의도된 동작이다. Windows에서 hard link로 연결된
경우에는 아래 Windows 참고의 주의사항을 먼저 확인한다.

local scope(`~/.claude.json`, 개인·현재 프로젝트)와 user scope(`~/.claude.json`, 개인·모든
프로젝트)는 홈 디렉터리에 저장되므로 이 파일의 범위를 벗어난다.

### 안전 동작

- **실제 디렉터리·파일은 절대 덮어쓰지 않는다.** target이 링크가 아닌 실제 데이터면
  `[ERROR]`로 해당 리소스만 실패 처리하고 그대로 남긴다.
- **잘못된 링크는 링크만 교체한다.** 다른 곳을 가리키거나 끊어진 링크는 제거 후 재생성하며,
  링크가 가리키던 데이터에는 영향이 없다. `rm -rf`, `Remove-Item -Recurse`는 사용하지 않는다.
- **리소스는 독립적으로 처리한다.** `.agent/rules`가 없어도 나머지 설정은 정상 진행된다.
- **`.agent` 자체가 없으면** 설정 오류로 보고 non-zero exit code로 종료한다.
- `.claude/`가 없으면 생성하되 기존 내용은 보존한다.

### Windows 참고

- 디렉터리는 **directory junction**(`New-Item -ItemType Junction`)을 사용한다. 관리자 권한과
  Developer Mode가 모두 필요 없다.
- `.mcp.json`과 `CLAUDE.md`는 단일 파일이라 junction을 쓸 수 없다(junction은 디렉터리만 가리킨다).
  파일 symbolic link를 먼저 시도하고, 실패하면 hard link로 fallback한다. hard link는 NTFS
  동일 볼륨에서 권한 상승 없이 생성된다. **파일 복사 fallback은 없다** — 복사본은 원본 추적이
  조용히 끊기기 때문이다. 둘 다 실패하면 이유와 해결 방법을 출력하고 실패 처리한다.
- hard link 주의: 에디터가 "임시 파일 작성 후 이름 변경" 방식으로 저장하면 hard link가 끊어져
  양쪽 내용이 갈라진다. 스크립트는 재실행 시 내용 해시로 이를 감지해 `[ERROR]`로 알리며,
  어느 쪽이 최신인지 임의로 판단하지 않는다.

### Git

디렉터리 링크·junction은 `.gitignore`로 제외한다. junction은 절대 경로를 저장해 머신 간
공유가 불가능하고, 링크는 각자 setup 스크립트로 만드는 local artifact다. `CLAUDE.md`도
같은 이유로 제외하며, 공유되는 원본은 커밋되는 `AGENTS.md`다.

## 구조

```text
AGENTS.md                                 # 모든 에이전트 공통 진입점 (committed)
.agent/                                   # 벤더 중립 정본 (committed)
  skills/project-documentation/
    SKILL.md                              # 문서화 Rule 정본
    references/document-types.md          # 문서 9종별 판정 기준
  commands/doc-sync.md                    # /doc-sync
  mcp.json                                # MCP 설정 정본 (빈 상태로 포함)
script/
  setup-agent-links.sh                    # Linux / macOS
  setup-agent-links.ps1                   # Windows PowerShell
```

setup 스크립트가 생성하며 Git에서 제외되는 경로(gitignored):

```text
.claude/skills, .claude/rules, .claude/agents, .claude/commands
.agents/skills
.opencode/commands
CLAUDE.md
```

`.mcp.json`도 setup 스크립트가 생성하지만 gitignore하지 않는다(위 Git 절 참고).

`.claude/`, `.agents/`, `.opencode/`는 각 도구가 요구하는 고정 경로이므로 옮길 수 없다.
규칙을 고칠 때는 `.agent/` 아래 정본과 `AGENTS.md`만 수정한다.

`.agent/`는 숨은 디렉터리이므로 `grep`, `rg` 기본 설정에서는 검색되지 않는다. 에이전트는
`AGENTS.md`나 등록된 스킬을 통해 정본 경로를 안내받으므로 문제되지 않지만, 직접 찾을 때는
`rg --hidden`을 쓴다.

## 수록된 규칙

### 문서화 Rule (`.agent/skills/project-documentation`)

프로젝트 문서 9종(PRD, Requirements, ADR, System/Application/Data Architecture, Tech stacks,
Wireframe, Storyboard)에 대해 현재 형상 기준으로 새 문서 작성 / 최신화 / Deprecation 필요 여부를
판정하고 작업을 trigger한다. 정보가 부족한 문서는 작성하지 않는다.

문서 저장 위치와 각 문서의 작성 방법은 이 규칙의 범위가 아니다.
