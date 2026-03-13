// ============================================================================
// 2-bit 포화 카운터 기반 분기 이력 테이블 (BHT)
// Chapter 11: 제어 해저드와 분기 처리 — 11.5절 동적 분기 예측
// ============================================================================
// - 256 엔트리, PC[9:2]로 인덱싱 (태그 없음, aliasing 허용)
// - 2-bit 포화 카운터: 00(Strongly NT), 01(Weakly NT),
//                      10(Weakly T), 11(Strongly T)
// - Basys 3: 256 × 2bit = 512bit, LUTRAM 1개 슬라이스로 구현 가능
// ============================================================================

module branch_history_table #(
   parameter BHT_ADDR_WIDTH = 8,                          // 인덱스 비트 수
   parameter BHT_ENTRIES    = 2**BHT_ADDR_WIDTH           // 256 엔트리
)(
   input  logic                       clk,
   input  logic                       rst_n,

   // ---- IF 스테이지: 예측 요청 ----
   input  logic [31:0]                if_pc,              // 현재 fetch 중인 PC
   output logic                       predict_taken,      // 예측 결과 (1=Taken)

   // ---- EX 스테이지: 갱신 요청 ----
   input  logic                       ex_branch_valid,    // 분기 명령어 완료
   input  logic [31:0]                ex_pc,              // 분기 명령어의 PC
   input  logic                       ex_branch_taken     // 실제 분기 결과
);

   // ---------------------------------------------------------------
   // BHT 저장소: 2-bit 포화 카운터 배열
   // ---------------------------------------------------------------
   logic [1:0] bht [BHT_ENTRIES];

   // 인덱스 추출: PC[9:2] (하위 2비트는 항상 00이므로 제외)
   logic [BHT_ADDR_WIDTH-1:0] if_idx;
   logic [BHT_ADDR_WIDTH-1:0] ex_idx;

   assign if_idx = if_pc[BHT_ADDR_WIDTH+1:2];
   assign ex_idx = ex_pc[BHT_ADDR_WIDTH+1:2];

   // ---------------------------------------------------------------
   // 예측 로직 (조합 논리, IF 스테이지)
   // MSB가 1이면 Taken 예측 (상태 10 또는 11)
   // ---------------------------------------------------------------
   assign predict_taken = bht[if_idx][1];

   // ---------------------------------------------------------------
   // 카운터 갱신 로직 (순차 논리, EX 스테이지 결과 반영)
   // ---------------------------------------------------------------
   integer i;

   always_ff @(posedge clk or negedge rst_n) begin
      if (!rst_n) begin
         // 리셋 시 모든 엔트리를 Weakly Not-Taken (01)으로 초기화
         for (i = 0; i < BHT_ENTRIES; i = i + 1)
            bht[i] <= 2'b01;
      end
      else if (ex_branch_valid) begin
         if (ex_branch_taken) begin
            // 실제 Taken → 카운터 증가 (최대 11에서 포화)
            if (bht[ex_idx] < 2'b11)
               bht[ex_idx] <= bht[ex_idx] + 2'b01;
         end
         else begin
            // 실제 Not-Taken → 카운터 감소 (최소 00에서 포화)
            if (bht[ex_idx] > 2'b00)
               bht[ex_idx] <= bht[ex_idx] - 2'b01;
         end
      end
   end

endmodule
