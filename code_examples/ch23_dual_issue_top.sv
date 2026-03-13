// =============================================================================
// 2-이슈 인오더 파이프라인 — 최상위 발행 제어 모듈
// Chapter 23 — 성능 최적화 기법 (23.4절 미니 설계 과제)
// =============================================================================
// 64비트 폭 명령어 인출, 2개 명령어 동시 디코드, 의존성 검사 후 발행
// Way A: 모든 명령어 유형 / Way B: ALU 전용 (메모리 접근 불가)
// =============================================================================

module dual_issue_fetch_unit #(
   parameter ADDR_WIDTH = 12
)(
   input  logic        clk,
   input  logic        rst_n,

   // 파이프라인 제어
   input  logic        stall_i,          // 후단 스톨
   input  logic        flush_i,          // 분기 오예측 플러시
   input  logic [31:0] branch_target_i,  // 분기 목표 주소

   // 명령어 메모리 인터페이스 (64비트 인출)
   output logic [31:0] imem_addr_o,      // IMEM 주소 (PC)
   input  logic [63:0] imem_data_i,      // 64비트 명령어 데이터

   // Way A 출력 (슬롯 0)
   output logic [31:0] way_a_instr_o,    // Way A 명령어
   output logic [31:0] way_a_pc_o,       // Way A PC
   output logic        way_a_valid_o,    // Way A 유효

   // Way B 출력 (슬롯 1)
   output logic [31:0] way_b_instr_o,    // Way B 명령어
   output logic [31:0] way_b_pc_o,       // Way B PC
   output logic        way_b_valid_o     // Way B 유효
);

   // =========================================================================
   // PC 레지스터 (2씩 증가: 한 사이클에 8바이트 인출)
   // =========================================================================
   logic [31:0] pc_reg;
   logic [31:0] pc_next;

   always_ff @(posedge clk or negedge rst_n) begin
      if (!rst_n)
         pc_reg <= 32'h0000_0000;
      else if (!stall_i)
         pc_reg <= pc_next;
   end

   always_comb begin
      if (flush_i)
         pc_next = branch_target_i;
      else
         pc_next = pc_reg + 32'd8;  // 2개 명령어 = 8바이트
   end

   assign imem_addr_o = pc_reg;

   // =========================================================================
   // 명령어 분리: 64비트 데이터에서 2개 명령어 추출
   // =========================================================================
   // 리틀 엔디안 기준: 하위 32비트 = 먼저 실행할 명령어 (Way A)
   logic [31:0] instr_a;
   logic [31:0] instr_b;

   assign instr_a = imem_data_i[31:0];    // 낮은 주소 명령어
   assign instr_b = imem_data_i[63:32];   // 높은 주소 명령어

   // =========================================================================
   // IF/ID 파이프라인 레지스터
   // =========================================================================
   always_ff @(posedge clk or negedge rst_n) begin
      if (!rst_n) begin
         way_a_instr_o <= 32'h0000_0013;  // NOP
         way_a_pc_o    <= 32'h0;
         way_a_valid_o <= 1'b0;
         way_b_instr_o <= 32'h0000_0013;  // NOP
         way_b_pc_o    <= 32'h0;
         way_b_valid_o <= 1'b0;
      end else if (flush_i) begin
         way_a_instr_o <= 32'h0000_0013;
         way_a_pc_o    <= 32'h0;
         way_a_valid_o <= 1'b0;
         way_b_instr_o <= 32'h0000_0013;
         way_b_pc_o    <= 32'h0;
         way_b_valid_o <= 1'b0;
      end else if (!stall_i) begin
         way_a_instr_o <= instr_a;
         way_a_pc_o    <= pc_reg;
         way_a_valid_o <= 1'b1;
         way_b_instr_o <= instr_b;
         way_b_pc_o    <= pc_reg + 32'd4;
         way_b_valid_o <= 1'b1;
      end
   end

endmodule

// =============================================================================
// 간이 명령어 디코더 (2-이슈용)
// =============================================================================
// Way A/B 공용: opcode에서 명령어 속성을 추출
// =============================================================================

module simple_decoder (
   input  logic [31:0] instr_i,

   output logic [4:0]  rs1_o,
   output logic [4:0]  rs2_o,
   output logic [4:0]  rd_o,
   output logic        use_rs1_o,     // rs1 사용 여부
   output logic        use_rs2_o,     // rs2 사용 여부
   output logic        reg_wen_o,     // 레지스터 쓰기 여부
   output logic        mem_read_o,    // 로드 명령어
   output logic        mem_write_o,   // 스토어 명령어
   output logic        mem_access_o,  // 메모리 접근 (로드 또는 스토어)
   output logic        is_branch_o,   // 분기 명령어
   output logic        is_alu_o       // ALU 연산 명령어
);

   logic [6:0] opcode;
   assign opcode = instr_i[6:0];
   assign rs1_o  = instr_i[19:15];
   assign rs2_o  = instr_i[24:20];
   assign rd_o   = instr_i[11:7];

   always_comb begin
      // 기본값
      use_rs1_o   = 1'b0;
      use_rs2_o   = 1'b0;
      reg_wen_o   = 1'b0;
      mem_read_o  = 1'b0;
      mem_write_o = 1'b0;
      mem_access_o= 1'b0;
      is_branch_o = 1'b0;
      is_alu_o    = 1'b0;

      case (opcode)
         7'b0110011: begin // R-type (ADD, SUB, ...)
            use_rs1_o = 1'b1;
            use_rs2_o = 1'b1;
            reg_wen_o = 1'b1;
            is_alu_o  = 1'b1;
         end
         7'b0010011: begin // I-type ALU (ADDI, ...)
            use_rs1_o = 1'b1;
            reg_wen_o = 1'b1;
            is_alu_o  = 1'b1;
         end
         7'b0000011: begin // Load (LW, LH, LB, ...)
            use_rs1_o    = 1'b1;
            reg_wen_o    = 1'b1;
            mem_read_o   = 1'b1;
            mem_access_o = 1'b1;
         end
         7'b0100011: begin // Store (SW, SH, SB)
            use_rs1_o    = 1'b1;
            use_rs2_o    = 1'b1;
            mem_write_o  = 1'b1;
            mem_access_o = 1'b1;
         end
         7'b1100011: begin // B-type (BEQ, BNE, ...)
            use_rs1_o   = 1'b1;
            use_rs2_o   = 1'b1;
            is_branch_o = 1'b1;
         end
         7'b0110111: begin // LUI
            reg_wen_o = 1'b1;
         end
         7'b0010111: begin // AUIPC
            reg_wen_o = 1'b1;
         end
         7'b1101111: begin // JAL
            reg_wen_o   = 1'b1;
            is_branch_o = 1'b1;
         end
         7'b1100111: begin // JALR
            use_rs1_o   = 1'b1;
            reg_wen_o   = 1'b1;
            is_branch_o = 1'b1;
         end
         default: begin
            // NOP 또는 미지원 명령어
         end
      endcase
   end

endmodule
