// =============================================================================
// L1 명령어 캐시 (L1 Instruction Cache)
// 직접 매핑 (Direct-Mapped), 4KB, 128 엔트리, 32바이트(8워드) 블록
// Basys 3 (XC7A35T) BRAM 기반 합성 가능 설계
// =============================================================================

module l1_icache #(
   parameter ADDR_WIDTH   = 32,  // 주소 폭
   parameter DATA_WIDTH   = 32,  // 데이터 폭 (명령어 = 32비트)
   parameter CACHE_LINES  = 128, // 캐시 엔트리 수
   parameter BLOCK_WORDS  = 8,   // 블록 내 워드 수 (32바이트)
   // 자동 계산 파라미터
   parameter INDEX_WIDTH  = $clog2(CACHE_LINES),        // 7비트
   parameter OFFSET_WIDTH = $clog2(BLOCK_WORDS * 4),    // 5비트 (바이트 오프셋)
   parameter WORD_SEL     = $clog2(BLOCK_WORDS),        // 3비트 (워드 선택)
   parameter TAG_WIDTH    = ADDR_WIDTH - INDEX_WIDTH - OFFSET_WIDTH  // 20비트
)(
   input  logic                    clk,
   input  logic                    rst_n,

   // 프로세서 인터페이스 (IF 스테이지)
   input  logic [ADDR_WIDTH-1:0]   proc_addr,      // PC 주소
   input  logic                    proc_req,       // 읽기 요청
   output logic [DATA_WIDTH-1:0]   proc_rdata,     // 명령어 출력
   output logic                    icache_stall,   // 스톨 신호

   // 메모리 인터페이스 (하위 메모리)
   output logic [ADDR_WIDTH-1:0]   mem_addr,       // 메모리 주소
   output logic                    mem_req,        // 메모리 읽기 요청
   input  logic [DATA_WIDTH-1:0]   mem_rdata,      // 메모리 데이터
   input  logic                    mem_ready       // 메모리 응답 완료
);

   // =========================================================================
   // 주소 분해 (Address Decomposition)
   // [31:12] = Tag (20비트), [11:5] = Index (7비트), [4:0] = Offset (5비트)
   // =========================================================================
   logic [TAG_WIDTH-1:0]    addr_tag;
   logic [INDEX_WIDTH-1:0]  addr_index;
   logic [WORD_SEL-1:0]     addr_word_sel;  // 워드 선택 (Offset[4:2])

   assign addr_tag      = proc_addr[ADDR_WIDTH-1 : INDEX_WIDTH+OFFSET_WIDTH];
   assign addr_index    = proc_addr[INDEX_WIDTH+OFFSET_WIDTH-1 : OFFSET_WIDTH];
   assign addr_word_sel = proc_addr[OFFSET_WIDTH-1 : 2];  // 바이트 오프셋 중 워드 부분

   // =========================================================================
   // 캐시 저장소 (Cache Storage)
   // BRAM 추론을 위해 reg 배열로 선언
   // =========================================================================
   logic                              valid_array [0:CACHE_LINES-1];
   logic [TAG_WIDTH-1:0]              tag_array   [0:CACHE_LINES-1];
   logic [DATA_WIDTH-1:0]             data_array  [0:CACHE_LINES-1][0:BLOCK_WORDS-1];

   // =========================================================================
   // 히트/미스 판정 (Hit/Miss Detection)
   // =========================================================================
   logic cache_hit;
   logic tag_match;

   assign tag_match  = (tag_array[addr_index] == addr_tag);
   assign cache_hit  = valid_array[addr_index] && tag_match;

   // =========================================================================
   // 캐시 미스 처리 FSM (Cache Miss Handler FSM)
   // =========================================================================
   typedef enum logic [1:0] {
      S_IDLE     = 2'b00,   // 대기 상태
      S_FILL     = 2'b01,   // 블록 채움 상태 (메모리에서 워드 단위로 수신)
      S_DONE     = 2'b10    // 채움 완료, 태그/유효 비트 갱신
   } state_t;

   state_t                  state, next_state;
   logic [WORD_SEL-1:0]     fill_cnt;         // 현재 채우고 있는 워드 인덱스
   logic [INDEX_WIDTH-1:0]  fill_index;       // 채움 대상 캐시 인덱스
   logic [TAG_WIDTH-1:0]    fill_tag;         // 채움 대상 태그

   // 상태 레지스터
   always_ff @(posedge clk or negedge rst_n) begin
      if (!rst_n)
         state <= S_IDLE;
      else
         state <= next_state;
   end

   // 다음 상태 로직
   always_comb begin
      next_state = state;
      case (state)
         S_IDLE: begin
            if (proc_req && !cache_hit)
               next_state = S_FILL;
         end
         S_FILL: begin
            if (mem_ready && (fill_cnt == BLOCK_WORDS[WORD_SEL-1:0] - 1))
               next_state = S_DONE;
         end
         S_DONE: begin
            next_state = S_IDLE;
         end
         default: next_state = S_IDLE;
      endcase
   end

   // 채움 카운터 (Fill Counter)
   always_ff @(posedge clk or negedge rst_n) begin
      if (!rst_n) begin
         fill_cnt   <= '0;
         fill_index <= '0;
         fill_tag   <= '0;
      end else begin
         case (state)
            S_IDLE: begin
               if (proc_req && !cache_hit) begin
                  fill_cnt   <= '0;
                  fill_index <= addr_index;
                  fill_tag   <= addr_tag;
               end
            end
            S_FILL: begin
               if (mem_ready)
                  fill_cnt <= fill_cnt + 1'b1;
            end
            default: ;
         endcase
      end
   end

   // =========================================================================
   // 캐시 데이터 쓰기 (블록 채움 시)
   // =========================================================================
   always_ff @(posedge clk or negedge rst_n) begin
      if (!rst_n) begin
         // 리셋 시 모든 유효 비트를 0으로 초기화
         for (int i = 0; i < CACHE_LINES; i++) begin
            valid_array[i] <= 1'b0;
         end
      end else begin
         if (state == S_FILL && mem_ready) begin
            // 메모리에서 수신한 워드를 데이터 배열에 기록
            data_array[fill_index][fill_cnt] <= mem_rdata;
         end
         if (state == S_DONE) begin
            // 블록 채움 완료: 태그와 유효 비트 갱신
            tag_array[fill_index]   <= fill_tag;
            valid_array[fill_index] <= 1'b1;
         end
      end
   end

   // =========================================================================
   // 출력 로직
   // =========================================================================
   // 프로세서로 명령어 출력 (히트 시 캐시 데이터, 채움 완료 직후에도 사용 가능)
   assign proc_rdata = data_array[addr_index][addr_word_sel];

   // 스톨 신호: 미스가 발생하여 채움 중이면 파이프라인 정지
   assign icache_stall = proc_req && !cache_hit && (state != S_DONE);

   // 메모리 요청: 채움 상태에서 메모리에 워드 단위 요청
   assign mem_req = (state == S_FILL);

   // 메모리 주소: 블록 시작 주소 + 현재 채움 카운터 × 4
   assign mem_addr = {fill_tag, fill_index, fill_cnt, 2'b00};

endmodule
