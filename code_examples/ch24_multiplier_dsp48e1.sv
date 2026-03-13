///////////////////////////////////////////////////////////////////////////////
// 모듈명 : multiplier_dsp48e1
// 설  명 : DSP48E1 슬라이스를 활용한 32x32 부호 있는/없는 곱셈기
//          3단계 파이프라인으로 구현하여 고속 동작을 보장한다.
//          Vivado가 자동으로 DSP48E1 프리미티브를 추론하도록 코딩한다.
// 표  준 : IEEE 1800-2017 (SystemVerilog)
// 대상 보드 : Basys 3 (XC7A35T) — DSP48E1 최대 90개
// 참  고 : (* use_dsp = "yes" *) 속성으로 DSP 추론을 강제할 수 있다.
///////////////////////////////////////////////////////////////////////////////

(* use_dsp = "yes" *)
module multiplier_dsp48e1 (
   input  logic        clk,        // 시스템 클럭
   input  logic        rst_n,      // 비동기 리셋 (액티브 로우)
   input  logic        start,      // 곱셈 시작 신호
   input  logic [1:0]  mul_op,     // 00: MUL, 01: MULH, 10: MULHSU, 11: MULHU
   input  logic [31:0] operand_a,  // 피연산자 A (rs1)
   input  logic [31:0] operand_b,  // 피연산자 B (rs2)
   output logic [31:0] result,     // 곱셈 결과 (32비트)
   output logic        valid       // 결과 유효 신호
);

   // ---------------------------------------------------------------
   // 부호 확장: mul_op에 따라 33비트로 확장
   // MUL/MULH  : 양쪽 부호 확장 (signed x signed)
   // MULHSU    : A만 부호 확장, B는 0 확장 (signed x unsigned)
   // MULHU     : 양쪽 0 확장 (unsigned x unsigned)
   // ---------------------------------------------------------------
   logic signed [32:0] ext_a;  // 33비트 확장된 A
   logic signed [32:0] ext_b;  // 33비트 확장된 B

   always_comb begin
      case (mul_op)
         2'b00,                          // MUL  (하위 32비트, 부호 무관)
         2'b01: begin                    // MULH (signed x signed)
            ext_a = {operand_a[31], operand_a};
            ext_b = {operand_b[31], operand_b};
         end
         2'b10: begin                    // MULHSU (signed x unsigned)
            ext_a = {operand_a[31], operand_a};
            ext_b = {1'b0, operand_b};
         end
         2'b11: begin                    // MULHU (unsigned x unsigned)
            ext_a = {1'b0, operand_a};
            ext_b = {1'b0, operand_b};
         end
         default: begin
            ext_a = '0;
            ext_b = '0;
         end
      endcase
   end

   // ---------------------------------------------------------------
   // 3단계 파이프라인 곱셈기
   // Stage 1: 입력 레지스터 (DSP48E1 A/B 입력 레지스터 대응)
   // Stage 2: 곱셈 수행 (DSP48E1 M 레지스터 대응)
   // Stage 3: 출력 레지스터 (DSP48E1 P 레지스터 대응)
   // ---------------------------------------------------------------

   // Stage 1: 입력 레지스터
   logic signed [32:0] stage1_a;
   logic signed [32:0] stage1_b;
   logic [1:0]         stage1_op;

   // Stage 2: 곱셈 결과 레지스터
   logic signed [65:0] stage2_product;  // 33x33 = 66비트
   logic [1:0]         stage2_op;

   // Stage 3: 최종 출력 레지스터
   logic [31:0]        stage3_result;

   // 유효 비트 시프트 레지스터 (3단계 지연)
   logic [2:0] valid_pipe;

   always_ff @(posedge clk or negedge rst_n) begin
      if (!rst_n) begin
         stage1_a       <= '0;
         stage1_b       <= '0;
         stage1_op      <= 2'b00;
         stage2_product <= '0;
         stage2_op      <= 2'b00;
         stage3_result  <= '0;
         valid_pipe     <= 3'b000;
      end else begin
         // Stage 1: 입력 래치
         stage1_a  <= ext_a;
         stage1_b  <= ext_b;
         stage1_op <= mul_op;

         // Stage 2: 곱셈 수행 — Vivado가 DSP48E1로 추론
         stage2_product <= stage1_a * stage1_b;
         stage2_op      <= stage1_op;

         // Stage 3: 결과 선택
         case (stage2_op)
            2'b00:   stage3_result <= stage2_product[31:0];   // MUL  : 하위 32비트
            default: stage3_result <= stage2_product[63:32];  // MULH/MULHSU/MULHU : 상위 32비트
         endcase

         // 유효 신호 전파
         valid_pipe <= {valid_pipe[1:0], start};
      end
   end

   // 출력 할당
   assign result = stage3_result;
   assign valid  = valid_pipe[2];

endmodule
