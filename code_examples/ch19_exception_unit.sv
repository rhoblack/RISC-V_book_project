// ============================================================================
// 예외 처리 유닛 (Exception Unit)
// Chapter 19 — 예외/인터럽트와 파이프라인 통합
// RISC-V 프로세서 설계 완전정복
// ============================================================================
// 파이프라인 각 스테이지에서 발생하는 동기 예외를 감지하고,
// 예외 정보를 파이프라인 레지스터를 통해 WB 스테이지까지 전달한다.
// WB 스테이지에서 최종 커밋 시 CSR 업데이트 및 트랩 진입을 수행한다.
// ============================================================================

`timescale 1ns / 1ps

module exception_unit (
   // --- 클럭/리셋 ---
   input  logic        clk,
   input  logic        rst_n,

   // --- ID 스테이지 예외 입력 ---
   input  logic        id_illegal_instr,   // 불법 명령어 감지
   input  logic        id_ecall,           // ECALL 명령어 감지
   input  logic        id_ebreak,          // EBREAK 명령어 감지
   input  logic [31:0] id_pc,              // ID 스테이지 PC

   // --- EX 스테이지 예외 입력 ---
   input  logic        ex_branch_misaligned, // 분기 대상 주소 비정렬
   input  logic [31:0] ex_branch_target,     // 분기 대상 주소
   input  logic [31:0] ex_pc,                // EX 스테이지 PC

   // --- MEM 스테이지 예외 입력 ---
   input  logic        mem_load_misaligned,  // 로드 주소 비정렬
   input  logic        mem_store_misaligned, // 스토어 주소 비정렬
   input  logic [31:0] mem_alu_result,       // 비정렬 접근 주소
   input  logic [31:0] mem_pc,               // MEM 스테이지 PC

   // --- 비동기 인터럽트 입력 ---
   input  logic        ext_irq,             // 외부 인터럽트
   input  logic        timer_irq,           // 타이머 인터럽트
   input  logic        sw_irq,              // 소프트웨어 인터럽트

   // --- CSR 상태 입력 ---
   input  logic        mstatus_mie,         // 전역 인터럽트 인에이블
   input  logic        mie_meie,            // 외부 인터럽트 인에이블
   input  logic        mie_mtie,            // 타이머 인터럽트 인에이블
   input  logic        mie_msie,            // 소프트웨어 인터럽트 인에이블
   input  logic [31:0] mtvec,               // 트랩 벡터 주소

   // --- 출력: 트랩 제어 ---
   output logic        trap_taken,          // 트랩 발생 (플러시 트리거)
   output logic [31:0] trap_pc,             // 트랩 핸들러 PC (= mtvec)
   output logic [31:0] trap_mepc,           // 저장할 mepc 값
   output logic [31:0] trap_mcause,         // 저장할 mcause 값
   output logic [31:0] trap_mtval,          // 저장할 mtval 값

   // --- 출력: 파이프라인 제어 ---
   output logic        flush_if,            // IF 스테이지 플러시
   output logic        flush_id,            // ID 스테이지 플러시
   output logic        flush_ex,            // EX 스테이지 플러시
   output logic        flush_mem            // MEM 스테이지 플러시
);

   // -----------------------------------------------------------------------
   // 내부 신호 선언
   // -----------------------------------------------------------------------

   // 각 스테이지의 예외 발생 여부
   logic id_exception;
   logic ex_exception;
   logic mem_exception;
   logic interrupt_pending;

   // 예외 코드 (mcause 값)
   logic [31:0] id_cause;
   logic [31:0] ex_cause;
   logic [31:0] mem_cause;
   logic [31:0] int_cause;

   // 예외 부가 정보 (mtval 값)
   logic [31:0] id_tval;
   logic [31:0] ex_tval;
   logic [31:0] mem_tval;

   // -----------------------------------------------------------------------
   // 동기 예외 감지 — ID 스테이지
   // -----------------------------------------------------------------------
   // ID 스테이지에서 감지 가능한 예외:
   //   - Illegal Instruction (mcause = 2)
   //   - ECALL (mcause = 11)
   //   - EBREAK (mcause = 3)
   // -----------------------------------------------------------------------
   assign id_exception = id_illegal_instr | id_ecall | id_ebreak;

   always_comb begin
      id_cause = 32'd0;
      id_tval  = 32'd0;
      if (id_illegal_instr) begin
         id_cause = 32'd2;    // Illegal instruction
         id_tval  = 32'd0;    // 불법 명령어 비트패턴 (필요시 연결)
      end else if (id_ecall) begin
         id_cause = 32'd11;   // Environment call from M-mode
         id_tval  = 32'd0;
      end else if (id_ebreak) begin
         id_cause = 32'd3;    // Breakpoint
         id_tval  = 32'd0;
      end
   end

   // -----------------------------------------------------------------------
   // 동기 예외 감지 — EX 스테이지
   // -----------------------------------------------------------------------
   // EX 스테이지에서 감지 가능한 예외:
   //   - Instruction address misaligned (mcause = 0)
   //     분기/점프 대상 주소의 하위 비트가 0이 아닌 경우
   // -----------------------------------------------------------------------
   assign ex_exception = ex_branch_misaligned;

   always_comb begin
      ex_cause = 32'd0;
      ex_tval  = 32'd0;
      if (ex_branch_misaligned) begin
         ex_cause = 32'd0;              // Instruction address misaligned
         ex_tval  = ex_branch_target;   // 잘못된 분기 대상 주소
      end
   end

   // -----------------------------------------------------------------------
   // 동기 예외 감지 — MEM 스테이지
   // -----------------------------------------------------------------------
   // MEM 스테이지에서 감지 가능한 예외:
   //   - Load address misaligned  (mcause = 4)
   //   - Store address misaligned (mcause = 6)
   // -----------------------------------------------------------------------
   assign mem_exception = mem_load_misaligned | mem_store_misaligned;

   always_comb begin
      mem_cause = 32'd0;
      mem_tval  = 32'd0;
      if (mem_load_misaligned) begin
         mem_cause = 32'd4;           // Load address misaligned
         mem_tval  = mem_alu_result;  // 비정렬 로드 주소
      end else if (mem_store_misaligned) begin
         mem_cause = 32'd6;           // Store/AMO address misaligned
         mem_tval  = mem_alu_result;  // 비정렬 스토어 주소
      end
   end

   // -----------------------------------------------------------------------
   // 비동기 인터럽트 감지
   // -----------------------------------------------------------------------
   // 인터럽트 조건: 전역 인에이블(mstatus.MIE) AND 개별 인에이블(mie) AND 펜딩(mip)
   // 우선순위: MEI > MSI > MTI (RISC-V 스펙 기준)
   // -----------------------------------------------------------------------
   logic mei_pending;  // 외부 인터럽트 펜딩
   logic msi_pending;  // 소프트웨어 인터럽트 펜딩
   logic mti_pending;  // 타이머 인터럽트 펜딩

   assign mei_pending = ext_irq   & mie_meie & mstatus_mie;
   assign msi_pending = sw_irq    & mie_msie & mstatus_mie;
   assign mti_pending = timer_irq & mie_mtie & mstatus_mie;

   assign interrupt_pending = mei_pending | msi_pending | mti_pending;

   // 인터럽트 우선순위 인코딩
   always_comb begin
      int_cause = 32'd0;
      if (mei_pending)
         int_cause = 32'h8000_000B;   // Machine external interrupt
      else if (msi_pending)
         int_cause = 32'h8000_0003;   // Machine software interrupt
      else if (mti_pending)
         int_cause = 32'h8000_0007;   // Machine timer interrupt
   end

   // -----------------------------------------------------------------------
   // 최종 트랩 결정 — 우선순위: 동기 예외 > 비동기 인터럽트
   // -----------------------------------------------------------------------
   // 동기 예외는 파이프라인 순서(MEM > EX > ID)에 따라 우선순위를 결정한다.
   // 이유: 더 오래된(선행) 명령어의 예외가 먼저 처리되어야 정확한 예외가 보장됨.
   // 인터럽트는 동기 예외가 없을 때만 처리한다.
   // -----------------------------------------------------------------------
   always_comb begin
      trap_taken  = 1'b0;
      trap_pc     = mtvec;
      trap_mepc   = 32'd0;
      trap_mcause = 32'd0;
      trap_mtval  = 32'd0;

      // 우선순위 1: MEM 스테이지 동기 예외 (가장 오래된 명령어)
      if (mem_exception) begin
         trap_taken  = 1'b1;
         trap_mepc   = mem_pc;
         trap_mcause = mem_cause;
         trap_mtval  = mem_tval;
      end
      // 우선순위 2: EX 스테이지 동기 예외
      else if (ex_exception) begin
         trap_taken  = 1'b1;
         trap_mepc   = ex_pc;
         trap_mcause = ex_cause;
         trap_mtval  = ex_tval;
      end
      // 우선순위 3: ID 스테이지 동기 예외
      else if (id_exception) begin
         trap_taken  = 1'b1;
         trap_mepc   = id_pc;
         trap_mcause = id_cause;
         trap_mtval  = id_tval;
      end
      // 우선순위 4: 비동기 인터럽트
      else if (interrupt_pending) begin
         trap_taken  = 1'b1;
         // ----------------------------------------------------------------
         // [교육적 단순화 — 주의]
         // RISC-V 특권 아키텍처 스펙 §3.1.14에 따르면, 비동기 인터럽트에서
         // mepc에는 "인터럽트 수용 시점에 미완료된 가장 오래된 명령어의 PC"를
         // 저장해야 합니다.
         // 완전 구현에서는 파이프라인 스테이지 상태(MEM/EX/ID/IF의 버블 여부)를
         // 검사하여 올바른 복귀 PC를 결정해야 합니다.
         // 이 구현은 MEM 스테이지 PC + 4를 사용하는 단순화 버전입니다:
         //   - MEM 스테이지가 유효 명령어일 때: MRET 후 MEM 명령어 다음부터 실행 (정상)
         //   - MEM 스테이지가 버블(NOP)일 때: mem_pc + 4는 의미 없는 주소가 될 수 있음
         // 교육 목적 구현으로, 실제 프로덕션 설계에서는 반드시 보완이 필요합니다.
         // ----------------------------------------------------------------
         trap_mepc   = mem_pc + 32'd4;  // 단순화: MEM 스테이지 PC + 4
         trap_mcause = int_cause;
         trap_mtval  = 32'd0;
      end
   end

   // -----------------------------------------------------------------------
   // 파이프라인 플러시 제어
   // -----------------------------------------------------------------------
   // 트랩이 발생하면 모든 파이프라인 스테이지를 플러시한다.
   // 이는 정확한 예외를 보장하기 위해 필수적이다.
   // -----------------------------------------------------------------------
   assign flush_if  = trap_taken;
   assign flush_id  = trap_taken;
   assign flush_ex  = trap_taken;
   assign flush_mem = trap_taken;

endmodule