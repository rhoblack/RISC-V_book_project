# RISC-V 프로세서 설계 완전정복 — 교재 집필 프로젝트

## 프로젝트 개요
RV32I 파이프라인 프로세서를 SystemVerilog로 설계하고 Xilinx Basys 3 FPGA에 구현하는 과정을 다루는 교재입니다. Claude Code Agent Team을 활용하여 집필합니다.

## 개발 환경
- **OS**: Windows
- **HDL**: SystemVerilog
- **ISA**: RISC-V RV32I
- **시뮬레이션**: Vivado / VCS / Verdi
- **FPGA**: Xilinx Basys 3
- **버스**: AMBA AHB, APB
- **문서 형식**: HTML (브라우저에서 바로 확인 가능)
- **다이어그램**: SVG (ASCII art 사용 금지)

## 에이전트 팀 구성 (7명)

| 에이전트 | 역할 | 파일 |
|---------|------|------|
| 📋 총괄 편집장 | 프로젝트 관리, 최종 품질 결정 | agents/editor_in_chief.md |
| ✍️ 기술 저자 | 전문 콘텐츠 집필 | agents/technical_author.md |
| 🔍 기술 리뷰어 | 코드 정확성, 실무 적합성 | agents/technical_reviewer.md |
| 🎓 초보자 독자 | 독자 관점 피드백, 이해도 평가 | agents/beginner_reader.md |
| 📐 교육 설계자 | 학습 흐름, 실습 설계 | agents/instructional_designer.md |
| 🧠 교육심리전문가 | 학습 동기, 학습 불안 관리 | agents/educational_psychologist.md |
| 🎤 교육전문강사 | 설명 품질, 비유 검증 | agents/expert_instructor.md |

## 집필 워크플로우

Phase 1: 기획 회의 → Phase 2: 초안 작성 → Phase 3: 병렬 리뷰 → Phase 4: 수정 및 승인

상세: workflows/agent_team_workflow.md 참조

## 디렉터리 구조

```
RISC-V_book_project/
├── README.md
├── CLAUDE.md
├── TABLE_OF_CONTENTS.md
├── .claude/
│   ├── settings.json
│   └── skills/textbook-authoring/
├── agents/               (에이전트 정의 7명)
├── templates/            (HTML/CSS 템플릿)
├── workflows/            (워크플로우 정의)
├── manuscripts/          (원고 HTML)
├── code_examples/        (SystemVerilog 코드 예제)
├── figures/              (SVG 다이어그램)
├── review_logs/          (리뷰 기록)
└── output/               (최종 산출물)
    ├── ppt/
    ├── workbook/
    └── docx/
```

## 사용법

### Claude Code에서 실행
```
cd d:/dev/AI/Claude_Code/RISC-V_book_project
claude
```

### 주요 명령어
- "Chapter [N] 집필을 시작해줘"
- "Chapter [N] 초안에 대해 에이전트 회의를 진행해줘"
- "초보자 독자 관점에서 Chapter [N]을 평가해줘"
- "Part [N] 전체에 대해 품질 체크리스트를 실행해줘"

## 원고 미리보기
브라우저에서 manuscripts/partN/chapterNN.html을 열어 확인
