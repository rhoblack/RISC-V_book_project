// ============================================================================
// Chapter 14 — 2-Way Set-Associative Write-Back D-Cache
// RISC-V 프로세서 설계 완전정복
// ============================================================================
// 설명: 2-Way 세트 연관 데이터 캐시 (Write-Back + LRU 교체 정책)
//       각 세트에 2개의 Way가 있으며, LRU 비트로 교체 대상을 결정합니다.
// 구성:
//   - 64 sets x 2 ways x 32 bytes/line = 4KB 총 용량
//   - Tag 21비트, Index 6비트, Offset 5비트
//   - Pseudo-LRU: 세트당 1비트 (최근 접근 Way의 반대편을 교체)
// 합성 대상: Xilinx Basys 3 (XC7A35T)
// ============================================================================

module dcache_2way_wb #(
   parameter ADDR_WIDTH   = 32,
   parameter NUM_SETS     = 64,           // 세트 수
   parameter NUM_WAYS     = 2,            // Way 수
   parameter BLOCK_WORDS  = 8,            // 라인당 워드 수 (32바이트)
   parameter INDEX_WIDTH  = $clog2(NUM_SETS),    // 6비트
   parameter OFFSET_WIDTH = $clog2(BLOCK_WORDS) + 2, // 5비트
   parameter TAG_WIDTH    = ADDR_WIDTH - INDEX_WIDTH - OFFSET_WIDTH // 21비트
)(
   input  logic                    clk,
   input  logic                    rst_n,

   // CPU 인터페이스
   input  logic                    cpu_req_i,
   input  logic                    cpu_write_i,
   input  logic [ADDR_WIDTH-1:0]   cpu_addr_i,
   input  logic [31:0]             cpu_wdata_i,
   input  logic [3:0]              cpu_byte_en_i,
   output logic [31:0]             cpu_rdata_o,
   output logic                    dcache_stall_o,

   // 메모리 인터페이스
   output logic                    mem_req_o,
   output logic                    mem_write_o,
   output logic [ADDR_WIDTH-1:0]   mem_addr_o,
   output logic [31:0]             mem_wdata_o,
   input  logic [31:0]             mem_rdata_i,
   input  logic                    mem_ready_i
);

   // -----------------------------------------------------------------------
   // 주소 필드 분해
   // -----------------------------------------------------------------------
   logic [TAG_WIDTH-1:0]    addr_tag;
   logic [INDEX_WIDTH-1:0]  addr_index;
   logic [2:0]              addr_word_offset;

   assign addr_tag         = cpu_addr_i[ADDR_WIDTH-1 : INDEX_WIDTH+OFFSET_WIDTH];
   assign addr_index       = cpu_addr_i[INDEX_WIDTH+OFFSET_WIDTH-1 : OFFSET_WIDTH];
   assign addr_word_offset = cpu_addr_i[OFFSET_WIDTH-1 : 2];

   // -----------------------------------------------------------------------
   // 캐시 저장소: Way 0, Way 1
   // -----------------------------------------------------------------------
   logic                         valid_array [0:NUM_WAYS-1][0:NUM_SETS-1];
   logic                         dirty_array [0:NUM_WAYS-1][0:NUM_SETS-1];
   logic [TAG_WIDTH-1:0]         tag_array   [0:NUM_WAYS-1][0:NUM_SETS-1];
   logic [31:0]                  data_array  [0:NUM_WAYS-1][0:NUM_SETS-1][0:BLOCK_WORDS-1];

   // LRU 비트: 세트당 1비트 (0=Way0이 LRU, 1=Way1이 LRU)
   logic lru_array [0:NUM_SETS-1];

   // -----------------------------------------------------------------------
   // 히트/미스 판정 (Way 0, Way 1 동시 비교)
   // -----------------------------------------------------------------------
   logic hit_way0, hit_way1;
   logic cache_hit;
   logic hit_way_sel;     // 히트된 Way (0 또는 1)
   logic replace_way_sel; // 교체 대상 Way

   assign hit_way0 = valid_array[0][addr_index] &&
                     (tag_array[0][addr_index] == addr_tag);
   assign hit_way1 = valid_array[1][addr_index] &&
                     (tag_array[1][addr_index] == addr_tag);
   assign cache_hit   = hit_way0 || hit_way1;
   assign hit_way_sel = hit_way1; // Way1 히트이면 1, Way0 히트이면 0

   // 교체 대상: LRU가 가리키는 Way
   assign replace_way_sel = lru_array[addr_index];

   // 교체 대상 Way의 Dirty 여부
   logic replace_dirty;
   assign replace_dirty = valid_array[replace_way_sel][addr_index] &&
                          dirty_array[replace_way_sel][addr_index];

   // -----------------------------------------------------------------------
   // FSM 상태 정의
   // -----------------------------------------------------------------------
   typedef enum logic [2:0] {
      S_IDLE,
      S_TAG_CHECK,
      S_WRITE_BACK,
      S_REFILL,
      S_UPDATE
   } state_t;

   state_t state, next_state;

   logic [2:0] word_cnt;
   logic       word_cnt_done;
   assign word_cnt_done = (word_cnt == BLOCK_WORDS - 1) && mem_ready_i;

   // 교체 Way를 래치 (TAG_CHECK에서 결정, 이후 상태에서 유지)
   logic latched_replace_way;

   // -----------------------------------------------------------------------
   // FSM: 상태 레지스터
   // -----------------------------------------------------------------------
   always_ff @(posedge clk or negedge rst_n) begin
      if (!rst_n)
         state <= S_IDLE;
      else
         state <= next_state;
   end

   // -----------------------------------------------------------------------
   // FSM: 다음 상태 로직
   // -----------------------------------------------------------------------
   always_comb begin
      next_state = state;
      case (state)
         S_IDLE: begin
            if (cpu_req_i)
               next_state = S_TAG_CHECK;
         end

         S_TAG_CHECK: begin
            if (cache_hit)
               next_state = S_IDLE;
            else if (replace_dirty)
               next_state = S_WRITE_BACK;
            else
               next_state = S_REFILL;
         end

         S_WRITE_BACK: begin
            if (word_cnt_done)
               next_state = S_REFILL;
         end

         S_REFILL: begin
            if (word_cnt_done)
               next_state = S_UPDATE;
         end

         S_UPDATE: begin
            next_state = S_IDLE;
         end

         default: next_state = S_IDLE;
      endcase
   end

   // -----------------------------------------------------------------------
   // 워드 카운터
   // -----------------------------------------------------------------------
   always_ff @(posedge clk or negedge rst_n) begin
      if (!rst_n)
         word_cnt <= 3'b0;
      else begin
         case (state)
            S_WRITE_BACK, S_REFILL: begin
               if (mem_ready_i)
                  word_cnt <= word_cnt + 3'b1;
            end
            default: word_cnt <= 3'b0;
         endcase
      end
   end

   // -----------------------------------------------------------------------
   // 교체 Way 래치 (TAG_CHECK 시점에 결정)
   // -----------------------------------------------------------------------
   always_ff @(posedge clk or negedge rst_n) begin
      if (!rst_n)
         latched_replace_way <= 1'b0;
      else if (state == S_TAG_CHECK && !cache_hit)
         latched_replace_way <= replace_way_sel;
   end

   // -----------------------------------------------------------------------
   // 캐시 데이터 갱신
   // -----------------------------------------------------------------------
   always_ff @(posedge clk or negedge rst_n) begin
      if (!rst_n) begin
         for (int w = 0; w < NUM_WAYS; w++) begin
            for (int s = 0; s < NUM_SETS; s++) begin
               valid_array[w][s] <= 1'b0;
               dirty_array[w][s] <= 1'b0;
            end
         end
         for (int s = 0; s < NUM_SETS; s++)
            lru_array[s] <= 1'b0;
      end else begin
         case (state)
            // 히트 시: 데이터 쓰기 + LRU 갱신
            S_TAG_CHECK: begin
               if (cache_hit) begin
                  // LRU 갱신: 접근한 Way의 반대편을 LRU로 표시
                  lru_array[addr_index] <= hit_way_sel ? 1'b0 : 1'b1;

                  if (cpu_write_i) begin
                     if (cpu_byte_en_i[0])
                        data_array[hit_way_sel][addr_index][addr_word_offset][7:0]
                           <= cpu_wdata_i[7:0];
                     if (cpu_byte_en_i[1])
                        data_array[hit_way_sel][addr_index][addr_word_offset][15:8]
                           <= cpu_wdata_i[15:8];
                     if (cpu_byte_en_i[2])
                        data_array[hit_way_sel][addr_index][addr_word_offset][23:16]
                           <= cpu_wdata_i[23:16];
                     if (cpu_byte_en_i[3])
                        data_array[hit_way_sel][addr_index][addr_word_offset][31:24]
                           <= cpu_wdata_i[31:24];
                     dirty_array[hit_way_sel][addr_index] <= 1'b1;
                  end
               end
            end

            // Refill: 교체 대상 Way에 메모리 데이터 저장
            S_REFILL: begin
               if (mem_ready_i)
                  data_array[latched_replace_way][addr_index][word_cnt]
                     <= mem_rdata_i;
            end

            // Update: 태그/제어 비트 갱신 + LRU 갱신
            S_UPDATE: begin
               valid_array[latched_replace_way][addr_index] <= 1'b1;
               dirty_array[latched_replace_way][addr_index] <= 1'b0;
               tag_array[latched_replace_way][addr_index]   <= addr_tag;
               // LRU: 새로 채운 Way의 반대편을 LRU로 표시
               lru_array[addr_index] <= latched_replace_way ? 1'b0 : 1'b1;

               if (cpu_write_i) begin
                  if (cpu_byte_en_i[0])
                     data_array[latched_replace_way][addr_index][addr_word_offset][7:0]
                        <= cpu_wdata_i[7:0];
                  if (cpu_byte_en_i[1])
                     data_array[latched_replace_way][addr_index][addr_word_offset][15:8]
                        <= cpu_wdata_i[15:8];
                  if (cpu_byte_en_i[2])
                     data_array[latched_replace_way][addr_index][addr_word_offset][23:16]
                        <= cpu_wdata_i[23:16];
                  if (cpu_byte_en_i[3])
                     data_array[latched_replace_way][addr_index][addr_word_offset][31:24]
                        <= cpu_wdata_i[31:24];
                  dirty_array[latched_replace_way][addr_index] <= 1'b1;
               end
            end

            default: ;
         endcase
      end
   end

   // -----------------------------------------------------------------------
   // 출력 로직
   // -----------------------------------------------------------------------
   // CPU 읽기 데이터: 히트된 Way에서 선택
   assign cpu_rdata_o = cache_hit ?
      data_array[hit_way_sel][addr_index][addr_word_offset] :
      data_array[latched_replace_way][addr_index][addr_word_offset];

   // 스톨 신호
   assign dcache_stall_o = (state != S_IDLE) &&
                           !(state == S_TAG_CHECK && cache_hit);

   // 메모리 인터페이스
   always_comb begin
      mem_req_o   = 1'b0;
      mem_write_o = 1'b0;
      mem_addr_o  = '0;
      mem_wdata_o = '0;

      case (state)
         S_WRITE_BACK: begin
            mem_req_o   = 1'b1;
            mem_write_o = 1'b1;
            mem_addr_o  = {tag_array[latched_replace_way][addr_index],
                          addr_index, word_cnt, 2'b00};
            mem_wdata_o = data_array[latched_replace_way][addr_index][word_cnt];
         end

         S_REFILL: begin
            mem_req_o   = 1'b1;
            mem_write_o = 1'b0;
            mem_addr_o  = {addr_tag, addr_index, word_cnt, 2'b00};
         end

         default: ;
      endcase
   end

endmodule
