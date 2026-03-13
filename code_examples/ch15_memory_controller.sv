// =============================================================================
// Chapter 15: 메모리 컨트롤러 (Memory Controller)
// =============================================================================
// I-Cache와 D-Cache의 메모리 요청을 중재(arbitrate)하고,
// 메인 메모리와의 버스트 전송을 관리하는 통합 컨트롤러.
// D-Cache 우선 정책(D-Cache priority)을 적용한다.
// 합성 가능한 설계 (Xilinx Basys 3, XC7A35T)
// =============================================================================

module memory_controller #(
   parameter ADDR_WIDTH = 32,           // 주소 비트 수
   parameter DATA_WIDTH = 32,           // 데이터 비트 수
   parameter LINE_WORDS = 4,            // 캐시 라인 워드 수
   parameter MEM_LATENCY = 2            // 메모리 읽기 지연 (사이클 수)
)(
   input  logic                    clk,
   input  logic                    rst_n,

   // === I-Cache 인터페이스 ===
   input  logic                    icache_req_i,     // I-Cache 읽기 요청
   input  logic [ADDR_WIDTH-1:0]   icache_addr_i,    // I-Cache 요청 주소
   output logic [DATA_WIDTH-1:0]   icache_rdata_o,   // I-Cache 응답 데이터
   output logic                    icache_valid_o,   // I-Cache 응답 유효
   output logic                    icache_ready_o,   // I-Cache 요청 수락

   // === D-Cache 인터페이스 ===
   input  logic                    dcache_req_i,     // D-Cache 요청
   input  logic                    dcache_write_i,   // D-Cache 쓰기(1)/읽기(0)
   input  logic [ADDR_WIDTH-1:0]   dcache_addr_i,    // D-Cache 요청 주소
   input  logic [DATA_WIDTH-1:0]   dcache_wdata_i,   // D-Cache 쓰기 데이터
   output logic [DATA_WIDTH-1:0]   dcache_rdata_o,   // D-Cache 응답 데이터
   output logic                    dcache_valid_o,   // D-Cache 응답 유효
   output logic                    dcache_ready_o,   // D-Cache 요청 수락

   // === 메인 메모리 인터페이스 ===
   output logic                    mem_ce_o,         // 메모리 칩 인에이블
   output logic                    mem_we_o,         // 메모리 쓰기 인에이블
   output logic [ADDR_WIDTH-1:0]   mem_addr_o,       // 메모리 주소
   output logic [DATA_WIDTH-1:0]   mem_wdata_o,      // 메모리 쓰기 데이터
   input  logic [DATA_WIDTH-1:0]   mem_rdata_i,      // 메모리 읽기 데이터
   input  logic                    mem_ready_i       // 메모리 준비 완료
);

   // =========================================================================
   // 지역 파라미터
   // =========================================================================
   localparam BEAT_W = $clog2(LINE_WORDS);

   // =========================================================================
   // 상태 정의
   // =========================================================================
   typedef enum logic [2:0] {
      S_IDLE      = 3'b000,    // 대기: 요청 감시
      S_DCACHE_RD = 3'b001,    // D-Cache 읽기 버스트
      S_DCACHE_WR = 3'b010,    // D-Cache 쓰기 버스트
      S_ICACHE_RD = 3'b011,    // I-Cache 읽기 버스트
      S_WAIT      = 3'b100     // 메모리 지연 대기
   } state_t;

   state_t state_q, state_d;

   // =========================================================================
   // 내부 레지스터
   // =========================================================================
   logic [BEAT_W-1:0]    beat_cnt_q, beat_cnt_d;
   logic [ADDR_WIDTH-1:0] base_addr_q, base_addr_d;
   logic [$clog2(MEM_LATENCY+1)-1:0] wait_cnt_q, wait_cnt_d;
   logic                  is_dcache_q, is_dcache_d;  // 현재 서비스 대상
   logic                  is_write_q, is_write_d;    // 쓰기 트랜잭션 여부

   // =========================================================================
   // 순차 논리
   // =========================================================================
   always_ff @(posedge clk or negedge rst_n) begin
      if (!rst_n) begin
         state_q     <= S_IDLE;
         beat_cnt_q  <= '0;
         base_addr_q <= '0;
         wait_cnt_q  <= '0;
         is_dcache_q <= 1'b0;
         is_write_q  <= 1'b0;
      end else begin
         state_q     <= state_d;
         beat_cnt_q  <= beat_cnt_d;
         base_addr_q <= base_addr_d;
         wait_cnt_q  <= wait_cnt_d;
         is_dcache_q <= is_dcache_d;
         is_write_q  <= is_write_d;
      end
   end

   // =========================================================================
   // 다음 상태 및 출력 논리
   // =========================================================================
   always_comb begin
      // 기본값
      state_d     = state_q;
      beat_cnt_d  = beat_cnt_q;
      base_addr_d = base_addr_q;
      wait_cnt_d  = wait_cnt_q;
      is_dcache_d = is_dcache_q;
      is_write_d  = is_write_q;

      mem_ce_o    = 1'b0;
      mem_we_o    = 1'b0;
      mem_addr_o  = '0;
      mem_wdata_o = '0;

      icache_rdata_o = '0;
      icache_valid_o = 1'b0;
      icache_ready_o = 1'b0;

      dcache_rdata_o = '0;
      dcache_valid_o = 1'b0;
      dcache_ready_o = 1'b0;

      case (state_q)
         // -----------------------------------------------------------------
         // IDLE: D-Cache 우선 중재 (D-Cache priority arbitration)
         // -----------------------------------------------------------------
         S_IDLE: begin
            icache_ready_o = 1'b0;
            dcache_ready_o = 1'b0;

            if (dcache_req_i) begin
               // D-Cache 우선
               base_addr_d = dcache_addr_i;
               is_dcache_d = 1'b1;
               is_write_d  = dcache_write_i;
               beat_cnt_d  = '0;
               wait_cnt_d  = '0;
               dcache_ready_o = 1'b1;

               if (dcache_write_i) begin
                  state_d = S_DCACHE_WR;
               end else begin
                  state_d = S_WAIT;  // 읽기 지연 대기
               end
            end else if (icache_req_i) begin
               // I-Cache 요청
               base_addr_d = icache_addr_i;
               is_dcache_d = 1'b0;
               is_write_d  = 1'b0;
               beat_cnt_d  = '0;
               wait_cnt_d  = '0;
               icache_ready_o = 1'b1;
               state_d = S_WAIT;  // 읽기 지연 대기
            end
         end

         // -----------------------------------------------------------------
         // WAIT: 메모리 읽기 지연 카운트
         // -----------------------------------------------------------------
         S_WAIT: begin
            mem_ce_o   = 1'b1;
            mem_we_o   = 1'b0;
            mem_addr_o = {base_addr_q[ADDR_WIDTH-1:BEAT_W+2],
                          beat_cnt_q, 2'b00};

            if (wait_cnt_q >= MEM_LATENCY[$clog2(MEM_LATENCY+1)-1:0] - 1) begin
               // 지연 완료 → 데이터 전송 시작
               if (is_dcache_q)
                  state_d = S_DCACHE_RD;
               else
                  state_d = S_ICACHE_RD;
            end else begin
               wait_cnt_d = wait_cnt_q + 1'b1;
            end
         end

         // -----------------------------------------------------------------
         // DCACHE_RD: D-Cache 읽기 버스트 (4 beat)
         // -----------------------------------------------------------------
         S_DCACHE_RD: begin
            mem_ce_o   = 1'b1;
            mem_we_o   = 1'b0;
            mem_addr_o = {base_addr_q[ADDR_WIDTH-1:BEAT_W+2],
                          beat_cnt_q, 2'b00};

            if (mem_ready_i) begin
               dcache_rdata_o = mem_rdata_i;
               dcache_valid_o = 1'b1;

               if (beat_cnt_q == BEAT_W'(LINE_WORDS - 1)) begin
                  state_d = S_IDLE;
               end else begin
                  beat_cnt_d = beat_cnt_q + 1'b1;
               end
            end
         end

         // -----------------------------------------------------------------
         // DCACHE_WR: D-Cache 쓰기 버스트 (dirty eviction)
         // -----------------------------------------------------------------
         S_DCACHE_WR: begin
            mem_ce_o    = 1'b1;
            mem_we_o    = 1'b1;
            mem_addr_o  = {base_addr_q[ADDR_WIDTH-1:BEAT_W+2],
                           beat_cnt_q, 2'b00};
            mem_wdata_o = dcache_wdata_i;

            if (mem_ready_i) begin
               dcache_valid_o = 1'b1;  // 쓰기 확인

               if (beat_cnt_q == BEAT_W'(LINE_WORDS - 1)) begin
                  state_d = S_IDLE;
               end else begin
                  beat_cnt_d = beat_cnt_q + 1'b1;
               end
            end
         end

         // -----------------------------------------------------------------
         // ICACHE_RD: I-Cache 읽기 버스트 (4 beat)
         // -----------------------------------------------------------------
         S_ICACHE_RD: begin
            mem_ce_o   = 1'b1;
            mem_we_o   = 1'b0;
            mem_addr_o = {base_addr_q[ADDR_WIDTH-1:BEAT_W+2],
                          beat_cnt_q, 2'b00};

            if (mem_ready_i) begin
               icache_rdata_o = mem_rdata_i;
               icache_valid_o = 1'b1;

               if (beat_cnt_q == BEAT_W'(LINE_WORDS - 1)) begin
                  state_d = S_IDLE;
               end else begin
                  beat_cnt_d = beat_cnt_q + 1'b1;
               end
            end
         end

         default: state_d = S_IDLE;
      endcase
   end

endmodule
