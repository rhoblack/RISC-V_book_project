// =============================================================================
// Ch13: L1 직접 매핑 명령어 캐시 (Direct-Mapped L1 Instruction Cache)
// 파라미터: 4KB / 128 엔트리 / 32바이트(8워드) 블록
// Basys 3 (XC7A35T) FPGA 합성 가능 설계
// Tag  배열: LUTRAM (분산 RAM, 비동기 읽기)
// Data 배열: BRAM   (블록 RAM, 동기 읽기)
// Valid 배열: FF 배열 (동기 리셋)
//
// [수정 이력 2026-03-12]
// C-1: fill_cnt 초기화를 IDLE/DONE 상태에서 명시적 0 보장
//      (MISS→FILL 첫 사이클에 이전 잔류값으로 BRAM 쓰기 오류 방지)
// C-2: flush 포트 추가. FILL 중 flush=1이면 IDLE로 즉시 전환.
//      fill_flushed 플래그로 채우다 중단된 라인의 valid 갱신 억제.
// C-3: DONE 상태에서 cpu_rdata를 CPU가 요청한 word_offset 기준으로 반환.
//      FILL 완료 직전 사이클에 BRAM 읽기를 트리거하여 DONE 1사이클에 흡수.
// M-5: 메모리 지연 모델 단순화 — FILL_CYCLES=5 고정 카운터로 DONE 전환.
//      mem_ready는 MISS→FILL 전환 트리거로만 사용, FILL 내부는 카운터로 진행.
// =============================================================================

module icache_direct_mapped #(
   parameter CACHE_SIZE    = 4096,  // 캐시 전체 크기 (바이트)
   parameter BLOCK_SIZE    = 32,    // 블록 크기 (바이트) = 8워드
   parameter NUM_ENTRIES   = 128,   // 캐시 엔트리 수 = CACHE_SIZE / BLOCK_SIZE
   parameter ADDR_WIDTH    = 32,    // 주소 폭
   // 자동 계산 파라미터
   parameter OFFSET_WIDTH  = 5,     // log2(32) = 5비트
   parameter INDEX_WIDTH   = 7,     // log2(128) = 7비트
   parameter TAG_WIDTH     = 20,    // 32 - 5 - 7 = 20비트
   parameter WORD_SEL      = 3,     // 블록 내 워드 선택: log2(8) = 3비트
   parameter DATA_DEPTH    = 1024,  // data_mem 깊이 = 128 × 8워드
   // [M-5] 교재 단순화: 고정 채움 사이클 수 (MISS 1 + FILL 4 = 5사이클 미스 페널티)
   parameter FILL_CYCLES   = 4      // FILL 상태 사이클 수 (0~3 카운트)
)(
   input  logic                  clk,
   input  logic                  rst_n,
   // [C-2] flush 포트: FILL 중 wrong-path 명령어 검출 시 즉시 중단
   input  logic                  flush,

   // ---- 프로세서(IF 스테이지) 인터페이스 ----
   input  logic [ADDR_WIDTH-1:0] cpu_addr,      // PC 주소 (32비트)
   input  logic                  cpu_req,       // 읽기 요청
   output logic [31:0]           cpu_rdata,     // 명령어 출력
   output logic                  cache_hit,     // 히트 신호 (조합 논리)
   output logic                  icache_stall,  // 스톨 신호

   // ---- 하위 메모리 인터페이스 ----
   output logic [ADDR_WIDTH-1:0] mem_addr,      // 메모리 요청 주소
   output logic                  mem_req,       // 메모리 읽기 요청
   input  logic [31:0]           mem_rdata,     // 메모리 응답 데이터
   input  logic                  mem_ready      // 메모리 데이터 유효 신호
);

   // =========================================================================
   // 내부 신호 선언
   // =========================================================================

   // 주소 필드 추출 (조합 논리)
   wire [TAG_WIDTH-1:0]    addr_tag    = cpu_addr[31:12];  // Tag: 상위 20비트
   wire [INDEX_WIDTH-1:0]  addr_index  = cpu_addr[11:5];   // Index: 7비트
   wire [OFFSET_WIDTH-1:0] addr_offset = cpu_addr[4:0];    // Offset: 5비트
   wire [WORD_SEL-1:0]     word_offset = cpu_addr[4:2];    // 워드 Offset: 3비트

   // =========================================================================
   // 캐시 배열 선언
   // =========================================================================

   // Valid 배열: 128개 플립플롭 (동기 리셋)
   logic valid [0:NUM_ENTRIES-1];

   // Tag 배열: LUTRAM (분산 RAM, 비동기 읽기) - XST/Vivado 합성 속성
   (* ram_style = "distributed" *)
   logic [TAG_WIDTH-1:0] tag_mem [0:NUM_ENTRIES-1];

   // Data 배열: BRAM (블록 RAM, 동기 읽기) - Basys 3 BRAM36 매핑
   (* ram_style = "block" *)
   logic [31:0] data_mem [0:DATA_DEPTH-1];

   // BRAM 동기 읽기용 레지스터 (히트 시 및 DONE 시 공용)
   logic [31:0] bram_rdata_reg;

   // =========================================================================
   // 히트 판정 (조합 논리 - LUTRAM 비동기 읽기 활용)
   // =========================================================================

   assign cache_hit = valid[addr_index] && (tag_mem[addr_index] == addr_tag);

   // =========================================================================
   // FSM 상태 정의
   // =========================================================================

   typedef enum logic [1:0] {
      IDLE = 2'b00,  // 대기: 히트 or 요청 없음
      MISS = 2'b01,  // 미스: 메모리 요청 전송 (mem_ready 대기)
      FILL = 2'b10,  // 채움: FILL_CYCLES 사이클 고정 대기
      DONE = 2'b11   // 완료: 데이터 준비됨 (1사이클 후 IDLE 복귀)
   } cache_state_t;

   cache_state_t state, next_state;

   // [M-5] FILL 상태 고정 사이클 카운터 (0 ~ FILL_CYCLES-1)
   logic [1:0] fill_cnt;  // FILL_CYCLES=4이므로 2비트로 충분
   wire  fill_done = (fill_cnt == FILL_CYCLES - 1);

   // 채움 중 저장할 주소 (블록 기저 주소)
   logic [ADDR_WIDTH-1:0] miss_addr_reg;

   // [C-3] CPU가 요청한 word_offset 래치 — DONE에서 올바른 워드 반환에 사용
   logic [WORD_SEL-1:0] miss_word_offset;

   // [C-2] FILL 중 flush 발생 기록 — valid 갱신 억제에 사용
   logic fill_flushed;

   // =========================================================================
   // 출력 신호 연결
   // =========================================================================

   // icache_stall: MISS 또는 FILL 상태일 때 파이프라인 홀드
   assign icache_stall = (state == MISS) || (state == FILL);

   // mem_req: MISS 상태에서만 메모리 요청 (블록 기저 주소 요청)
   assign mem_req  = (state == MISS);

   // mem_addr: 블록 기저 주소 (하위 5비트 = 0으로 정렬)
   // 교재 단순화: 단일 블록 요청. 실제 구현에서는 버스트 전송 프로토콜 사용.
   assign mem_addr = {miss_addr_reg[31:5], 5'b00000};

   // cpu_rdata: 히트와 DONE 모두 bram_rdata_reg 사용 (word_offset 정확성 보장)
   assign cpu_rdata = bram_rdata_reg;

   // =========================================================================
   // FSM 상태 레지스터 (동기 리셋)
   // =========================================================================

   always_ff @(posedge clk) begin
      if (!rst_n) begin
         state            <= IDLE;
         fill_cnt         <= 2'b0;
         fill_flushed     <= 1'b0;
         miss_word_offset <= 3'b0;
         for (int i = 0; i < NUM_ENTRIES; i++) begin
            valid[i] <= 1'b0;
         end
      end else begin
         state <= next_state;

         // ---- miss_addr_reg, miss_word_offset 래치 ----
         // IDLE에서 미스 감지 시 주소와 요청 word_offset 모두 저장
         if (state == IDLE && cpu_req && !cache_hit) begin
            miss_addr_reg    <= cpu_addr;
            miss_word_offset <= word_offset;  // [C-3] 요청 워드 위치 기억
         end

         // ---- [C-1] fill_cnt 초기화 ----
         // IDLE 또는 DONE 상태에서 명시적으로 0 보장
         // (이전 FILL 완료 시 잔류값이 다음 MISS에 오염되는 것 방지)
         if (state == IDLE || state == DONE) begin
            fill_cnt <= 2'b0;
         end else if (state == FILL && !flush && !fill_flushed) begin
            // [M-5] FILL 중 매 사이클 카운트 증가 (mem_ready 무관)
            fill_cnt <= fill_cnt + 1'b1;
         end

         // ---- [C-2] fill_flushed 관리 ----
         // FILL 중 flush가 발생하면 세트, IDLE/DONE 진입 시 클리어
         if (state == IDLE || state == DONE) begin
            fill_flushed <= 1'b0;
         end else if ((state == MISS || state == FILL) && flush) begin
            fill_flushed <= 1'b1;
         end

         // ---- Valid, Tag 갱신 ----
         // [C-2] flush 중단된 라인은 valid 갱신 억제 (invalid 유지)
         if (state == FILL && fill_done && !flush && !fill_flushed) begin
            valid[miss_addr_reg[11:5]]   <= 1'b1;
            tag_mem[miss_addr_reg[11:5]] <= miss_addr_reg[31:12];
         end
      end
   end

   // =========================================================================
   // FSM 다음 상태 로직 (조합 논리)
   // =========================================================================

   always_comb begin
      next_state = state;

      case (state)
         IDLE: begin
            if (cpu_req && !cache_hit)
               next_state = MISS;       // 요청 있고 미스 → MISS 진입
         end
         MISS: begin
            // [C-2] flush 최우선: wrong-path 채움 즉시 취소
            if (flush)
               next_state = IDLE;
            else if (mem_ready)
               next_state = FILL;       // 메모리 응답 수신 → 채움 시작
         end
         FILL: begin
            // [C-2] FILL 중 flush: 즉시 IDLE 복귀 (채움 중단)
            if (flush)
               next_state = IDLE;
            // [M-5] 고정 FILL_CYCLES 카운터 완료 → DONE 전환
            else if (fill_done)
               next_state = DONE;
         end
         DONE: begin
            next_state = IDLE;          // 1사이클 후 즉시 IDLE 복귀
         end
         default: next_state = IDLE;
      endcase
   end

   // =========================================================================
   // BRAM 동기 쓰기: FILL 완료 시 요청 워드 기록
   // [M-5] 교재 단순화: FILL 마지막 사이클에 mem_rdata(요청 워드) 기록
   // 실제 구현: 버스트 전송으로 매 사이클 1워드씩 기록
   // =========================================================================

   // 채움 기록 주소: Index × 8 + miss_word_offset (요청 워드 위치)
   wire [9:0] fill_word_addr = {miss_addr_reg[11:5], miss_word_offset};

   always_ff @(posedge clk) begin
      if (state == FILL && fill_done && !flush && !fill_flushed && mem_ready) begin
         data_mem[fill_word_addr] <= mem_rdata;  // CPU가 요청한 워드 BRAM에 저장
      end
   end

   // =========================================================================
   // BRAM 동기 읽기 (히트 시 및 DONE 시 공용)
   // [C-3] DONE에서 올바른 word_offset 워드를 반환하기 위해
   //       FILL 완료 직전 사이클에 BRAM 읽기 주소를 미리 트리거
   // =========================================================================

   // 일반 히트 읽기 주소
   wire [9:0] read_word_addr = {addr_index, word_offset};

   // [C-3] DONE에서 사용할 읽기 주소: 미스가 발생한 슬롯의 요청 워드
   wire [9:0] done_read_addr = {miss_addr_reg[11:5], miss_word_offset};

   always_ff @(posedge clk) begin
      if (state == FILL && fill_done) begin
         // FILL 완료 직전 → DONE 진입 시 올바른 워드가 bram_rdata_reg에 준비됨
         bram_rdata_reg <= data_mem[done_read_addr];
      end else begin
         // 히트 경로: 현재 cpu_addr의 word_offset에 해당하는 워드
         bram_rdata_reg <= data_mem[read_word_addr];
      end
   end

endmodule
