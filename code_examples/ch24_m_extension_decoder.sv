///////////////////////////////////////////////////////////////////////////////
// 모듈명 : m_extension_decoder
// 설  명 : M 확장 명령어 디코더
//          funct7 = 7'b0000001, opcode = 7'b0110011 조합으로
//          MUL/MULH/MULHSU/MULHU/DIV/DIVU/REM/REMU 8개 명령어를 디코딩한다.
// 표  준 : IEEE 1800-2017 (SystemVerilog)
// 대상 보드 : Basys 3 (XC7A35T)
///////////////////////////////////////////////////////////////////////////////

module m_extension_decoder (
   input  logic [6:0] opcode,     // 명령어 opcode 필드
   input  logic [2:0] funct3,     // 명령어 funct3 필드
   input  logic [6:0] funct7,     // 명령어 funct7 필드
   output logic       is_m_ext,   // M 확장 명령어 여부
   output logic [3:0] m_op        // M 확장 연산 종류
);

   // M 확장 연산 코드 정의
   localparam logic [3:0] M_OP_MUL    = 4'b0000;  // MUL    : 하위 32비트
   localparam logic [3:0] M_OP_MULH   = 4'b0001;  // MULH   : 상위 32비트 (signed x signed)
   localparam logic [3:0] M_OP_MULHSU = 4'b0010;  // MULHSU : 상위 32비트 (signed x unsigned)
   localparam logic [3:0] M_OP_MULHU  = 4'b0011;  // MULHU  : 상위 32비트 (unsigned x unsigned)
   localparam logic [3:0] M_OP_DIV    = 4'b0100;  // DIV    : 부호 있는 나눗셈 몫
   localparam logic [3:0] M_OP_DIVU   = 4'b0101;  // DIVU   : 부호 없는 나눗셈 몫
   localparam logic [3:0] M_OP_REM    = 4'b0110;  // REM    : 부호 있는 나머지
   localparam logic [3:0] M_OP_REMU   = 4'b0111;  // REMU   : 부호 없는 나머지
   localparam logic [3:0] M_OP_NONE   = 4'b1111;  // 해당 없음

   // M 확장 식별: opcode = OP (0110011), funct7 = 0000001
   localparam logic [6:0] OPCODE_OP    = 7'b0110011;
   localparam logic [6:0] FUNCT7_MULDIV = 7'b0000001;

   always_comb begin
      // 기본값: M 확장 아님
      is_m_ext = 1'b0;
      m_op     = M_OP_NONE;

      if (opcode == OPCODE_OP && funct7 == FUNCT7_MULDIV) begin
         is_m_ext = 1'b1;
         case (funct3)
            3'b000: m_op = M_OP_MUL;
            3'b001: m_op = M_OP_MULH;
            3'b010: m_op = M_OP_MULHSU;
            3'b011: m_op = M_OP_MULHU;
            3'b100: m_op = M_OP_DIV;
            3'b101: m_op = M_OP_DIVU;
            3'b110: m_op = M_OP_REM;
            3'b111: m_op = M_OP_REMU;
            default: begin
               is_m_ext = 1'b0;
               m_op     = M_OP_NONE;
            end
         endcase
      end
   end

endmodule
