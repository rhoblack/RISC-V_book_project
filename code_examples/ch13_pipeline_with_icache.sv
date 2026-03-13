// =============================================================================
// Ch13: L1 I-Cache 통합 파이프라인 래퍼 (Pipeline with L1 I-Cache)
// rv32i_pipeline_complete (Ch12) + icache_direct_mapped (Ch13) 연결
// IMEM은 시뮬레이션용 내부 배열로 단순화 (실제 FPGA에서는 외부 DRAM 또는 DDR 연결)
// icache_stall 신호로 파이프라인 홀드 제어
// =============================================================================

module rv32i_pipeline_with_icache #(
   parameter DATA_WIDTH  = 32,
   parameter ADDR_WIDTH  = 32,
   parameter RF_DEPTH    = 32,
   parameter MEM_DEPTH   = 4096  // 시뮬레이션용 IMEM 깊이 (워드 단위)
)(
   input  logic                  clk,
   input  logic                  rst_n,
   // 외부 디버그 포트 (선택)
   output logic [ADDR_WIDTH-1:0] dbg_pc,
   output logic [DATA_WIDTH-1:0] dbg_instr
);

   // =========================================================================
   // 내부 연결 신호
   // =========================================================================

   // --- PC / 명령어 인터페이스 ---
   logic [ADDR_WIDTH-1:0] if_pc;           // 현재 PC (IF 스테이지)
   logic [DATA_WIDTH-1:0] if_instr;        // 명령어 (캐시 또는 IMEM에서)
   logic                  icache_hit;      // 캐시 히트
   logic                  icache_stall;    // 캐시 미스 스톨

   // --- 캐시 ↔ IMEM 인터페이스 ---
   logic [ADDR_WIDTH-1:0] cache_mem_addr;  // 캐시가 요청하는 IMEM 주소
   logic                  cache_mem_req;   // IMEM 읽기 요청
   logic [DATA_WIDTH-1:0] cache_mem_rdata; // IMEM 응답 데이터
   logic                  cache_mem_ready; // IMEM 응답 유효

   // --- 파이프라인 내부 제어 (Ch10~Ch12에서 완성) ---
   // hdu_pc_en, hdu_if_id_en: Hazard Detection Unit 출력
   // flush 신호: 분기 플러시 (Ch11)
   // 아래 신호는 rv32i_pipeline_complete 내부에서 생성됨
   logic                  hdu_pc_en;
   logic                  hdu_if_id_en;
   logic                  if_id_flush;

   // --- 최종 파이프라인 제어 (우선순위: flush > icache_stall > load_use) ---
   // pc_en, if_id_en: 파이프라인 레지스터 enable
   logic                  pc_en_final;
   logic                  if_id_en_final;

   // =========================================================================
   // 우선순위 스톨 제어 로직
   // 순위: flush(분기 플러시) > icache_stall > load_use_stall
   // =========================================================================

   // PC enable: flush 시 항상 업데이트, 캐시 미스 시 정지, 나머지는 HDU 결정
   assign pc_en_final    = if_id_flush  ? 1'b1  :   // 분기 플러시 최우선
                           icache_stall ? 1'b0  :   // 캐시 미스: PC 홀드
                           hdu_pc_en;               // load-use 스톨

   // IF/ID 레지스터 enable: 캐시 미스 시 홀드 (flush는 파이프라인 내부 처리)
   assign if_id_en_final = icache_stall ? 1'b0 : hdu_if_id_en;

   // =========================================================================
   // 시뮬레이션용 내부 IMEM 모델
   // 실제 FPGA: 외부 DDR/BRAM 또는 AHB 버스로 교체
   // =========================================================================

   logic [DATA_WIDTH-1:0] sim_imem [0:MEM_DEPTH-1];

   // IMEM 초기화: 시뮬레이션에서 $readmemh로 로드
   initial begin
      // 기본값: NOP (ADDI x0, x0, 0)
      for (int i = 0; i < MEM_DEPTH; i++) begin
         sim_imem[i] = 32'h0000_0013;
      end
      // 실제 테스트벤치에서 오버라이드 가능:
      // $readmemh("program.hex", sim_imem);
   end

   // IMEM 접근 지연 모델 (교재 단순화: 5사이클 fixed 지연)
   // [M-5 수정] 캐시 FSM이 FILL 내부에서 고정 카운터(FILL_CYCLES=4)로 동작하므로,
   //            DRAM 모델은 MISS 상태에서 mem_req를 받아 1사이클 내에 ready=1과 데이터를 응답.
   //            이후 FILL은 캐시 내부 카운터(4사이클)로 진행되어 DONE 전환.
   //            총 미스 페널티: MISS(1사이클) + FILL(4사이클) + DONE(1사이클) = 6사이클.
   // 실제 구현: AHB/DDR 컨트롤러와 연동, 버스트 전송으로 8워드 순차 응답.
   logic [2:0] mem_delay_cnt;

   always_ff @(posedge clk) begin
      if (!rst_n) begin
         mem_delay_cnt   <= 3'b0;
         cache_mem_ready <= 1'b0;
         cache_mem_rdata <= 32'h0;
      end else if (cache_mem_req && mem_delay_cnt == 3'b0) begin
         // 메모리 요청 수신: 1사이클 지연 후 ready=1 응답
         // (교재 단순화: 이후 블록 채움은 캐시 내부 FILL_CYCLES 카운터가 처리)
         mem_delay_cnt   <= 3'd1;
         cache_mem_ready <= 1'b0;
      end else if (mem_delay_cnt > 3'b0) begin
         mem_delay_cnt <= mem_delay_cnt - 1'b1;
         if (mem_delay_cnt == 3'd1) begin
            // 1사이클 후: ready=1과 함께 요청 주소의 워드 데이터 응답
            cache_mem_ready <= 1'b1;
            cache_mem_rdata <= sim_imem[cache_mem_addr[ADDR_WIDTH-1:2]];
         end else begin
            cache_mem_ready <= 1'b0;
         end
      end else begin
         cache_mem_ready <= 1'b0;
      end
   end

   // =========================================================================
   // L1 I-Cache 인스턴스
   // =========================================================================

   icache_direct_mapped #(
      .CACHE_SIZE    (4096),
      .BLOCK_SIZE    (32),
      .NUM_ENTRIES   (128),
      .ADDR_WIDTH    (ADDR_WIDTH)
   ) u_icache (
      .clk           (clk),
      .rst_n         (rst_n),
      // [C-2 수정] flush 신호 연결: 분기 플러시 시 FILL 중 wrong-path 채움 중단
      .flush         (if_id_flush),
      // 프로세서 인터페이스
      .cpu_addr      (if_pc),
      .cpu_req       (1'b1),            // 항상 요청 (IF 스테이지는 항상 명령어 필요)
      .cpu_rdata     (if_instr),        // 캐시에서 명령어 수신
      .cache_hit     (icache_hit),
      .icache_stall  (icache_stall),
      // 하위 메모리 인터페이스
      .mem_addr      (cache_mem_addr),
      .mem_req       (cache_mem_req),
      .mem_rdata     (cache_mem_rdata),
      .mem_ready     (cache_mem_ready)
   );

   // =========================================================================
   // RV32I 파이프라인 프로세서 인스턴스 (Ch12 완성 버전)
   // =========================================================================

   rv32i_pipeline_complete #(
      .DATA_WIDTH    (DATA_WIDTH),
      .ADDR_WIDTH    (ADDR_WIDTH),
      .RF_DEPTH      (RF_DEPTH)
   ) u_pipeline (
      .clk           (clk),
      .rst_n         (rst_n),
      // 외부 캐시 제어 신호 연결
      .ext_pc_en     (pc_en_final),
      .ext_if_id_en  (if_id_en_final),
      .ext_instr     (if_instr),        // 캐시에서 받은 명령어
      // 내부 제어 신호 출력 (캐시 우선순위 계산에 사용)
      .hdu_pc_en_out (hdu_pc_en),
      .hdu_if_id_en_out(hdu_if_id_en),
      .if_id_flush_out(if_id_flush),
      .pc_out        (if_pc),           // 현재 PC → 캐시에 전달
      // 디버그
      .dbg_pc        (dbg_pc),
      .dbg_instr     (dbg_instr)
   );

endmodule

// =============================================================================
// 주의: rv32i_pipeline_complete 모듈(Ch12)에 아래 포트가 추가 필요
// - input  logic ext_pc_en
// - input  logic ext_if_id_en
// - input  logic [31:0] ext_instr
// - output logic hdu_pc_en_out
// - output logic hdu_if_id_en_out
// - output logic if_id_flush_out
// - output logic [31:0] pc_out
// 실제 통합 시 Ch12 top 모듈의 포트를 확장하거나,
// 또는 래퍼 내부에서 icache_stall을 Ch12 스톨 신호와 OR 연결
// =============================================================================
