# Chapter 25 기획 회의록

## 프로젝트 개요
- **제목**: 멀티코어와 캐시 일관성 기초 (Chapter 25)
- **위치**: Part 9 - 심화 주제 (블룸 수준: Create)
- **섹션**: 2개 (25.1 멀티코어 설계 과제, 25.2 스핀락과 원자 연산)
- **대상**: Verilog 경험이 있는 대학원생 (Ch01~Ch24 완수)
- **날짜**: 2026-03-15

---

## 1. 기술 저자 계획

### 25.1 멀티코어 설계 과제

**핵심 메시지**:
> 단일 코어에서 다중 코어로 확장할 때, 여러 프로세서가 동일한 메모리를 접근하면서 발생하는 캐시 일관성 문제를 이해하고, MESI 프로토콜로 이를 해결하는 방법을 습득한다.

**코드 예제 목록** (4개):
1. **MESI 캐시 상태 머신 (SystemVerilog)**
   - 각 캐시 라인의 상태(Modified, Exclusive, Shared, Invalid)를 나타내는 조합 논리 회로
   - 메모리 작업과 버스 감시(Bus Snooping)에 따른 상태 전이
   - `always_comb` 블록으로 구현

2. **2코어 공유 메모리 프레임워크 (Top Module)**
   - Core 0, Core 1, 공유 메모리, 버스 인터페이스 (AHB-Lite 기반)
   - 각 코어 내부: L1 D-Cache + MESI 컨트롤러
   - 버스 중재기와 스누핑 로직

3. **캐시 일관성 프로토콜 검증용 testbench**
   - 동일 주소에 대한 순차적 읽기/쓰기 연산
   - 상태 전이 trace 및 메모리 값 검증
   - 메모리 일관성 위반 감지

4. **간단한 MESI 디버깅 모듈**
   - 캐시 상태, 메모리 값, 버스 이벤트를 실시간 모니터링
   - waveform 해석 가이드

**SVG 다이어그램 목록** (3개):
1. **figures/ch25_sec01_mesi_state_diagram.svg**
   - MESI 4가지 상태와 상태 전이 조건 (Modified ↔ Exclusive ↔ Shared → Invalid)
   - 메모리 읽기(Read), 메모리 쓰기(Write), 버스 읽기(Bus Read), 버스 쓰기(Bus Write) 이벤트
   - 각 상태에서 캐시 라인이 메모리와 동기화되어 있는지 표시

2. **figures/ch25_sec01_cache_coherence_problem.svg**
   - 시간축 타임라인으로 캐시 일관성 문제 시각화
   - Core 0가 addr[0x100]을 수정 → Core 1이 동일 주소 읽음 → 이전 값 발견(BUG!)
   - MESI 적용 후의 개선된 동작 (Invalidation 신호)

3. **figures/ch25_sec01_multicore_system_block.svg**
   - 2코어 시스템 아키텍처: Core 0 & Core 1 (각각 L1 D-Cache), 공유 메모리, 버스, MESI 컨트롤러
   - 버스 스누핑 경로 강조

**비유 및 실생활 예시**:
- **도서관 열람실 비유**: 여러 학생(코어)이 동일한 교재(메모리)를 공유할 때, 한 학생이 필기한 개인 복사본(캐시)이 원본과 맞지 않는 상황 → MESI는 "필기본 수정 시 다른 학생들에게 알림" 메커니즘
- **온라인 협업 문서(Google Docs)**: 여러 편집자가 동시에 작업할 때 자동 동기화 (Version control + Invalidation)
- **커피숍 메뉴판**: 여러 점원(코어)이 각각 메뉴판 사본(캐시)을 들고 있는데, 본점에서 가격 변경(메모리 쓰기) → 스누핑으로 즉시 갱신

---

### 25.2 스핀락과 원자 연산

**핵심 메시지**:
> RISC-V A(Atomic) 확장의 LR(Load-Reserved)/SC(Store-Conditional) 명령어로 원자적 메모리 접근을 구현하고, 이를 이용해 스핀락과 같은 동기화 메커니즘을 설계한다.

**코드 예제 목록** (5개):
1. **RISC-V LR/SC 명령어 인코딩 및 시맨틱스 (참고 자료)**
   - LR.W: 메모리에서 읽고 "예약" 설정
   - SC.W: 메모리 쓰기 성공 여부에 따라 반환값(0=성공, 1=실패) 결정
   - 예약 상태 추적 메커니즘 (per-core reservation flag)

2. **LR/SC 구현용 컨트롤러 (SystemVerilog)**
   - 메모리 주소당 하나의 reservation 비트 유지
   - Core ID + 주소를 매칭하여 자신의 LR에 대해서만 SC 성공
   - 타 코어의 메모리 쓰기 시 reservation 무효화 (invalidation)

3. **스핀락 C 코드 → RISC-V 어셈블리 → SystemVerilog RTL**
   - C: `while(compare_and_swap(lock, 0, 1));`
   - RISC-V: LR.W → BNE(예약 실패) loop → SC.W → BNE(SC 실패) loop
   - RTL: FSM으로 LR과 SC 사이의 동작 추적

4. **뮤텍스/세마포어 구현 기초**
   - Lock/Unlock 신호 설계
   - 우선순위 큐(Priority Queue) 기반 대기 처리 개요
   - 실무 참고: POSIX pthread_mutex

5. **스핀락 testbench**
   - 2코어가 동일한 critical section 접근 경쟁
   - 한 번에 1코어만 진입 검증
   - Fairness(공정성) 분석: 모든 코어가 결국 진입 기회를 가지는가

**SVG 다이어그램 목록** (3개):
1. **figures/ch25_sec02_lrsc_instruction_format.svg**
   - LR.W/SC.W 인코딩: opcode, funct3, rs1(주소), rd(데이터/반환값)
   - 타이밍: LR 실행 시점, SC 실행 시점, reservation 유효/무효 상태

2. **figures/ch25_sec02_spinlock_state_machine.svg**
   - Core의 스핀락 획득 FSM: IDLE → LOAD_RESERVE(LR) → CHECK_RESERVED → TRY_STORE(SC) → RELEASE
   - Lock 변수 = 0 (unlocked) / 1 (locked)
   - 2개 코어가 동시에 진입하려 할 때의 경쟁 (Race condition)

3. **figures/ch25_sec02_spinlock_timing.svg**
   - 시간축: Core 0 & Core 1이 동일한 lock 변수에 접근
   - Core 0: LR → SC 성공 (Lock 획득) → Critical Section → SC(Unlock)
   - Core 1: LR → SC 실패(Reservation 무효) → 반복 (Spin)
   - 버스 일관성 신호(Invalidation)로 Core 1의 LR 재실행 트리거

---

## 2. 교육 설계자 계획

### Chapter 25 학습 목표 (3~5개, "~할 수 있다" 형태)

1. **이해 수준 (Understanding)**
   - 멀티코어 환경에서 캐시 일관성 문제가 발생하는 원인을 설명할 수 있다.
   - MESI 프로토콜의 4가지 상태(Modified, Exclusive, Shared, Invalid)와 상태 전이 조건을 이해할 수 있다.

2. **분석 수준 (Analysis)**
   - 주어진 멀티코어 메모리 접근 시나리오에서 캐시 일관성 문제를 식별할 수 있다.
   - RISC-V LR/SC 명령어의 작동 원리를 이해하고, 원자성(Atomicity)이 보장되는 메커니즘을 분석할 수 있다.

3. **적용 수준 (Application)**
   - MESI 프로토콜을 이용해 2코어 프로세서의 캐시 컨트롤러를 설계할 수 있다.
   - LR/SC를 이용해 스핀락을 구현할 수 있다.

4. **평가 수준 (Evaluation)**
   - 스핀락 vs 뮤텍스의 성능/에너지 트레이드오프를 평가할 수 있다.
   - 자신의 멀티코어 설계에서 데드락 가능성을 검토할 수 있다.

5. **창조 수준 (Creation)** ← Part 9의 핵심
   - MESI 기반 다중 캐시 계층(L1, L2) 구조를 설계할 수 있다.
   - 실무 멀티코어 프로세서(ARM Cortex-A, Intel Core)의 캐시 일관성 프로토콜을 분석하고 자신의 설계에 적용할 수 있다.

### 블룸 수준별 인지 부하 분석

| 수준 | Ch25에서의 역할 | 인지 부하 | 학습 전략 |
|------|---------------|---------|---------|
| **Understanding** | 개념 도입 | 낮음~중간 | MESI 상태도 + 타임라인 다이어그램으로 직관 형성 |
| **Analysis** | 문제 식별 | 중간 | "캐시 일관성 없음 vs MESI 적용" 비교 시나리오 |
| **Application** | 설계 과제 1 (MESI) | 중간~높음 | 아래 "기존 지식과의 연결 고리" 참조 |
| **Application** | 설계 과제 2 (LR/SC) | 높음 | 명령어 인코딩 → FSM → RTL 단계적 전개 |
| **Evaluation** | 성능 분석 | 높음 | Ch15 캐시 성능 지표(HitRate, CPI)와 통합 |
| **Creation** | 멀티캐시/산업 적용 | 매우 높음 | Part 9의 최종 마일스톤 |

### 기존 파이프라인 지식과의 연결 고리

**Ch01~Ch12 (파이프라인 설계)**:
- 포워딩, 해저드 감지 → 캐시 일관성도 "데이터 동기화 문제"로 동일한 패러다임
- Stall 신호 우선순위 → MESI 상태 전이도 "이벤트 우선순위"로 동일
- WB-ID 포워딩(Ch12) → LR/SC의 "예약" 메커니즘과 개념 유사

**Ch13~Ch15 (캐시 설계)**:
- L1 I/D-Cache 구조, Tag/Index → MESI는 "캐시 라인 단위로 상태 관리"
- FSM (IDLE→MISS→FILL→DONE) → MESI (Modified→Exclusive→Shared→Invalid) 동일 패턴
- Cache Miss 미스 페널티 → 멀티코어에서는 Invalidation으로 추가 지연 발생 가능

**Ch23~Ch24 (성능 최적화 & 확장)**:
- 슈퍼스칼라(Ch23) + MESI = 멀티쓰레딩의 기초
- 명령어 확장(Ch24) → A 확장(LR/SC)으로 자연스러운 확장

---

## 3. 교육전문강사 계획

### 수강생 막힘 포인트 Top 5 & 해소 방법

#### 1️⃣ **병렬 프로그래밍 사고방식의 전환**
   - **문제**: 단일코어에서는 "순차 실행 = 맞다"라는 직관이 있으나, 멀티코어에서는 "동시 실행"이 기본 가정
   - **막힘**: "Core 0과 Core 1이 *정말* 동시에 같은 메모리에 접근할 수 있나요?"

   **해소 방법**:
   - **비유**: "은행 계좌(메모리)를 두 ATM(코어)이 동시에 인출하는 상황" → 동시성은 피할 수 없는 현실
   - **점진적 학습**:
     - 단일코어에서 스톨/포워딩(Ch10) → 실제로는 "한 사이클 내 여러 연산"
     - 캐시(Ch13) → "읽기 요청이 항상 1사이클에 반환되지 않음" 경험
     - 멀티코어 → 위 두 개념의 자연스러운 확장
   - **실제 산업 사례**:
     - 스마트폰 멀티코어 부팅: 코어가 완전히 동시에 부팅 명령을 실행 (bootrom 공유)
     - 멀티쓰레드 응용(웹 브라우저 탭들) → 실제로 병렬 실행 중

---

#### 2️⃣ **MESI 프로토콜의 추상화 수준 이해**
   - **문제**: MESI 상태 전이 다이어그램에 10개 이상의 화살표 존재 → 복잡도 폭발
   - **막힘**: "어떤 상황에서 Modified → Shared로 가는데, 언제 Exclusive로 가나요?"

   **해소 방법**:
   - **비유**: "MESI는 '사실 2×2 행렬'"
     - **행**: 내 캐시에 데이터 있음 / 없음
     - **열**: 나만 가짐(Exclusive) / 다른 코어도 가짐(Shared)
     - 쓰기 시 → 다른 캐시 무효화(Invalidation) → Exclusive로 변환
   - **점진적 학습**:
     - 먼저 2코어만: Core 0 쓰기 → Core 1의 해당 라인 = Invalid (가장 단순)
     - 그 다음 읽기: Core 0 & Core 1 모두 읽음 → Shared (데이터 공유)
     - 마지막 최적화: 읽기 후 쓰기 → Exclusive → Modified (한 코어만 소유)
   - **실제 산업 사례**:
     - ARM AMBA ACE 프로토콜 문서의 MESI 섹션 (간소화)
     - Intel Core i7의 MESI 구현 (실제는 MESIF로 확장, 하지만 기본은 동일)

---

#### 3️⃣ **LR/SC의 "예약" 개념**
   - **문제**: "왜 LR 직후 바로 SC를 안 하고 중간에 계산 코드가 들어가도 되나요?"
   - **막힘**: LR과 SC 사이의 "예약 유지 시간" 정의가 모호함

   **해소 방법**:
   - **비유**: "도서관 자리 예약" (LR) → 노트북 가져오기 (계산) → 자리에 앉기 (SC)
     - 자리 예약은 "너 지금 이 자리 쓰려고 하지?" 신호만 전달
     - 자리에 앉기는 예약이 유효한지 확인 (다른 학생이 앉지 않았는지)
   - **점진적 학습**:
     - Step 1: LR/SC 사이에 코드가 없는 경우 (항상 성공)
     - Step 2: LR/SC 사이에 단순 산술 연산 (성공 확률 높음)
     - Step 3: LR/SC 사이에 메모리 접근 (Invalidation으로 실패 가능)
   - **실제 산업 사례**:
     - RISC-V ISA 문서: LR/SC의 "forward progress guarantee" 정의 (비결정적 실패 허용)
     - Linux kernel의 CAS(compare_and_swap) 구현 → LR/SC 기반 반복문

---

#### 4️⃣ **버스 스누핑(Bus Snooping)의 실제 동작**
   - **문제**: "MESI 상태 전이는 이해했는데, 어떻게 Core 1이 Core 0의 쓰기를 '감지'하나요?"
   - **막힘**: 스누핑이 "매직"처럼 느껴짐 (단순히 버스 신호 감시로 가능한가?)

   **해소 방법**:
   - **비유**: "반도체 팹의 불량률 관리 시스템"
     - 각 생산 라인(코어)이 품질 메트릭 방송 → 중앙 모니터링 시스템 수신 → 정책 결정
   - **점진적 학습**:
     - Ch15에서 배운 "버스 인터페이스(AHB-Lite)" 복습
     - MESI에서 "버스 이벤트" = AHB의 `hwrite`, `haddr`, `hwdata` 신호
     - 스누핑 = "모든 캐시가 AHB 신호를 동시에 구독"
   - **실제 산업 사례**:
     - Xilinx AMBA AXI 프로토콜 (Basys 3도 AXI-Lite 기반)
     - ARM AMBA 문서의 "Address Phase" = 스누핑 신호 수신 시점

---

#### 5️⃣ **멀티코어의 성능 이점과 한계**
   - **문제**: "멀티코어를 쓰면 항상 2배 빨라지나요?"
   - **막힘**: 진짜로 2배 개선 vs 1.3배 개선의 차이를 모름 → 성능 예측 불가

   **해소 방법**:
   - **비유**: "인력으로 벽을 쌓을 때 workers × 2 ≠ productivity × 2"
     - 자재 운반(메모리 경쟁) 병목
     - 의사소통 오버헤드(캐시 일관성)
     - 일부 순차적 작업(Amdahl's Law)
   - **점진적 학습**:
     - Ch15의 성능 지표(L1 Hit Rate, CPI) 재검토
     - MESI + LR/SC 추가 → 더 나은 Hit Rate이지만, 동기화 오버헤드 발생
     - "Speedup = 1 / (Serial + Parallel/N)" (Amdahl's Law) 수식 도입
   - **실제 산업 사례**:
     - 스마트폰 멀티코어 성능: 게임(병렬) vs 메일(순차) → 다른 speedup
     - 서버 CPU(Intel Xeon) 성능 리포트: 코어 수 vs 실제 throughput 비교

---

### 각 막힘 포인트별 강의 전달 전략

| 포인트 | 강의 시간 | 추천 자료 |
|--------|---------|---------|
| 1. 병렬 사고방식 | 시작 10분 | 비유(은행 ATM) + 타임라인 다이어그램 |
| 2. MESI 복잡도 | 25분 | 상태도 단순화 + 2×2 행렬 설명 + 예제 3개 (read, write, invalidate) |
| 3. LR/SC 예약 | 20분 | 도서관 자리 비유 + 코드 3단계 진행 + ISA 문서 참고 |
| 4. 버스 스누핑 | 20분 | Ch15 AHB 복습 + 신호 매핑 + 논리회로 다이어그램 |
| 5. 성능 한계 | 15분 | Amdahl's Law + 실제 벤치마크(smartphone vs server) |

---

## 4. 통합 기획

### 최종 집필 전략

#### **Phase 2: 초안 작성** (기술 저자)
- 25.1: 2000~2500자 + MESI 상태도 SVG + 코드 2개
- 25.2: 2500~3000자 + LR/SC 타이밍 SVG + 코드 2개
- 비유는 각 절 도입부에 강조

#### **Phase 3: 병렬 리뷰** (4명 동시)
- 기술 리뷰어: SystemVerilog 합성 가능성, RISC-V A 확장 스펙 준수
- 초보자 독자: "파이프라인 지식만으로 MESI를 이해할 수 있나?" → 대상은 대학원생이므로 ⭐⭐⭐⭐ 목표
- 교육 설계자: 학습 목표와의 일치도 검증
- 교육심리전문가: "동시성 개념 전환"에서 오는 학습 불안 감지 → 초반부 비유 강화
- 교육전문강사: "병렬 사고 전환" 관점 리뷰

#### **Phase 4: 종합 회의**
- 피드백 통합: 정확성 > 심리적 안전 > 이해도 > 분량 우선순위 적용
- MESI 상태도 개선 (복잡도 vs 완전성 트레이드오프)
- 코드 예제 최적화 (synthesis 가능성 + 교육적 명확성)

---

### 주요 설계 결정 (Go Forward)

1. **2코어 모델 고정**
   - 4코어 이상 → 복잡도 폭증, 기본 개념 전달 어려움
   - 2코어로 MESI 원리 정확히 이해 → 확장은 독자 몫

2. **MESI + LL/SC (구현 수준)**
   - 실무 멀티코어(ARM, Intel)의 표준
   - RISC-V 공식 스펙에 포함
   - 다른 동기화(뮤텍스, 세마포어)의 기초

3. **Basys 3 FPGA 고려**
   - 2코어 + L1D-Cache + MESI = ~15,000 LUT 추정
   - XC7A35T = 33,280 LUT → 가능 (여유도 있음)
   - 하지만 **구현은 선택사항** (시뮬레이션 주력)

4. **코드 하이라이팅 + 비유 병행**
   - SystemVerilog RTL만으로는 개념 이해 어려움
   - 각 절 도입부: "은행 ATM", "도서관 자리" 같은 실생활 비유로 호기심 유발
   - 코드는 비유의 "확인" 역할

---

## 다음 단계 (Phase 2 진입)

기술 저자가 다음을 준비:
1. manuscripts/part9/chapter25.html 생성 (chapter_template.html 기반)
2. 세 SVG 다이어그램 작성 시작
3. 4~5개 SystemVerilog 예제 코드 작성 완료

교육 전담 팀원들은 초안 완성 후 Phase 3 리뷰 대기

---

**회의 완료**: 2026-03-15
**다음 회의**: Phase 3 병렬 리뷰 (초안 완료 후 3일 후)
