// ============================================================================
// 제어 유닛 (Control Unit)
// Chapter 06 — 제어 유닛과 단일 사이클 통합
// RISC-V 프로세서 설계 완전정복
// ============================================================================
// 명령어 디코더 + 분기 비교기를 포함하는 상위 모듈
// 데이터패스에 필요한 모든 제어 신호를 통합 출력
// ============================================================================

`timescale 1ns / 1ps

module control_unit (
   // --- 입력 ---
   input  logic [31:0] instr,       // 32비트 명령어
   input  logic [31:0] rs1_data,    // rs1 레지스터 데이터 (분기 비교용)
   input  logic [31:0] rs2_data,    // rs2 레지스터 데이터 (분기 비교용)

   // --- 제어 신호 출력 ---
   output alu_op_t     alu_sel,     // ALU 연산 선택
   output imm_sel_t    imm_sel,     // 즉치수 타입 선택
   output logic        reg_w_en,    // 레지스터 파일 쓰기 인에이블
   output mem_rw_t     mem_rw,      // 메모리 읽기/쓰기 제어
   output pc_sel_t     pc_sel,      // 다음 PC 선택
   output wb_sel_t     wb_sel,      // Write-Back 소스 선택
   output logic        a_sel,       // ALU A 입력 선택
   output logic        b_sel,       // ALU B 입력 선택
   output logic        br_un,       // 무부호 분기 비교
   output logic        illegal_instr,// 미정의 명령어

   // --- 명령어 필드 출력 (데이터패스용) ---
   output logic [4:0]  rs1_addr,    // rs1 레지스터 주소
   output logic [4:0]  rs2_addr,    // rs2 레지스터 주소
   output logic [4:0]  rd_addr,     // rd 레지스터 주소
   output logic [2:0]  funct3_out   // funct3 (메모리 접근 폭 제어용)
);

   // --- 명령어 필드 추출 ---
   assign rs1_addr   = instr[19:15];
   assign rs2_addr   = instr[24:20];
   assign rd_addr    = instr[11:7];
   assign funct3_out = instr[14:12];

   // --- 분기 비교기 (Branch Comparator) ---
   logic br_eq;   // 두 값이 같은가?
   logic br_lt;   // rs1 < rs2 인가?

   branch_comparator u_branch_comp (
      .rs1_data (rs1_data),
      .rs2_data (rs2_data),
      .br_un    (br_un),
      .br_eq    (br_eq),
      .br_lt    (br_lt)
   );

   // --- 명령어 디코더 인스턴스 ---
   instruction_decoder u_decoder (
      .instr         (instr),
      .br_eq         (br_eq),
      .br_lt         (br_lt),
      .alu_sel       (alu_sel),
      .imm_sel       (imm_sel),
      .reg_w_en      (reg_w_en),
      .mem_rw        (mem_rw),
      .pc_sel        (pc_sel),
      .wb_sel        (wb_sel),
      .a_sel         (a_sel),
      .b_sel         (b_sel),
      .br_un         (br_un),
      .illegal_instr (illegal_instr)
   );

endmodule

// ============================================================================
// 분기 비교기 (Branch Comparator)
// ============================================================================
// 두 레지스터 값을 비교하여 분기 조건 판정
// br_un=1이면 무부호 비교 (BLTU, BGEU)
// ============================================================================
module branch_comparator (
   input  logic [31:0] rs1_data,
   input  logic [31:0] rs2_data,
   input  logic        br_un,     // 1: 무부호 비교, 0: 부호 있는 비교
   output logic        br_eq,     // rs1 == rs2
   output logic        br_lt      // rs1 < rs2
);

   always_comb begin
      br_eq = (rs1_data == rs2_data);

      if (br_un)
         br_lt = (rs1_data < rs2_data);            // 무부호 비교
      else
         br_lt = ($signed(rs1_data) < $signed(rs2_data)); // 부호 있는 비교
   end

endmodule