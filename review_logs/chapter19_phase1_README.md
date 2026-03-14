# Ch19 Phase 1 기획 회의 — 문서 색인

**완료일:** 2026-03-14
**편집장:** team-lead@ch19-exception-interrupt
**상태:** ✅ Phase 1 완료, Phase 2 준비 완료

---

## 문서 네비게이션

### 📋 전체 개요 (먼저 읽기)

**파일:** `chapter19_phase1_completion_report.md` (16 KB, 350줄)

**내용:**
- Executive Summary
- 산출물 목록 (5개)
- 핵심 기획 내용 종합
- Phase 2 기술 저자 준비 사항
- 편집장 체크리스트

→ **이 파일부터 읽으세요.**

---

### 🎯 기술 배경 및 설계 결정

**파일:** `chapter19_phase1_meeting.md` (8 KB, 220줄)

**내용:**
- 이전 장 기초 (Ch18 CSR, Ch17 Timer)
- 핵심 신규 개념 4가지 상세 설명
- 기술 설계 제약사항 (변경 불가)
- 기획 일정 및 일정표
- 편집장 승인 기준

→ **기술 배경이 필요하면 읽으세요.**

---

### 📚 교육 설계자의 기획

**파일:** `chapter19_phase1_edu_designer_briefing.md` (8 KB, 180줄)

**내용:**
- 교육 설계자의 역할 정의
- Ch19 개요 (목표, 대상, 선수 지식)
- **Task 1:** 학습 목표 5~7개 작성 (블룸 분류)
- **Task 2:** 섹션별 선수 지식 검증
- **Task 3:** 인지 부하 분석 (복잡도/위험도/해결책)
- **Task 4:** 연습문제 설계 (5~7개)
- **Task 5:** 기술 제약사항 확인

→ **학습 목표와 인지 부하 분석이 필요하면 읽으세요.**

---

### 🧠 교육심리전문가의 기획

**파일:** `chapter19_phase1_psych_briefing.md` (12 KB, 380줄)

**내용:**
- 교육심리전문가의 역할 정의
- 학생 프로필 (대학원생, Verilog 경험)
- **Task 1:** 학습 불안 지점 Top 3 분석
  - #1 우선순위 인코더 추상성 (⭐⭐⭐⭐)
  - #2 벡터화 주소 비트 시프트 (⭐⭐⭐)
  - #3 중첩 인터럽트 메모리 (⭐⭐⭐⭐⭐)
- **Task 2:** 감정 곡선 설계 (섹션별)
- **Task 3:** 자기효능감 관리 (첫 성공 지점)
- **Task 4:** 메타인지 촉진 장치 (7개 질문)
- **Task 5:** 실패 정상화 & 격려 문구

→ **감정 곡선과 메타인지 질문이 필요하면 읽으세요.**

---

### 🎤 교육전문강사의 기획

**파일:** `chapter19_phase1_instructor_briefing.md` (20 KB, 520줄)

**내용:**
- 교육전문강사의 역할 정의
- **Task 1:** 수강생 막힘 포인트 Top 5
  1. 우선순위 인코더의 필요성
  2. cause << 2의 의미
  3. 중첩 인터럽트 상태 보존
  4. MRET vs RET
  5. 고정 우선순위 정당성
- **Task 2:** 실생활 비유 5개 + 한계/대안
  - 응급실 트리아주 (정확도 ⭐⭐⭐⭐)
  - 책의 목차 (정확도 ⭐⭐⭐⭐)
  - 함수 호출 스택 (정확도 ⭐⭐⭐⭐⭐)
  - 저장된 백업 (정확도 ⭐⭐⭐⭐⭐)
  - 신호등 규칙 (정확도 ⭐⭐⭐⭐⭐)
- **Task 3:** 면접 연결 포인트 5개
- **Task 4:** Basys 3 데모 제안 3개
- **Task 5:** 강사 팁 정리 (현장 경험)

→ **비유, 막힘 포인트, 데모가 필요하면 읽으세요.**

---

### ✨ 편집장의 요약

**파일:** `chapter19_phase1_executive_summary.md` (8 KB, 210줄)

**내용:**
- 기획 완료 artifacts 목록
- 핵심 내용 종합
  - 학습 목표 5개 표
  - 핵심 비유 5개 표
  - 메타인지 질문 7개
  - 불안 지점 3곳 + 완화책
  - 감정 곡선
  - 막힘 포인트 Top 5
  - 면접 포인트 5개
  - 데모 3개
- 기술 제약사항 (변경 금지)
- 섹션 구성 (19.1~19.7) — SVG/코드 배치
- Phase 2 기술 저자 가이드라인
- 편집장 승인 기준
- 다음 일정

→ **기술 저자가 읽어야 할 핵심 내용이 요약되어 있습니다.**

---

## 읽기 순서 추천

### 기술 저자 (Phase 2 집필자)
1. `chapter19_phase1_completion_report.md` (전체 개요)
2. `chapter19_phase1_executive_summary.md` (기술 저자 가이드)
3. `chapter19_phase1_meeting.md` (기술 배경)
4. 필요시: `chapter19_phase1_*_briefing.md` (세부 사항)

**핵심 요약:**
- 학습 목표 5개 (표)
- 핵심 비유 5개 (표)
- 감정 곡선 (그래프)
- SVG 11개 (목록)
- 메타인지 7개 (목록)

### 기술 리뷰어 (Phase 3)
1. `chapter19_phase1_meeting.md` (기술 제약)
2. `chapter19_phase1_completion_report.md` (체크리스트)

### 초보자 독자 (Phase 3)
1. `chapter19_phase1_edu_designer_briefing.md` (선수 지식)
2. `chapter19_phase1_psych_briefing.md` (이해도 기준)

### 교육심리전문가 (Phase 3)
1. `chapter19_phase1_psych_briefing.md` (불안 지점)
2. `chapter19_phase1_completion_report.md` (체크리스트)

### 교육전문강사 (Phase 3)
1. `chapter19_phase1_instructor_briefing.md` (막힘 포인트, 비유, 데모)
2. `chapter19_phase1_completion_report.md` (체크리스트)

---

## 핵심 정보 Quick Reference

### 학습 목표 (5개)
```
1. [Remember] RISC-V 인터럽트 원인 코드 열거
2. [Understand] 우선순위 인코더 동작 설명
3. [Apply] SystemVerilog 구현
4. [Analyze] 중첩 인터럽트 CSR 추적
5. [Evaluate] 고정 vs 동적 우선순위 비교
```

### 핵심 비유 (5개)
```
1. 우선순위 인코더 → 응급실 트리아주
2. 벡터화 주소 → 책의 목차
3. 중첩 인터럽트 → 함수 호출 스택
4. MPIE → 저장된 백업 복사본
5. 고정 우선순위 → 신호등 규칙
```

### 메타인지 질문 (7개)
```
1. interrupt vs exception 차이
2. mtvec MODE=0 vs MODE=1 비교
3. 우선순위: MSIP vs MTIP (변경 가능?)
4. trap_pc 1사이클 지연 이유
5. MRET 3번 후 복귀 주소
6. Interrupt Controller vs Priority Encoder 관계
7. volatile 키워드의 필요성
```

### 불안 지점 (3곳)
```
1. 19.3절 우선순위 인코더 (⭐⭐⭐⭐)
   → 비유(응급실) + 단계적 예제

2. 19.2절 벡터화 주소 (⭐⭐⭐)
   → 메모리 맵 그림

3. 19.5절 중첩 인터럽트 (⭐⭐⭐⭐⭐)
   → 함수 스택 비유 + 단계 추적
```

### SVG 다이어그램 (11개)
```
ch19_sec01_interrupts_overview.svg
ch19_sec02_vectorized_address.svg
ch19_sec02_address_calculation.svg
ch19_sec03_priority_encoder.svg
ch19_sec03_cause_code.svg
ch19_sec04_trap_fsm.svg
ch19_sec05_nested_interrupt.svg
ch19_sec05_stack_memory.svg
ch19_sec06_controller_block.svg
ch19_sec06_controller_fsm.svg
ch19_sec07_uart_handler.svg
```

### Basys 3 데모 (3개)
```
Demo 1: Timer LED (1초마다 깜박임)
Demo 2: UART Echo (데이터 에코)
Demo 3: Priority (동시 interrupt 우선순위)
```

---

## Phase 2 기술 저자 체크리스트

### 필수 준수 사항
- [ ] chapter_template.html 구조 준수
- [ ] 각 절 2000~4000자
- [ ] 비유/메타인지/강사팁 모두 포함
- [ ] SVG 11개 (figures/ 디렉터리)
- [ ] 코드 4개 (code_examples/ 디렉터리)
- [ ] Highlight.js 하이라이팅
- [ ] aside 박스 5종류 배치

### 섹션 구성
- [ ] 19.1 인터럽트 개요 (SVG 1개)
- [ ] 19.2 벡터화 주소 (SVG 2개)
- [ ] 19.3 우선순위 인코더 (SVG 2개, 코드 1개)
- [ ] 19.4 Trap 전이 (SVG 1개)
- [ ] 19.5 중첩 인터럽트 (SVG 2개)
- [ ] 19.6 Interrupt Controller (SVG 2개, 코드 1개)
- [ ] 19.7 실습 + C 코드 (SVG 1개, 코드 2개)

### 제약사항 확인
- [ ] CSR 7개 고정 (변경 없음)
- [ ] 우선순위 정책: 고정
- [ ] Interrupt 소스: MTIP, MSIP, MEIP (3개만)
- [ ] 벡터화 주소: mtvec[31:2] + (cause << 2)
- [ ] Part 6 신호 호환성

---

## 파일 통계

| 파일 | 크기 | 줄 수 | 용도 |
|------|------|-------|------|
| chapter19_phase1_completion_report.md | 16 KB | 350줄 | 전체 개요 |
| chapter19_phase1_edu_designer_briefing.md | 8 KB | 180줄 | 교육설계 |
| chapter19_phase1_executive_summary.md | 8 KB | 210줄 | 기술 저자 가이드 |
| chapter19_phase1_instructor_briefing.md | 20 KB | 520줄 | 강사 자료 |
| chapter19_phase1_meeting.md | 8 KB | 220줄 | 기술 배경 |
| chapter19_phase1_psych_briefing.md | 12 KB | 380줄 | 심리학 |
| **합계** | **72 KB** | **1,860줄** | - |

---

## 다음 단계

### Phase 2: 기술 저자 집필 (예상 3-4시간)
→ 산출물: `manuscripts/part7/chapter19.html` + SVG 11개 + 코드 4개

### Phase 3: 병렬 리뷰 (예상 2-3시간)
→ 4명 리뷰어: 기술/초보자/심리/강사

### Phase 4: 종합 회의 및 수정 (예상 1-2시간)
→ 최종 승인 + output 생성

---

## 문의사항

- 기술 배경: `chapter19_phase1_meeting.md` 참조
- 학습 목표: `chapter19_phase1_edu_designer_briefing.md` 참조
- 불안 지점 해소: `chapter19_phase1_psych_briefing.md` 참조
- 강사 팁/비유: `chapter19_phase1_instructor_briefing.md` 참조
- 전체 체크리스트: `chapter19_phase1_completion_report.md` 참조

---

**편집장 서명:** team-lead@ch19-exception-interrupt
**작성일:** 2026-03-14
**상태:** ✅ Phase 1 완료

