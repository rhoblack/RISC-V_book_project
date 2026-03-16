// ============================================================
// DSP48E1 추론 패턴 — Artix-7 곱셈기/MAC 자동 추론
// ============================================================
// 핵심 조건: 곱셈 연산자(*), 곱셈-누적(MAC), 파이프라인 레지스터
// Artix-7 DSP48E1: 25×18 곱셈기 + 48비트 가산기
// 주의: DSP48E1은 비동기 리셋을 지원하지 않으므로 동기 리셋 사용
// ============================================================
module dsp_multiplier (
   input  logic        clk,
   input  logic        rst,      // 동기 리셋 (비동기 리셋 사용 시 DSP 추론 실패)
   input  logic [15:0] a,        // 피승수 (16비트)
   input  logic [15:0] b,        // 승수 (16비트)
   output logic [31:0] product   // 결과 (32비트)
);
   // 파이프라인 레지스터 추가 → DSP48E1 내부 레지스터 활용
   logic [15:0] a_reg, b_reg;
   logic [31:0] mult_reg;

   always_ff @(posedge clk) begin
      if (rst) begin
         a_reg    <= '0;
         b_reg    <= '0;
         mult_reg <= '0;
         product  <= '0;
      end else begin
         // 입력 레지스터 (DSP48E1 A/B 레지스터 매핑)
         a_reg <= a;
         b_reg <= b;
         // 곱셈 (DSP48E1 M 레지스터 매핑)
         mult_reg <= a_reg * b_reg;    // ← 곱셈 연산자 → DSP 추론
         // 출력 레지스터 (DSP48E1 P 레지스터 매핑)
         product <= mult_reg;
      end
   end
endmodule
