// ============================================================
// ch15_cache_system.sv
// 파이프라인 + I-Cache + D-Cache + 메모리 컨트롤러 통합 top 모듈
//
// 구성:
//   - rv32i_pipeline_complete : Ch09~12에서 완성한 파이프라인
//   - icache_ch15             : WAIT_GRANT 추가된 I-Cache FSM (Ch13 수정본)
//   - dcache_ch15             : WAIT_GRANT 추가된 D-Cache FSM (Ch14 수정본)
//   - mem_controller          : 중재기 + Main SRAM (DRAIN 상태 포함)
//   - perf_counter            : 성능 카운터 (CPI 측정용)
//
// 미스 페널티 (BRAM 동기 읽기 1사이클 지연 반영):
//   I-Cache / D-Cache Clean : 12사이클 (1+1+8+1DRAIN+1)
//   D-Cache Dirty           : 22사이클 (1+1+8+1DRAIN+1+8+1DRAIN+1)
// ============================================================

module cache_system #(
   parameter DATA_WIDTH = 32,
   parameter ADDR_WIDTH = 32
)(
   input  logic        clk,
   input  logic        rst_n,

   // FPGA 외부 인터페이스 (Basys 3)
   input  logic [15:0] sw,         // 스위치 (입력)
   output logic [15:0] led,        // LED (성능 표시)
   output logic [ 6:0] seg,        // 7-세그먼트
   output logic [ 3:0] an          // 7-세그먼트 자릿수 선택
);

   // ============================================================
   // 내부 신호 선언
   // ============================================================

   // 파이프라인 ↔ I-Cache
   logic [ADDR_WIDTH-1:0] pc_o;           // 현재 PC (명령어 요청 주소)
   logic [DATA_WIDTH-1:0] instr_i;        // 캐시에서 받은 명령어
   logic                  icache_stall;   // I-Cache 미스 스톨

   // 파이프라인 ↔ D-Cache
   logic                  dmem_req;       // 데이터 메모리 요청
   logic                  dmem_wen;       // 쓰기 인에이블
   logic [ADDR_WIDTH-1:0] dmem_addr;      // 데이터 주소
   logic [DATA_WIDTH-1:0] dmem_wdata;     // 쓰기 데이터
   logic [ 3:0]           dmem_be;        // Byte Enable (funct3 기반)
   logic [DATA_WIDTH-1:0] dmem_rdata;     // 읽기 데이터
   logic                  dcache_stall;   // D-Cache 미스 스톨

   // 파이프라인 스톨 통합
   logic                  load_use_stall; // Load-Use 해저드 스톨
   logic                  pipeline_stall; // 통합 스톨 신호
   assign pipeline_stall = load_use_stall || icache_stall || dcache_stall;

   // I-Cache ↔ 메모리 컨트롤러
   logic                  icache_req_mem;
   logic [ADDR_WIDTH-1:0] icache_addr_mem;
   logic                  icache_ack_mem;
   logic [DATA_WIDTH-1:0] icache_rdata_mem;
   logic                  icache_grant;

   // D-Cache ↔ 메모리 컨트롤러
   logic                  dcache_req_mem;
   logic                  dcache_wen_mem;
   logic [ADDR_WIDTH-1:0] dcache_addr_mem;
   logic [DATA_WIDTH-1:0] dcache_wdata_mem;
   logic                  dcache_ack_mem;
   logic [DATA_WIDTH-1:0] dcache_rdata_mem;
   logic                  dcache_grant;

   // ============================================================
   // 파이프라인 프로세서 (Ch09~12 완성본)
   // ============================================================
   rv32i_pipeline_complete #(
      .DATA_WIDTH(DATA_WIDTH),
      .ADDR_WIDTH(ADDR_WIDTH)
   ) u_pipeline (
      .clk            (clk),
      .rst_n          (rst_n),
      // I-Cache 인터페이스
      .pc_o           (pc_o),
      .instr_i        (instr_i),
      .icache_stall_i (icache_stall),
      // D-Cache 인터페이스
      .dmem_req_o     (dmem_req),
      .dmem_wen_o     (dmem_wen),
      .dmem_addr_o    (dmem_addr),
      .dmem_wdata_o   (dmem_wdata),
      .dmem_be_o      (dmem_be),
      .dmem_rdata_i   (dmem_rdata),
      .dcache_stall_i (dcache_stall),
      // 해저드 제어
      .load_use_stall_o (load_use_stall)
   );

   // ============================================================
   // I-Cache (Ch13 수정본 — WAIT_GRANT 상태 추가)
   // FSM: IDLE → MISS → WAIT_GRANT → FILL(×8) → DONE → IDLE
   // ============================================================
   icache_ch15 #(
      .DATA_WIDTH(DATA_WIDTH),
      .ADDR_WIDTH(ADDR_WIDTH)
   ) u_icache (
      .clk          (clk),
      .rst_n        (rst_n),
      .flush_i      (1'b0),           // 분기 플러시 (간단화)
      // CPU 인터페이스
      .cpu_req_i    (1'b1),           // 항상 명령어 요청
      .cpu_addr_i   (pc_o),
      .cpu_rdata_o  (instr_i),
      .icache_stall_o (icache_stall),
      // 메모리 컨트롤러 인터페이스
      .mem_req_o    (icache_req_mem),
      .mem_addr_o   (icache_addr_mem),
      .mem_grant_i  (icache_grant),
      .mem_ack_i    (icache_ack_mem),
      .mem_rdata_i  (icache_rdata_mem)
   );

   // ============================================================
   // D-Cache (Ch14 수정본 — WAIT_GRANT 상태 추가)
   // FSM: IDLE → TAG_CHECK → [dirty?] WAIT_WB_GRANT →
   //      WRITE_BACK(×8) → WAIT_REFILL_GRANT → REFILL(×8) → UPDATE
   // ============================================================
   dcache_ch15 #(
      .DATA_WIDTH(DATA_WIDTH),
      .ADDR_WIDTH(ADDR_WIDTH)
   ) u_dcache (
      .clk          (clk),
      .rst_n        (rst_n),
      // CPU 인터페이스
      .cpu_req_i    (dmem_req),
      .cpu_wen_i    (dmem_wen),
      .cpu_addr_i   (dmem_addr),
      .cpu_wdata_i  (dmem_wdata),
      .cpu_be_i     (dmem_be),
      .cpu_rdata_o  (dmem_rdata),
      .dcache_stall_o (dcache_stall),
      // 메모리 컨트롤러 인터페이스
      .mem_req_o    (dcache_req_mem),
      .mem_wen_o    (dcache_wen_mem),
      .mem_addr_o   (dcache_addr_mem),
      .mem_wdata_o  (dcache_wdata_mem),
      .mem_grant_i  (dcache_grant),
      .mem_ack_i    (dcache_ack_mem),
      .mem_rdata_i  (dcache_rdata_mem)
   );

   // ============================================================
   // 메모리 컨트롤러 (중재기 + Main SRAM)
   // ============================================================
   mem_controller #(
      .DATA_WIDTH(DATA_WIDTH),
      .ADDR_WIDTH(ADDR_WIDTH),
      .MEM_DEPTH (16384),
      .BURST_LEN (8)
   ) u_mem_ctrl (
      .clk            (clk),
      .rst_n          (rst_n),
      // I-Cache 포트
      .icache_req_i   (icache_req_mem),
      .icache_addr_i  (icache_addr_mem),
      .icache_ack_o   (icache_ack_mem),
      .icache_rdata_o (icache_rdata_mem),
      .icache_grant_o (icache_grant),
      // D-Cache 포트
      .dcache_req_i   (dcache_req_mem),
      .dcache_wen_i   (dcache_wen_mem),
      .dcache_addr_i  (dcache_addr_mem),
      .dcache_wdata_i (dcache_wdata_mem),
      .dcache_ack_o   (dcache_ack_mem),
      .dcache_rdata_o (dcache_rdata_mem),
      .dcache_grant_o (dcache_grant)
   );

   // ============================================================
   // 성능 카운터 (perf_counter)
   // ============================================================
   logic [31:0] cycle_cnt;       // 총 클록 사이클 수
   logic [31:0] instr_cnt;       // 완료된 명령어 수 (은퇴 카운터)
   logic [31:0] icache_miss_cnt; // I-Cache 미스 횟수
   logic [31:0] dcache_miss_cnt; // D-Cache 미스 횟수

   // 사이클 카운터
   always_ff @(posedge clk or negedge rst_n) begin
      if (!rst_n)
         cycle_cnt <= '0;
      else
         cycle_cnt <= cycle_cnt + 1'b1;
   end

   // 명령어 진행 카운터 (파이프라인이 진행할 때만 카운트)
   // 주의: 이 카운터는 WB 스테이지 은퇴(retire) 카운터가 아니라
   //       파이프라인 진행 사이클 카운터이다.
   //       분기 플러시로 삽입된 버블(NOP=32'h0000_0013)이 포함되어
   //       실제 완료 명령어보다 많이 카운트될 수 있으므로
   //       계산된 CPI가 실제보다 낮게 표시될 수 있다.
   //       정확한 CPI가 필요하면 WB 스테이지 instr_valid 신호를 사용할 것.
   always_ff @(posedge clk or negedge rst_n) begin
      if (!rst_n)
         instr_cnt <= '0;
      else if (!pipeline_stall)
         instr_cnt <= instr_cnt + 1'b1;
   end

   // I-Cache 미스 카운터
   always_ff @(posedge clk or negedge rst_n) begin
      if (!rst_n)
         icache_miss_cnt <= '0;
      else if (icache_req_mem && icache_grant)  // 새 미스 발생 (GRANT 시점)
         icache_miss_cnt <= icache_miss_cnt + 1'b1;
   end

   // D-Cache 미스 카운터
   always_ff @(posedge clk or negedge rst_n) begin
      if (!rst_n)
         dcache_miss_cnt <= '0;
      else if (dcache_req_mem && dcache_grant)  // 새 미스 발생 (GRANT 시점)
         dcache_miss_cnt <= dcache_miss_cnt + 1'b1;
   end

   // ── LED: 하위 16비트 = 사이클 카운터 하위 16비트 ──
   assign led = cycle_cnt[15:0];

   // ── 7-세그먼트: CPI 정수부 표시 (간단화) ──────────
   // 실제 FPGA에서는 분주기 + 세그먼트 디코더 필요
   assign seg = 7'b1111111; // 우선 OFF
   assign an  = 4'b1111;

endmodule

// ============================================================
// icache_ch15.sv (Ch13 I-Cache의 WAIT_GRANT 추가 수정본)
// FSM: IDLE → MISS → WAIT_GRANT → FILL(0~7) → DONE → IDLE
// ============================================================
module icache_ch15 #(
   parameter DATA_WIDTH  = 32,
   parameter ADDR_WIDTH  = 32,
   parameter CACHE_SETS  = 128,       // 직접 매핑 128엔트리
   parameter BLOCK_WORDS = 8          // 블록당 워드 수 (32바이트)
)(
   input  logic                  clk,
   input  logic                  rst_n,
   input  logic                  flush_i,

   // CPU 인터페이스
   input  logic                  cpu_req_i,
   input  logic [ADDR_WIDTH-1:0] cpu_addr_i,
   output logic [DATA_WIDTH-1:0] cpu_rdata_o,
   output logic                  icache_stall_o,

   // 메모리 컨트롤러 인터페이스
   output logic                  mem_req_o,
   output logic [ADDR_WIDTH-1:0] mem_addr_o,
   input  logic                  mem_grant_i,   // 중재기 승인
   input  logic                  mem_ack_i,     // 데이터 유효
   input  logic [DATA_WIDTH-1:0] mem_rdata_i    // 읽기 데이터
);

   // 주소 분해: Tag[31:12]=20비트, Index[11:5]=7비트, Offset[4:2]=3비트(워드)
   localparam TAG_W    = 20;
   localparam INDEX_W  = 7;
   localparam OFFSET_W = 3;   // 워드 오프셋 (하위 2비트는 바이트)

   logic [TAG_W-1:0]    addr_tag;
   logic [INDEX_W-1:0]  addr_index;
   logic [OFFSET_W-1:0] addr_offset;
   assign addr_tag    = cpu_addr_i[31:12];
   assign addr_index  = cpu_addr_i[11:5];
   assign addr_offset = cpu_addr_i[4:2];

   // 캐시 태그·유효 배열 (LUTRAM)
   logic [TAG_W-1:0] tag_array  [0:CACHE_SETS-1];
   logic             valid_array[0:CACHE_SETS-1];

   // 캐시 데이터 배열 (BRAM — 128세트 × 8워드)
   (* ram_style = "block" *)
   logic [DATA_WIDTH-1:0] data_array[0:CACHE_SETS*BLOCK_WORDS-1];

   // 히트 판정
   logic cache_hit;
   assign cache_hit = valid_array[addr_index] &&
                      (tag_array[addr_index] == addr_tag);

   // ── FSM ─────────────────────────────────────────────
   typedef enum logic [2:0] {
      S_IDLE       = 3'b000,
      S_MISS       = 3'b001,   // 미스 감지, mem_req 발송
      S_WAIT_GRANT = 3'b010,   // 중재기 승인 대기 (Ch15 신규)
      S_FILL       = 3'b011,   // 8-beat 버스트 수신
      S_DONE       = 3'b100    // 완료, 1사이클 후 IDLE
   } icache_state_t;

   icache_state_t state, next_state;
   logic [2:0] beat_cnt;   // 0~7

   // 래치된 요청 주소 (WAIT_GRANT 이후에도 유지)
   logic [ADDR_WIDTH-1:0] miss_addr_lat;

   always_ff @(posedge clk or negedge rst_n) begin
      if (!rst_n) begin
         state <= S_IDLE;
         beat_cnt <= '0;
         miss_addr_lat <= '0;
      end else begin
         state <= next_state;
         // 미스 주소 래치: MISS 진입 시 저장
         if (state == S_IDLE && cpu_req_i && !cache_hit)
            miss_addr_lat <= {cpu_addr_i[ADDR_WIDTH-1:5], 5'b0};
         // beat 카운터 초기화: IDLE 또는 DONE 진입 시 명시적으로 0 리셋
         // S_FILL 중 beat_cnt==7에서 S_DONE으로 전이하는 동시에
         // beat_cnt가 3'b111 → 다음 사이클 S_DONE에서 '0으로 리셋됨.
         // 오버플로우(3'b000)가 일시 발생하지만 S_DONE에서 즉시 리셋되므로
         // 기능상 문제없음. IDLE 진입 시에도 명시적으로 초기화.
         if (state == S_IDLE || state == S_DONE)
            beat_cnt <= 3'd0;
         else if (state == S_FILL && mem_ack_i)
            beat_cnt <= beat_cnt + 1'b1;
         // FILL 중 flush 시 캐시 라인 무효화
         if (flush_i && state == S_FILL)
            valid_array[miss_addr_lat[11:5]] <= 1'b0;
      end
   end

   always_comb begin
      next_state = state;
      case (state)
         S_IDLE:       if (cpu_req_i && !cache_hit) next_state = S_MISS;
         S_MISS:       if (flush_i)   next_state = S_IDLE;
                       else            next_state = S_WAIT_GRANT;
         S_WAIT_GRANT: if (flush_i)   next_state = S_IDLE;
                       else if (mem_grant_i) next_state = S_FILL;
         S_FILL:       if (flush_i)   next_state = S_IDLE;
                       else if (mem_ack_i && beat_cnt == 3'd7) next_state = S_DONE;
         S_DONE:                       next_state = S_IDLE;
         default:                      next_state = S_IDLE;
      endcase
   end

   // ── 스톨 신호 ───────────────────────────────────────
   assign icache_stall_o = (state == S_MISS) || (state == S_WAIT_GRANT) || (state == S_FILL);

   // ── 메모리 요청 ─────────────────────────────────────
   assign mem_req_o  = (state == S_MISS) || (state == S_WAIT_GRANT);
   assign mem_addr_o = miss_addr_lat;

   // ── FILL: BRAM에 데이터 기록 ────────────────────────
   // 타이밍 보장 (mem_controller의 DRAIN 상태 덕분에):
   //   S_FILL 상태에서 mem_ack_i는 총 8사이클 발생 (beat 0~7).
   //   beat_cnt==7이고 mem_ack_i==1인 사이클 → next_state = S_DONE.
   //   이 사이클에 data_array[7]과 tag_array/valid_array가 동시에 갱신됨.
   //   다음 사이클 S_DONE에서 valid_array==1이고 icache_stall_o==0이므로
   //   CPU는 S_DONE 사이클 즉시 캐시를 히트로 읽을 수 있다.
   //   → S_DONE 진입 시 cache_hit=1이 보장됨 (valid+tag 이미 갱신).
   always_ff @(posedge clk) begin
      if (state == S_FILL && mem_ack_i) begin
         data_array[{miss_addr_lat[11:5], beat_cnt}] <= mem_rdata_i;
         // 마지막 beat(beat_cnt==7)에서 Tag/Valid를 data_array와 동일 클록 엣지에 갱신
         // S_DONE 진입 후 CPU 읽기 가능
         if (beat_cnt == 3'd7) begin
            tag_array  [miss_addr_lat[11:5]] <= miss_addr_lat[31:12];
            valid_array[miss_addr_lat[11:5]] <= 1'b1;
         end
      end
   end

   // ── CPU 읽기 데이터 출력 ─────────────────────────────
   assign cpu_rdata_o = data_array[{addr_index, addr_offset}];

   // ── 초기화 ───────────────────────────────────────────
   integer i_init;
   initial begin
      for (i_init = 0; i_init < CACHE_SETS; i_init++) begin
         valid_array[i_init] = 1'b0;
         tag_array  [i_init] = '0;
      end
   end

endmodule

// ============================================================
// dcache_ch15.sv (Ch14 D-Cache의 WAIT_GRANT 상태 추가 수정본)
// FSM: IDLE → TAG_CHECK → [dirty?] WAIT_WB_GRANT →
//      WRITE_BACK(×8) → WAIT_REFILL_GRANT → REFILL(×8) → UPDATE
// ============================================================
module dcache_ch15 #(
   parameter DATA_WIDTH   = 32,
   parameter ADDR_WIDTH   = 32,
   parameter CACHE_SETS   = 64,    // 2-Way, 64세트 = 4KB
   parameter WAYS         = 2,
   parameter BLOCK_WORDS  = 8
)(
   input  logic                  clk,
   input  logic                  rst_n,

   // CPU 인터페이스
   input  logic                  cpu_req_i,
   input  logic                  cpu_wen_i,
   input  logic [ADDR_WIDTH-1:0] cpu_addr_i,
   input  logic [DATA_WIDTH-1:0] cpu_wdata_i,
   input  logic [ 3:0]           cpu_be_i,
   output logic [DATA_WIDTH-1:0] cpu_rdata_o,
   output logic                  dcache_stall_o,

   // 메모리 컨트롤러 인터페이스
   output logic                  mem_req_o,
   output logic                  mem_wen_o,
   output logic [ADDR_WIDTH-1:0] mem_addr_o,
   output logic [DATA_WIDTH-1:0] mem_wdata_o,
   input  logic                  mem_grant_i,
   input  logic                  mem_ack_i,
   input  logic [DATA_WIDTH-1:0] mem_rdata_i
);

   // 주소 분해: Tag[31:11]=21비트, Index[10:5]=6비트, Offset[4:2]=3비트
   localparam TAG_W    = 21;
   localparam INDEX_W  = 6;
   localparam OFFSET_W = 3;

   logic [TAG_W-1:0]    addr_tag;
   logic [INDEX_W-1:0]  addr_index;
   logic [OFFSET_W-1:0] addr_offset;
   assign addr_tag    = cpu_addr_i[31:11];
   assign addr_index  = cpu_addr_i[10:5];
   assign addr_offset = cpu_addr_i[4:2];

   // 캐시 태그·유효·Dirty 배열 (LUTRAM, 2-Way)
   logic [TAG_W-1:0] tag_array  [0:WAYS-1][0:CACHE_SETS-1];
   logic             valid_array[0:WAYS-1][0:CACHE_SETS-1];
   logic             dirty_array[0:WAYS-1][0:CACHE_SETS-1];

   // LRU 비트 (세트당 1비트: 0=Way0 LRU, 1=Way1 LRU)
   logic lru_array[0:CACHE_SETS-1];

   // 캐시 데이터 배열 (2-Way)
   // Write-Back 시 mem_wdata_o를 조합 논리로 읽어야 하므로 LUTRAM(distributed) 사용.
   // LUTRAM은 조합 읽기를 지원하여 Write-Back 데이터를 1사이클 지연 없이 출력 가능.
   // Basys 3(Artix-7)에서 64세트×8워드×32비트×2Way = 32768비트 = 약 256 LUT6 소비.
   // 추후 성능 최적화가 필요하면 BRAM으로 교체하되
   // WRITE_BACK 상태 진입 전 사이클에 미리 읽기를 시작하는 파이프라인 구조 필요.
   (* ram_style = "distributed" *)
   logic [DATA_WIDTH-1:0] data_array[0:WAYS-1][0:CACHE_SETS*BLOCK_WORDS-1];

   // 히트 판정
   logic [WAYS-1:0] hit_way;
   logic            cache_hit;
   logic            hit_way_sel;  // 히트된 Way 인덱스
   genvar w;
   generate
      for (w = 0; w < WAYS; w++) begin : gen_hit
         assign hit_way[w] = valid_array[w][addr_index] &&
                             (tag_array[w][addr_index] == addr_tag);
      end
   endgenerate
   assign cache_hit   = |hit_way;
   assign hit_way_sel = hit_way[1]; // Way1 히트 시 1, Way0 히트 시 0

   // 교체 Way 결정 (LRU)
   logic replace_way_sel;
   assign replace_way_sel = lru_array[addr_index]; // LRU Way 교체

   // Dirty 확인
   logic replace_dirty;
   assign replace_dirty = dirty_array[replace_way_sel][addr_index] &&
                          valid_array[replace_way_sel][addr_index];

   // ── FSM ─────────────────────────────────────────────
   typedef enum logic [2:0] {
      S_IDLE            = 3'b000,
      S_TAG_CHECK       = 3'b001,
      S_WAIT_WB_GRANT   = 3'b010,   // Write-Back 버스 승인 대기 (Ch15 신규)
      S_WRITE_BACK      = 3'b011,   // Dirty 라인 메모리 기록 (8-beat)
      S_WAIT_REFILL_GNT = 3'b100,   // REFILL 버스 승인 대기 (Ch15 신규)
      S_REFILL          = 3'b101,   // 새 캐시 라인 채움 (8-beat)
      S_UPDATE          = 3'b110    // 캐시 갱신 완료
   } dcache_state_t;

   dcache_state_t state, next_state;
   logic [2:0]          word_cnt;          // 버스트 카운터 0~7
   logic                latched_replace_way; // TAG_CHECK 시 결정 래치
   logic [ADDR_WIDTH-1:0] latched_wb_addr;  // Write-Back 대상 주소 래치
   logic [ADDR_WIDTH-1:0] latched_new_addr; // REFILL 대상 주소 래치

   always_ff @(posedge clk or negedge rst_n) begin
      if (!rst_n) begin
         state <= S_IDLE;
         word_cnt <= '0;
         latched_replace_way <= 1'b0;
         latched_wb_addr     <= '0;
         latched_new_addr    <= '0;
      end else begin
         state <= next_state;
         // TAG_CHECK 시 교체 Way 및 주소 래치
         if (state == S_TAG_CHECK && !cache_hit) begin
            latched_replace_way <= replace_way_sel;
            latched_wb_addr     <= {tag_array[replace_way_sel][addr_index], addr_index, 5'b0};
            latched_new_addr    <= {addr_tag, addr_index, 5'b0};
         end
         // 버스트 카운터
         if (state == S_IDLE || state == S_UPDATE)
            word_cnt <= '0;
         else if ((state == S_WRITE_BACK || state == S_REFILL) && mem_ack_i)
            word_cnt <= word_cnt + 1'b1;
      end
   end

   always_comb begin
      next_state = state;
      case (state)
         S_IDLE:           if (cpu_req_i) next_state = S_TAG_CHECK;
         S_TAG_CHECK: begin
            if (cache_hit)           next_state = S_IDLE;
            else if (replace_dirty)  next_state = S_WAIT_WB_GRANT;
            else                     next_state = S_WAIT_REFILL_GNT;
         end
         S_WAIT_WB_GRANT:  if (mem_grant_i) next_state = S_WRITE_BACK;
         S_WRITE_BACK:     if (mem_ack_i && word_cnt == 3'd7) next_state = S_WAIT_REFILL_GNT;
         S_WAIT_REFILL_GNT: if (mem_grant_i) next_state = S_REFILL;
         S_REFILL:         if (mem_ack_i && word_cnt == 3'd7) next_state = S_UPDATE;
         S_UPDATE:                           next_state = S_IDLE;
         default:                            next_state = S_IDLE;
      endcase
   end

   // ── 스톨 신호 ────────────────────────────────────────
   // TAG_CHECK에서 히트 시 스톨 없음, 미스 시 스톨
   assign dcache_stall_o = (state == S_TAG_CHECK && !cache_hit) ||
                           (state == S_WAIT_WB_GRANT)   ||
                           (state == S_WRITE_BACK)       ||
                           (state == S_WAIT_REFILL_GNT)  ||
                           (state == S_REFILL)           ||
                           (state == S_UPDATE);

   // ── 메모리 요청 신호 ─────────────────────────────────
   assign mem_req_o   = (state == S_WAIT_WB_GRANT)  ||
                        (state == S_WRITE_BACK)      ||
                        (state == S_WAIT_REFILL_GNT) ||
                        (state == S_REFILL);
   assign mem_wen_o   = (state == S_WRITE_BACK) || (state == S_WAIT_WB_GRANT);
   assign mem_addr_o  = (state == S_WRITE_BACK || state == S_WAIT_WB_GRANT)
                        ? latched_wb_addr
                        : latched_new_addr;
   assign mem_wdata_o = data_array[latched_replace_way]
                                  [{addr_index, word_cnt}];

   // ── WRITE_BACK: BRAM 읽어서 메모리로 ────────────────
   // (mem_wdata_o가 BRAM에서 직접 연결되므로 별도 로직 불필요)

   // ── REFILL: 메모리 데이터를 BRAM에 기록 ─────────────
   always_ff @(posedge clk) begin
      if (state == S_REFILL && mem_ack_i)
         data_array[latched_replace_way][{addr_index, word_cnt}] <= mem_rdata_i;
   end

   // ── UPDATE: Tag/Valid/Dirty 갱신 ─────────────────────
   always_ff @(posedge clk) begin
      if (state == S_UPDATE) begin
         tag_array  [latched_replace_way][addr_index] <= latched_new_addr[31:11];
         valid_array[latched_replace_way][addr_index] <= 1'b1;
         dirty_array[latched_replace_way][addr_index] <= 1'b0;
      end
   end

   // ── CPU 히트 처리 ─────────────────────────────────────
   // 읽기: 히트 시 BRAM에서 직접 출력
   assign cpu_rdata_o = data_array[hit_way_sel][{addr_index, addr_offset}];

   // 쓰기: TAG_CHECK에서 히트 시 동기 쓰기 + Dirty 설정
   always_ff @(posedge clk) begin
      if (state == S_TAG_CHECK && cache_hit && cpu_wen_i) begin
         // Byte Enable 적용
         if (cpu_be_i[0]) data_array[hit_way_sel][{addr_index, addr_offset}][ 7: 0] <= cpu_wdata_i[ 7: 0];
         if (cpu_be_i[1]) data_array[hit_way_sel][{addr_index, addr_offset}][15: 8] <= cpu_wdata_i[15: 8];
         if (cpu_be_i[2]) data_array[hit_way_sel][{addr_index, addr_offset}][23:16] <= cpu_wdata_i[23:16];
         if (cpu_be_i[3]) data_array[hit_way_sel][{addr_index, addr_offset}][31:24] <= cpu_wdata_i[31:24];
         dirty_array[hit_way_sel][addr_index] <= 1'b1;
      end
   end

   // ── LRU 갱신 ─────────────────────────────────────────
   always_ff @(posedge clk) begin
      if (state == S_TAG_CHECK && cache_hit)
         lru_array[addr_index] <= ~hit_way_sel; // 히트된 Way의 반대가 LRU
      else if (state == S_UPDATE)
         lru_array[addr_index] <= ~latched_replace_way;
   end

   // ── 초기화 ───────────────────────────────────────────
   integer i_init, w_init;
   initial begin
      for (i_init = 0; i_init < CACHE_SETS; i_init++) begin
         for (w_init = 0; w_init < WAYS; w_init++) begin
            valid_array[w_init][i_init] = 1'b0;
            dirty_array[w_init][i_init] = 1'b0;
            tag_array  [w_init][i_init] = '0;
         end
         lru_array[i_init] = 1'b0;
      end
   end

endmodule
