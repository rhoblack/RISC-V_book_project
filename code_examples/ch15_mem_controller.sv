// ============================================================
// ch15_mem_controller.sv
// 통합 메모리 컨트롤러 — 중재기(Arbiter) + Main SRAM
//
// 기능:
//   - I-Cache와 D-Cache의 메모리 요청을 중재 (D-Cache 우선)
//   - 8-beat 버스트 전송으로 캐시 라인(32바이트) 채움
//   - BRAM 기반 Main SRAM (Xilinx Block RAM)
//
// 파라미터:
//   DATA_WIDTH : 데이터 폭 (기본 32비트)
//   ADDR_WIDTH : 주소 폭 (기본 32비트)
//   MEM_DEPTH  : 메모리 깊이 (워드 수, 기본 16384 = 16KB)
//   BURST_LEN  : 버스트 길이 (기본 8워드 = 32바이트 = 1 캐시 라인)
//
// 미스 페널티 (BRAM 1사이클 동기 읽기 지연 반영):
//   I-Cache        : 12사이클 (1 MISS + 1 WAIT_GRANT + 8 FILL + 1 DRAIN + 1 DONE)
//   D-Cache Clean  : 12사이클
//   D-Cache Dirty  : 20사이클 (8 WRITE_BACK + 8 REFILL + 오버헤드 4)
//
// BRAM 동기 읽기 타이밍:
//   - BRAM은 동기 읽기만 지원: 주소 적용 사이클 다음 사이클에 데이터 출력
//   - ARB_SERVE_x 상태 진입 후 1사이클 후부터 ACK(serve_x_q) 유효
//   - beat_cnt=7까지 카운트 후 ARB_DRAIN 상태로 1사이클 추가하여
//     마지막 beat 데이터가 mem_rdata_reg에 안정적으로 수신됨을 보장
//
// 버스트 중 req 신호:
//   - 캐시 FSM은 WAIT_GRANT 상태에서 mem_req=1을 유지하지만,
//     FILL/WRITE_BACK/REFILL 상태에서는 mem_req=0으로 내린다.
//   - 중재기는 ARB_SERVE_x 진입 후 req 신호 상태와 무관하게
//     burst_done까지 버스트를 지속한다 (버스트 무결성 보장).
//
// $readmemh hex 파일:
//   - "mem_init.hex" 파일을 시뮬레이션 실행 디렉터리 또는
//     code_examples/test_programs/ 폴더에 위치시켜야 한다.
//   - 파일이 없으면 BRAM이 X(don't care)로 초기화됨.
// ============================================================

module mem_controller #(
   parameter DATA_WIDTH = 32,
   parameter ADDR_WIDTH = 32,
   parameter MEM_DEPTH  = 16384,   // 워드 수 (16KB)
   parameter BURST_LEN  = 8        // 버스트 길이 (캐시 라인 = 8워드)
)(
   input  logic                  clk,
   input  logic                  rst_n,

   // ── I-Cache 인터페이스 ──────────────────────────────
   input  logic                  icache_req_i,     // I-Cache 요청 (MISS, WAIT_GRANT 상태에서 High)
   input  logic [ADDR_WIDTH-1:0] icache_addr_i,    // 요청 주소 (하위 5비트=0)
   output logic                  icache_ack_o,     // 데이터 유효 (매 beat, BRAM 1사이클 지연)
   output logic [DATA_WIDTH-1:0] icache_rdata_o,   // 읽기 데이터
   output logic                  icache_grant_o,   // 버스 승인 (1사이클 펄스)

   // ── D-Cache 인터페이스 ──────────────────────────────
   input  logic                  dcache_req_i,     // D-Cache 요청
   input  logic                  dcache_wen_i,     // 1=Write-Back, 0=REFILL
   input  logic [ADDR_WIDTH-1:0] dcache_addr_i,    // 요청 주소 (하위 5비트=0)
   input  logic [DATA_WIDTH-1:0] dcache_wdata_i,   // 쓰기 데이터 (Write-Back 시)
   output logic                  dcache_ack_o,     // 전송 완료 신호 (BRAM 1사이클 지연)
   output logic [DATA_WIDTH-1:0] dcache_rdata_o,   // 읽기 데이터 (REFILL 시)
   output logic                  dcache_grant_o    // 버스 승인 (1사이클 펄스)
);

   // ============================================================
   // BRAM — Main SRAM (* ram_style = "block" * 속성으로 Vivado가
   //                    자동으로 Block RAM으로 합성)
   // ============================================================
   (* ram_style = "block" *)
   logic [DATA_WIDTH-1:0] mem [0:MEM_DEPTH-1];

   // 초기화 (시뮬레이션 및 FPGA 비트스트림 초기값)
   // hex 파일은 code_examples/test_programs/mem_init.hex에 위치
   initial begin
      $readmemh("mem_init.hex", mem);
   end

   // ============================================================
   // 중재기 FSM (Arbiter FSM)
   // D-Cache 우선 고정 우선순위 (Fixed Priority)
   //
   // 상태:
   //   ARB_IDLE    : 대기. D-Cache 요청 우선 확인, 없으면 I-Cache 확인.
   //   ARB_SERVE_D : D-Cache 버스트 서비스 중 (beat_cnt 0~7).
   //   ARB_DRAIN_D : D-Cache 마지막 beat BRAM 읽기 지연 흡수 (1사이클).
   //   ARB_SERVE_I : I-Cache 버스트 서비스 중 (beat_cnt 0~7).
   //   ARB_DRAIN_I : I-Cache 마지막 beat BRAM 읽기 지연 흡수 (1사이클).
   //
   // DRAIN 상태 설명:
   //   BRAM은 동기 읽기로, beat_cnt=7 사이클에 주소가 제공되면
   //   다음 사이클(DRAIN)에 데이터가 mem_rdata_reg에 도착한다.
   //   serve_x_q는 DRAIN 사이클에도 1이 유지되어 ACK가 정상 발생한다.
   // ============================================================
   typedef enum logic [2:0] {
      ARB_IDLE    = 3'b000,   // 대기 — 요청 없음
      ARB_SERVE_D = 3'b001,   // D-Cache 버스트 서비스 중
      ARB_DRAIN_D = 3'b010,   // D-Cache 마지막 beat 데이터 배출 대기
      ARB_SERVE_I = 3'b011,   // I-Cache 버스트 서비스 중
      ARB_DRAIN_I = 3'b100    // I-Cache 마지막 beat 데이터 배출 대기
   } arb_state_t;

   arb_state_t arb_state, arb_next;

   // 버스트 카운터 (0~7, beat_cnt==7에서 SERVE→DRAIN 전이)
   logic [2:0] beat_cnt;
   // burst_done: beat_cnt가 최대값(BURST_LEN-1=7)에 도달한 사이클
   // DRAIN 상태 1사이클 후 IDLE 복귀 → 마지막 beat 데이터 보장
   assign burst_done = (beat_cnt == 3'(BURST_LEN - 1)); // 명시적 3비트 캐스팅

   // ── FSM 상태 레지스터 ──────────────────────────────
   always_ff @(posedge clk or negedge rst_n) begin
      if (!rst_n)
         arb_state <= ARB_IDLE;
      else
         arb_state <= arb_next;
   end

   // ── FSM 다음 상태 로직 ────────────────────────────
   always_comb begin
      arb_next = arb_state;
      case (arb_state)
         ARB_IDLE: begin
            if (dcache_req_i)       // D-Cache 우선
               arb_next = ARB_SERVE_D;
            else if (icache_req_i)
               arb_next = ARB_SERVE_I;
         end
         ARB_SERVE_D: begin
            if (burst_done)         // beat_cnt==7: DRAIN으로 전이 (마지막 데이터 수신 보장)
               arb_next = ARB_DRAIN_D;
         end
         ARB_DRAIN_D: begin
            // 1사이클 DRAIN 후 IDLE 복귀
            // 이 사이클에 serve_d_q=1 유지 → 8번째 ACK 발생
            arb_next = ARB_IDLE;
         end
         ARB_SERVE_I: begin
            if (burst_done)
               arb_next = ARB_DRAIN_I;
         end
         ARB_DRAIN_I: begin
            arb_next = ARB_IDLE;
         end
         default: arb_next = ARB_IDLE;
      endcase
   end

   // ── 버스트 카운터 ─────────────────────────────────
   // IDLE 또는 DRAIN 진입 시 0 초기화
   // SERVE 상태에서만 증가 (DRAIN에서는 증가하지 않음)
   always_ff @(posedge clk or negedge rst_n) begin
      if (!rst_n)
         beat_cnt <= 3'b0;
      else if (arb_state == ARB_IDLE || arb_state == ARB_DRAIN_D || arb_state == ARB_DRAIN_I)
         beat_cnt <= 3'b0;               // IDLE/DRAIN 진입 시 초기화
      else if (arb_state == ARB_SERVE_D || arb_state == ARB_SERVE_I)
         beat_cnt <= beat_cnt + 1'b1;    // 매 사이클 증가 (0→1→...→7)
   end

   // ── 승인 신호 ─────────────────────────────────────
   // ARB_IDLE에서 요청을 받아들이는 사이클에 1사이클 펄스 발생
   // 캐시 FSM은 이 신호를 수신하는 사이클에 WAIT_GRANT → FILL 전이
   assign icache_grant_o = (arb_state == ARB_IDLE) &&  icache_req_i && !dcache_req_i;
   assign dcache_grant_o = (arb_state == ARB_IDLE) &&  dcache_req_i;

   // ============================================================
   // BRAM 읽기/쓰기 동작
   // 버스트 기준 주소: {addr[31:5], 5'b0} → 워드 인덱스 addr[31:2]
   // beat_cnt 증가에 따라 연속 워드 주소 자동 생성
   // ============================================================

   // ── I-Cache 버스트 기준 주소 래치 ────────────────
   // grant 수신 사이클에 기준 주소 확정 (WAIT_GRANT 이후 유지)
   logic [ADDR_WIDTH-1:0] icache_base_addr;
   always_ff @(posedge clk or negedge rst_n) begin
      if (!rst_n)
         icache_base_addr <= '0;
      else if (icache_grant_o)
         icache_base_addr <= {icache_addr_i[ADDR_WIDTH-1:5], 5'b0}; // 캐시 라인 기준 주소
   end

   // ── D-Cache 버스트 기준 주소 래치 ───────────────
   logic [ADDR_WIDTH-1:0] dcache_base_addr;
   always_ff @(posedge clk or negedge rst_n) begin
      if (!rst_n)
         dcache_base_addr <= '0;
      else if (dcache_grant_o)
         dcache_base_addr <= {dcache_addr_i[ADDR_WIDTH-1:5], 5'b0};
   end

   // ── BRAM 동기 읽기/쓰기 ───────────────────────────
   // BRAM은 동기 읽기: mem_word_addr을 클록 엣지에 제공하면
   // 다음 클록 엣지에 mem_rdata_reg에 데이터가 출력됨
   //
   // 타이밍 예시 (I-Cache FILL):
   //   T+0: ARB_SERVE_I 진입, beat_cnt=0, mem_word_addr=base+0
   //   T+1: mem_rdata_reg=mem[base+0], serve_i_q=1, ACK 유효 (beat 0)
   //   ...
   //   T+7: beat_cnt=7, mem_word_addr=base+7 → ARB_DRAIN_I 전이
   //   T+8: mem_rdata_reg=mem[base+7], serve_i_q=1, ACK 유효 (beat 7)
   //        ARB_DRAIN_I 상태, beat_cnt=0 초기화

   logic [ADDR_WIDTH-1:0] mem_word_addr;   // 실제 워드 주소
   logic [DATA_WIDTH-1:0] mem_rdata_reg;
   logic                  mem_wen_reg;

   always_comb begin
      case (arb_state)
         ARB_SERVE_I: mem_word_addr = (icache_base_addr >> 2) + {29'b0, beat_cnt};
         ARB_SERVE_D: mem_word_addr = (dcache_base_addr >> 2) + {29'b0, beat_cnt};
         // DRAIN 상태: beat_cnt가 이미 0으로 리셋되므로 마지막 주소를 유지하기 위해
         // 별도 래치 불필요 — serve_x_q가 이전 읽기 결과를 전달함
         default:     mem_word_addr = '0;
      endcase
   end

   // BRAM 동기 읽기
   always_ff @(posedge clk) begin
      mem_rdata_reg <= mem[mem_word_addr[$clog2(MEM_DEPTH)-1:0]];
   end

   // BRAM 동기 쓰기 (D-Cache Write-Back 전용)
   always_ff @(posedge clk) begin
      if ((arb_state == ARB_SERVE_D) && dcache_wen_i)
         mem[mem_word_addr[$clog2(MEM_DEPTH)-1:0]] <= dcache_wdata_i;
   end

   // ── ACK 및 데이터 출력 ────────────────────────────
   // serve_x_q: ARB_SERVE_x 또는 ARB_DRAIN_x 상태에서 1
   // → BRAM 동기 읽기 1사이클 지연과 정확히 동기화됨
   // → SERVE 진입 다음 사이클(첫 ACK)부터 DRAIN 사이클(마지막 ACK)까지
   //    총 8사이클 ACK 발생 보장
   logic serve_i_q, serve_d_q;
   always_ff @(posedge clk or negedge rst_n) begin
      if (!rst_n) begin
         serve_i_q <= 1'b0;
         serve_d_q <= 1'b0;
      end else begin
         // SERVE 또는 DRAIN 상태에서 ACK 유효
         serve_i_q <= (arb_state == ARB_SERVE_I) || (arb_state == ARB_DRAIN_I);
         serve_d_q <= (arb_state == ARB_SERVE_D) || (arb_state == ARB_DRAIN_D);
      end
   end

   assign icache_ack_o   = serve_i_q;                         // BRAM 읽기 유효
   assign icache_rdata_o = mem_rdata_reg;

   // D-Cache: 읽기는 REFILL, 쓰기(WB)는 완료 시 ack
   assign dcache_ack_o   = serve_d_q;
   assign dcache_rdata_o = mem_rdata_reg;

endmodule
