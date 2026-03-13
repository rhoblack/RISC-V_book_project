// =============================================================================
// Chapter 15: 캐시 미스 처리 FSM (Cache Miss Handler)
// =============================================================================
// 캐시 미스 발생 시 메모리에서 캐시 라인을 읽어와 채우는 상태 머신.
// Write-Back 캐시의 dirty eviction도 처리한다.
// 합성 가능한 설계 (Xilinx Basys 3, XC7A35T)
// =============================================================================

module cache_miss_handler #(
   parameter ADDR_WIDTH   = 32,          // 주소 비트 수
   parameter DATA_WIDTH   = 32,          // 데이터 비트 수
   parameter LINE_WORDS   = 4,           // 캐시 라인 내 워드 수 (4워드 = 128비트)
   parameter BEAT_CNT_W   = $clog2(LINE_WORDS) // 버스트 카운터 비트 수
)(
   input  logic                    clk,
   input  logic                    rst_n,

   // === 캐시로부터의 요청 인터페이스 ===
   input  logic                    miss_req_i,       // 미스 요청
   input  logic                    dirty_i,          // 교체 대상 라인의 dirty 비트
   input  logic [ADDR_WIDTH-1:0]   miss_addr_i,      // 미스 발생 주소
   input  logic [ADDR_WIDTH-1:0]   writeback_addr_i, // dirty 라인의 쓰기 주소
   input  logic [DATA_WIDTH-1:0]   writeback_data_i, // dirty 라인의 쓰기 데이터 (워드 단위)
   output logic                    fill_valid_o,     // 캐시 라인 채움 데이터 유효
   output logic [DATA_WIDTH-1:0]   fill_data_o,      // 캐시 라인 채움 데이터
   output logic [BEAT_CNT_W-1:0]   fill_word_idx_o,  // 채움 워드 인덱스
   output logic                    miss_done_o,      // 미스 처리 완료
   output logic                    stall_o,          // 파이프라인 스톨 신호

   // === 메모리 버스 인터페이스 ===
   output logic                    mem_req_o,        // 메모리 요청
   output logic                    mem_write_o,      // 메모리 쓰기 (1) / 읽기 (0)
   output logic [ADDR_WIDTH-1:0]   mem_addr_o,       // 메모리 주소
   output logic [DATA_WIDTH-1:0]   mem_wdata_o,      // 메모리 쓰기 데이터
   input  logic [DATA_WIDTH-1:0]   mem_rdata_i,      // 메모리 읽기 데이터
   input  logic                    mem_valid_i,      // 메모리 응답 유효
   input  logic                    mem_ready_i       // 메모리 수신 준비
);

   // =========================================================================
   // 상태 정의
   // =========================================================================
   typedef enum logic [2:0] {
      S_IDLE       = 3'b000,   // 대기 상태
      S_COMPARE    = 3'b001,   // 태그 비교 (미스 확인)
      S_WRITEBACK  = 3'b010,   // dirty 라인을 메모리에 쓰기 (버스트)
      S_ALLOCATE   = 3'b011,   // 메모리에 읽기 요청 발행
      S_FILL       = 3'b100    // 메모리 응답으로 캐시 라인 채움
   } state_t;

   state_t state_q, state_d;

   // =========================================================================
   // 내부 레지스터
   // =========================================================================
   logic [BEAT_CNT_W-1:0] beat_cnt_q, beat_cnt_d;     // 버스트 카운터
   logic [ADDR_WIDTH-1:0] addr_q, addr_d;              // 저장된 주소
   logic [ADDR_WIDTH-1:0] wb_addr_q, wb_addr_d;        // Write-back 주소
   logic                  dirty_q, dirty_d;             // dirty 플래그 래치

   // =========================================================================
   // 상태 레지스터 (순차 논리)
   // =========================================================================
   always_ff @(posedge clk or negedge rst_n) begin
      if (!rst_n) begin
         state_q    <= S_IDLE;
         beat_cnt_q <= '0;
         addr_q     <= '0;
         wb_addr_q  <= '0;
         dirty_q    <= 1'b0;
      end else begin
         state_q    <= state_d;
         beat_cnt_q <= beat_cnt_d;
         addr_q     <= addr_d;
         wb_addr_q  <= wb_addr_d;
         dirty_q    <= dirty_d;
      end
   end

   // =========================================================================
   // 다음 상태 및 출력 논리 (조합 논리)
   // =========================================================================
   always_comb begin
      // 기본값 설정 (래치 방지)
      state_d       = state_q;
      beat_cnt_d    = beat_cnt_q;
      addr_d        = addr_q;
      wb_addr_d     = wb_addr_q;
      dirty_d       = dirty_q;

      mem_req_o     = 1'b0;
      mem_write_o   = 1'b0;
      mem_addr_o    = '0;
      mem_wdata_o   = '0;
      fill_valid_o  = 1'b0;
      fill_data_o   = '0;
      fill_word_idx_o = '0;
      miss_done_o   = 1'b0;
      stall_o       = 1'b0;

      case (state_q)
         // -----------------------------------------------------------------
         // IDLE: 미스 요청 대기
         // -----------------------------------------------------------------
         S_IDLE: begin
            if (miss_req_i) begin
               addr_d    = miss_addr_i;
               wb_addr_d = writeback_addr_i;
               dirty_d   = dirty_i;
               stall_o   = 1'b1;
               state_d   = S_COMPARE;
            end
         end

         // -----------------------------------------------------------------
         // COMPARE: 미스 유형 판별 (dirty 여부에 따라 분기)
         // -----------------------------------------------------------------
         S_COMPARE: begin
            stall_o = 1'b1;
            if (dirty_q) begin
               // dirty 라인 → Write-Back 먼저 수행
               beat_cnt_d = '0;
               state_d    = S_WRITEBACK;
            end else begin
               // clean 라인 → 바로 메모리 읽기
               beat_cnt_d = '0;
               state_d    = S_ALLOCATE;
            end
         end

         // -----------------------------------------------------------------
         // WRITEBACK: dirty 캐시 라인을 메모리에 버스트 쓰기
         // -----------------------------------------------------------------
         S_WRITEBACK: begin
            stall_o     = 1'b1;
            mem_req_o   = 1'b1;
            mem_write_o = 1'b1;
            // 워드 단위 주소 계산: base + beat_cnt * 4
            mem_addr_o  = {wb_addr_q[ADDR_WIDTH-1:$clog2(LINE_WORDS)+2],
                           beat_cnt_q, 2'b00};
            mem_wdata_o = writeback_data_i;

            if (mem_ready_i) begin
               if (beat_cnt_q == BEAT_CNT_W'(LINE_WORDS - 1)) begin
                  // Write-back 완료 → 메모리 읽기로 전환
                  beat_cnt_d = '0;
                  state_d    = S_ALLOCATE;
               end else begin
                  beat_cnt_d = beat_cnt_q + 1'b1;
               end
            end
         end

         // -----------------------------------------------------------------
         // ALLOCATE: 메모리에 캐시 라인 읽기 요청 발행
         // -----------------------------------------------------------------
         S_ALLOCATE: begin
            stall_o    = 1'b1;
            mem_req_o  = 1'b1;
            mem_write_o = 1'b0;
            // 블록 정렬 주소 (하위 비트 클리어)
            mem_addr_o = {addr_q[ADDR_WIDTH-1:$clog2(LINE_WORDS)+2],
                          {($clog2(LINE_WORDS)+2){1'b0}}};

            if (mem_ready_i) begin
               beat_cnt_d = '0;
               state_d    = S_FILL;
            end
         end

         // -----------------------------------------------------------------
         // FILL: 메모리 응답을 받아 캐시 라인 채움
         // -----------------------------------------------------------------
         S_FILL: begin
            stall_o = 1'b1;

            if (mem_valid_i) begin
               fill_valid_o    = 1'b1;
               fill_data_o     = mem_rdata_i;
               fill_word_idx_o = beat_cnt_q;

               if (beat_cnt_q == BEAT_CNT_W'(LINE_WORDS - 1)) begin
                  // 모든 워드 수신 완료
                  miss_done_o = 1'b1;
                  stall_o     = 1'b0;  // 스톨 해제
                  state_d     = S_IDLE;
               end else begin
                  beat_cnt_d = beat_cnt_q + 1'b1;
               end
            end
         end

         // -----------------------------------------------------------------
         // 기본값: 안전한 상태로 복귀
         // -----------------------------------------------------------------
         default: begin
            state_d = S_IDLE;
         end
      endcase
   end

endmodule
