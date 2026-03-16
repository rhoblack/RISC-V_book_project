// ============================================================
// LUTRAM (분산 RAM) 추론 패턴 — 비동기 읽기 지원
// ============================================================
// 핵심 조건: 비동기 읽기 (조합 논리) + 동기 쓰기
// 용도: 레지스터 파일, 소규모 캐시 Tag/Data 배열
// 제약: LUT 소비량이 크므로 소규모 메모리에만 사용
// ============================================================
module lutram_async_read #(
   parameter ADDR_WIDTH = 5,     // 2^5 = 32 엔트리
   parameter DATA_WIDTH = 32     // 32비트 데이터
)(
   input  logic                    clk,
   input  logic                    we,       // 쓰기 인에이블
   input  logic [ADDR_WIDTH-1:0]   waddr,    // 쓰기 주소
   input  logic [ADDR_WIDTH-1:0]   raddr,    // 읽기 주소
   input  logic [DATA_WIDTH-1:0]   din,      // 쓰기 데이터
   output logic [DATA_WIDTH-1:0]   dout      // 읽기 데이터 (조합 출력)
);
   (* ram_style = "distributed" *)           // Vivado 힌트: LUTRAM 강제
   logic [DATA_WIDTH-1:0] mem [0:2**ADDR_WIDTH-1];

   // 동기 쓰기
   always_ff @(posedge clk) begin
      if (we)
         mem[waddr] <= din;
   end

   // 비동기 읽기 → LUTRAM 추론 (조합 논리)
   assign dout = mem[raddr];     // ← 비동기 읽기 (조합 출력)
endmodule