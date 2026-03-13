// ============================================================================
// Chapter 14 — Write-Back Direct-Mapped D-Cache
// RISC-V 프로세서 설계 완전정복
// ============================================================================
// 설명: Write-Back 정책을 사용하는 직접 매핑 데이터 캐시
//       Dirty 비트를 통해 수정된 캐시 라인을 추적하고,
//       Eviction 시 메모리에 기록(Write-Back)합니다.
// 파라미터:
//   ADDR_WIDTH  = 32비트 주소
//   CACHE_LINES = 128 (캐시 라인 수)
//   BLOCK_WORDS = 8  (캐시 라인당 워드 수 = 32바이트)
// 합성 대상: Xilinx Basys 3 (XC7A35T)
// ============================================================================

module dcache_direct_mapped_wb #(
   parameter ADDR_WIDTH   = 32,
   parameter CACHE_LINES  = 128,          // 캐시 라인 수
   parameter BLOCK_WORDS  = 8,            // 라인당 워드 수 (32바이트)
   parameter INDEX_WIDTH  = $clog2(CACHE_LINES),  // 7비트
   parameter OFFSET_WIDTH = $clog2(BLOCK_WORDS) + 2, // 5비트 (워드 오프셋 + 바이트 오프셋)
   parameter TAG_WIDTH    = ADDR_WIDTH - INDEX_WIDTH - OFFSET_WIDTH // 20비트
)(
   input  logic                    clk,
   input  logic                    rst_n,

   // CPU 인터페이스 (MEM 스테이지)
   input  logic                    cpu_req_i,      // 캐시 요청
   input  logic                    cpu_write_i,    // 1=쓰기, 0=읽기
   input  logic [ADDR_WIDTH-1:0]   cpu_addr_i,     // 주소
   input  logic [31:0]             cpu_wdata_i,    // 쓰기 데이터
   input  logic [3:0]              cpu_byte_en_i,  // 바이트 인에이블
   output logic [31:0]             cpu_rdata_o,    // 읽기 데이터
   output logic                    dcache_stall_o, // 스톨 신호

   // 메모리 인터페이스 (하위 메모리)
   output logic                    mem_req_o,      // 메모리 요청
   output logic                    mem_write_o,    // 메모리 쓰기
   output logic [ADDR_WIDTH-1:0]   mem_addr_o,     // 메모리 주소
   output logic [31:0]             mem_wdata_o,    // 메모리 쓰기 데이터
   input  logic [31:0]             mem_rdata_i,    // 메모리 읽기 데이터
   input  logic                    mem_ready_i     // 메모리 준비 완료
);

   // -----------------------------------------------------------------------
   // 주소 필드 분해
   // -----------------------------------------------------------------------
   logic [TAG_WIDTH-1:0]    addr_tag;
   logic [INDEX_WIDTH-1:0]  addr_index;
   logic [2:0]              addr_word_offset; // 블록 내 워드 인덱스

   assign addr_tag         = cpu_addr_i[ADDR_WIDTH-1 : INDEX_WIDTH+OFFSET_WIDTH];
   assign addr_index       = cpu_addr_i[INDEX_WIDTH+OFFSET_WIDTH-1 : OFFSET_WIDTH];
   assign addr_word_offset = cpu_addr_i[OFFSET_WIDTH-1 : 2]; // 워드 오프셋

   // -----------------------------------------------------------------------
   // 캐시 저장소: Valid, Dirty, Tag, Data
   // -----------------------------------------------------------------------
   logic                         valid_array [0:CACHE_LINES-1];
   logic                         dirty_array [0:CACHE_LINES-1];
   logic [TAG_WIDTH-1:0]         tag_array   [0:CACHE_LINES-1];
   logic [31:0]                  data_array  [0:CACHE_LINES-1][0:BLOCK_WORDS-1];

   // -----------------------------------------------------------------------
   // 히트/미스 판정
   // -----------------------------------------------------------------------
   logic cache_hit;
   logic cache_dirty;

   assign cache_hit   = valid_array[addr_index] &&
                         (tag_array[addr_index] == addr_tag);
   assign cache_dirty = valid_array[addr_index] && dirty_array[addr_index];

   // -----------------------------------------------------------------------
   // FSM 상태 정의
   // -----------------------------------------------------------------------
   typedef enum logic [2:0] {
      S_IDLE,        // 대기 상태
      S_TAG_CHECK,   // 태그 비교
      S_WRITE_BACK,  // Dirty 라인 메모리 기록
      S_REFILL,      // 메모리에서 캐시 라인 읽기
      S_UPDATE       // 캐시 갱신 완료
   } state_t;

   state_t state, next_state;

   // 워드 카운터: Write-Back/Refill 시 블록 내 워드 인덱스
   logic [2:0] word_cnt;
   logic       word_cnt_done;

   assign word_cnt_done = (word_cnt == BLOCK_WORDS - 1) && mem_ready_i;

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
               next_state = S_IDLE;      // 히트: 즉시 완료
            else if (cache_dirty)
               next_state = S_WRITE_BACK; // 미스 + Dirty: 먼저 기록
            else
               next_state = S_REFILL;     // 미스 + Clean: 바로 채움
         end

         S_WRITE_BACK: begin
            if (word_cnt_done)
               next_state = S_REFILL;     // Write-Back 완료 후 Refill
         end

         S_REFILL: begin
            if (word_cnt_done)
               next_state = S_UPDATE;     // Refill 완료
         end

         S_UPDATE: begin
            next_state = S_IDLE;          // 캐시 갱신 후 복귀
         end

         default: next_state = S_IDLE;
      endcase
   end

   // -----------------------------------------------------------------------
   // 워드 카운터 제어
   // -----------------------------------------------------------------------
   always_ff @(posedge clk or negedge rst_n) begin
      if (!rst_n) begin
         word_cnt <= 3'b0;
      end else begin
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
   // 캐시 데이터 갱신 (Write Hit 및 Refill)
   // -----------------------------------------------------------------------
   always_ff @(posedge clk or negedge rst_n) begin
      if (!rst_n) begin
         for (int i = 0; i < CACHE_LINES; i++) begin
            valid_array[i] <= 1'b0;
            dirty_array[i] <= 1'b0;
         end
      end else begin
         case (state)
            // 히트 시 쓰기: Dirty 비트 설정
            S_TAG_CHECK: begin
               if (cache_hit && cpu_write_i) begin
                  // 바이트 인에이블에 따른 부분 쓰기
                  if (cpu_byte_en_i[0])
                     data_array[addr_index][addr_word_offset][7:0]
                        <= cpu_wdata_i[7:0];
                  if (cpu_byte_en_i[1])
                     data_array[addr_index][addr_word_offset][15:8]
                        <= cpu_wdata_i[15:8];
                  if (cpu_byte_en_i[2])
                     data_array[addr_index][addr_word_offset][23:16]
                        <= cpu_wdata_i[23:16];
                  if (cpu_byte_en_i[3])
                     data_array[addr_index][addr_word_offset][31:24]
                        <= cpu_wdata_i[31:24];
                  dirty_array[addr_index] <= 1'b1; // Dirty 표시
               end
            end

            // Refill: 메모리에서 읽은 데이터를 캐시에 저장
            S_REFILL: begin
               if (mem_ready_i)
                  data_array[addr_index][word_cnt] <= mem_rdata_i;
            end

            // Update: 태그와 제어 비트 갱신
            S_UPDATE: begin
               valid_array[addr_index] <= 1'b1;
               dirty_array[addr_index] <= 1'b0; // 새로 채운 라인은 Clean
               tag_array[addr_index]   <= addr_tag;
               // Store 미스였다면 새 데이터도 기록
               if (cpu_write_i) begin
                  if (cpu_byte_en_i[0])
                     data_array[addr_index][addr_word_offset][7:0]
                        <= cpu_wdata_i[7:0];
                  if (cpu_byte_en_i[1])
                     data_array[addr_index][addr_word_offset][15:8]
                        <= cpu_wdata_i[15:8];
                  if (cpu_byte_en_i[2])
                     data_array[addr_index][addr_word_offset][23:16]
                        <= cpu_wdata_i[23:16];
                  if (cpu_byte_en_i[3])
                     data_array[addr_index][addr_word_offset][31:24]
                        <= cpu_wdata_i[31:24];
                  dirty_array[addr_index] <= 1'b1;
               end
            end

            default: ; // 아무 동작 없음
         endcase
      end
   end

   // -----------------------------------------------------------------------
   // 출력 로직
   // -----------------------------------------------------------------------
   // CPU 읽기 데이터
   assign cpu_rdata_o = data_array[addr_index][addr_word_offset];

   // 스톨 신호: IDLE 이외 상태에서 활성화
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
            // Eviction 주소: 기존 태그 + 현재 인덱스 + 워드 오프셋
            mem_addr_o  = {tag_array[addr_index], addr_index,
                          word_cnt, 2'b00};
            mem_wdata_o = data_array[addr_index][word_cnt];
         end

         S_REFILL: begin
            mem_req_o   = 1'b1;
            mem_write_o = 1'b0;
            // Refill 주소: 새 태그 + 현재 인덱스 + 워드 오프셋
            mem_addr_o  = {addr_tag, addr_index, word_cnt, 2'b00};
         end

         default: ; // 메모리 요청 없음
      endcase
   end

endmodule
