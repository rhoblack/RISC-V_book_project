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
**용도**: 동기 vs 비동기 예외 분류 (2×2 매트릭스)
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

### 2.3 ch19_sec05_precise_exception_timing.svg
**용도**: 파이프라인에서 정확한 예외(precise exception) 타이밍
**크기**: 1000×600px
**내용**:
- **사이클 0**: instr#(N-2) in WB, instr#(N-1) in MEM, instr#N in EX, instr#(N+1) in ID, instr#(N+2) in IF
- **사이클 1**: instr#N에서 예외 감지 (EX 또는 MEM) → flush 신호 발생
- **사이클 2~3**: instr#(N+1), instr#(N+2) flush (취소) → PC = mepc로 복귀 준비
- **사이클 4**: trap handler (mepc의 PC에서) 시작
- **색상 코딩**:
  - 초록(완료된 명령어) / 파랑(진행 중) / 빨강(flush 대상) / 주황(trap handler)

**핵심 메시지**: "예외 발생 명령어 이전은 완료✓, 이후는 취소✗ → 정확성 보장"

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

### 2.5 ch19_sec05_csr_hazard_resolution.svg
**용도**: CSR 해저드 (CSR 수정 중 인터럽트) 해결
**크기**: 1000×500px
**내용**:
- **좌측 (문제)**: "mie.MTIE = 1로 수정하는 동안 timer_irq 도착" → 불완전한 mie 값 적용 위험
- **중앙 (파이프라인)**: CSRRS mie, mie 명령어 (EX 단계)
  - EX: ALU에서 mie = mie | (1 << 7) 계산
  - MEM: CSR 쓰기 (동기화)
  - WB: mie 실제 업데이트 완료
- **우측 (해결)**: "WB 단계 완료 후 인터럽트 샘플링" → mie 업데이트 일관성
- **인터럽트 샘플링 포인트**: WB 이후 단계 표시 (화살표)

**색상**:
- 빨강: 위험 구간 (CSR 수정 중)
- 초록: 안전 구간 (WB 이후)

**핵심 메시지**: "CSR 쓰기 명령어는 WB까지 완료 후 해당 CSR 사용"

---

## 3. SystemVerilog 코드 아웃라인

### 3.1 exception_detect_unit.sv (~200줄)
**목적**: 각 파이프라인 스테이지에서 예외 감지 및 플래그 전파

**구조**:
```systemverilog
module exception_detect_unit (
  // 입력: 각 스테이지 정보
  input  logic [31:0]  if_pc,           // IF 스테이지 PC
  input  logic [31:0]  id_instr,        // ID 스테이지 명령어
  input  logic [4:0]   id_rs1, id_rs2, id_rd,

  input  logic [31:0]  ex_pc,           // EX 스테이지 PC
  input  logic [31:0]  ex_alu_result,   // ALU 출력
  input  logic [2:0]   ex_funct3,       // 로드/스토어 타입

  input  logic [31:0]  mem_addr,        // MEM 스테이지 주소
  input  logic         mem_is_load,     // 로드 신호
  input  logic         mem_is_store,    // 스토어 신호

  // 출력: 예외 플래그 (각 스테이지)
  output logic         if_except,       // IF 예외 (미사용, 0)
  output logic         id_except,       // ID 예외 (현재 미사용)
  output logic         ex_except,       // EX: Illegal, 주소 misaligned
  output logic         mem_except,      // MEM: Load/Store misaligned

  output logic [3:0]   except_code,     // mcause 코드 (2/4/6/11)
  output logic [31:0]  except_pc        // 예외 발생 PC (mepc)
);

  // ====== EX 단계: Illegal Instruction 감지 ======
  logic illegal_instr;
  assign illegal_instr = (ex_opcode == 7'b0000_011 && ex_funct3 == 3'b110) ? 1 : 0; // 예시: 지원하지 않는 명령어

  // ====== EX 단계: 주소 정렬 확인 (Misaligned) ======
  logic addr_misaligned;
  assign addr_misaligned = (ex_funct3[1:0] == 2'b10 && ex_alu_result[1:0] != 0) ? 1 : // Word는 4바이트 정렬
                           (ex_funct3[1:0] == 2'b01 && ex_alu_result[0] != 0) ? 1 :   // Half-word는 2바이트 정렬
                           0;

  assign ex_except = illegal_instr;  // EX 예외: Illegal만

  // ====== MEM 단계: Load/Store Misaligned ======
  logic load_misaligned, store_misaligned;
  assign load_misaligned  = (mem_is_load && addr_misaligned) ? 1 : 0;
  assign store_misaligned = (mem_is_store && addr_misaligned) ? 1 : 0;

  assign mem_except = load_misaligned || store_misaligned;

  // ====== mcause 인코딩 ======
  always_comb begin
    if (ex_except && illegal_instr)
      except_code = 4'h2;      // Illegal Instruction
    else if (mem_except && load_misaligned)
      except_code = 4'h4;      // Load Address Misaligned
    else if (mem_except && store_misaligned)
      except_code = 4'h6;      // Store Address Misaligned
    else
      except_code = 4'h0;      // No exception
  end

  // mepc = 예외 발생 명령어의 PC
  assign except_pc = ex_except ? ex_pc : (mem_except ? mem_pc : 32'h0);
endmodule
```

**핵심 설계**:
- EX 단계: Illegal Instruction 감지
- MEM 단계: Load/Store Misaligned 감지
- ECALL: ID 단계에서 감지 (opcode=0x1B, 특수 처리)
- 각 예외 코드(except_code)는 mcause에 직접 기록

### 3.2 precise_exception_tb.sv (~250줄)
**목적**: 예외 감지, flush, trap handler 복귀 전체 시뮬레이션

**테스트 시나리오**:
1. **Scenario 1: ECALL 명령어 실행**
   - instr[0] = ADDI x5, x0, 10 (정상)
   - instr[1] = ECALL (trap 발생)
   - 검증: mepc = instr[1]의 PC, mcause = 11, flush 신호 발생, 다음 PC = mtvec

2. **Scenario 2: Load Misaligned**
   - instr[0] = LW x1, 0x0(x2) (정상, 주소 정렬됨)
   - instr[1] = LW x3, 0x1(x4) (misaligned, 짝수 주소 필요)
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
@(posedge clk) if (ecall_instr) begin
  @(posedge clk) assert(mepc == ecall_pc) else $error("mepc mismatch");
  @(posedge clk) assert(mcause == 11) else $error("mcause should be 11");
  @(posedge clk) assert(flush) else $error("flush signal missing");
end

// Precise exception 검증: 예외 후 N사이클 내 다음 명령어 flush
@(posedge clk) if (exception_detected && ~flush_in_progress) begin
  flush_in_progress = 1;
  repeat(3) @(posedge clk);
  assert(flush_complete) else $error("Exception not fully flushed");
  flush_in_progress = 0;
end
```

### 3.3 trap_handler_asm.s (~100줄, 어셈블리)
**목적**: 예외 처리 trap handler 최소 구현

```asm
# =================================================
# Minimal Trap Handler for RISC-V RV32I
# =================================================

.section .text.trap_handler
.align 4

trap_handler:
  # Handler 진입 시점: PC = mtvec

  # Step 1: 범용 레지스터 저장 (최소: ra, a0-a7)
  addi sp, sp, -64           # 스택 공간 할당
  sw   ra, 0(sp)             # return address 저장
  sw   a0, 4(sp)
  sw   a1, 8(sp)
  # ... a2~a7도 동일
  sw   t0, 32(sp)            # 임시 레지스터도 저장

  # Step 2: 예외 원인 읽기
  csrr a0, mcause            # a0 = mcause (예외 코드)

  # Step 3: 원인별 분기 처리
  li   t0, 11                # ECALL = 11
  beq  a0, t0, handle_ecall

  li   t0, 4                 # Load Misaligned = 4
  beq  a0, t0, handle_load_misaligned

  li   t0, 2                 # Illegal Instruction = 2
  beq  a0, t0, handle_illegal

  j    handle_unknown        # 미처리 예외

# ====== ECALL 핸들러 ======
handle_ecall:
  # 간단한 예시: ECALL 코드를 a7에서 읽고 syscall 분기
  # (실제 OS에서는 여기서 open, read, write 등 처리)
  addi a7, a7, 1             # 예시: a7 = a7 + 1
  j    restore_and_return

# ====== Load Misaligned 핸들러 ======
handle_load_misaligned:
  # mepc에 저장된 명령어 주소에서 Load 재시도 (또는 에러 처리)
  li   a0, 0xDEAD_BEEF       # 에러 코드
  j    restore_and_return

# ====== Illegal Instruction 핸들러 ======
handle_illegal:
  # 미지원 명령어: 에뮬레이션 또는 에러 처리
  li   a0, 0xDEAD_CAFE
  j    restore_and_return

# ====== 미지원 예외 ======
handle_unknown:
  li   a0, 0xDEAD_0000
  # 이 경우 재부팅 또는 무한 루프
  j    .

# ====== Handler 종료: 레지스터 복구 및 MRET ======
restore_and_return:
  lw   t0, 32(sp)
  # ... a2~a7도 복구
  lw   a1, 8(sp)
  lw   a0, 4(sp)
  lw   ra, 0(sp)
  addi sp, sp, 64            # 스택 복구
  mret                        # PC = mepc로 복귀
```

**핵심 설계**:
- Handler 시작: PC = mtvec
- 레지스터 저장/복구: 호출 규약 준수 (ra, a0-a7, t0)
- mepc 자동 복귀: MRET 명령어 (CSR 하드웨어 처리)

---

## 4. 비유 및 실생활 예시 전략

### 4.1 비유 #1: 응급실 트리아지 (예외 처리 우선순위)
**목표**: "예외가 여러 개 발생할 때 어떤 것을 먼저 처리하나?"

**비유 내용**:
- "응급실에서 환자가 여러 명 들어온다면?"
- "의사는 우선순위 기준(심각도)에 따라 순서를 정한다"
- "RISC-V 프로세서도 동일: Illegal > Load Misaligned > ECALL > Timer 순서로 mcause 코드 번호를 할당"
- **정확성 매핑**: mcause[3:0] 값 = 우선순위 번호 (작은 수일수록 동기 예외, 큰 수는 비동기)
- **한계 명시**: "실제 응급실은 의료진 판단이지만, 프로세서는 하드코드된 규칙을 따름"

**강의 포인트**:
- 비유 후 표 제시: "mcause 값 → 우선순위" 명시
- RISC-V 스펙 참조: "이건 설계 규칙이다. 외우는 게 아니라 필요할 때 표에서 찾는다"

### 4.2 비유 #2: 비행기 블랙박스 (CSR 상태 기록)
**목표**: "예외 발생 순간의 프로세서 상태를 어떻게 저장하나?"

**비유 내용**:
- "비행기가 추락할 때 블랙박스는 사건 직전 상태를 기록한다"
- "마찬가지로 예외 발생 순간 프로세서 상태(PC, 작업 모드, 인터럽트 마스크 등)를 CSR에 저장"
- mepc = PC (비행기 추락 시각)
- mcause = 예외 원인 (엔진 고장? 조종사 실수?)
- mstatus = 프로세서 모드 (Machine mode로 전환)

**정확성 매핑**:
- mepc[31:0] = 정확히 예외 발생 명령어의 PC (32비트)
- mcause[31:0] = 예외 코드 (또는 인터럽트 번호, 비트 31은 INT 구분자)
- mstatus.MPP = 돌아갈 모드

**한계 명시**:
- "블랙박스는 사건 후 분석용이지만, CSR은 **실시간**으로 사건을 처리하는 데 사용"
- "따라서 trap handler는 CSR 값을 읽어서 예외 원인을 파악하고 대응"

### 4.3 비유 #3: 영화 편집 (Flush 메커니즘)
**목표**: "파이프라인에서 예외 발생 후 왜 이후 명령어를 취소(flush)해야 하나?"

**비유 내용**:
- "영화 촬영 중 배우가 대사를 틀렸다면?"
- "그 장면 이후의 촬영분은 모두 버려진다 (쓸모없기 때문)"
- "마찬가지로 예외 발생 명령어 이후의 명령어들은 완료되지 않았으므로 취소(flush)"
- "예외 명령어 이전의 명령어들은 이미 완료됐으므로 결과가 메모리에 반영됨"

**파이프라인 타이밍 매핑**:
- Cycle 0: 예외 명령어(N) 실행 중
- Cycle 1: "컷!" (flush 신호 발생)
- Cycle 2~3: N+1, N+2 명령어 취소 (파이프라인 비움)
- Cycle 4: trap handler 시작 (새로운 영화 장면)

**한계 명시**:
- "실제 영화와 달리 CPU는 flush가 즉시 일어나지 않음"
- "파이프라인 깊이(보통 5단계)만큼 시간 필요"

### 4.4 비유 #4: 회복력 있는 팀 (MRET 복귀)
**목표**: "예외 처리 후 왜 원래 일로 돌아갈 수 있나?"

**비유 내용**:
- "프로젝트 팀이 갑자기 위기 상황을 처리하기 위해 현재 작업을 중단한다"
- "위기 처리(trap handler) 후 원래 작업으로 돌아간다"
- "복귀 지점은 정확히 중단한 지점 (mepc에 저장된 PC)"
- "MRET = 위기 처리 후 원래 일로 돌아가기"

**프로세서 매핑**:
- 원래 작업 PC = mepc에 저장
- 위기 처리(ISR) 실행 = trap handler 코드
- MRET = mepc 값을 PC에 로드 → 원래 위치에서 재개

---

## 5. 연습문제 블룸 분류 및 개요

| 절 | 문제 | 블룸 수준 | 난이도 | 내용 |
|----|------|---------|--------|------|
| 19.1 | 1-1. 파이프라인 5단계 각각의 역할을 쓰고, "stall"과 "flush"의 차이를 설명하시오. | L2 (이해) | ⭐ | 복습용 확인 문제 |
| 19.2 | 2-1. 동기 예외의 정의를 쓰고, 3가지 예시를 들어라. | L2 (이해) | ⭐ | 개념 이해도 확인 |
| 19.2 | 2-2. 다음 코드에서 예외가 발생하는 시점을 찾고, mepc와 mcause 값을 구하시오. (Load Misaligned 예제) | L3 (적용) | ⭐⭐ | 실제 주소 계산 |
| 19.3 | 3-1. 비동기 인터럽트와 동기 예외의 처리 시점 차이를 쓰시오. | L2 (이해) | ⭐ | 개념 구분 |
| 19.3 | 3-2. mie.MTIE=0일 때 timer_irq 신호가 도착해도 trap handler가 실행되지 않는 이유를 설명하시오. | L3 (적용) | ⭐⭐ | 인터럽트 마스킹 |
| 19.4 | 4-1. MRET 명령어 실행 후 PC 값이 mepc로 설정되는 이유를 설명하시오. | L2 (이해) | ⭐ | 복귀 메커니즘 |
| 19.5 | 5-1. "정확한 예외(precise exception)"의 정의를 쓰고, 왜 이것이 중요한지 설명하시오. | L2 (이해) | ⭐ | 핵심 개념 |
| 19.5 | 5-2. 예외 발생 명령어 이전의 명령어는 완료되고, 이후는 취소되는 이유를 파이프라인 타이밍 다이어그램으로 설명하시오. | L4 (분석) | ⭐⭐⭐ | **가장 어려움** |
| 19.5 | 5-3. mie 레지스터를 수정하는 CSRRS 명령어 실행 중 timer_irq가 도착했다. 이 인터럽트가 처리되는 시점은? (WB 이전 vs WB 이후) | L4 (분석) | ⭐⭐⭐ | CSR 해저드 |
| 19.6 | 6-1. ECALL 명령어를 실행한 후 trap handler로 점프, 핸들러 내에서 값을 수정한 후 MRET로 돌아오는 전체 흐름을 그리시오. | L3 (적용) | ⭐⭐ | 실제 시나리오 |
| 19.7 | 7-1. (종합) 파이프라인에서 여러 예외가 동시에 감지되었을 때 우선순위를 정하는 메커니즘을 설명하시오. | L5 (평가) | ⭐⭐⭐⭐ | **최고 난이도** |

**블룸 분포**:
- L2(이해): 4문제 (기초 개념)
- L3(적용): 3문제 (실제 계산/시나리오)
- L4(분석): 3문제 (정확한 예외, CSR 해저드)
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
0      addi             ecall            [이전]           [이전]           [이전]
1      ecall            [flush]          addi             [이전]           [이전]
2      [flush]          [flush]          [flush]          ecall            [이전]
3      trap_handler_PC  [flush]          [flush]          [flush]          ecall
4      [handler]        trap_handler_PC  [flush]          [flush]          [flush]
```

**CSR 값 변화**:
- Cycle 1 (예외 감지): mepc ← ecall의 PC, mcause ← 11
- Cycle 3 (trap handler 진입): PC ← mtvec[31:2]
- Cycle 5+ (handler 실행): CSR 읽기/쓰기
- Handler 중간 (MRET): PC ← mepc (ecall의 PC)

**검증 체크리스트**:
- [ ] mepc 값이 ECALL 명령어의 PC와 일치
- [ ] mcause = 11 (ECALL 코드)
- [ ] flush 신호가 2사이클 이상 지속 (N+1, N+2 명령어 취소)
- [ ] 다음 PC가 mtvec[31:2] 값으로 설정
- [ ] MRET 후 원래 위치(mepc)에서 재개

### Scenario 2: Load Misaligned 예외 (중간)
**목표**: 메모리 접근 예외 감지 및 처리

**어셈블리**:
```asm
  li   a0, 0x0000_0001  # 홀수 주소 (misaligned)
  lw   a1, 0(a0)        # Load word: 4바이트 정렬 필수 → 예외 발생
  nop
  nop
```

**메모리 주소 계산**:
- a0 = 0x0000_0001 (홀수)
- Load word는 4바이트 정렬 필요 → addr[1:0] == 00이어야 함
- 현재 addr[1:0] = 01 → **misaligned!**

**예외 감지 시점**:
- ID 단계: 명령어 해독 (LW인지 확인, funct3 읽기)
- EX 단계: 주소 계산 (a0 = 0x0000_0001)
- MEM 단계: 주소 정렬 확인
  ```
  if (funct3 == 3'b010 && addr[1:0] != 2'b00)  // Word load with misaligned
    mem_except = 1;
    except_code = 4'h4;  // Load Address Misaligned
  ```

**CSR 업데이트**:
- mepc = LW 명령어의 PC
- mcause = 4 (Load Address Misaligned)

**Trap handler 동작**:
```asm
handle_load_misaligned:
  csrr a0, mepc         # mepc 읽기 (LW 명령어 PC)
  # → 여기서 주소 정렬 수정 또는 에러 처리
  mret                  # 원래 위치로 복귀 (같은 LW 명령어 재시도)
```

### Scenario 3: 타이머 인터럽트 처리 (중간)
**목표**: 비동기 인터럽트의 "명령어 경계" 처리

**파이프라인 상태**:
```
Cycle  명령어 #N (진행)
0      addi (IF)
1      addi (ID), lw (IF)
2      addi (EX), lw (ID), sw (IF)
       ↓ [timer_irq 신호 도착!]
3      addi (MEM), lw (EX), sw (ID), sub (IF) ← 이 시점
       인터럽트 샘플링: mie.MTIE=1이면 처리 예약
4      addi (WB) 완료
       ↓ 인터럽트 처리 시작
5      [trap handler 진입] (PC = mtvec)
```

**핵심 포인트**:
- timer_irq 신호는 Cycle 2에 도착
- 하지만 인터럽트 처리는 Cycle 4 (addi 완료 후)에 시작
- addi 이후의 모든 명령어(lw, sw, sub)는 flush
- mepc = sub 명령어의 PC (다음 명령어)

**CSR 업데이트**:
- mcause[31] = 1 (인터럽트 표시)
- mcause[3:0] = 7 (타이머 인터럽트)
- mepc = sub 명령어 PC (현재 진행 중이던 다음 명령어)

### Scenario 4: CSR 해저드 (고급)
**목표**: CSR 수정 명령어 실행 중 인터럽트 발생 시 일관성 보장

**초기 상태**:
- mie = 0x0000_0000 (모든 인터럽트 비활성화)
- mstatus.MIE = 1 (전역 인터럽트 활성화)

**코드**:
```asm
  # MTIE(timer interrupt) 활성화
  li   a0, (1 << 7)        # a0 = 0x80 (비트 7)
  csrrs mie, a0            # mie = mie | a0 (MTIE = 1)
  nop
  nop
  # MTIE 활성화 후 timer_irq 도착 → trap handler 실행 가능
```

**파이프라인 타이밍**:
```
Cycle  IF               ID               EX               MEM              WB
0      csrrs            [이전]           [이전]           [이전]           [이전]
1      nop#1            csrrs            [이전]           [이전]           [이전]
2      nop#2            nop#1            csrrs            [이전]           [이전]
       ↓ [timer_irq 도착, mie 업데이트 완료 전]
3      [후속]           nop#2            nop#1            csrrs            [이전]
4      [후속]           [후속]           nop#2            nop#1            csrrs(WB 시작)
       ↓ [WB 완료: mie 실제 업데이트됨]
5      [후속]           [후속]           [후속]           nop#2            nop#1(WB)
       ↓ [이제 timer_irq 샘플링 가능]
6      [trap handler]   [후속]           [후속]           [후속]           nop#2(WB)
```

**핵심 설계**:
- CSRRS의 WB 단계(Cycle 4)에서 mie 실제 업데이트
- Cycle 5 이후에만 새로운 mie 값으로 timer_irq 샘플링
- Cycle 2 (timer_irq 도착)에는 아직 mie 업데이트가 진행 중이므로, 이전 mie 값(0x00) 사용
- 결과: timer_irq가 도착했지만 이전 mie=0이므로 무시, Cycle 5 이후 새로운 샘플링에서 처리

**CSR 해저드 해결 메커니즘**:
1. **Write-Through**: CSR 쓰기 명령어의 결과를 같은 사이클에 바로 사용하지 않음 (파이프라인 일관성)
2. **Stall**: CSR 읽기 직후 쓰기 → 명령어 간격 강제 (EX stall)
3. **Sampling Point**: 인터럽트 신호는 WB 단계 이후에만 샘플링 (일관성 보장)

**검증**:
- Cycle 4 전: mie는 여전히 0x00 (MTIE=0) → timer_irq 무시
- Cycle 5 이후: mie = 0x80 (MTIE=1) → timer_irq 처리 가능

---

## 7. 코드 작성 가이드라인

### StyleGuid 확인
- **들여쓰기**: 3칸 (CH01~CH18과 일관성)
- **명명규칙**: snake_case (except_code, load_misaligned 등)
- **주석**: 한국어 (절 제목, 섹션 분리, 신호 설명)
- **합성**: IEEE 1800-2017 표준 (always_ff/always_comb 분리)

### SystemVerilog 패턴
```systemverilog
// ====== 예외 감지 ======
// 동기식 로직: always_ff
always_ff @(posedge clk or negedge rst_n) begin
  if (~rst_n) begin
    ex_except <= 1'b0;
  end else begin
    ex_except <= illegal_instr;  // 비블로킹 할당
  end
end

// 조합 로직: always_comb
always_comb begin
  // 주소 정렬 확인
  addr_misaligned = (funct3 == 3'b010 && addr[1:0] != 0) ? 1'b1 : 1'b0;
end
```

### 테스트벤치 패턴
```systemverilog
// SVA Assertion 활용
property ecall_exception;
  @(posedge clk)
  (ecall_instr) |=> (mepc == ecall_pc) && (mcause == 11);
endproperty
assert property (ecall_exception) else $error("ECALL exception failed");
```

---

## 요약

**Chapter 19 기술 저자 기획 완료**:
- ✅ 7개 절, 약 15,000~18,000자 분량
- ✅ 5개 SVG (파이프라인 복습, 예외 분류, precise exception, trap handler, CSR 해저드)
- ✅ 3개 SystemVerilog 모듈 (예외 감지, 테스트벤치, 어셈블리 trap handler)
- ✅ 4개 비유 (응급실, 블랙박스, 영화 편집, 팀 복구)
- ✅ 11개 연습문제 (L2~L5, 블룸 분포)
- ✅ 4개 핵심 시나리오 (ECALL, Load Misaligned, 타이머, CSR 해저드)

**다음 단계**: Phase 2 (기술 저자 원고 작성)

