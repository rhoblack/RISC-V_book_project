// ============================================================================
// branch_unit.sv
// Chapter 11 — 제어 해저드와 분기 처리
// RISC-V 프로세서 설계 완전정복
// ============================================================================
// 6가지 분기 조건 평가 (BEQ/BNE/BLT/BGE/BLTU/BGEU)
// EX 스테이지에서 포워딩된 rs1, rs2 값으로 직접 비교
// ============================================================================

`timescale 1ns / 1ps

module branch_unit (
   input  logic [31:0] rs1_data,      // 포워딩된 rs1 값
   input  logic [31:0] rs2_data,      // 포워딩된 rs2 값
   input  logic [2:0]  funct3,        // 분기 조건 코드 (BEQ=000, BNE=001, ...)
   input  logic        branch,        // 분기 명령어 여부 (1 = branch 명령어)
   output logic        branch_taken   // 분기 실행 여부 (1 = 분기 taken)
);

   logic cond; // 분기 조건 평가 결과

   // -------------------------------------------------------------------------
   // 분기 조건 평가 — funct3에 따라 6가지 비교 수행
   // -------------------------------------------------------------------------
   always_comb begin
      case (funct3)
         3'b000: cond = (rs1_data == rs2_data);                       // BEQ: 같으면 분기
         3'b001: cond = (rs1_data != rs2_data);                       // BNE: 다르면 분기
         3'b100: cond = ($signed(rs1_data) < $signed(rs2_data));      // BLT: 부호 있는 작으면
         3'b101: cond = ($signed(rs1_data) >= $signed(rs2_data));     // BGE: 부호 있는 크거나 같으면
         3'b110: cond = (rs1_data < rs2_data);                        // BLTU: 부호 없는 작으면
         3'b111: cond = (rs1_data >= rs2_data);                       // BGEU: 부호 없는 크거나 같으면
         default: cond = 1'b0;
      endcase
   end

   // -------------------------------------------------------------------------
   // 최종 branch_taken: 분기 명령어이면서 조건이 참일 때만 1
   // -------------------------------------------------------------------------
   assign branch_taken = branch && cond;

endmodule
