# Ch19 Phase 1 기획 회의 (2026-03-14)

## 회의 목표
**Ch19: 예외와 인터럽트 처리** — 3명 teammate의 전문가 기획 회의

---

## 기술 배경 정보

### 이전 장 기초
- **Ch18** (CSR과 특권 수준): mstatus, mie, mtvec, mscratch, mepc, mcause, mip 레지스터 설계 완료
  - mtvec BASE[31:2] = 30비트 (벡터화 주소의 기본 주소)
  - mtvec MODE[1:0] = 2비트 (0=Direct, 1=Vectored)
  - mstatus MPIE[7], MIE[3], MPP[12:11] — interupt 복구용
  - mepc = trap 발생 시점의 PC (복구용)
  - mcause = trap 원인 코드
  - mip = interrupt pending (하드웨어 직결)

- **Ch17** (APB 브리지와 주변장치): Timer, UART, GPIO 완성
  - timer_irq 신호 (Ch19에서 MTIP 인터럽트로 매핑)
  - uart_rx_intr (UART 데이터 수신)
  - gpio_intr (GPIO 입력 변화 감지)

- **파이프라인 기본** (Ch09-12): 5단계 파이프라인, 포워딩, 스톨 메커니즘

### 핵심 신규 개념
1. **우선순위 인코더** (Priority Encoder)
   - 입력: 8개 interrupt 소스 (MEIP, MTIP, MSIP, SEIP, STIP, SSIP, UEIP, UTIP)
   - 출력: 1개 cause_code (3~4비트, RISC-V 정의)
   - 고정 우선순위: 소스별로 정해진 순서로 가장 높은 우선순위 인터럽트 선택
   - 설계 선택: 하드웨어 우선순위 고정 vs 소프트웨어 우선순위 제어 (Chapter 19에서 고정)

2. **벡터화 주소 계산** (Vectored Addressing)
   - mtvec MODE=0 (Direct): 모든 trap → 동일 주소
   - mtvec MODE=1 (Vectored): 각 cause별로 다른 주소
     - 주소 = mtvec[31:2] + (cause << 2)
     - 우선순위 인코더 출력과 직접 연결
   - 사이클 정확도: 다음 사이클에 PC 업데이트

3. **Trap Handler 호출**
   - 조건: irq_pending = mstatus[MIE] && |(mie & mip)
   - 다음 사이클: PC ← vectored_address
   - CSR 자동 저장: mepc ← current_pc, mcause ← cause_code, mstatus 업데이트
   - 이전 인터럽트 상태: mstatus[MIE] → mstatus[MPIE] (자동 저장)

4. **중첩 인터럽트 처리** (Nested Interrupt)
   - Trap Handler 내부: MPIE = 저장된 이전 MIE 상태
   - Handler 내에서 재활성화: mstatus[MIE] ← 1 (다시 인터럽트 수락)
   - MRET 실행: MIE ← MPIE (이전 상태로 복구)
   - 스택: mepc/mcause/mstatus를 스택에 저장하여 깊은 중첩 지원

---

## 기획 요청 (3 Teammates)

### 1. 교육 설계자 (Instructional Designer)

**임무:**
- Ch19 학습 목표를 "~할 수 있다" 형태로 정의 (블룸 분류 동사 포함)
- 19.1~19.7 각 섹션의 학습 목표
- 선수 지식 검증: Ch18 CSR, Ch17 Timer 이해도
- 인지 부하 분석: 우선순위 인코더 + 벡터화 주소 복합성
- 연습문제 구성 제안 (블룸 분류 최소 3수준)

**출력:** `review_logs/chapter19_phase1_edu_designer.md`

**핵심 질문:**
- Ch19 5개 학습 목표를 작성해주세요. 예:
  * "RV32I 인터럽트의 우선순위 인코딩 로직을 설계할 수 있다"
  * "벡터화 주소 계산식을 SystemVerilog로 구현할 수 있다"
  * 등등...
- 19.1~19.7 섹션별 선수 지식 전제: Ch18의 어느 부분이 반드시 이해되어야 하는가?
- 인지 부하가 가장 높을 위험 섹션은? (예: 19.3 우선순위 인코더?)
- 연습문제 5~7개 제안 (블룸 Remember/Understand/Apply/Analyze)

---

### 2. 교육심리전문가 (Educational Psychologist)

**임무:**
- 감정 곡선 설계: 호기심 → 불안 지점 → 이해 → 성취감
- 스트레스 포인트 감지: 어디서 학생이 "이해가 안 된다"고 느낄까?
- 자기효능감 관리: 첫 번째 성공 경험이 언제 올 것인가?
- 메타인지 촉진 장치: "스스로 점검" 박스, 질문 제안

**출력:** `review_logs/chapter19_phase1_psych_expert.md`

**핵심 질문:**
- 예상되는 불안 지점 Top 3:
  1. (예: "우선순위 인코더 로직이 복잡하고 추상적인가?")
  2. (예: "벡터화 주소 계산의 (cause << 2) 비트 시프트가 혼란스러운가?")
  3. (예: "중첩 인터럽트에서 메모리 구조(스택) 개념이 새로운가?")
- 첫 성공 경험: 19.몇 절에서 "아, 우선순위는 이렇게 작동하는구나"를 깨달을까?
- 메타인지 질문 5개 제안 (예: "이 코드가 우선순위를 어떻게 구분하는지 설명할 수 있나?")
- 감정 곡선: 각 절별 예상 감정 변화

---

### 3. 교육전문강사 (Expert Instructor)

**임무:**
- 설명 품질: "강의에서 그대로 읽을 수 있는 수준"
- 비유 검증: ① 기술 사실과 매핑 ② 한계 명시 ③ 오해 유발 여부 ④ 대안 비유
- 수강생 막힘 포인트 예측 + 돌파 전략
- 면접 연결 포인트: "인터럽트 우선순위는 프로세서마다 다를까?"
- 데모 제안 (Basys 3 FPGA 보드)

**출력:** `review_logs/chapter19_phase1_instructor.md`

**핵심 질문:**
- Ch19에서 막힐 가능성 Top 5:
  1. 우선순위 인코더: 어떤 비유가 좋을까? (응급실 분류 / 신호등 신호 우선순위 / 은행 대기번호 시스템?)
  2. 벡터화 주소: (cause << 2)의 의미가 명확한가? (주소 alignment? 4바이트?)
  3. 중첩 인터럽트: mepc/mcause/mstatus 스택 저장의 필요성
  4. MRET vs 일반 RET: 무엇이 다른가?
  5. 우선순위의 "고정성": 왜 우선순위는 변경 불가한가?
- 각 막힘 포인트별 "강사 팁" 제안
- 면접 포인트: "ARM의 인터럽트 우선순위는 RISC-V와 다른가?" (Yes, ARM은 동적 우선순위 제어 가능)
- 데모 시나리오: Timer interrupt + UART interrupt 동시 발생 시 우선순위 관찰

---

## 기술 설계 제약사항 (변경 불가)

| 항목 | 값 | 근거 |
|------|---|------|
| **CSR 7개 고정** | mstatus, mie, mtvec, mscratch, mepc, mcause, mip | Ch18 완성 |
| **mtvec 주소** | BASE[31:2] (30비트) + MODE[1:0] (2비트) | RISC-V Privileged Spec |
| **Interrupt 소스** | MTIP(Timer), MSIP(Software), MEIP(External) + U/S mode 예약 | RV32I only (M-mode) |
| **우선순위 정책** | 고정 우선순위 (하드웨어 인코더) | 단순화 (Ch19 범위) |
| **벡터화 주소** | mtvec[31:2] + (cause << 2) | RISC-V 정의 |
| **Trap 저장** | mepc, mcause, mstatus[MPIE/MIE/MPP] 자동 저장 | ISA 정의 |
| **MRET 복구** | MIE ← MPIE, MPIE ← 1, MPP ← 2'b11 | Ch18 설계 확인 |
| **Part 6 의존성** | timer_irq, uart_intr, gpio_intr 신호 수용 | Ch17 제공 |

---

## 기획 일정

| Phase | Teammate | 예상 시간 | 완료 기준 |
|-------|----------|----------|---------|
| **1A** | 교육설계자 | 1-2시간 | review_logs/chapter19_phase1_edu_designer.md |
| **1B** | 교육심리전문가 | 1-2시간 | review_logs/chapter19_phase1_psych_expert.md |
| **1C** | 교육전문강사 | 1-2시간 | review_logs/chapter19_phase1_instructor.md |
| **1D** | 편집장 (통합) | 30분 | ch19_phase1_meeting.md 최종 작성 |
| **Phase 2** | 기술 저자 | 3-4시간 | manuscripts/part7/chapter19.html |

---

## 다음 단계: Phase 2 (기술 저자)

Phase 1 회의 완료 후:
1. 교육설계자 제안 학습 목표 확정
2. 교육심리전문가 제안 메타인지 박스 배치 계획 확인
3. 교육전문강사 제안 비유/예제 목록 수집

→ 기술 저자: templates/chapter_template.html 구조로 19.1~19.7 집필
→ SVG 다이어그램: ch19_sec01~sec07 설계
→ SystemVerilog 코드: ch19_priority_encoder.sv, ch19_interrupt_controller.sv 등

---

## 편집장 최종 승인 기준

- ✅ 학습 목표 5개 확정 (블룸 분류 기준)
- ✅ 감정 곡선 설계 확인 (불안 지점 3곳 파악)
- ✅ 메타인지 박스 배치 5곳 이상
- ✅ 강사 팁 + 비유 5개 이상
- ✅ 기술 제약사항 전혀 변경 안 함

**승인 서명:**
- 편집장: team-lead@ch19-exception-interrupt (2026-03-14)

