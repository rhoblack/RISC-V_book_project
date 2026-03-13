// ============================================================================
// 트랩 컨트롤러 (Trap Controller)
// Chapter 19 — 예외/인터럽트와 파이프라인 통합
// RISC-V 프로세서 설계 완전정복
// ============================================================================
// 트랩 진입(trap entry)과 복귀(MRET) 시퀀스를 관리한다.
// CSR 모듈(Ch18)과 연동하여 mepc/mcause/mstatus를 업데이트한다.
// ============================================================================

`timescale 1ns / 1ps

module trap_controller (
   // --- 클럭/리셋 ---
   input  logic        clk,
   input  logic        rst_n,

   // --- 예외 유닛 입력 ---
   input  logic        trap_taken,          // 트랩 발생
   input  logic [31:0] trap_mepc,           // 저장할 mepc 값
   input  logic [31:0] trap_mcause,         // 저장할 mcause 값
   input  logic [31:0] trap_mtval,          // 저장할 mtval 값

   // --- MRET 감지 ---
   input  logic        mret_instr,          // MRET 명령어 감지 (ID 스테이지)

   // --- CSR 현재 값 입력 ---
   input  logic [31:0] csr_mtvec,           // 트랩 벡터 기저 주소
   input  logic [31:0] csr_mepc,            // 저장된 복귀 주소
   input  logic [31:0] csr_mstatus,         // 현재 mstatus

   // --- CSR 쓰기 출력 ---
   output logic        csr_we,              // CSR 쓰기 인에이블
   output logic [11:0] csr_waddr,           // CSR 쓰기 주소
   output logic [31:0] csr_wdata,           // CSR 쓰기 데이터

   // --- PC 제어 출력 ---
   output logic        pc_trap,             // 트랩으로 인한 PC 변경
   output logic [31:0] pc_next,             // 다음 PC 값

   // --- 파이프라인 제어 ---
   output logic        pipeline_flush       // 파이프라인 전체 플러시
);

   // -----------------------------------------------------------------------
   // CSR 주소 상수 정의
   // -----------------------------------------------------------------------
   localparam CSR_MSTATUS = 12'h300;
   localparam CSR_MTVEC   = 12'h305;
   localparam CSR_MEPC    = 12'h341;
   localparam CSR_MCAUSE  = 12'h342;
   localparam CSR_MTVAL   = 12'h343;

   // mstatus 비트 필드 위치
   localparam MIE_BIT  = 3;    // Machine Interrupt Enable
   localparam MPIE_BIT = 7;    // Machine Previous Interrupt Enable

   // -----------------------------------------------------------------------
   // 트랩 진입/복귀 상태 머신
   // -----------------------------------------------------------------------
   typedef enum logic [2:0] {
      S_IDLE,           // 정상 동작
      S_TRAP_MEPC,      // 트랩: mepc 쓰기
      S_TRAP_MCAUSE,    // 트랩: mcause 쓰기
      S_TRAP_MTVAL,     // 트랩: mtval 쓰기
      S_TRAP_MSTATUS,   // 트랩: mstatus 업데이트
      S_MRET_MSTATUS    // MRET: mstatus 복원
   } trap_state_t;

   trap_state_t state, next_state;

   // 트랩 정보 래치
   logic [31:0] latched_mepc;
   logic [31:0] latched_mcause;
   logic [31:0] latched_mtval;

   // -----------------------------------------------------------------------
   // 상태 레지스터
   // -----------------------------------------------------------------------
   always_ff @(posedge clk or negedge rst_n) begin
      if (!rst_n) begin
         state          <= S_IDLE;
         latched_mepc   <= 32'd0;
         latched_mcause <= 32'd0;
         latched_mtval  <= 32'd0;
      end else begin
         state <= next_state;
         if (trap_taken && state == S_IDLE) begin
            latched_mepc   <= trap_mepc;
            latched_mcause <= trap_mcause;
            latched_mtval  <= trap_mtval;
         end
      end
   end

   // -----------------------------------------------------------------------
   // 상태 전이 로직
   // -----------------------------------------------------------------------
   always_comb begin
      next_state = state;
      case (state)
         S_IDLE: begin
            if (trap_taken)
               next_state = S_TRAP_MEPC;
            else if (mret_instr)
               next_state = S_MRET_MSTATUS;
         end
         S_TRAP_MEPC:    next_state = S_TRAP_MCAUSE;
         S_TRAP_MCAUSE:  next_state = S_TRAP_MTVAL;
         S_TRAP_MTVAL:   next_state = S_TRAP_MSTATUS;
         S_TRAP_MSTATUS: next_state = S_IDLE;
         S_MRET_MSTATUS: next_state = S_IDLE;
         default:        next_state = S_IDLE;
      endcase
   end

   // -----------------------------------------------------------------------
   // 출력 로직 — CSR 쓰기
   // -----------------------------------------------------------------------
   always_comb begin
      csr_we    = 1'b0;
      csr_waddr = 12'd0;
      csr_wdata = 32'd0;

      case (state)
         // 트랩 진입: mepc ← 예외 발생 PC
         S_TRAP_MEPC: begin
            csr_we    = 1'b1;
            csr_waddr = CSR_MEPC;
            csr_wdata = latched_mepc;
         end

         // 트랩 진입: mcause ← 예외/인터럽트 코드
         S_TRAP_MCAUSE: begin
            csr_we    = 1'b1;
            csr_waddr = CSR_MCAUSE;
            csr_wdata = latched_mcause;
         end

         // 트랩 진입: mtval ← 부가 정보
         S_TRAP_MTVAL: begin
            csr_we    = 1'b1;
            csr_waddr = CSR_MTVAL;
            csr_wdata = latched_mtval;
         end

         // 트랩 진입: mstatus 업데이트
         //   MPIE ← MIE (이전 인터럽트 인에이블 백업)
         //   MIE  ← 0   (인터럽트 비활성화)
         S_TRAP_MSTATUS: begin
            csr_we    = 1'b1;
            csr_waddr = CSR_MSTATUS;
            csr_wdata = csr_mstatus;
            csr_wdata[MPIE_BIT] = csr_mstatus[MIE_BIT]; // MPIE ← MIE
            csr_wdata[MIE_BIT]  = 1'b0;                  // MIE ← 0
         end

         // MRET: mstatus 복원
         //   MIE  ← MPIE (인터럽트 인에이블 복원)
         //   MPIE ← 1    (기본값)
         S_MRET_MSTATUS: begin
            csr_we    = 1'b1;
            csr_waddr = CSR_MSTATUS;
            csr_wdata = csr_mstatus;
            csr_wdata[MIE_BIT]  = csr_mstatus[MPIE_BIT]; // MIE ← MPIE
            csr_wdata[MPIE_BIT] = 1'b1;                   // MPIE ← 1
         end

         default: ; // S_IDLE: 쓰기 없음
      endcase
   end

   // -----------------------------------------------------------------------
   // PC 제어 및 파이프라인 플러시
   // -----------------------------------------------------------------------
   always_comb begin
      pc_trap        = 1'b0;
      pc_next        = 32'd0;
      pipeline_flush = 1'b0;

      // 트랩 진입: mtvec 주소로 점프
      if (trap_taken && state == S_IDLE) begin
         pc_trap        = 1'b1;
         pc_next        = csr_mtvec;
         pipeline_flush = 1'b1;
      end
      // MRET: mepc 주소로 복귀
      else if (mret_instr && state == S_IDLE) begin
         pc_trap        = 1'b1;
         pc_next        = csr_mepc;
         pipeline_flush = 1'b1;
      end
   end

endmodule