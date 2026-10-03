---
name: project-documentation
description: 프로젝트의 현재 형상을 기준으로 프로젝트 문서(PRD, Requirements, ADR, System/Application/Data Architecture, Tech stacks, Wireframe, Storyboard)를 새로 작성할지, 최신화할지, Deprecation할지 판단하고 그 작업을 트리거한다. Use when a design decision is finalized; when scope, requirements, tech stack, architecture, data model, or screens change; when a new project is initialized; before closing a milestone or PR that changed any of those; or when the user asks to write, review, refresh, sync, or clean up project documentation ("문서화", "문서 최신화", "문서 점검", "are the docs up to date"). 정보가 부족한 문서는 억지로 작성하지 않고 "작성 불가"로 보고한다.
---

# 프로젝트 문서화 Rule

## 이 스킬의 역할

현재 형상(코드, 결정 사항, 합의된 내용)을 기준으로 **어떤 문서에 어떤 조치가 필요한지 판단하고 그 작업을 trigger**한다.

이 스킬이 하는 일:

- 대상 문서 9종의 상태를 점검한다.
- 각 문서에 대해 `CREATE` / `UPDATE` / `DEPRECATE` / `NO_CHANGE` / `NOT_READY` / `NOT_APPLICABLE` 중 하나를 판정한다.
- 판정 결과를 보고하고, 조치가 필요한 문서의 작성·수정 작업을 시작한다.

이 스킬이 하지 않는 일:

- **문서 저장 위치를 정의하지 않는다.** 기존 문서가 있으면 그 위치·이름 관례를 따른다. 관례가 없으면 사용자에게 묻는다.
- **각 문서의 작성 방법·양식·템플릿을 정의하지 않는다.** 프로젝트에 양식이나 별도 스킬이 있으면 그것을 따르고, 없으면 사용자에게 확인한다.
- 문서 리뷰 승인, 버전 관리 정책, 배포 절차를 정의하지 않는다.

## 대상 문서 9종

| 문서 | 답하는 질문 |
|---|---|
| PRD | 무엇을, 누구를 위해, 왜 만드는가 |
| Requirements | 무엇을 충족해야 완료인가 (기능/비기능/수용 기준) |
| ADR | 어떤 결정을, 왜, 어떤 대안을 제치고 내렸는가 |
| System Architecture | 시스템 경계·구성요소·외부 연동·런타임 토폴로지는 어떤가 |
| Application Architecture | 애플리케이션 내부 레이어·모듈·의존성 규칙은 어떤가 |
| Data Architecture | 데이터가 어디에 어떤 모양으로 있고 어떻게 흐르는가 |
| Tech stacks | 어떤 기술을 어떤 버전으로 쓰는가 |
| Wireframe | 각 화면은 무엇으로 구성되는가 |
| Storyboard | 사용자가 어떤 순서로 화면·단계를 지나가는가 |

각 문서의 **최소 입력 조건**, **변경 신호**, **Deprecation 조건**은 `references/document-types.md`에 정의되어 있다. 판정 전에 그 파일을 읽는다.

## 핵심 Rule

### Rule 1. 정보가 부족하면 작성하지 않는다

현재 형상에 정보가 부족해 작성할 수 없는 문서는 **억지로 작성하지 않는다**. `NOT_READY`로 판정하고, **무엇이 확정되면 작성 가능한지**를 함께 보고한다.

금지:

- 추측으로 빈칸을 채우는 것
- `TBD`, `미정`, `추후 결정`으로 채워진 껍데기 문서를 만드는 것
- 하나의 확정 사실을 근거로 문서 전체를 추론해서 쓰는 것

`NOT_READY`는 실패가 아니라 정상적인 판정 결과다. 그대로 보고하고 넘어간다.

### Rule 2. `NOT_READY`와 `NOT_APPLICABLE`을 구분한다

- `NOT_READY`: 언젠가 필요하지만 지금은 정보가 부족하다. (예: 사용자 시나리오가 아직 정의되지 않아 Storyboard를 쓸 수 없다)
- `NOT_APPLICABLE`: 이 프로젝트에 해당 문서가 애초에 필요하지 않다. (예: UI가 없는 CLI·라이브러리 프로젝트의 Wireframe, 영속 데이터가 없는 프로젝트의 Data Architecture)

`NOT_APPLICABLE`은 이유를 한 줄로 남기고 다음 점검에서 다시 묻지 않는다. 프로젝트 성격이 바뀌면 재판정한다.

### Rule 3. ADR은 수정하지 않는다

ADR은 결정 시점의 기록이다. 결정이 바뀌면 기존 ADR을 고치지 말고:

1. 새 ADR을 작성하고,
2. 기존 ADR에 `Superseded by <새 ADR>` 표시만 추가한다.

### Rule 4. 현재 형상과 충돌하는 문서는 방치하지 않는다

문서가 현재 형상과 어긋나면 `UPDATE` 또는 `DEPRECATE`로 판정한다. 틀린 문서를 그대로 두는 것은 문서가 없는 것보다 나쁘다. 어느 쪽이 맞는지 판단할 수 없으면(문서가 의도이고 코드가 미구현인지, 코드가 최신이고 문서가 낡았는지) 사용자에게 묻는다.

### Rule 5. 판정 근거는 현재 형상에서 가져온다

모든 판정에는 근거가 있어야 한다: 확정된 결정, 실제 코드·설정, 사용자가 명시한 합의 내용. "있으면 좋을 것 같아서"는 근거가 아니다.

## 실행 절차

### 1단계. 기존 문서 인벤토리

현재 작업 공간에서 9종 문서에 해당하는 기존 문서를 찾는다. 파일명·제목·내용으로 식별한다. 저장 위치는 이 스킬이 정하지 않으므로, 문서가 저장되는 외부 공간(위키, Notion 등)을 쓰는 프로젝트라면 사용자에게 확인한다.

### 2단계. 변경 신호 수집

현재 형상에서 무엇이 바뀌었거나 새로 확정되었는지 파악한다. 변경 신호 → 영향 문서 매핑:

| 변경 신호 | 영향받는 문서 |
|---|---|
| 제품 목적·대상 사용자·성공 지표 변경 | PRD, Requirements, Storyboard |
| 범위 추가·축소 | PRD, Requirements |
| 기능 추가·삭제, 수용 기준 변경 | Requirements, Wireframe, Storyboard |
| 기술 선택·버전 변경 | Tech stacks, ADR, System Architecture |
| 시스템 경계·외부 연동·배포 토폴로지 변경 | System Architecture, ADR |
| 레이어·모듈·의존성 규칙 변경 | Application Architecture, ADR |
| 스키마·저장소·데이터 흐름·보존 정책 변경 | Data Architecture, ADR |
| 화면 추가·삭제·구성 변경 | Wireframe, Storyboard |
| 사용자 흐름·단계 순서 변경 | Storyboard, Requirements |
| 대안이 있었고 되돌리기 어려운 결정 | ADR |
| 문서와 코드의 불일치 발견 | 해당 문서 |

### 3단계. 문서별 판정

9종 각각에 대해 순서대로 판단한다:

1. 이 프로젝트에 해당하는 문서인가? → 아니면 `NOT_APPLICABLE` (이유 기록)
2. `references/document-types.md`의 최소 입력 조건을 충족하는가? → 아니면 `NOT_READY` (부족한 정보 목록 기록)
3. 기존 문서가 있는가?
   - 없다 → `CREATE`
   - 있고 현재 형상과 불일치 → `UPDATE`
   - 있고 서술 대상이 사라졌거나 다른 문서로 대체됨 → `DEPRECATE`
   - 있고 일치 → `NO_CHANGE`

### 4단계. 보고

판정 결과를 표로 보고한다. `NO_CHANGE`와 `NOT_APPLICABLE`은 한 줄로 묶어도 된다.

```
| 문서 | 판정 | 근거 | 다음 조건 |
|---|---|---|---|
| Tech stacks | CREATE | Spring Boot 3.4 / PostgreSQL 16 확정 | - |
| ADR | CREATE | 메시지 브로커를 Kafka 대신 SQS로 결정 | - |
| PRD | NOT_READY | 대상 사용자·성공 지표 미정 | 타깃 사용자와 성공 지표 합의 |
| Wireframe | NOT_APPLICABLE | UI 없는 백엔드 서비스 | - |
```

### 5단계. 작업 수행

`CREATE` / `UPDATE` / `DEPRECATE` 항목에 대해 작업을 진행한다.

- 작성 방법은 이 스킬의 범위가 아니다. 프로젝트의 기존 문서 양식, 템플릿, 또는 별도 스킬을 따른다.
- 저장 위치는 기존 관례를 따르고, 관례가 없으면 사용자에게 묻는다.
- 조치 대상이 3개를 넘으면 진행 순서를 먼저 제시하고 확인을 받는다. 의존 관계상 Tech stacks → PRD → Requirements → ADR → Architecture 3종 → Wireframe → Storyboard 순이 자연스럽다.

## 이 스킬을 실행할 시점

- 사용자가 문서 작성·최신화·점검을 요청했을 때
- 설계 결정이 확정된 직후
- 기술 스택, 아키텍처, 스키마, 화면, 요구사항을 바꾸는 작업을 완료한 직후
- 새 프로젝트를 초기화할 때
- 마일스톤이나 PR을 닫기 전
