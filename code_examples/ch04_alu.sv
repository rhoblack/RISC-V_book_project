// =============================================================================
// 모듈명: alu
// 설  명: RV32I ALU — 10가지 연산 (산술, 논리, 시프트, 비교)
// 파  일: ch04_alu.sv
// 표  준: IEEE 1800-2017 (SystemVerilog)
// 저  자: RISC-V 프로세서 설계 완전정복 — Chapter 04
// =============================================================================
// ALU 제어 코드 (alu_ctrl[3:0]):
//   4'b0000 : ADD   (덧셈)
//   4'b0001 : SUB   (뺄셈)
//   4'b0010 : AND   (비트 AND)
//   4'b0011 : OR    (비트 OR)
//   4'b0100 : XOR   (비트 XOR)
//   4'b0101 : SLL   (논리 좌측 시프트)
//   4'b0110 : SRL   (논리 우측 시프트)
//   4'b0111 : SRA   (산술 우측 시프트)
//   4'b1000 : SLT   (부호 있는 비교, Set Less Than)
//   4'b1001 : SLTU  (부호 없는 비교, Set Less Than Unsigned)
// =============================================================================

module alu (
   input  logic [31:0] operand_a,   // 첫 번째 피연산자 (rs1 데이터)
   input  logic [31:0] operand_b,   // 두 번째 피연산자 (rs2 데이터 또는 즉치수)
   input  logic [3:0]  alu_ctrl,    // ALU 제어 신호 (연산 선택)
   output logic [31:0] alu_result,  // 연산 결과
   output logic        alu_zero     // 결과가 0일 때 1 (분기 판정용)
);

   // 시프트량: 하위 5비트만 사용 (RV32I는 32비트이므로 0~31)
   logic [4:0] shamt;
   assign shamt = operand_b[4:0];

   // ALU 핵심 연산 — 조합 논리 (always_comb)
   always_comb begin
      case (alu_ctrl)
         // === 산술 연산 ===
         4'b0000: alu_result = operand_a + operand_b;                        // ADD
         4'b0001: alu_result = operand_a - operand_b;                        // SUB

         // === 논리 연산 ===
         4'b0010: alu_result = operand_a & operand_b;                        // AND
         4'b0011: alu_result = operand_a | operand_b;                        // OR
         4'b0100: alu_result = operand_a ^ operand_b;                        // XOR

         // === 시프트 연산 ===
         4'b0101: alu_result = operand_a << shamt;                           // SLL (논리 좌측)
         4'b0110: alu_result = operand_a >> shamt;                           // SRL (논리 우측)
         4'b0111: alu_result = $signed(operand_a) >>> shamt;                 // SRA (산술 우측)

         // === 비교 연산 ===
         4'b1000: alu_result = {31'b0, $signed(operand_a) < $signed(operand_b)};   // SLT
         4'b1001: alu_result = {31'b0, operand_a < operand_b};                      // SLTU

         // === 기본값 (정의되지 않은 제어 코드) ===
         default: alu_result = 32'b0;
      endcase
   end

   // 제로 플래그: ALU 결과가 0이면 1 (BEQ/BNE 분기 판정에 사용)
   assign alu_zero = (alu_result == 32'b0);

endmodule
