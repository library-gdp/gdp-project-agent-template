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
[OK]     guardrails   .claude/settings.json -> .agent/guardrails/claude-settings.json
[OK]     guardrails   opencode.json -> .agent/guardrails/opencode.json
[OK]     guardrails   .codex/rules/guardrails.rules -> .agent/guardrails/codex.rules

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
| `.agent/guardrails/claude-settings.json` | `.claude/settings.json` | Claude Code |
| `.agent/guardrails/opencode.json` | `opencode.json` | opencode |
| `.agent/guardrails/codex.rules` | `.codex/rules/guardrails.rules` | Codex |

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

## Git guardrails

에이전트가 다음을 하지 못하도록 각 에이전트의 **tool permission deny rule**로 막는다.

1. 보호 브랜치에 직접 push — 기본값 `dev`, `qa`, `prod`, `main`, `release`
2. PR merge

deny rule은 모델의 판단과 무관하게 harness가 명령을 실행하기 전에 패턴으로 차단하므로
결정론적이다. Claude Code에서는 `bypassPermissions`·`auto` 모드에서도 적용된다.

### 보호 브랜치 변경

정본은 `.agent/guardrails/protected-branches`(한 줄에 하나, `#` 주석)다. 수정 후 생성
스크립트를 실행하고 결과 파일을 함께 커밋한다. Windows에서는 Git Bash로 실행한다.

```bash
./script/generate-guardrails.sh
```

생성 결과(`.agent/guardrails/` 아래 3개 파일)는 손으로 고치지 않는다. 다시 생성하면 덮어쓴다.
`release/*`처럼 `*` glob을 쓸 수 있으나 Codex는 literal token만 매칭하므로 glob 항목을 건너뛴다.

### 차단 범위

| 차단 대상 | Claude Code | opencode | Codex |
|---|---|---|---|
| `git push <remote> <보호 브랜치>` (`+b`, `src:b`, `:b`, `refs/heads/b`, flag 포함) | O | O | O (remote는 `origin`·`upstream`, 앞쪽 flag 3개까지) |
| `git -C <dir> push …`, `git -c k=v push …` | O | O | X |
| 대상이 명령에 드러나지 않는 push: `git push`, `git push origin`, `… HEAD`, `… @`, `--all`, `--branches`, `--mirror` | O | O | `HEAD`·`@`·`--all` 등만 O, bare `git push`/`git push origin`은 X |
| `gh api`로 보호 브랜치 ref·contents 갱신, `gh api …/merges` | O | O | X |
| `gh pr merge`, `glab mr merge` | O | O | O |
| `gh api`의 PR merge REST·GraphQL (`pulls/*/merge`, `mergePullRequest`, `enablePullRequestAutoMerge`) | O | O | X |
| MCP의 PR merge tool (`mcp__*__*merge_pull_request*`, `mcp__*__*auto_merge*`) | O | X | X |

대상 브랜치가 명령에 드러나지 않는 push는 현재 브랜치에 따라 보호 브랜치로 갈 수 있지만
패턴으로는 현재 브랜치를 알 수 없다. 그래서 Claude Code·opencode에서는 이런 push를 모두
막고, push는 `git push -u origin <feature-branch>`처럼 대상을 명시하게 한다.

### 한계

permission rule은 에이전트가 쓴 **명령 문자열**을 매칭하므로 같은 동작의 다른 표현까지 막는
보안 경계가 아니다. 다음은 막지 못한다.

- `sh -c '…'`, `/usr/bin/git push …`, 스크립트·Makefile·git alias 안에서의 push
- 따옴표로 감싼 브랜치 이름(`git push origin "main"`), `origin` 외 remote 이름만 쓴 push
- Codex: 위 표에서 X인 항목. prefix rule은 literal token prefix만 매칭하고 명령의 끝을 지정할 수 없다
- opencode: MCP tool 호출

실제 보호는 원격 저장소의 branch protection / ruleset(직접 push 금지, PR 필수)으로 보장하고,
이 guardrail은 에이전트가 그 이전에 멈추도록 하는 1차 방어선으로 쓴다.

### 에이전트별 주의

- **Claude Code** — `.claude/settings.json`은 생성 파일로 가는 링크다. 개인 permission은
  `.claude/settings.local.json`에 둔다. `/permissions`에서 project 설정에 rule을 추가하면 링크를
  따라 생성 파일이 바뀌고 다음 생성 때 사라진다.
- **opencode** — 마지막으로 매칭된 rule이 이긴다. 다른 설정에서 더 넓은 `allow`를 이 rule들보다
  뒤에 추가하면 deny가 무력화된다.
- **Codex** — project의 `.codex/` layer는 **신뢰된 프로젝트**에서만 로드된다. 처음 실행할 때
  프로젝트를 trust해야 `.codex/rules/guardrails.rules`가 적용된다. 확인:
  `codex execpolicy check --rules .codex/rules/guardrails.rules git push origin main`
  → `"decision": "forbidden"`.

## 구조

```text
AGENTS.md                                 # 모든 에이전트 공통 진입점 (committed)
.agent/                                   # 벤더 중립 정본 (committed)
  skills/project-documentation/
    SKILL.md                              # 문서화 Rule 정본
    references/document-types.md          # 문서 9종별 판정 기준
  commands/doc-sync.md                    # /doc-sync
  mcp.json                                # MCP 설정 정본 (빈 상태로 포함)
  guardrails/
    protected-branches                    # 보호 브랜치 목록 정본
    claude-settings.json                  # 생성됨: Claude Code permission
    opencode.json                         # 생성됨: opencode permission
    codex.rules                           # 생성됨: Codex execpolicy rule
script/
  setup-agent-links.sh                    # Linux / macOS
  setup-agent-links.ps1                   # Windows PowerShell
  generate-guardrails.sh                  # guardrail permission 파일 생성
```

