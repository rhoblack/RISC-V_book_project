// ============================================================================
// 파이프라인 레지스터 4종 (Pipeline Stage Registers)
// Chapter 09 — 파이프라인 기초: 스테이지 분할
// RISC-V 프로세서 설계 완전정복
// ============================================================================
// IF/ID, ID/EX, EX/MEM, MEM/WB 파이프라인 레지스터
// 비동기 리셋 (액티브 로우), 클록 상승 에지 래치
// 해저드 처리 미포함 (Ch10~11에서 enable/flush 추가 예정)
// ============================================================================

`timescale 1ns / 1ps

// ============================================================================
// 제어 신호 패키지 (Ch06 제어 유닛과 호환)
// ============================================================================
package pipeline_pkg;

   // ALU 연산 선택
   typedef enum logic [3:0] {
      ALU_ADD  = 4'b0000,
      ALU_SUB  = 4'b0001,
      ALU_AND  = 4'b0010,
      ALU_OR   = 4'b0011,
      ALU_XOR  = 4'b0100,
      ALU_SLL  = 4'b0101,
      ALU_SRL  = 4'b0110,
      ALU_SRA  = 4'b0111,
      ALU_SLT  = 4'b1000,
      ALU_SLTU = 4'b1001
   } alu_op_t;

   // 즉치수 타입 선택
   typedef enum logic [2:0] {
      IMM_I = 3'b000,
      IMM_S = 3'b001,
      IMM_B = 3'b010,
      IMM_U = 3'b011,
      IMM_J = 3'b100
   } imm_sel_t;

   // 메모리 읽기/쓰기 제어
   typedef enum logic [1:0] {
      MEM_NONE  = 2'b00,
      MEM_READ  = 2'b01,
      MEM_WRITE = 2'b10
   } mem_rw_t;

   // PC 소스 선택
   typedef enum logic [1:0] {
      PC_PLUS4  = 2'b00,
      PC_BRANCH = 2'b01,
      PC_JALR   = 2'b10
   } pc_sel_t;

   // Write-Back 소스 선택
   typedef enum logic [1:0] {
      WB_ALU = 2'b00,
      WB_MEM = 2'b01,
      WB_PC4 = 2'b10
   } wb_sel_t;

   // -----------------------------------------------------------------------
   // EX 스테이지 제어 신호 묶음
   // -----------------------------------------------------------------------
   typedef struct packed {
      alu_op_t    alu_sel;     // ALU 연산 선택
      logic       a_sel;       // ALU A 입력: 0=rs1, 1=PC
      logic       b_sel;       // ALU B 입력: 0=rs2, 1=imm
   } ctrl_ex_t;

   // -----------------------------------------------------------------------
   // MEM 스테이지 제어 신호 묶음
   // -----------------------------------------------------------------------
   typedef struct packed {
      mem_rw_t    mem_rw;      // 메모리 읽기/쓰기
      logic       br_taken;    // 분기 성립 여부 (EX에서 결정)
   } ctrl_mem_t;

   // -----------------------------------------------------------------------
   // WB 스테이지 제어 신호 묶음
   // -----------------------------------------------------------------------
   typedef struct packed {
      wb_sel_t    wb_sel;      // Write-Back 소스 선택
      logic       reg_w_en;    // 레지스터 파일 쓰기 인에이블
   } ctrl_wb_t;

endpackage

import pipeline_pkg::*;

// ============================================================================
// 1. IF/ID 파이프라인 레지스터
// ============================================================================
// IF 스테이지에서 인출한 명령어와 PC를 ID 스테이지로 전달
// ============================================================================
module pipe_reg_if_id (
   input  logic        clk,
   input  logic        rst_n,

   // IF 스테이지 출력 (입력)
   input  logic [31:0] if_instr,      // 인출된 명령어
   input  logic [31:0] if_pc,         // 현재 PC
   input  logic [31:0] if_pc_plus4,   // PC + 4

   // ID 스테이지 입력 (출력)
   output logic [31:0] id_instr,
   output logic [31:0] id_pc,
   output logic [31:0] id_pc_plus4
);

   always_ff @(posedge clk or negedge rst_n) begin
      if (!rst_n) begin
         // 리셋 시 NOP (ADDI x0, x0, 0 = 0x00000013)으로 초기화
         id_instr    <= 32'h0000_0013;
         id_pc       <= 32'h0;
         id_pc_plus4 <= 32'h0;
      end else begin
         id_instr    <= if_instr;
         id_pc       <= if_pc;
         id_pc_plus4 <= if_pc_plus4;
      end
   end

endmodule

// ============================================================================
// 2. ID/EX 파이프라인 레지스터
// ============================================================================
// ID 스테이지에서 디코딩된 데이터와 제어 신호를 EX 스테이지로 전달
// 가장 많은 필드를 전달하는 파이프라인 레지스터
// ============================================================================
module pipe_reg_id_ex (
   input  logic        clk,
   input  logic        rst_n,

   // ID 스테이지 출력 (입력) — 데이터
   input  logic [31:0] id_rs1_data,   // rs1 레지스터 값
   input  logic [31:0] id_rs2_data,   // rs2 레지스터 값
   input  logic [31:0] id_imm,        // 즉치수 (부호 확장 완료)
   input  logic [31:0] id_pc,         // PC (분기 주소 계산용)
   input  logic [31:0] id_pc_plus4,   // PC+4 (JAL/JALR rd 기록용)
   input  logic [4:0]  id_rs1_addr,   // rs1 주소 (포워딩 비교용, Ch10)
   input  logic [4:0]  id_rs2_addr,   // rs2 주소 (포워딩 비교용, Ch10)
   input  logic [4:0]  id_rd_addr,    // rd 주소
   input  logic [2:0]  id_funct3,     // funct3 (메모리 접근 폭)

   // ID 스테이지 출력 (입력) — 제어 신호
   input  ctrl_ex_t    id_ctrl_ex,    // EX 스테이지용 제어 신호
   input  ctrl_mem_t   id_ctrl_mem,   // MEM 스테이지용 제어 신호
   input  ctrl_wb_t    id_ctrl_wb,    // WB 스테이지용 제어 신호

   // EX 스테이지 입력 (출력) — 데이터
   output logic [31:0] ex_rs1_data,
   output logic [31:0] ex_rs2_data,
   output logic [31:0] ex_imm,
   output logic [31:0] ex_pc,
   output logic [31:0] ex_pc_plus4,
   output logic [4:0]  ex_rs1_addr,
   output logic [4:0]  ex_rs2_addr,
   output logic [4:0]  ex_rd_addr,
   output logic [2:0]  ex_funct3,

   // EX 스테이지 입력 (출력) — 제어 신호
   output ctrl_ex_t    ex_ctrl_ex,
   output ctrl_mem_t   ex_ctrl_mem,
   output ctrl_wb_t    ex_ctrl_wb
);

   always_ff @(posedge clk or negedge rst_n) begin
      if (!rst_n) begin
         // 데이터 필드 초기화
         ex_rs1_data  <= 32'h0;
         ex_rs2_data  <= 32'h0;
         ex_imm       <= 32'h0;
         ex_pc        <= 32'h0;
         ex_pc_plus4  <= 32'h0;
         ex_rs1_addr  <= 5'h0;
         ex_rs2_addr  <= 5'h0;
         ex_rd_addr   <= 5'h0;
         ex_funct3    <= 3'h0;
         // 제어 신호 초기화 — 모든 동작 비활성화 (= NOP과 동일)
         ex_ctrl_ex   <= '{alu_sel: ALU_ADD, a_sel: 1'b0, b_sel: 1'b0};
         ex_ctrl_mem  <= '{mem_rw: MEM_NONE, br_taken: 1'b0};
         ex_ctrl_wb   <= '{wb_sel: WB_ALU, reg_w_en: 1'b0};
      end else begin
         ex_rs1_data  <= id_rs1_data;
         ex_rs2_data  <= id_rs2_data;
         ex_imm       <= id_imm;
         ex_pc        <= id_pc;
         ex_pc_plus4  <= id_pc_plus4;
         ex_rs1_addr  <= id_rs1_addr;
         ex_rs2_addr  <= id_rs2_addr;
         ex_rd_addr   <= id_rd_addr;
         ex_funct3    <= id_funct3;
         ex_ctrl_ex   <= id_ctrl_ex;
         ex_ctrl_mem  <= id_ctrl_mem;
         ex_ctrl_wb   <= id_ctrl_wb;
      end
   end

endmodule

// ============================================================================
// 3. EX/MEM 파이프라인 레지스터
// ============================================================================
// EX 스테이지의 ALU 결과와 분기 정보를 MEM 스테이지로 전달
// ============================================================================
module pipe_reg_ex_mem (
   input  logic        clk,
   input  logic        rst_n,

   // EX 스테이지 출력 (입력) — 데이터
   input  logic [31:0] ex_alu_result, // ALU 연산 결과
   input  logic [31:0] ex_rs2_data,   // rs2 값 (Store 명령어 데이터)
   input  logic [31:0] ex_pc_plus4,   // PC+4 (JAL/JALR용)
   input  logic [4:0]  ex_rd_addr,    // rd 주소
   input  logic [2:0]  ex_funct3,     // funct3 (메모리 접근 폭)

   // EX 스테이지 출력 (입력) — 제어 신호
   input  ctrl_mem_t   ex_ctrl_mem,   // MEM 스테이지용 제어 신호
   input  ctrl_wb_t    ex_ctrl_wb,    // WB 스테이지용 제어 신호

   // MEM 스테이지 입력 (출력) — 데이터
   output logic [31:0] mem_alu_result,
   output logic [31:0] mem_rs2_data,
   output logic [31:0] mem_pc_plus4,
   output logic [4:0]  mem_rd_addr,
   output logic [2:0]  mem_funct3,

   // MEM 스테이지 입력 (출력) — 제어 신호
   output ctrl_mem_t   mem_ctrl_mem,
   output ctrl_wb_t    mem_ctrl_wb
);

   always_ff @(posedge clk or negedge rst_n) begin
      if (!rst_n) begin
         mem_alu_result <= 32'h0;
         mem_rs2_data   <= 32'h0;
         mem_pc_plus4   <= 32'h0;
         mem_rd_addr    <= 5'h0;
         mem_funct3     <= 3'h0;
         mem_ctrl_mem   <= '{mem_rw: MEM_NONE, br_taken: 1'b0};
         mem_ctrl_wb    <= '{wb_sel: WB_ALU, reg_w_en: 1'b0};
      end else begin
         mem_alu_result <= ex_alu_result;
         mem_rs2_data   <= ex_rs2_data;
         mem_pc_plus4   <= ex_pc_plus4;
         mem_rd_addr    <= ex_rd_addr;
         mem_funct3     <= ex_funct3;
         mem_ctrl_mem   <= ex_ctrl_mem;
         mem_ctrl_wb    <= ex_ctrl_wb;
      end
   end

endmodule

// ============================================================================
// 4. MEM/WB 파이프라인 레지스터
// ============================================================================
// MEM 스테이지의 결과를 WB 스테이지로 전달
// 마지막 파이프라인 레지스터 — WB 제어 신호만 전파
// ============================================================================
module pipe_reg_mem_wb (
   input  logic        clk,
   input  logic        rst_n,

   // MEM 스테이지 출력 (입력) — 데이터
   input  logic [31:0] mem_alu_result, // ALU 결과 (R/I 타입)
   input  logic [31:0] mem_rdata,      // 메모리 읽기 데이터 (Load 명령어)
   input  logic [31:0] mem_pc_plus4,   // PC+4 (JAL/JALR용)
   input  logic [4:0]  mem_rd_addr,    // rd 주소

   // MEM 스테이지 출력 (입력) — 제어 신호
   input  ctrl_wb_t    mem_ctrl_wb,    // WB 스테이지용 제어 신호

   // WB 스테이지 입력 (출력) — 데이터
   output logic [31:0] wb_alu_result,
   output logic [31:0] wb_mem_rdata,
   output logic [31:0] wb_pc_plus4,
   output logic [4:0]  wb_rd_addr,

   // WB 스테이지 입력 (출력) — 제어 신호
   output ctrl_wb_t    wb_ctrl_wb
);

   always_ff @(posedge clk or negedge rst_n) begin
      if (!rst_n) begin
         wb_alu_result <= 32'h0;
         wb_mem_rdata  <= 32'h0;
         wb_pc_plus4   <= 32'h0;
         wb_rd_addr    <= 5'h0;
         wb_ctrl_wb    <= '{wb_sel: WB_ALU, reg_w_en: 1'b0};
      end else begin
         wb_alu_result <= mem_alu_result;
         wb_mem_rdata  <= mem_rdata;
         wb_pc_plus4   <= mem_pc_plus4;
         wb_rd_addr    <= mem_rd_addr;
         wb_ctrl_wb    <= mem_ctrl_wb;
      end
   end

endmodule
