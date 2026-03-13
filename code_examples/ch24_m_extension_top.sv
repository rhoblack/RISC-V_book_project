///////////////////////////////////////////////////////////////////////////////
// 모듈명 : m_extension_top
// 설  명 : M 확장 최상위 모듈
//          디코더 + 곱셈기(DSP48E1) + 나눗셈기(반복)를 통합하고
//          기존 파이프라인의 EX 스테이지에 연결하기 위한 인터페이스를 제공한다.
// 표  준 : IEEE 1800-2017 (SystemVerilog)
// 대상 보드 : Basys 3 (XC7A35T)
///////////////////////////////////////////////////////////////////////////////

module m_extension_top (
   input  logic        clk,         // 시스템 클럭
   input  logic        rst_n,       // 비동기 리셋 (액티브 로우)
   input  logic [6:0]  opcode,      // 명령어 opcode
   input  logic [2:0]  funct3,      // 명령어 funct3
   input  logic [6:0]  funct7,      // 명령어 funct7
   input  logic [31:0] rs1_data,    // rs1 값
   input  logic [31:0] rs2_data,    // rs2 값
   input  logic        ex_valid,    // EX 스테이지 유효 신호
   output logic [31:0] m_result,    // M 확장 연산 결과
   output logic        m_valid,     // 결과 유효
   output logic        m_stall      // 파이프라인 스톨 요청
);

   // ---------------------------------------------------------------
   // 내부 신호
   // ---------------------------------------------------------------
   logic       is_m_ext;
   logic [3:0] m_op;

   logic        mul_start;
   logic [1:0]  mul_op;
   logic [31:0] mul_result;
   logic        mul_valid;

   logic        div_start;
   logic        div_signed;
   logic        div_is_rem;
   logic [31:0] div_result;
   logic        div_valid;
   logic        div_busy;

   // ---------------------------------------------------------------
   // 디코더 인스턴스
   // ---------------------------------------------------------------
   m_extension_decoder u_decoder (
      .opcode   (opcode),
      .funct3   (funct3),
      .funct7   (funct7),
      .is_m_ext (is_m_ext),
      .m_op     (m_op)
   );

   // ---------------------------------------------------------------
   // 곱셈/나눗셈 시작 신호 생성
   // ---------------------------------------------------------------
   wire is_mul_op = is_m_ext && (m_op[3:2] == 2'b00);  // MUL/MULH/MULHSU/MULHU
   wire is_div_op = is_m_ext && (m_op[3:2] == 2'b01);  // DIV/DIVU/REM/REMU

   assign mul_start  = ex_valid && is_mul_op && !div_busy;
   assign mul_op     = m_op[1:0];

   assign div_start  = ex_valid && is_div_op && !div_busy;
   assign div_signed = ~m_op[0];       // DIV(100)/REM(110)은 부호 있음
   assign div_is_rem = m_op[1];        // REM(110)/REMU(111)은 나머지

   // ---------------------------------------------------------------
   // 곱셈기 인스턴스 (DSP48E1 추론, 3사이클 파이프라인)
   // ---------------------------------------------------------------
   multiplier_dsp48e1 u_mul (
      .clk       (clk),
      .rst_n     (rst_n),
      .start     (mul_start),
      .mul_op    (mul_op),
      .operand_a (rs1_data),
      .operand_b (rs2_data),
      .result    (mul_result),
      .valid     (mul_valid)
   );

   // ---------------------------------------------------------------
   // 나눗셈기 인스턴스 (반복 방식, 최대 32사이클)
   // ---------------------------------------------------------------
   divider_iterative u_div (
      .clk       (clk),
      .rst_n     (rst_n),
      .start     (div_start),
      .is_signed (div_signed),
      .is_rem    (div_is_rem),
      .dividend  (rs1_data),
      .divisor   (rs2_data),
      .result    (div_result),
      .valid     (div_valid),
      .busy      (div_busy)
   );

   // ---------------------------------------------------------------
   // 결과 다중화 및 스톨 생성
   // ---------------------------------------------------------------
   always_comb begin
      m_result = 32'd0;
      m_valid  = 1'b0;

      if (mul_valid) begin
         m_result = mul_result;
         m_valid  = 1'b1;
      end else if (div_valid) begin
         m_result = div_result;
         m_valid  = 1'b1;
      end
   end

   // 스톨 조건: M 확장 명령어가 EX에 있으나 아직 결과가 나오지 않은 경우
   // 곱셈기: 3사이클 파이프라인이므로 후속 명령어가 결과를 사용하면 스톨 필요
   // 나눗셈기: busy 동안 파이프라인 전체 홀드
   assign m_stall = (ex_valid && is_m_ext) && !m_valid &&
                    (div_busy || (is_mul_op && !mul_valid));

endmodule
