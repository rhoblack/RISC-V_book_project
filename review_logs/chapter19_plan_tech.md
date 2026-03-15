# Chapter 19 기술 저자 기획 (Phase 1)

**작성일**: 2026-03-15
**챕터**: 19 — 예외/인터럽트와 파이프라인 통합
**상태**: Phase 1 완료 (기획)

---

## 1. 각 절별 분량 및 개념 계획

| 절 | 제목 | 예상 자수 | 신규 개념 수 | 핵심 내용 |
|----|------|---------|-----------|---------|
| 19.1 | 파이프라인 구조 핵심 복습 | 1,500~2,000 | 0 (복습) | Ch12 파이프라인 구조 1페이지 요약, 5단계(IF/ID/EX/MEM/WB), 스톨/플러시 메커니즘 재확인 |
| 19.2 | 동기 예외 처리 | 2,500~3,000 | 3 | Illegal Instruction, Load/Store Misaligned, ECALL, 예외 발생 시점(decode/execute/memory), mepc/mcause 업데이트 |
| 19.3 | 비동기 인터럽트 처리 | 2,500~3,000 | 3 | 외부 인터럽트(PLIC), 타이머 인터럽트(timer_irq), 우선순위(mcause[31] = 1), mie/mip 레지스터 |
| 19.4 | 트랩 진입/복귀 메커니즘 | 2,000~2,500 | 2 | Trap handler PC = mtvec, MRET 명령어 (mepc 복귀), 레지스터 저장/복구 어셈블리 |
| 19.5 | 파이프라인과 예외 처리 통합 | 3,000~4,000 | 4 | **최고 난이도** — 예외 감지 스테이지 선택, precise exception 보장, flush 메커니즘, CSR 해저드 처리(mie 수정 중 인터럽트) |
| 19.6 | 예외/인터럽트 테스트벤치 | 2,000~2,500 | 1 | ECALL 시나리오(trap handler 진입/복귀), Load Misaligned 감지, 타이머 인터럽트 응답 시간 측정 |
| 19.7 | 본 챕터 요약 및 다음 단계 | 1,500~2,000 | 0 (정리) | 핵심 개념 5줄 요약, 자가 점검 질문 5개, Ch20(FPGA 합성) 예고 |
| **합계** | | **15,000~18,000** | **13** | — |

**설계 원칙**:
- 19.1은 **인지 부하 상쇄용** 1페이지 복습 (새 개념 없음)
- 19.2~19.4는 **각 2~3개 신규 개념** 단계적 도입
- 19.5는 **파이프라인 통합**으로 최고 난이도 (4개 개념)
- 각 절 종료 시 "이 절을 마치며" 자가 점검 1~2개 포함

**Part 7 마일스톤 확인**:
- Ch18(CSR 레지스터 + CSR 명령어) + Ch19(예외/인터럽트 파이프라인 통합)
- 최종 마일스톤: 타이머 인터럽트 기반 LED 깜빡임 (Part 8에서 FPGA 구현)
- Part 6(AMBA 버스)의 인터럽트 소스(UART, 타이머)가 Ch19의 입력

---

## 2. SVG 다이어그램 상세 설계 (5개)

### 2.1 ch19_sec01_pipeline_review.svg
**용도**: 파이프라인 구조 1페이지 핵심 복습
**크기**: 800×600px
**내용**:
- IF(명령어 인출) → ID(해독) → EX(실행) → MEM(메모리) → WB(쓰기)
- 각 스테이지 입출력: pc_in/instr/alu_out/mem_data 명시
- 파이프라인 레지스터 4종 표시 (IF/ID, ID/EX, EX/MEM, MEM/WB)
- 하단에 stall/flush 신호 4개 표시 (구체적 동작은 19.5에서 상세)
- 색상: 파란 계열 (#2563EB 주요, #3B82F6 보조)

**핵심 메시지**: "5개 스테이지, 4개 레지스터, 2개 신호(stall/flush)만 기억하면 된다"

### 2.2 ch19_sec02_exception_types.svg
**용도**: 동기 vs 비동기 예외 분류 (2×2 매트릭스) + mcause 코드 매핑
**크기**: 900×500px
**내용**:
- **좌상단**: "동기 예외(Synchronous)" = 명령어 실행 중 발생
  - Illegal Instruction (mcause=2)
  - Load Misaligned (mcause=4)
  - Store Misaligned (mcause=6)
  - ECALL (mcause=11)
- **우상단**: "비동기 인터럽트(Asynchronous)" = 언제든 발생 가능
  - 외부 인터럽트 (mcause=0x80000001)
  - 타이머 인터럽트 (mcause=0x80000007)
  - 소프트웨어 인터럽트 (mcause=0x80000003)
- **하단**: 타이밍 다이어그램 (시계열)
  - 동기: 명령어 #N 실행 → 예외 감지 → flush #(N+1)~#(N+k)
  - 비동기: 임의 시점 → 인터럽트 신호 → 현재 명령어 완료 후 trap

**핵심 메시지**: "동기는 '이 명령어가 문제', 비동기는 '이 시점에 외부 이벤트'"

### 2.3 ch19_sec03_interrupt_priority.svg
**용도**: mie/mip 비트 매칭 및 인터럽트 우선순위 판정 로직
**크기**: 900×500px
**내용**:
- **좌측**: mie 레지스터 비트 필드 (MSIE[3], MTIE[7], MEIE[11])
- **중앙**: mip 레지스터 비트 필드 (MSIP[3], MTIP[7], MEIP[11])
- **연결**: mie[N] & mip[N] = "처리 가능" (AND 게이트 시각화)
- **우측**: 우선순위 인코더 (MEI > MSI > MTI 순)
- **하단**: mstatus.MIE (전역 인터럽트 활성화) 게이트

**핵심 메시지**: "mie로 개별 허용, mstatus.MIE로 전역 허용, mip로 현재 요청 확인"

### 2.4 ch19_sec04_trap_handler_flow.svg
**용도**: Trap handler 진입 → CSR 업데이트 → 복귀
**크기**: 900×700px
**내용**:
- **Step 1**: "예외 발생" → flush
- **Step 2**: "mtvec에서 handler PC 읽기" (mtvec[31:2] = handler base)
- **Step 3**: "Handler 진입" (CSRRW mstatus로 상태 저장)
- **Step 4**: "ISR 실행" (원인별 처리)
- **Step 5**: "mepc 복구" (CSRR로 mepc 읽어서 원래 위치 확인)
- **Step 6**: "MRET 실행" → PC = mepc로 복귀
- **흐름선**: 왼쪽→오른쪽 위로 arc, 마지막에 원점으로 루프

**CSR 레지스터 패널** (우측):
- mtvec (trap handler 주소)
- mepc (예외 발생 PC)
- mcause (예외 원인)
- mstatus (모드 / 인터럽트 활성화)

**핵심 메시지**: "Trap handler = 예외 처리 함수, MRET = return from exception"

### 2.5 ch19_sec05_precise_exception_timing.svg
**용도**: 파이프라인에서 정확한 예외(precise exception) 타이밍
**크기**: 1000×600px
**내용**:
- **사이클 0**: instr#(N-2) in WB, instr#(N-1) in MEM, instr#N in EX, instr#(N+1) in ID, instr#(N+2) in IF
- **사이클 1**: instr#N에서 예외 감지 (EX 또는 MEM) → flush 신호 발생
- **사이클 2~3**: instr#(N+1), instr#(N+2) flush (취소) → PC = mepc로 복귀 준비
- **사이클 4**: trap handler (mepc의 PC에서) 시작
- **색상 코딩**:
  - 초록(완료된 명령어) / 파랑(진행 중) / 빨강(flush 대상) / 주황(trap handler)

**핵심 메시지**: "예외 발생 명령어 이전은 완료, 이후는 취소 → 정확성 보장"

---

## 3. SystemVerilog 코드 상세 설계 (3개)

### 3.1 code_examples/ch19_exception_handler.sv (~250줄)
**목적**: 예외 발생 감지, flush 로직, mtvec 리다이렉션 통합 구현

**구조**:
```systemverilog
module exception_handler (
   input  logic        clk,
   input  logic        rst_n,

   // ====== 각 스테이지 예외 신호 ======
   // ID 단계
   input  logic [31:0] id_instr,        // 명령어
   input  logic [31:0] id_pc,           // PC
   // EX 단계
   input  logic [31:0] ex_pc,
   input  logic [31:0] ex_alu_result,
   input  logic [2:0]  ex_funct3,
   input  logic        ex_is_load,
   input  logic        ex_is_store,
   // MEM 단계
   input  logic [31:0] mem_pc,
   input  logic [31:0] mem_addr,
   input  logic        mem_is_load,
   input  logic        mem_is_store,

   // ====== 인터럽트 입력 ======
   input  logic        timer_irq,       // 타이머 인터럽트
   input  logic        external_irq,    // 외부 인터럽트
   input  logic        software_irq,    // 소프트웨어 인터럽트

   // ====== CSR 입력 ======
   input  logic [31:0] mie,             // 인터럽트 활성화
   input  logic [31:0] mstatus,         // 전역 인터럽트 활성화
   input  logic [31:0] mtvec,           // trap handler 주소

   // ====== 출력: 파이프라인 제어 ======
   output logic        trap_taken,      // trap 발생
   output logic [31:0] trap_pc,         // trap handler PC
   output logic [31:0] trap_mepc,       // 예외 발생 PC (mepc에 저장)
   output logic [31:0] trap_mcause,     // 예외 코드 (mcause에 저장)
   output logic        flush_if_id,     // IF/ID 레지스터 flush
   output logic        flush_id_ex,     // ID/EX 레지스터 flush
   output logic        flush_ex_mem     // EX/MEM 레지스터 flush
);
```

**핵심 설계**:
- **예외 감지 영역 분리**:
  - ID 단계: ECALL/EBREAK 감지 (opcode == 7'b1110011, funct3 == 3'b000)
  - EX 단계: Illegal Instruction 감지 (미지원 opcode/funct3 조합)
  - MEM 단계: Load/Store Misaligned 감지 (addr[1:0] != 0 for word)
- **다단계 예외 우선순위**: MEM > EX > ID (파이프라인 순서상 앞선 명령어 우선)
- **인터럽트 샘플링**: mstatus.MIE == 1 && mie[N] && mip[N] → 명령어 경계에서 처리
- **flush 범위**: 예외 발생 스테이지 이후 모든 파이프라인 레지스터 flush

### 3.2 code_examples/ch19_interrupt_controller.sv (~150줄)
**목적**: mie/mip 비트 관리, 인터럽트 우선순위 판정

**구조**:
```systemverilog
module interrupt_controller (
   input  logic        clk,
   input  logic        rst_n,

   // ====== 인터럽트 소스 (Ch17 주변 장치) ======
   input  logic        timer_irq,       // 타이머 인터럽트 (Ch17.5)
   input  logic        external_irq,    // 외부 인터럽트 (PLIC)
   input  logic        software_irq,    // 소프트웨어 인터럽트

   // ====== CSR 레지스터 입력 ======
   input  logic [31:0] mie,             // 인터럽트 개별 활성화
   input  logic        mstatus_mie,     // 전역 인터럽트 활성화

   // ====== 출력 ======
   output logic [31:0] mip,             // 인터럽트 Pending 비트
   output logic        irq_pending,     // 처리 가능한 인터럽트 존재
   output logic [3:0]  irq_code         // 최우선 인터럽트 코드
);

   // ====== mip 레지스터 업데이트 ======
   // mip는 외부 인터럽트 신호를 반영 (하드웨어 제어)
   assign mip[3]  = software_irq;   // MSIP
   assign mip[7]  = timer_irq;      // MTIP
   assign mip[11] = external_irq;   // MEIP

   // ====== 인터럽트 활성화 판정 ======
   logic [31:0] enabled_irq;
   assign enabled_irq = mie & mip & {32{mstatus_mie}};

   // ====== 우선순위 인코더 ======
   // RISC-V 우선순위: MEI(11) > MSI(3) > MTI(7)
   always_comb begin
      irq_pending = |enabled_irq;
      if (enabled_irq[11])      irq_code = 4'd11;  // External
      else if (enabled_irq[3])  irq_code = 4'd3;   // Software
      else if (enabled_irq[7])  irq_code = 4'd7;   // Timer
      else                      irq_code = 4'd0;   // None
   end
endmodule
```

**핵심 설계**:
- mip 비트는 하드웨어가 직접 제어 (외부 신호 반영)
- mie 비트는 CSR 명령어로 소프트웨어 제어
- 우선순위: MEI(11) > MSI(3) > MTI(7) (RISC-V 특권 스펙 준수)
- mstatus.MIE로 전역 인터럽트 게이팅

### 3.3 code_examples/ch19_exception_tb.sv (~200줄)
**목적**: 예외 및 인터럽트 시뮬레이션 테스트벤치

**테스트 시나리오**:

1. **Scenario 1: ECALL 명령어 실행**
   - instr[0] = ADDI x5, x0, 10 (정상)
   - instr[1] = ECALL (trap 발생)
   - 검증: mepc = instr[1]의 PC, mcause = 11, flush 신호 발생, 다음 PC = mtvec

2. **Scenario 2: Load Misaligned**
   - instr[0] = LW x1, 0x0(x2) (정상, 주소 정렬됨)
   - instr[1] = LW x3, 0x1(x4) (misaligned, 4바이트 정렬 필요)
   - 검증: 메모리 접근 전 예외 감지, mcause = 4 (Load Misaligned)

3. **Scenario 3: 타이머 인터럽트**
   - 명령어 실행 중 timer_irq 신호 도착
   - 현재 명령어 완료 후 PC = mtvec로 점프
   - 검증: 비동기이므로 명령어 경계에서만 처리, mepc = 다음 명령어 PC

4. **Scenario 4: CSR 해저드 (mie 수정 중 인터럽트)**
   - CSRRS mie, (1<<7) 실행 (MTIE 활성화)
   - WB 단계 완료 전 timer_irq 도착
   - 검증: mie 업데이트 완료(WB) 후 인터럽트 샘플링

**어설션(assertions)**:
```systemverilog
// ECALL 예외 검증
property p_ecall_exception;
   @(posedge clk)
   (ecall_instr) |=> (mepc == ecall_pc) && (mcause == 11);
endproperty
assert property (p_ecall_exception) else $error("ECALL exception failed");

// Precise exception 검증: 예외 후 N사이클 내 다음 명령어 flush
property p_precise_exception;
   @(posedge clk)
   (exception_detected) |-> ##[1:3] (flush_complete);
endproperty
assert property (p_precise_exception) else $error("Exception not precise");
```

---

## 4. 비유 및 실생활 예시 전략

### 4.1 비유 #1: 응급실 트리아지 (예외 처리 우선순위)
**목표**: "예외가 여러 개 발생할 때 어떤 것을 먼저 처리하나?"

**비유 내용**:
- "응급실에서 환자가 여러 명 들어온다면?"
- "의사는 우선순위 기준(심각도)에 따라 순서를 정한다"
- "RISC-V 프로세서도 동일: 파이프라인 앞쪽 스테이지(더 오래된 명령어)의 예외가 우선"
- **정확성 매핑**: 파이프라인 순서 = 시간순. MEM 스테이지 예외(이전 명령어) > EX 스테이지 예외(나중 명령어)
- **한계 명시**: "실제 응급실은 의료진 판단이지만, 프로세서는 하드코드된 규칙을 따름. 또한 응급실은 여러 환자를 동시에 치료하지만, 프로세서는 한 번에 하나의 예외만 처리"

### 4.2 비유 #2: 비행기 블랙박스 (CSR 상태 기록)
**목표**: "예외 발생 순간의 프로세서 상태를 어떻게 저장하나?"

**비유 내용**:
- "비행기가 문제를 만나면 블랙박스에 사건 직전 상태를 기록한다"
- "마찬가지로 예외 발생 순간 프로세서 상태를 CSR에 저장"
- mepc = PC (비행기에 문제가 발생한 시각)
- mcause = 예외 원인 (엔진 고장? 난기류?)
- mstatus = 프로세서 모드 (Machine mode로 전환)

**정확성 매핑**:
- mepc[31:0] = 정확히 예외 발생 명령어의 PC (32비트)
- mcause[31:0] = 예외 코드 (비트 31은 인터럽트/예외 구분자)
- mstatus.MPP = 돌아갈 모드

**한계 명시**:
- "블랙박스는 사건 후 분석용이지만, CSR은 **실시간**으로 사건을 처리하는 데 사용"
- "따라서 trap handler는 CSR 값을 읽어서 예외 원인을 파악하고 즉시 대응"

### 4.3 비유 #3: 영화 편집 (Flush 메커니즘)
**목표**: "파이프라인에서 예외 발생 후 왜 이후 명령어를 취소(flush)해야 하나?"

**비유 내용**:
- "영화 촬영 중 배우가 대사를 크게 틀렸다면?"
- "그 장면 이후의 촬영분은 모두 버려진다 (잘못된 전제 위에 세워졌으므로)"
- "마찬가지로 예외 발생 명령어 이후의 명령어들은 완료되지 않았으므로 취소(flush)"
- "예외 명령어 이전의 명령어들은 이미 완료됐으므로 결과가 반영됨"

**파이프라인 타이밍 매핑**:
- Cycle 0: 예외 명령어(N) 실행 중
- Cycle 1: "컷!" (flush 신호 발생)
- Cycle 2~3: N+1, N+2 명령어 취소 (파이프라인 비움)
- Cycle 4: trap handler 시작 (새로운 장면)

**한계 명시**:
- "실제 영화와 달리 CPU는 flush가 즉시 일어나지 않고 파이프라인 깊이만큼 시간이 필요"
- "또한 flush는 물리적 삭제가 아니라 valid 비트를 끄는 논리적 취소"

### 4.4 비유 #4: 전화 중 긴급 전화 받기 (인터럽트)
**목표**: "인터럽트는 현재 작업을 잠시 멈추고 긴급 사안을 처리한 뒤 복귀"

**비유 내용**:
- "업무 전화 중 긴급 전화가 온다면?"
- "현재 통화(명령어)를 마무리하고 → 긴급 전화(trap handler) 응대 → 복귀"
- mepc = 통화 메모(어디까지 얘기했는지 기록)
- MRET = "긴급 전화 끊고 원래 통화로 돌아가기"

**프로세서 매핑**:
- 원래 작업 PC = mepc에 저장
- 긴급 처리(ISR) 실행 = trap handler 코드
- MRET = mepc 값을 PC에 로드 → 원래 위치에서 재개

**한계 명시**:
- "전화와 달리, 프로세서는 인터럽트를 '거절'할 수 있다 (mstatus.MIE=0 또는 mie 비트로)"
- "또한 여러 긴급 전화가 동시에 오면 우선순위 인코더가 가장 긴급한 하나만 선택"

---

## 5. 연습문제 블룸 분류 및 개요

| 절 | 문제 | 블룸 수준 | 난이도 | 내용 |
|----|------|---------|--------|------|
| 19.1 | 1-1. 파이프라인 5단계 각각의 역할을 쓰고, "stall"과 "flush"의 차이를 설명하시오. | L2 (이해) | ★ | 복습용 확인 문제 |
| 19.2 | 2-1. 동기 예외의 정의를 쓰고, 3가지 예시를 들어라. | L2 (이해) | ★ | 개념 이해도 확인 |
| 19.2 | 2-2. 다음 코드에서 예외가 발생하는 시점을 찾고, mepc와 mcause 값을 구하시오. (Load Misaligned 예제) | L3 (적용) | ★★ | 실제 주소 계산 |
| 19.3 | 3-1. 비동기 인터럽트와 동기 예외의 처리 시점 차이를 쓰시오. | L2 (이해) | ★ | 개념 구분 |
| 19.3 | 3-2. mie.MTIE=0일 때 timer_irq 신호가 도착해도 trap handler가 실행되지 않는 이유를 설명하시오. | L3 (적용) | ★★ | 인터럽트 마스킹 |
| 19.4 | 4-1. MRET 명령어 실행 후 PC 값이 mepc로 설정되는 이유를 설명하시오. | L2 (이해) | ★ | 복귀 메커니즘 |
| 19.5 | 5-1. "정확한 예외(precise exception)"의 정의를 쓰고, 왜 이것이 중요한지 설명하시오. | L2 (이해) | ★ | 핵심 개념 |
| 19.5 | 5-2. 예외 발생 명령어 이전의 명령어는 완료되고, 이후는 취소되는 이유를 파이프라인 타이밍 다이어그램으로 설명하시오. | L4 (분석) | ★★★ | **가장 어려움** |
| 19.5 | 5-3. mie 레지스터를 수정하는 CSRRS 명령어 실행 중 timer_irq가 도착했다. 이 인터럽트가 처리되는 시점은? (WB 이전 vs WB 이후) | L4 (분석) | ★★★ | CSR 해저드 |
| 19.6 | 6-1. ECALL → trap handler 진입 → MRET 복귀 전체 흐름을 타이밍 다이어그램으로 그리시오. | L3 (적용) | ★★ | 실제 시나리오 |
| 19.7 | 7-1. (종합) 파이프라인에서 여러 예외가 동시에 감지되었을 때 우선순위를 정하는 메커니즘을 설명하시오. | L5 (평가) | ★★★★ | **최고 난이도** |

**블룸 분포**:
- L2(이해): 4문제 (기초 개념)
- L3(적용): 3문제 (실제 계산/시나리오)
- L4(분석): 2문제 (정확한 예외, CSR 해저드)
- L5(평가): 1문제 (종합 문제)

---

## 6. 핵심 예제 코드 시나리오

### Scenario 1: ECALL 명령어 실행 (기본)
**목표**: Trap handler 진입과 복귀 전체 흐름 이해

**어셈블리**:
```asm
start:
  li   a0, 100          # 사용자 코드: a0 = 100
  ecall                 # 예외 발생 → trap handler 진입
  addi a0, a0, 1        # 돌아온 후 실행 (trap handler 복귀 후)
  j    start
```

**파이프라인 타이밍**:
```
Cycle  IF               ID               EX               MEM              WB
0      li a0,100        [이전]           [이전]           [이전]           [이전]
1      ecall            li a0,100        [이전]           [이전]           [이전]
2      addi a0,a0,1     ecall            li a0,100        [이전]           [이전]
3      [flush]          [flush]          ecall(예외감지)  li a0,100        [이전]
4      trap_handler_PC  [flush]          [flush]          ecall            li a0,100
5      [handler]        trap_handler_PC  [flush]          [flush]          ecall
```

**CSR 값 변화**:
- Cycle 3 (예외 감지): mepc ← ecall의 PC, mcause ← 11
- Cycle 4 (trap handler 진입): PC ← mtvec[31:2]
- Handler 종료 (MRET): PC ← mepc + 4 (ecall 다음 명령어)

### Scenario 2: Load Misaligned 예외 (중간)
**어셈블리**:
```asm
  li   a0, 0x0000_0001  # 홀수 주소 (misaligned)
  lw   a1, 0(a0)        # Load word: 4바이트 정렬 필수 → 예외 발생
```

**예외 감지 시점**:
- EX 단계: 주소 계산 (a0 + 0 = 0x0000_0001)
- MEM 단계: 주소 정렬 확인 → addr[1:0] = 01 → **misaligned!**
- mcause = 4 (Load Address Misaligned), mepc = LW 명령어의 PC

### Scenario 3: 타이머 인터럽트 (비동기)
**핵심 포인트**:
- timer_irq 신호는 임의 시점에 도착
- 인터럽트 처리는 현재 WB 단계 완료 후 (명령어 경계)
- mepc = 다음 실행할 명령어의 PC (인터럽트는 다음 명령어 PC를 저장)
- mcause[31] = 1 (인터럽트), mcause[3:0] = 7 (타이머)

### Scenario 4: CSR 해저드 (고급)
**코드**:
```asm
  li   a0, (1 << 7)        # a0 = 0x80 (MTIE 비트)
  csrrs mie, a0            # mie = mie | a0 (MTIE = 1)
  nop                       # timer_irq 여기서 도착 가능
```

**핵심 설계**:
- CSRRS의 WB 단계에서 mie 실제 업데이트
- 인터럽트 샘플링은 WB 이후에만 수행 → CSR 일관성 보장
- WB 이전에 도착한 timer_irq는 이전 mie 값으로 판정 (아직 MTIE=0이면 무시)

---

## 7. 코드 작성 가이드라인

### 스타일 규칙
- **들여쓰기**: 3칸 (Ch01~Ch18과 일관성)
- **명명규칙**: snake_case (except_code, load_misaligned 등)
- **주석**: 한국어 (절 제목, 섹션 분리, 신호 설명)
- **합성**: IEEE 1800-2017 표준 (always_ff/always_comb 분리)

### SystemVerilog 패턴
```systemverilog
// ====== 예외 감지 (조합 로직) ======
always_comb begin
   // 주소 정렬 확인
   addr_misaligned = (funct3 == 3'b010 && addr[1:0] != 0) ? 1'b1 : 1'b0;
end

// ====== 예외 상태 전파 (순차 로직) ======
always_ff @(posedge clk or negedge rst_n) begin
   if (~rst_n) begin
      ex_except <= 1'b0;
   end else begin
      ex_except <= illegal_instr;
   end
end
```

### HTML 이스케이프 규칙 확인
- `<pre><code>` 내부: `<` → `&lt;`, `>` → `&gt;`, `&` → `&amp;`
- Highlight.js: `language-systemverilog` → `language-verilog` 런타임 변환

---

## 8. Ch18 선행 지식 복습 포인트

Ch19는 Ch18(CSR)에 강하게 의존. 다음 CSR을 19.1 또는 19.2 도입부에서 간략 복습:

| CSR | 주소 | 역할 | Ch18 참조 절 |
|-----|------|------|------------|
| mstatus | 0x300 | 전역 인터럽트 활성화(MIE), 이전 모드(MPP) | 18.2 |
| mtvec | 0x305 | Trap handler 시작 주소 | 18.2 |
| mepc | 0x341 | 예외 발생 명령어 PC | 18.2 |
| mcause | 0x342 | 예외/인터럽트 코드 | 18.2 |
| mie | 0x304 | 인터럽트 개별 활성화 (MEIE/MTIE/MSIE) | 18.2 |
| mip | 0x344 | 인터럽트 Pending 상태 | 18.2 |

---

## 요약

**Chapter 19 기술 저자 기획 완료**:
- ✅ 7개 절 (19.1~19.7), 약 15,000~18,000자 분량
- ✅ 5개 SVG (파이프라인 복습, 예외 분류, 인터럽트 우선순위, trap handler, precise exception)
- ✅ 3개 SystemVerilog 모듈 (ch19_exception_handler.sv, ch19_interrupt_controller.sv, ch19_exception_tb.sv)
- ✅ 4개 비유 (응급실 트리아지, 블랙박스, 영화 편집, 긴급 전화)
- ✅ 11개 연습문제 (L2~L5, 블룸 분포)
- ✅ 4개 핵심 시나리오 (ECALL, Load Misaligned, 타이머, CSR 해저드)
- ✅ Part 7 마일스톤: AMBA(Ch16~17) + CSR(Ch18) + 예외 처리(Ch19) 통합

**다음 단계**: Phase 2 (기술 저자 원고 작성)
