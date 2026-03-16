// ============================================================
// SRL (Shift Register LUT) 추론 패턴
// ============================================================
// 핵심 조건: 고정 길이 시프트 레지스터, 출력 = 마지막 단
// 용도: 파이프라인 지연 매칭, FIFO 대체 (소규모)
// Artix-7: SRL16E (16단) 또는 SRLC32E (32단)
// ============================================================
module srl_delay #(
   parameter DEPTH = 16,         // 지연 깊이 (1~32)
   parameter WIDTH = 8           // 데이터 폭
)(
   input  logic             clk,
   input  logic             ce,      // 클록 인에이블
   input  logic [WIDTH-1:0] din,     // 입력 데이터
   output logic [WIDTH-1:0] dout     // 지연된 출력
);
   // 시프트 레지스터 배열
   logic [WIDTH-1:0] shreg [0:DEPTH-1];

   always_ff @(posedge clk) begin
      if (ce) begin
         shreg[0] <= din;
         for (int i = 1; i < DEPTH; i++)
            shreg[i] <= shreg[i-1];
      end
   end

   // 마지막 단 출력 → SRL 추론
   assign dout = shreg[DEPTH-1];
endmodule