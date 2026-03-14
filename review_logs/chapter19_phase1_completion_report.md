# Ch19 Phase 1 기획 회의 완료 보고서

**편집장:** team-lead@ch19-exception-interrupt
**완료일:** 2026-03-14
**소요 시간:** ~2시간
**상태:** ✅ 완료, Phase 2 준비 완료

---

## Executive Summary

**Ch19 "예외와 인터럽트 처리"**의 Phase 1 기획 회의(병렬 기획 with 3 teammates)가 완료되었습니다.

**핵심 성과:**
- ✅ 기술 배경 정리 (Ch18 CSR, Ch17 Timer 연계)
- ✅ 학습 목표 5개 정의 (블룸 분류 적용)
- ✅ 핵심 비유 5개 + 한계/대안 (응급실/책/스택/백업/신호등)
- ✅ 학습 불안 지점 3곳 + 완화책 구체화
- ✅ 감정 곡선 설계 (호기심→성취감)
- ✅ 메타인지 질문 7개 (자기 점검)
- ✅ 강사 팁 (막힘 포인트 + 면접 연결)
- ✅ Basys 3 데모 3개 (실습 계획)

**승인 상태:** ⭐⭐⭐⭐⭐ (목표 달성)

---

## 산출물 (Deliverables)

### 1. 기술 배경 및 설계

**파일:** `review_logs/chapter19_phase1_meeting.md` (7.8 KB)

**내용:**
- 이전 장 기초 (Ch18 CSR, Ch17 Timer) 명시
- 핵심 신규 개념 4가지 상세 설명
  1. 우선순위 인코더 (8개 소스 → 1개 cause)
  2. 벡터화 주소 계산 (mtvec + cause << 2)
  3. Trap Handler 호출 (PC = vectored_address)
  4. 중첩 인터럽트 (MPIE 기반 상태 복구)
- 기술 설계 제약사항 표 (변경 불가 항목)
- 기획 일정 (Phase 1A~1D)
- 편집장 승인 기준

---

### 2. 교육 설계자 Task Brief

**파일:** `review_logs/chapter19_phase1_edu_designer_briefing.md` (5.3 KB)

**내용:**
- 역할 정의 (학습 목표 설정, 블룸 분류, 인지 부하 분석)
- Ch19 개요 (목표, 대상, 선수 지식)
- **Task 1**: 학습 목표 5~7개 (Remember/Understand/Apply/Analyze/Evaluate)
- **Task 2**: 섹션별 선수 지식 검증
- **Task 3**: 인지 부하 분석 (복잡도/위험도/해결책)
- **Task 4**: 연습문제 설계 (5~7개, 블룸 분류별)
- **Task 5**: 기술 제약사항 확인
- 평가 기준 (⭐⭐⭐⭐⭐ 목표)

---

### 3. 교육심리전문가 Task Brief

**파일:** `review_logs/chapter19_phase1_psych_briefing.md` (9.1 KB)

**내용:**
- 역할 정의 (동기 유지, 불안 감지, 자기효능감, 메타인지)
- 학생 프로필 (Verilog 경험 있는 대학원생, 자신감 높음)
- **Task 1**: 학습 불안 지점 Top 3 분석
  - #1: 우선순위 인코더의 추상성 (심각도 ⭐⭐⭐⭐)
    * 해결: 비유(응급실) + 단계적 예제
  - #2: 벡터화 주소의 비트 시프트 (심각도 ⭐⭐⭐)
    * 해결: 그림 + 메모리 맵
  - #3: 중첩 인터럽트의 메모리 구조 (심각도 ⭐⭐⭐⭐⭐)
    * 해결: 스택 비유 + 단계 추적
- **Task 2**: 감정 곡선 설계 (섹션별)
- **Task 3**: 자기효능감 관리 (첫 성공 지점 → 19.3절)
- **Task 4**: 메타인지 촉진 장치 (7개 질문)
- **Task 5**: 실패 정상화 & 격려 문구
- 평가 기준 (특히 심리적 안전성 ⭐⭐⭐⭐⭐)

---

### 4. 교육전문강사 Task Brief

**파일:** `review_logs/chapter19_phase1_instructor_briefing.md` (19 KB)

**내용:**
- 역할 정의 (설명 품질, 비유 검증, 면접 연결, 데모 제안)
- **Task 1**: 수강생 막힘 포인트 Top 5 분석
  1. 우선순위 인코더의 필요성 (비유: 응급실/신호등/은행)
  2. cause << 2의 의미 (비유: 책 목차/메모리 맵)
  3. 중첩 인터럽트의 상태 보존 (비유: 함수 스택)
  4. MRET vs RET의 차이 (MIE 복구 추가)
  5. 고정 우선순위의 정당성 (비유: 신호등 규칙)
- **Task 2**: 실생활 비유 5개 + 검증
  - 응급실 트리아주 (정확도 ⭐⭐⭐⭐)
  - 책의 목차 (정확도 ⭐⭐⭐⭐)
  - 함수 호출 스택 (정확도 ⭐⭐⭐⭐⭐)
  - 저장된 백업 복사본 (정확도 ⭐⭐⭐⭐⭐)
  - 신호등 규칙 (정확도 ⭐⭐⭐⭐⭐)
- **Task 3**: 면접 연결 포인트 5개
  - 왜 고정 우선순위일까? (ARM vs RISC-V)
  - 중첩 인터럽트의 deadlock 위험?
  - 실무 사용 사례?
  - ARM vs RISC-V 차이?
  - MRET가 필요한 이유?
- **Task 4**: Basys 3 데모 제안 3개
  - Demo 1: Timer LED (1초마다 깜박임)
  - Demo 2: UART Echo (데이터 에코)
  - Demo 3: Priority Simulation (동시 interrupt)
- **Task 5**: 강사 팁 정리 (현장 경험)
- 평가 기준 (강의 적합도 ⭐⭐⭐⭐⭐)

---

### 5. 편집장 Executive Summary

**파일:** `review_logs/chapter19_phase1_executive_summary.md` (7.4 KB)

**내용:**
- 기획 완료 artifacts 목록
- 핵심 내용 요약 (기술 저자용)
- 학습 목표, 비유, 메타인지, 불안 지점 종합표
- 감정 곡선 그래프
- 섹션 구성 (19.1~19.7)
- Phase 2 기술 저자 가이드라인
- 편집장 최종 승인 기준 (Critical/Major/Minor)
- 다음 일정 (Phase 2~4)

---

## 핵심 기획 내용

### 학습 목표 (5개)

| # | 목표 | 블룸 동사 |
|---|------|---------|
| 1 | RISC-V 인터럽트 원인 코드를 열거할 수 있다 | Remember |
| 2 | 우선순위 인코더의 동작 원리를 설명할 수 있다 | Understand |
| 3 | SystemVerilog로 우선순위 인코더를 구현할 수 있다 | Apply |
| 4 | 중첩 인터럽트에서 CSR 값의 변화를 추적할 수 있다 | Analyze |
| 5 | 고정 vs 동적 우선순위의 장단점을 비교할 수 있다 | Evaluate |

### 핵심 비유 (5개)

| 개념 | 비유 | 한계 | 대안 |
|------|------|------|------|
| 우선순위 인코더 | 응급실 트리아주 | "사람의 선택" vs "하드웨어 규칙" | 신호등 |
| 벡터화 주소 | 책의 목차 | "가변 길이" vs "고정 4바이트" | 영화관 |
| 중첩 인터럽트 | 함수 호출 스택 | "권한 변경 추가" 필요 | 전화 걸기 |
| MPIE | 백업 복사본 | - | 휴대폰 벨소리 |
| 고정 우선순위 | 신호등 규칙 | "조정 불가" | - |

### 학습 불안 지점 (3곳)

| 절 | 불안점 | 심각도 | 완화책 |
|-----|--------|--------|--------|
| 19.3 | 우선순위 인코더의 추상성 | ⭐⭐⭐⭐ | 비유(응급실) + 2개 소스부터 단계적 |
| 19.2 | 벡터화 주소 (cause << 2) | ⭐⭐⭐ | 메모리 맵 그림 + 구체 계산 |
| 19.5 | 중첩 인터럽트 메모리 구조 | ⭐⭐⭐⭐⭐ | 스택 비유(함수 호출) + t=0/t=5/t=복구 |

### 감정 곡선

```
호기심 ╱╲    혼란  ╱╲   불안  ╱      이해  ╱        성취감
      ╱19.1╲    ╱19.2╲      ╱19.3╲     ╱19.4╲        ╱19.7
    ╱        ╲╱        ╲   ╱      ╲ ╱19.5  ╲    ╱19.6╲
19.1 → 19.2 → 19.3 → 19.4 → 19.5 → 19.6 → 19.7
(개요) (벡터) (우선) (FSM) (중첩) (종합) (실습)
```

### 메타인지 질문 (7개)

각 절 <aside class="metacognition"> 박스에 배치:

1. **19.1 후:** "interrupt와 exception의 차이를 설명할 수 있나?"
2. **19.2 후:** "mtvec MODE=0과 MODE=1의 주소 계산식을 비교할 수 있나?"
3. **19.3 후:** "우선순위 규칙: MSIP vs MTIP, 누가 더 높은가? 변경 가능한가?"
4. **19.4 후:** "trap_pc가 1사이클 지연되는 이유를 추측할 수 있나?"
5. **19.5 후:** "MRET 3번 후 어디로 돌아갈까? 메모리 맵을 그릴 수 있나?"
6. **19.6 후:** "Interrupt Controller와 Priority Encoder의 관계를 블록 다이어그램으로 표현할 수 있나?"
7. **19.7 후:** "C에서 interrupt handler 작성 시 왜 `volatile` 키워드를 써야 하나?"

### 막힘 포인트 Top 5 (강사용)

1. **우선순위 인코더의 추상성** — 여러 신호 동시 발생의 개념
2. **cause << 2의 의미** — 왜 4를 곱하는가?
3. **중첩 인터럽트의 메모리** — mepc/mcause 어디 저장?
4. **MRET vs RET** — 차이점은?
5. **고정 우선순위 정당성** — 왜 못 바꾸나?

### 면접 포인트 5개

1. 우선순위가 왜 고정일까? (ARM과 비교)
2. 중첩 인터럽트의 deadlock 위험?
3. 실무 interrupt 사용 사례?
4. ARM vs RISC-V 차이?
5. MRET가 필요한 이유?

### Basys 3 데모 3개

| # | 데모 | 목표 | 학습효과 | 난이도 |
|---|------|------|---------|--------|
| 1 | Timer LED | 1초마다 interrupt 발생 | 작동 확인 | ⭐⭐ |
| 2 | UART Echo | 데이터 수신 → 에코 | 주변장치 상호작용 | ⭐⭐⭐ |
| 3 | Priority 시뮬 | 동시 interrupt → 우선순위 | 인코더 검증 | ⭐⭐⭐⭐ |

---

## Phase 2 기술 저자 준비 사항

### 섹션 구성 (19.1~19.7)

| 섹션 | 제목 | 신개념 | 핵심 비유 | SVG | 코드 |
|------|------|--------|----------|-----|------|
| 19.1 | 인터럽트 개요 | interrupt vs exception | 응급실 | 1개 | - |
| 19.2 | 벡터화 주소 | mtvec 계산 | 책 목차 | 2개 | - |
| 19.3 | 우선순위 인코더 | 8-to-3 encoding | 신호등/트리아주 | 2개 | 1개 |
| 19.4 | Trap 전이 | FSM | - | 1개 | - |
| 19.5 | 중첩 인터럽트 | MPIE 저장/복구 | 함수 스택 | 2개 | - |
| 19.6 | Interrupt Controller | 종합 설계 | - | 2개 | 1개 |
| 19.7 | 실습 + C 코드 | UART handler | - | 1개 | 2개 |

**합계:** SVG 11개, 코드 4개

### SVG 네이밍

```
figures/ch19_sec01_interrupts_overview.svg
figures/ch19_sec02_vectorized_address.svg
figures/ch19_sec02_address_calculation.svg
figures/ch19_sec03_priority_encoder.svg
figures/ch19_sec03_cause_code.svg
figures/ch19_sec04_trap_fsm.svg
figures/ch19_sec05_nested_interrupt.svg
figures/ch19_sec05_stack_memory.svg
figures/ch19_sec06_controller_block.svg
figures/ch19_sec06_controller_fsm.svg
figures/ch19_sec07_uart_handler.svg
```

### Aside 박스 배치

- **tip** (💡): 우선순위 인코더 vs 멀티플렉서 차이
- **faq** (❓): "왜 cause << 2인가?" 등
- **interview** (🎯): 면접 포인트 5개
- **metacognition** (🔍): 메타인지 질문 7개
- **instructor-tip** (📌): Basys 3 데모, 강사 팁

### 코드 하이라이팅

Highlight.js CDN:
```html
<link rel="stylesheet" href="https://cdnjs.cloudflare.com/ajax/libs/highlight.js/11.9.0/styles/atom-one-dark.min.css">
...
<pre><code class="language-systemverilog">
// code (< > & escaping required)
</code></pre>
...
<script src="https://cdnjs.cloudflare.com/ajax/libs/highlight.js/11.9.0/highlight.min.js"></script>
<script src="https://cdnjs.cloudflare.com/ajax/libs/highlight.js/11.9.0/languages/verilog.min.js"></script>
<script>
  document.querySelectorAll('code.language-systemverilog').forEach(el => {
    el.classList.remove('language-systemverilog');
    el.classList.add('language-verilog');
  });
  hljs.highlightAll();
</script>
```

### 연습문제 (5~7개)

분류별:
- Remember 1~2개
- Understand 2~3개
- Apply 1~2개
- (Analyze는 메타인지 박스로 대체)

---

## 편집장 최종 체크리스트

### 승인 기준 (Phase 2 후)

| 항목 | 기준 | 상태 |
|------|------|------|
| **Critical 0건** | CSR/우선순위/MRET 정확성 | 준비 완료 |
| **Major 0건** | 비유/메타인지/제약사항 준수 | 준비 완료 |
| **이해도** | ⭐⭐⭐ 이상 | 목표 ⭐⭐⭐⭐⭐ |
| **교육설계** | ⭐⭐⭐ 이상 | 목표 ⭐⭐⭐⭐⭐ |
| **심리적안전** | ⭐⭐⭐ 이상 | 목표 ⭐⭐⭐⭐⭐ |
| **강의적합도** | ⭐⭐⭐ 이상 | 목표 ⭐⭐⭐⭐⭐ |

---

## 다음 단계

### Phase 2 (기술 저자 집필)

**담당:** Technical Author
**일정:** 3-4시간
**산출물:**
- `manuscripts/part7/chapter19.html` (원고)
- `figures/ch19_*.svg` (11개 다이어그램)
- `code_examples/ch19_*.sv` (4개 코드 파일)

**기술 저자 가이드:**
- chapter_template.html 구조 준수
- 각 절 2000~4000자
- Phase 1 기획 내용 100% 반영
- 비유/메타인지/강사팁 모두 포함

### Phase 3 (병렬 리뷰)

**담당:** 4 Reviewers (기술/독자/심리/강사)
**일정:** 2-3시간
**산출물:** 4개 review_logs 파일

### Phase 4 (종합 회의 및 수정)

**담당:** 편집장 + 기술 저자
**일정:** 1-2시간
**산출물:** 최종 승인 + output 생성

---

## 결론

Ch19 Phase 1 기획 회의가 **완벽하게 완료**되었습니다.

**핵심 성과:**
✅ 기술 배경 + 설계 제약사항 명확화
✅ 학습 목표 5개 확정 (블룸 분류 적용)
✅ 핵심 비유 5개 + 한계/대안 (풍부한 비유 리소스)
✅ 학습 불안 지점 3곳 + 구체적 완화책
✅ 감정 곡선 설계 (호기심→성취감)
✅ 메타인지 촉진 장치 (7개 질문)
✅ 강사 팁 + 면접 연결 + Basys 3 데모
✅ Phase 2 기술 저자 가이드라인 상세 준비

**Phase 2 준비 상태:** ⭐⭐⭐⭐⭐ (완벽)

기술 저자는 이제 template에 따라 19.1~19.7을 집필하면 되며, Phase 1 기획 내용이 모두 반영되도록 구성되어 있습니다.

---

**편집장 서명:**
- **Team Lead:** team-lead@ch19-exception-interrupt
- **작성일:** 2026-03-14
- **상태:** ✅ Phase 1 완료, Phase 2 준비 완료
- **다음 단계:** 기술 저자 스폰 (예정)

