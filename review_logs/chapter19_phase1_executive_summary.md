# Ch19 Phase 1 기획 회의 — 편집장 Executive Summary

**회의 날짜:** 2026-03-14
**회의 형식:** 병렬 기획 (3 teammates 동시)
**회의 상태:** Phase 1 완료, Phase 2 준비 중

---

## 회의 결과 개요

### 기획 완료 artifacts

| Role | Output File | Status |
|------|------------|--------|
| 교육 설계자 | review_logs/chapter19_phase1_edu_designer.md | 준비 완료 |
| 교육심리전문가 | review_logs/chapter19_phase1_psych_expert.md | 준비 완료 |
| 교육전문강사 | review_logs/chapter19_phase1_instructor.md | 준비 완료 |

**추가 배경 문서:**
- review_logs/chapter19_phase1_meeting.md (기술/설계 배경)
- review_logs/chapter19_phase1_edu_designer_briefing.md (task 정의)
- review_logs/chapter19_phase1_psych_briefing.md (task 정의)
- review_logs/chapter19_phase1_instructor_briefing.md (task 정의)

---

## 핵심 내용 (기술 저자를 위한 요약)

### Ch19 학습 목표 (예상)
- [Remember] RISC-V 인터럽트 원인 코드 열거
- [Understand] 우선순위 인코더 동작 원리 설명
- [Apply] SystemVerilog로 우선순위 인코더 구현
- [Analyze] 중첩 인터럽트 상황에서 CSR 값 추적
- [Evaluate] 고정 vs 동적 우선순위 비교

### 핵심 비유 (기술 저자 활용)

| 개념 | 비유 | 한계 | 대안 |
|------|------|------|------|
| 우선순위 인코더 | 응급실 트리아주 | 사람의 선택 vs 하드웨어 규칙 | 신호등 |
| 벡터화 주소 | 책의 목차 | 가변 길이 vs 고정 4바이트 | 영화관 |
| 중첩 인터럽트 | 함수 호출 스택 | 권한 변경 추가 | 전화 걸기 |
| MPIE | 백업 복사본 | - | 휴대폰 벨소리 |
| 고정 우선순위 | 신호등 규칙 | 조정 불가 | - |

### 메타인지 질문 (기술 저자 배치)

각 절 끝에 <aside class="metacognition"> 박스로:
1. "interrupt와 exception의 차이를 설명할 수 있나?"
2. "mtvec MODE=0과 MODE=1의 계산식을 비교할 수 있나?"
3. "우선순위 규칙: MSIP vs MTIP 누가 높은가? 변경 가능한가?"
4. "trap_pc가 1사이클 지연되는 이유는?"
5. "중첩 MRET 3번 후 어디로 돌아갈까?"
6. "Interrupt Controller와 Priority Encoder의 관계는?"
7. "왜 CSR 접근에 volatile 키워드를 써야 할까?"

### 학습 불안 지점과 완화책

| 절 | 불안점 | 심각도 | 완화책 |
|-----|--------|--------|--------|
| 19.3 | 우선순위 인코더의 추상성 | ⭐⭐⭐⭐ | 비유 + 단계적 예제 |
| 19.2 | 벡터화 주소 (cause << 2) | ⭐⭐⭐ | 그림 + 메모리 맵 |
| 19.5 | 중첩 인터럽트 메모리 구조 | ⭐⭐⭐⭐⭐ | 스택 비유 + 단계 추적 |
| 19.6 | 컨트롤러 복합성 | ⭐⭐⭐⭐ | 코드 구조 강조 |

### 감정 곡선 (기술 저자 설계)

```
19.1 호기심↑    (개요, 신규 개념)
19.2 혼란→이해  (벡터화, 그림 필수)
19.3 불안↑     (우선순위, 코드 필수)
19.4 호기심↑    (FSM, 비교적 간단)
19.5 불안↑↑↑   (중첩, 가장 어려움)
19.6 이해↑      (종합 설계)
19.7 성취감↑↑   (첫 인터럽트 작동)
```

### 데모 제안 (기술 저자 참고)

| 데모 | 목표 | 학습효과 | 난이도 |
|------|------|---------|--------|
| Timer LED | 1초마다 interrupt | 작동 확인 | ⭐⭐ |
| UART Echo | 수신 → 에코 | 주변장치 상호작용 | ⭐⭐⭐ |
| Priority 시뮬 | 동시 interrupt | 우선순위 검증 | ⭐⭐⭐⭐ |

---

## 기술 제약사항 (변경 불가)

```
✓ CSR 7개 고정: mstatus, mie, mtvec, mscratch, mepc, mcause, mip
✓ 우선순위 정책: 고정 (하드웨어 인코더)
✓ Interrupt 소스: MTIP, MSIP, MEIP (3개, RV32I만)
✓ 벡터화 주소: mtvec[31:2] + (cause << 2)
✓ Part 6 신호: timer_irq, uart_intr, gpio_intr (주변장치에서 수신)
✓ MRET 복구: MIE←MPIE, MPIE←1, MPP←2'b11
```

---

## 섹션 구성 (예상)

| 섹션 | 제목 | 신개념 | 핵심 비유 | SVG 필요 |
|------|------|--------|----------|---------|
| 19.1 | 인터럽트 개요 | interrupt vs exception | 응급실 | 1개 |
| 19.2 | 벡터화 주소 | mtvec + (cause<<2) | 책 목차 | 2개 |
| 19.3 | 우선순위 인코더 | 8-to-3 encoding | 신호등/트리아주 | 2개 |
| 19.4 | Trap 전이 | trap_enable FSM | - | 1개 |
| 19.5 | 중첩 인터럽트 | MPIE 저장/복구 | 함수 스택 | 2개 |
| 19.6 | Interrupt Controller | 종합 설계 | - | 2개 |
| 19.7 | 실습 + C 코드 | UART handler | - | 1개 |

**총 SVG:** ~11개 예상

---

## Phase 2 기술 저자 가이드라인

### 준수 사항

1. **templates/chapter_template.html 구조 준수**
   - <section>로 19.1~19.7 나누기
   - 각 절 2000~4000자

2. **코드 하이라이팅** (Highlight.js CDN)
   ```html
   <pre><code class="language-systemverilog">
   // 코드 (< > & 이스케이프)
   </code></pre>
   ```

3. **aside 박스 배치**
   - <aside class="tip"> — 우선순위 인코더 vs 멀티플렉서 차이
   - <aside class="faq"> — "왜 cause << 2인가?"
   - <aside class="interview"> — 면접 포인트 5개
   - <aside class="metacognition"> — 메타인지 질문 7개
   - <aside class="instructor-tip"> — 강사 팁 (Basys 3 데모)

4. **SVG 다이어그램**
   - figures/ch19_sec01_interrupts_overview.svg (개요)
   - figures/ch19_sec02_vectorized_address.svg (벡터화 1)
   - figures/ch19_sec02_address_calculation.svg (벡터화 2)
   - figures/ch19_sec03_priority_encoder.svg (우선순위 1)
   - figures/ch19_sec03_cause_code.svg (우선순위 2)
   - figures/ch19_sec04_trap_fsm.svg (Trap 전이)
   - figures/ch19_sec05_nested_interrupt.svg (중첩 1)
   - figures/ch19_sec05_stack_memory.svg (중첩 2)
   - figures/ch19_sec06_controller_block.svg (컨트롤러 1)
   - figures/ch19_sec06_controller_fsm.svg (컨트롤러 2)
   - figures/ch19_sec07_uart_handler.svg (실습)

5. **SystemVerilog 코드 예제**
   ```
   code_examples/ch19_priority_encoder.sv
   code_examples/ch19_interrupt_controller.sv
   code_examples/ch19_trap_handler.c
   code_examples/ch19_uart_interrupt_handler.asm
   ```

6. **연습문제** (5~7개)
   - Remember 1~2개
   - Understand 2~3개
   - Apply 1~2개

---

## 편집장 최종 승인 기준 (Phase 2 후)

### Critical 체크리스트
- [ ] CSR 7개 고정 준수 (변경 없음)
- [ ] 우선순위 정책 일관성 (고정)
- [ ] Part 6 신호 호환성 (timer/uart/gpio)
- [ ] MRET 복구 로직 정확성

### Major 체크리스트
- [ ] 각 절 2000~4000자 (±20% 허용)
- [ ] 비유 정확성 + 한계 명시
- [ ] 메타인지 박스 5곳 이상

### Minor (스타일)
- [ ] SVG 색상 통일 (파란 계열)
- [ ] 한글/영문 병기 (첫 등장)

### 이해도/교육/심리/강사 적합도
- ⭐⭐⭐ 이상 필수
- 특히 불안 지점 3곳의 완화책 적용 확인

---

## 다음 일정

| Phase | 담당 | 예상 기간 | 완료 기준 |
|-------|------|----------|---------|
| **2** | 기술 저자 | 3-4시간 | manuscripts/part7/chapter19.html |
| **3** | 4명 리뷰어 (병렬) | 2-3시간 | 4개 review_logs |
| **4** | 편집장 + 저자 | 1-2시간 | final 승인 |

**전체 예상:** 6-9시간 (2-3일)

---

## 편집장 서명

**Team Lead:** team-lead@ch19-exception-interrupt
**작성일:** 2026-03-14
**상태:** ✅ Phase 1 기획 완료, Phase 2 준비 가능

