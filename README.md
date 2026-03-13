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

---

## 집필 진행 현황 (2026-03-11)

**진행률: 11/25 챕터 완성 (44%)**

| Part | 챕터 | 제목 | 상태 | 이해도 |
|------|:----:|------|:----:|:------:|
| Part 0 | Ch01 | 프로젝트 소개와 개발 환경 구축 | ✅ 완료 | ⭐⭐⭐⭐ |
| Part 1 | Ch02 | RISC-V 아키텍처 개요 | ✅ 완료 | ⭐⭐⭐⭐ |
| Part 1 | Ch03 | RV32I 명령어 세트 완전 분석 | ✅ 완료 | ⭐⭐⭐⭐ |
| Part 2 | Ch04 | 데이터패스 기초: ALU와 레지스터 파일 | ✅ 완료 | ⭐⭐⭐⭐ |
| Part 2 | Ch05 | 메모리 서브시스템 설계 | ✅ 완료 | ⭐⭐⭐⭐ |
| Part 2 | Ch06 | 제어 유닛과 단일 사이클 통합 | ✅ 완료 | ⭐⭐⭐⭐ |
| Part 3 | Ch07 | 멀티사이클 데이터패스 | ✅ 완료 | ⭐⭐⭐⭐ |
| Part 3 | Ch08 | FSM 기반 제어 유닛 | ✅ 완료 | ⭐⭐⭐⭐ |
| Part 4 | Ch09 | 파이프라인 기초: 스테이지 분할 | ✅ 완료 | ⭐⭐⭐⭐ |
| Part 4 | Ch10 | 데이터 해저드와 포워딩 | ✅ 완료 | ⭐⭐⭐⭐ |
| Part 4 | **Ch11** | **제어 해저드와 분기 처리** | ✅ 완료 | ⭐⭐⭐⭐ |
| Part 4 | Ch12 | 구조적 해저드와 파이프라인 완성 | 🔜 다음 | — |
| Part 5 | Ch13 | 캐시 기초와 L1 명령어 캐시 | ⬜ 대기 | — |
| Part 5 | Ch14 | L1 데이터 캐시와 쓰기 정책 | ⬜ 대기 | — |
| Part 5 | Ch15 | 메모리 컨트롤러와 캐시-메모리 인터페이스 | ⬜ 대기 | — |
| Part 6 | Ch16 | AMBA AHB 버스 설계 | ⬜ 대기 | — |
| Part 6 | Ch17 | APB 브리지와 주변 장치 연결 | ⬜ 대기 | — |
| Part 7 | Ch18 | CSR과 시스템 명령어 | ⬜ 대기 | — |
| Part 7 | Ch19 | 예외/인터럽트와 파이프라인 통합 | ⬜ 대기 | — |
| Part 8 | Ch20 | FPGA 합성 최적화와 타이밍 클로저 | ⬜ 대기 | — |
| Part 8 | Ch21 | 하드웨어 검증과 디버깅 | ⬜ 대기 | — |
| Part 8 | Ch22 | 소프트웨어 스택 연동 | ⬜ 대기 | — |
| Part 9 | Ch23 | 성능 최적화 기법 | ⬜ 대기 | — |
| Part 9 | Ch24 | RV32I 확장: M, F 표준 확장 | ⬜ 대기 | — |
| Part 9 | Ch25 | 멀티코어와 캐시 일관성 기초 | ⬜ 대기 | — |

### 주요 마일스톤

| 마일스톤 | 챕터 | 상태 |
|---------|------|:----:|
| ★ LED 점멸 (첫 FPGA 실습) | Ch01 | ✅ |
| ★★ 피보나치 수열 CPU 실행 (단일 사이클) | Ch06 | ✅ |
| ★★ FSM CPU + 시뮬레이션 성능 비교 | Ch08 | ✅ |
| ★★★ 포워딩 합산 실행 (1~10 합산 x10=55) | Ch10 | ✅ |
| ★★★ 분기 포함 루프 실행 (1~10 합산 x2=55) | Ch11 | ✅ |
| ★★★ 버블정렬 FPGA 실행 (대성취) | Ch12 | 🔜 |
| ★★★★ 캐시 히트율 측정 벤치마크 | Ch15 | ⬜ |
| ★★★★ UART "Hello RISC-V" 전송 | Ch17 | ⬜ |
| ★★★★ 타이머 인터럽트 처리 | Ch19 | ⬜ |
| ★★★★★ Basys 3 최종 SoC 데모 | Ch22 | ⬜ |
