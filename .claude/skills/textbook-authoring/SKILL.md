---
name: textbook-authoring
description: "교재/기술서적 집필 프로젝트를 체계적으로 구축하고 운영하는 범용 프레임워크 스킬. 프로젝트 초기 셋업(디렉토리 구조, 에이전트 팀, 워크플로우, 품질 체크리스트), 챕터 집필(기획→초안→리뷰→수정→승인 10단계), 산출물 생성(강의PPT, 워크북, Word)을 포함합니다. 교재 집필, 기술서적, 교육 콘텐츠, 집필 프로젝트 셋업, 에이전트 팀 구성, 챕터 작성 워크플로우 요청 시 사용하세요. '교재 프로젝트를 만들어줘', '집필 환경을 세팅해줘', '새 교재를 시작하고 싶어', '챕터를 써줘', '리뷰 회의를 진행해줘' 같은 요청에 반드시 트리거하세요."
---

# 교재 집필 프레임워크 (Textbook Authoring Framework)

기술 교재를 체계적으로 집필하기 위한 범용 프레임워크입니다.
7명의 에이전트 팀, 10단계 집필 워크플로우, 8영역 품질 체크리스트를 포함합니다.

## 사용 시점

| 요청 | 참조할 파일 |
|------|-----------|
| 새 교재 프로젝트 셋업 | 이 SKILL.md의 [프로젝트 초기화] 섹션 |
| 에이전트 팀 구성/수정 | `references/agents.md` |
| 챕터 집필 실행 | `references/workflows.md` |
| 품질 점검 | `references/quality.md` |
| 산출물 생성 (PPT/워크북/Word) | `references/outputs.md` |

---

## 프로젝트 초기화

새 교재 프로젝트를 시작할 때 다음 순서로 진행합니다.

### Step 1: 프로젝트 정보 수집

사용자에게 다음을 확인합니다:

1. **교재 제목** (예: "UVM 완전정복")
2. **대상 독자** (사전 지식 수준, 목표 역할)
3. **교재 구조** (몇 부, 몇 챕터)
4. **톤 & 스타일** (친근/격식, 언어 규칙)
5. **기술 스택** (해당 분야의 코드 언어, 도구)
6. **개발 환경** (OS, 에디터)

### Step 2: 디렉토리 생성

```bash
mkdir -p project-root/{agents,templates,workflows,manuscripts,code_examples,figures,review_logs,output/{ppt,workbook,docx},.claude}
```

디렉토리 구조:
```
project-root/
├── README.md                     # 프로젝트 안내
├── CLAUDE.md                     # Claude Code 프로젝트 지침
├── TABLE_OF_CONTENTS.md          # 최종 확정 목차
├── .claude/settings.json         # Agent Teams 활성화
├── agents/                       # 에이전트 정의 (7명)
├── templates/                    # HTML 템플릿 + CSS
├── workflows/                    # 워크플로우 정의
├── manuscripts/                  # 원고 HTML (partN/chapterNN.html)
├── code_examples/                # 코드 예제
├── figures/                      # SVG 다이어그램
├── review_logs/                  # 리뷰 기록
└── output/                       # 최종 산출물
```

### Step 3: 설정 파일 생성

**.claude/settings.json** — Agent Teams 활성화:
```json
{
  "env": { "CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS": "1" },
  "teammateMode": "in-process",
  "permissions": {
    "allow": [
      "Bash(*)", "Read(*)", "Write(*)", "Edit(*)",
      "Glob(*)", "Grep(*)", "WebFetch(*)", "WebSearch(*)", "TodoWrite(*)"
    ]
  }
}
```

**CLAUDE.md** — `references/claude-md-template.md`를 참조하여 프로젝트별로 커스터마이즈합니다.

**README.md** — `references/readme-template.md`를 참조합니다.

### Step 4: 에이전트 정의 파일 생성

`references/agents.md`를 참조하여 7명의 에이전트 정의 파일을 `agents/` 디렉토리에 생성합니다.

### Step 5: 워크플로우 파일 생성

`references/workflows.md`를 참조하여 `workflows/` 디렉토리에 다음 파일을 생성합니다:
- `agent_team_workflow.md` — Phase별 실행 프롬프트
- `chapter_writing.md` — 10단계 집필 워크플로우
- `review_meeting.md` — 리뷰 회의 규칙 + 회의록 템플릿
- `quality_checklist.md` — 8영역 품질 체크리스트

### Step 6: 템플릿 파일 생성

`templates/` 디렉토리에 `chapter_template.html`과 `book_style.css`를 생성합니다.
CSS는 교재의 기술 스택에 맞는 구문 하이라이트 클래스를 포함합니다.

---

## 챕터 집필

챕터를 집필할 때는 `references/workflows.md`의 4 Phase를 따릅니다.

**요약:**
```
Phase 1: 기획 회의 (3 teammates 병렬) → chapterNN_plan.md
Phase 2: 초안 작성 (기술 저자 단독) → chapterNN.html + SVG + 코드
Phase 3: 병렬 리뷰 (4 teammates 동시) → 4개 리뷰 파일
Phase 4: 종합 회의 + 수정 + 승인 → meeting.md + 수정된 HTML
```

각 Phase의 실행 프롬프트는 `references/workflows.md`에 있습니다.

---

## 품질 점검

챕터 완성 후 `references/quality.md`의 8영역 체크리스트로 점검합니다.

**8영역:** 구조/형식, 콘텐츠 품질, 코드 품질, 시각 자료, 특수 코너(5종 aside), 실습/연습문제, 심리적 품질, 강의 적합성

**최종 승인 기준:**
- Critical 이슈 0개, Major 이슈 0개
- 초보자 이해도 ⭐⭐⭐ 이상
- 교육 설계 / 심리적 안전성 / 강의 적합도 각 ⭐⭐⭐ 이상

---

## 산출물 생성

교재 원본(HTML)에서 3종류의 산출물을 생성합니다.
상세 가이드는 `references/outputs.md`를 참조합니다.

```
교재 HTML → 강의 PPT (pptxgenjs, 템플릿 스타일 적용)
          → 워크북 (HTML/DOCX/PPT, L1~L4 난이도)
          → 교재 Word (docx-js, 출판용)
```

---

## 핵심 규칙 요약

1. **원고는 HTML**, 다이어그램은 **SVG만** (ASCII art 금지)
2. **에이전트 7명** 팀 운영, 병렬 리뷰 필수
3. **10단계 워크플로우** (4 Phase로 압축 실행)
4. **피드백 충돌 우선순위**: 정확성 > 심리적 안전 > 이해도 > 분량
5. **파일 충돌 방지**: 기술 저자만 HTML 수정, 리뷰어는 review_logs만 작성
6. 각 절 **2000~4000자**, 새 개념 시 **비유 필수**, 용어 첫 등장 시 **한글 설명**
7. **감정 곡선**: 호기심 → 약간의 불안 → 이해 → 성취감
8. 작업 완료 후 반드시 **팀 정리**
