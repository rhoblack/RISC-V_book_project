// ============================================================================
// 제어 해저드 처리 모듈 — 분기 판정 및 Flush 신호 생성
// Chapter 11: 제어 해저드와 분기 처리
// ============================================================================
// - EX 스테이지에서 분기 결과를 판정
// - 분기 성공 시 IF/ID, ID/EX 파이프라인 레지스터 flush 신호 생성
// - branch_target 주소를 PC에 전달
// ============================================================================

module branch_control (
   input  logic [31:0] ex_pc,           // EX 스테이지의 PC 값
   input  logic [31:0] ex_imm,          // EX 스테이지의 즉치수
   input  logic [31:0] ex_rs1_data,     // rs1 값 (포워딩 적용 후)
   input  logic [31:0] ex_rs2_data,     // rs2 값 (포워딩 적용 후)
   input  logic [2:0]  ex_funct3,       // 분기 조건 선택 (funct3)
   input  logic        ex_branch,       // 분기 명령어 여부
   input  logic        ex_jal,          // JAL 명령어 여부
   input  logic        ex_jalr,         // JALR 명령어 여부

   output logic        branch_taken,    // 분기/점프 성공 여부
   output logic [31:0] branch_target,   // 분기/점프 대상 주소
   output logic        flush_if_id,     // IF/ID 레지스터 flush
   output logic        flush_id_ex      // ID/EX 레지스터 flush
);

   // ---------------------------------------------------------------
   // 분기 조건 판정 (funct3에 따른 비교 연산)
   // ---------------------------------------------------------------
   logic branch_cond;

   always_comb begin
      branch_cond = 1'b0;
      case (ex_funct3)
         3'b000: branch_cond = (ex_rs1_data == ex_rs2_data);          // BEQ
         3'b001: branch_cond = (ex_rs1_data != ex_rs2_data);          // BNE
         3'b100: branch_cond = ($signed(ex_rs1_data) <
                                $signed(ex_rs2_data));                 // BLT
         3'b101: branch_cond = ($signed(ex_rs1_data) >=
                                $signed(ex_rs2_data));                 // BGE
         3'b110: branch_cond = (ex_rs1_data < ex_rs2_data);           // BLTU
         3'b111: branch_cond = (ex_rs1_data >= ex_rs2_data);          // BGEU
         default: branch_cond = 1'b0;
      endcase
   end

   // ---------------------------------------------------------------
   // 분기/점프 성공 여부 판정
   // ---------------------------------------------------------------
   assign branch_taken = (ex_branch & branch_cond) | ex_jal | ex_jalr;

   // ---------------------------------------------------------------
   // 분기/점프 대상 주소 계산
   // - B 타입, JAL: PC + imm (PC 상대 주소)
   // - JALR: rs1 + imm (레지스터 기반, LSB 클리어)
   // ---------------------------------------------------------------
   always_comb begin
      if (ex_jalr)
         branch_target = (ex_rs1_data + ex_imm) & 32'hFFFF_FFFE;  // LSB = 0
      else
         branch_target = ex_pc + ex_imm;  // B 타입 및 JAL
   end

   // ---------------------------------------------------------------
   // Flush 신호 생성
   // 분기/점프 성공 시 IF/ID와 ID/EX 레지스터를 무효화
   // ---------------------------------------------------------------
   assign flush_if_id = branch_taken;
   assign flush_id_ex = branch_taken;

endmodule
