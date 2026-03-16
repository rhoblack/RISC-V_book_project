// ============================================================
// BRAM 추론 패턴 — Vivado에서 Block RAM으로 자동 추론
// ============================================================
// 핵심 조건: 동기 읽기 + 동기 쓰기 (클록 에지에서 읽기/쓰기)
// 최소 크기: 일반적으로 256비트 이상이어야 BRAM 추론
// ============================================================
module bram_single_port #(
   parameter ADDR_WIDTH = 10,    // 2^10 = 1024 엔트리
   parameter DATA_WIDTH = 32     // 32비트 데이터
)(
   input  logic                    clk,
   input  logic                    we,       // 쓰기 인에이블
   input  logic [ADDR_WIDTH-1:0]   addr,     // 주소
   input  logic [DATA_WIDTH-1:0]   din,      // 쓰기 데이터
   output logic [DATA_WIDTH-1:0]   dout      // 읽기 데이터 (1사이클 지연)
);
   // 메모리 배열 선언
   logic [DATA_WIDTH-1:0] mem [0:2**ADDR_WIDTH-1];

   // 동기 읽기 + 동기 쓰기 → BRAM 추론
   always_ff @(posedge clk) begin
      if (we)
         mem[addr] <= din;
      dout <= mem[addr];    // ← 동기 읽기 (레지스터 출력)
   end

   // 초기화 (시뮬레이션 전용, 합성 시 COE 파일 사용)
   // initial $readmemh("init.hex", mem);
endmodule