// =============================================================================
// 토너먼트 분기 예측기 (Tournament Branch Predictor)
// Chapter 23 — 성능 최적화 기법
// =============================================================================
// 지역(Local) 예측기와 전역(Global) 예측기를 조합하여
// 메타 예측기(Chooser)가 더 나은 예측을 동적으로 선택하는 구조
// =============================================================================

module tournament_predictor #(
   parameter PC_WIDTH     = 32,       // PC 비트 수
   parameter LOCAL_DEPTH  = 256,      // 지역 이력 테이블 엔트리 수
   parameter GLOBAL_DEPTH = 256,      // 전역 패턴 테이블 엔트리 수
   parameter GHR_WIDTH    = 8,        // 전역 이력 레지스터 비트 수
   parameter LOCAL_HIST_W = 8         // 지역 이력 비트 수
)(
   input  logic                  clk,
   input  logic                  rst_n,

   // 예측 인터페이스 (IF 스테이지)
   input  logic [PC_WIDTH-1:0]   pc_i,          // 분기 명령어 PC
   input  logic                  predict_en_i,   // 예측 요청
   output logic                  predict_taken_o, // 예측 결과

   // 갱신 인터페이스 (EX 스테이지, 분기 결과 확정 후)
   input  logic                  update_en_i,    // 갱신 요청
   input  logic [PC_WIDTH-1:0]   update_pc_i,    // 갱신 대상 PC
   input  logic                  actual_taken_i   // 실제 분기 결과
);

   // =========================================================================
   // 지역 변수 및 인덱스 계산
   // =========================================================================
   localparam IDX_W = $clog2(LOCAL_DEPTH);

   logic [IDX_W-1:0] pred_idx;    // 예측 시 인덱스
   logic [IDX_W-1:0] upd_idx;     // 갱신 시 인덱스

   assign pred_idx = pc_i[IDX_W+1:2];     // 워드 정렬 PC에서 인덱스 추출
   assign upd_idx  = update_pc_i[IDX_W+1:2];

   // =========================================================================
   // 전역 이력 레지스터 (GHR: Global History Register)
   // =========================================================================
   // 최근 GHR_WIDTH개 분기 결과를 시프트 레지스터로 저장
   logic [GHR_WIDTH-1:0] ghr;

   always_ff @(posedge clk or negedge rst_n) begin
      if (!rst_n)
         ghr <= '0;
      else if (update_en_i)
         ghr <= {ghr[GHR_WIDTH-2:0], actual_taken_i};
   end

   // =========================================================================
   // 지역 이력 테이블 (Local History Table)
   // =========================================================================
   // 각 분기 PC별로 개별 이력을 추적
   logic [LOCAL_HIST_W-1:0] local_hist_table [0:LOCAL_DEPTH-1];

   always_ff @(posedge clk or negedge rst_n) begin
      if (!rst_n) begin
         for (int i = 0; i < LOCAL_DEPTH; i++)
            local_hist_table[i] <= '0;
      end else if (update_en_i) begin
         local_hist_table[upd_idx] <=
            {local_hist_table[upd_idx][LOCAL_HIST_W-2:0], actual_taken_i};
      end
   end

   // =========================================================================
   // 지역 패턴 테이블 (Local PHT) — 2-bit 포화 카운터
   // =========================================================================
   logic [1:0] local_pht [0:GLOBAL_DEPTH-1];

   // 지역 예측: 지역 이력을 인덱스로 사용
   logic [IDX_W-1:0] local_pht_pred_idx;
   logic [IDX_W-1:0] local_pht_upd_idx;

   assign local_pht_pred_idx = local_hist_table[pred_idx][IDX_W-1:0];
   assign local_pht_upd_idx  = local_hist_table[upd_idx][IDX_W-1:0];

   logic local_prediction;
   assign local_prediction = local_pht[local_pht_pred_idx][1]; // MSB가 예측

   always_ff @(posedge clk or negedge rst_n) begin
      if (!rst_n) begin
         for (int i = 0; i < GLOBAL_DEPTH; i++)
            local_pht[i] <= 2'b01;  // 약한 Not-Taken으로 초기화
      end else if (update_en_i) begin
         // 2-bit 포화 카운터 갱신
         if (actual_taken_i && local_pht[local_pht_upd_idx] < 2'b11)
            local_pht[local_pht_upd_idx] <= local_pht[local_pht_upd_idx] + 1;
         else if (!actual_taken_i && local_pht[local_pht_upd_idx] > 2'b00)
            local_pht[local_pht_upd_idx] <= local_pht[local_pht_upd_idx] - 1;
      end
   end

   // =========================================================================
   // 전역 패턴 테이블 (Global PHT) — 2-bit 포화 카운터
   // =========================================================================
   logic [1:0] global_pht [0:GLOBAL_DEPTH-1];

   logic [IDX_W-1:0] global_pht_pred_idx;
   logic [IDX_W-1:0] global_pht_upd_idx;

   // GHR을 인덱스로 사용
   assign global_pht_pred_idx = ghr[IDX_W-1:0];
   assign global_pht_upd_idx  = ghr[IDX_W-1:0];

   logic global_prediction;
   assign global_prediction = global_pht[global_pht_pred_idx][1];

   always_ff @(posedge clk or negedge rst_n) begin
      if (!rst_n) begin
         for (int i = 0; i < GLOBAL_DEPTH; i++)
            global_pht[i] <= 2'b01;
      end else if (update_en_i) begin
         if (actual_taken_i && global_pht[global_pht_upd_idx] < 2'b11)
            global_pht[global_pht_upd_idx] <= global_pht[global_pht_upd_idx] + 1;
         else if (!actual_taken_i && global_pht[global_pht_upd_idx] > 2'b00)
            global_pht[global_pht_upd_idx] <= global_pht[global_pht_upd_idx] - 1;
      end
   end

   // =========================================================================
   // 메타 예측기 (Chooser) — 2-bit 포화 카운터
   // =========================================================================
   // 00, 01: 지역 예측기 선택 / 10, 11: 전역 예측기 선택
   logic [1:0] chooser [0:LOCAL_DEPTH-1];

   logic use_global;
   assign use_global = chooser[pred_idx][1]; // MSB로 선택

   always_ff @(posedge clk or negedge rst_n) begin
      if (!rst_n) begin
         for (int i = 0; i < LOCAL_DEPTH; i++)
            chooser[i] <= 2'b10;  // 초기: 전역 예측기 약간 선호
      end else if (update_en_i) begin
         // 두 예측기의 결과가 다를 때만 메타 예측기 갱신
         logic local_correct, global_correct;
         local_correct  = (local_pht[local_pht_upd_idx][1] == actual_taken_i);
         global_correct = (global_pht[global_pht_upd_idx][1] == actual_taken_i);

         if (local_correct && !global_correct) begin
            // 지역이 맞고 전역이 틀림 → 지역 선호도 증가 (카운터 감소)
            if (chooser[upd_idx] > 2'b00)
               chooser[upd_idx] <= chooser[upd_idx] - 1;
         end else if (!local_correct && global_correct) begin
            // 전역이 맞고 지역이 틀림 → 전역 선호도 증가 (카운터 증가)
            if (chooser[upd_idx] < 2'b11)
               chooser[upd_idx] <= chooser[upd_idx] + 1;
         end
         // 둘 다 맞거나 둘 다 틀리면 갱신하지 않음
      end
   end

   // =========================================================================
   // 최종 예측 출력
   // =========================================================================
   always_comb begin
      if (predict_en_i) begin
         predict_taken_o = use_global ? global_prediction : local_prediction;
      end else begin
         predict_taken_o = 1'b0;
      end
   end

endmodule
