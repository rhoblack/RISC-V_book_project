// =============================================================
// 2사이클 파이프라인 곱셈기 (미니 설계 과제)
// Stage 1: 곱셈 수행 (DSP 슬라이스 매핑)
// Stage 2: 결과 선택 및 출력
//
// Chapter 24 — RV32I 확장: M & F 표준 확장
//
// 파이프라인 통합 시 주의:
// - flush 신호를 반드시 연결하여 분기 미스 시 파이프라인 단계 초기화
// - valid_in은 ex_is_mul_div && !pipeline_stall 으로 생성
// - 나눗셈은 별도 mul_div_unit(ch24_mul_divider.sv)에서 처리
// =============================================================
module mul_pipelined #(
   parameter DATA_WIDTH = 32
)(
   input  logic                  clk,
   input  logic                  rst_n,
   input  logic                  flush,
   input  logic                  valid_in,    // 새 곱셈 요청
   input  logic [2:0]            funct3,
   input  logic [DATA_WIDTH-1:0] operand_a,
   input  logic [DATA_WIDTH-1:0] operand_b,
   output logic [DATA_WIDTH-1:0] result,
   output logic                  valid_out    // 결과 유효
);

   // funct3 인코딩 (곱셈만)
   localparam MUL    = 3'b000;
   localparam MULH   = 3'b001;
   localparam MULHSU = 3'b010;
   localparam MULHU  = 3'b011;

   // -------------------------------------------------------
   // Stage 1: 곱셈 수행 및 결과 래치
   // -------------------------------------------------------
   logic signed [63:0] stage1_product_ss;
   logic signed [63:0] stage1_product_su;
   logic        [63:0] stage1_product_uu;
   logic [2:0]         stage1_funct3;
   logic               stage1_valid;

   always_ff @(posedge clk or negedge rst_n) begin
      if (!rst_n || flush) begin
         stage1_product_ss <= '0;
         stage1_product_su <= '0;
         stage1_product_uu <= '0;
         stage1_funct3     <= '0;
         stage1_valid      <= 1'b0;
      end else begin
         stage1_valid  <= valid_in;
         stage1_funct3 <= funct3;
         if (valid_in) begin
            stage1_product_ss <= $signed(operand_a) * $signed(operand_b);
            stage1_product_su <= $signed(operand_a) * $signed({1'b0, operand_b});
            stage1_product_uu <= {32'b0, operand_a} * {32'b0, operand_b};
         end
      end
   end

   // -------------------------------------------------------
   // Stage 2: funct3에 따른 결과 선택
   // -------------------------------------------------------
   always_ff @(posedge clk or negedge rst_n) begin
      if (!rst_n || flush) begin
         result    <= '0;
         valid_out <= 1'b0;
      end else begin
         valid_out <= stage1_valid;
         if (stage1_valid) begin
            case (stage1_funct3)
               MUL:     result <= stage1_product_ss[31:0];   // 하위 32비트
               MULH:    result <= stage1_product_ss[63:32];  // 상위 (signed×signed)
               MULHSU:  result <= stage1_product_su[63:32];  // 상위 (signed×unsigned)
               MULHU:   result <= stage1_product_uu[63:32];  // 상위 (unsigned×unsigned)
               default: result <= '0;
            endcase
         end
      end
   end

endmodule
