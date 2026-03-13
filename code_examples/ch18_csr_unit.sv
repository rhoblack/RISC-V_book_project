// ============================================================================
// CSR 유닛 상위 모듈 (CSR Unit Top)
// Chapter 18 — CSR과 시스템 명령어
// RISC-V 프로세서 설계 완전정복
// ============================================================================
// CSR ALU + CSR 레지스터 파일을 통합하는 상위 모듈
// 디코더에서 제어 신호를 받아 원자적 읽기-수정-쓰기를 수행
// ============================================================================

`timescale 1ns / 1ps

module csr_unit (
   // --- 클럭 및 리셋 ---
   input  logic        clk,
   input  logic        rst_n,

   // --- 명령어 디코더 인터페이스 ---
   input  logic [11:0] csr_addr,     // 명령어[31:20] — CSR 주소
   input  logic [4:0]  rs1_addr,     // 명령어[19:15] — rs1 주소 (또는 zimm)
   input  logic [31:0] rs1_data,     // rs1 레지스터 데이터
   input  logic [2:0]  funct3,       // 명령어[14:12] — CSR 연산 타입
   input  logic        csr_en,       // CSR 명령어 유효 신호

   // --- 결과 출력 ---
   output logic [31:0] csr_rd_data,  // rd에 쓸 CSR 읽기 값

   // --- 트랩 인터페이스 (Ch19에서 연결) ---
   input  logic        trap_enter,
   input  logic [31:0] trap_pc,
   input  logic [31:0] trap_cause,
   input  logic        mret_exec,

   // --- 인터럽트 입력 ---
   input  logic        ext_irq,
   input  logic        timer_irq,
   input  logic        sw_irq,

   // --- 출력 ---
   output logic [31:0] mtvec_out,
   output logic [31:0] mepc_out,
   output logic        irq_pending,
   output logic        csr_access_fault
);

   // =========================================================================
   // funct3 디코딩
   // =========================================================================
   // funct3[2]   = 0: rs1 소스,  1: zimm 소스
   // funct3[1:0] = 01: Write, 10: Set, 11: Clear
   logic        use_zimm;
   logic [1:0]  csr_op;
   logic [31:0] src_data;
   logic        csr_w_en;

   assign use_zimm = funct3[2];              // 즉치수 변형 여부
   assign csr_op   = funct3[1:0];            // 연산 타입

   // =========================================================================
   // 소스 데이터 선택 MUX
   // =========================================================================
   // zimm: rs1 필드(5비트)를 무부호 즉치수로 제로 확장
   assign src_data = use_zimm ? {27'b0, rs1_addr} : rs1_data;

   // =========================================================================
   // 쓰기 인에이블 결정
   // =========================================================================
   // CSRRW/CSRRWI: 항상 쓰기
   // CSRRS/CSRRSI, CSRRC/CSRRCI: rs1 != x0 (또는 zimm != 0)일 때만 쓰기
   // — rs1=x0이면 읽기만 수행 (사이드이펙트 방지)
   always_comb begin
      if (!csr_en) begin
         csr_w_en = 1'b0;
      end
      else if (csr_op == 2'b01) begin
         // CSRRW/CSRRWI — 항상 쓰기
         csr_w_en = 1'b1;
      end
      else begin
         // CSRRS/CSRRC — rs1 == x0 (또는 zimm == 0)이면 쓰기 안 함
         csr_w_en = use_zimm ? (rs1_addr != 5'b0) : (rs1_addr != 5'b0);
      end
   end

   // =========================================================================
   // CSR ALU 인스턴스
   // =========================================================================
   logic [31:0] csr_rdata;
   logic [31:0] csr_wdata;

   csr_alu u_csr_alu (
      .csr_rdata (csr_rdata),
      .src_data  (src_data),
      .csr_op    (csr_op),
      .csr_wdata (csr_wdata)
   );

   // =========================================================================
   // CSR 레지스터 파일 인스턴스
   // =========================================================================
   csr_register_file u_csr_rf (
      .clk              (clk),
      .rst_n            (rst_n),
      .csr_addr         (csr_addr),
      .csr_wdata        (csr_wdata),
      .csr_w_en         (csr_w_en),
      .csr_rdata        (csr_rdata),
      .trap_enter       (trap_enter),
      .trap_pc          (trap_pc),
      .trap_cause       (trap_cause),
      .mret_exec        (mret_exec),
      .ext_irq          (ext_irq),
      .timer_irq        (timer_irq),
      .sw_irq           (sw_irq),
      .mtvec_out        (mtvec_out),
      .mepc_out         (mepc_out),
      .irq_pending      (irq_pending),
      .csr_access_fault (csr_access_fault)
   );

   // =========================================================================
   // 읽기 값 출력 (rd에 기록될 이전 CSR 값)
   // =========================================================================
   assign csr_rd_data = csr_rdata;

endmodule