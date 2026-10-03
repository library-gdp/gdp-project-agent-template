# gdp-project-agent-template

코딩 에이전트(Claude Code, Codex, OpenCode 등)에 공통으로 적용할 규칙을 담은 프로젝트 템플릿.

`.agent/`가 에이전트 관련 설정의 **source of truth**이고, 각 에이전트 전용 경로에는 링크만 생성한다.

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

[OK]     skills    .claude/skills -> .agent/skills
[SKIP]   rules     .agent/rules does not exist
[SKIP]   agents    .agent/agents does not exist
[OK]     commands  .claude/commands -> .agent/commands
[OK]     skills    .opencode/skill -> .agent/skills
[OK]     commands  .opencode/command -> .agent/commands
[SKIP]   mcp       .agent/mcp/servers.json does not exist

Done.
```

몇 번을 실행해도 결과가 같다(idempotent). 두 번째 실행부터는 `already points to`로 보고한다.

### Mapping

| 리소스 | Source (`.agent/`) | Target | Claude Code 공식 경로 |
|---|---|---|---|
| Skills | `.agent/skills` | `.claude/skills` | `.claude/skills/<name>/SKILL.md` |
| Rules | `.agent/rules` | `.claude/rules` | `.claude/rules/**/*.md` |
| Subagents | `.agent/agents` | `.claude/agents` | `.claude/agents/*.md` |
| Commands | `.agent/commands` | `.claude/commands` | `.claude/commands/*.md` |
| Skills | `.agent/skills` | `.opencode/skill` | (OpenCode) |
| Commands | `.agent/commands` | `.opencode/command` | (OpenCode) |
| MCP | `.agent/mcp/servers.json` | `.mcp.json` | 프로젝트 루트 `.mcp.json` |

리소스를 추가할 때는 두 스크립트의 mapping 테이블에 각각 한 줄만 추가한다
(`directory_links()` / `$DirectoryLinks`).

`.codex/prompts/`는 링크 대상이 아니다. Codex prompt 파일은 YAML frontmatter를 쓰지 않아
`.agent/commands/`의 파일과 내용이 달라 같은 원본을 공유할 수 없다.

### MCP 처리

MCP는 다른 리소스와 다르다. Claude Code의 project-scoped MCP 설정은 디렉터리가 아니라
프로젝트 루트의 **단일 파일 `.mcp.json`**이고 형식은 `{"mcpServers": {...}}`다.
`.claude/mcp` 같은 경로는 존재하지 않으므로 만들지 않는다.

`.agent/mcp/servers.json`이 그 형식을 그대로 사용하므로 변환 없이 파일 단위로 링크한다.
자세한 형식은 [`.agent/mcp/README.md`](.agent/mcp/README.md) 참고.

`servers.json`이 없으면 `[SKIP]`으로 보고하고 루트를 건드리지 않는다. 빈 `.mcp.json`을
만들지 않는다.

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
- `.mcp.json`은 단일 파일이라 junction을 쓸 수 없다(junction은 디렉터리만 가리킨다).
  파일 symbolic link를 먼저 시도하고, 실패하면 hard link로 fallback한다. hard link는 NTFS
  동일 볼륨에서 권한 상승 없이 생성된다. **파일 복사 fallback은 없다** — 복사본은 원본 추적이
  조용히 끊기기 때문이다. 둘 다 실패하면 이유와 해결 방법을 출력하고 실패 처리한다.
- hard link 주의: 에디터가 "임시 파일 작성 후 이름 변경" 방식으로 저장하면 hard link가 끊어져
  양쪽 내용이 갈라진다. 스크립트는 재실행 시 내용 해시로 이를 감지해 `[ERROR]`로 알리며,
  어느 쪽이 최신인지 임의로 판단하지 않는다.

### Git

생성되는 링크·junction은 `.gitignore`로 제외한다. junction은 절대 경로를 저장해 머신 간
공유가 불가능하고, 링크는 각자 setup 스크립트로 만드는 local artifact다.
`.mcp.json`도 같은 이유로 제외하며, 공유되는 원본은 커밋되는 `.agent/mcp/servers.json`이다.

## 구조

```text
AGENTS.md                                 # 모든 에이전트 공통 진입점 (CLAUDE.md는 이 파일의 symlink)
.agent/                                   # 벤더 중립 정본 (committed)
  skills/project-documentation/
    SKILL.md                              # 문서화 Rule 정본
    references/document-types.md          # 문서 9종별 판정 기준
  commands/doc-sync.md                    # /doc-sync
  mcp/README.md                           # MCP 설정 형식 (servers.json 위치)
script/
  setup-agent-links.sh                    # Linux / macOS
  setup-agent-links.ps1                   # Windows PowerShell
.codex/prompts/doc-sync.md                # Codex 전용 (frontmatter 없음, 링크 대상 아님)
.claude/, .opencode/                      # setup 스크립트가 생성 (gitignored)
```

`.claude/`, `.codex/`, `.opencode/`는 각 도구가 요구하는 고정 경로이므로 옮길 수 없다.
규칙을 고칠 때는 `.agent/` 아래 정본만 수정한다.

`.agent/`는 숨은 디렉터리이므로 `grep`, `rg` 기본 설정에서는 검색되지 않는다. 에이전트는
`AGENTS.md`나 등록된 스킬을 통해 정본 경로를 안내받으므로 문제되지 않지만, 직접 찾을 때는
`rg --hidden`을 쓴다.

## 수록된 규칙

### 문서화 Rule (`.agent/skills/project-documentation`)

프로젝트 문서 9종(PRD, Requirements, ADR, System/Application/Data Architecture, Tech stacks,
Wireframe, Storyboard)에 대해 현재 형상 기준으로 새 문서 작성 / 최신화 / Deprecation 필요 여부를
판정하고 작업을 trigger한다. 정보가 부족한 문서는 작성하지 않는다.

문서 저장 위치와 각 문서의 작성 방법은 이 규칙의 범위가 아니다.
