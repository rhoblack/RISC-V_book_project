//=============================================================================
// AHB-Lite Master: 캐시-버스 브리지
// - L1 캐시 미스 시 AHB 버스를 통해 SRAM에 접근
// - 단일 전송(SINGLE) 및 4-beat 증분 버스트(INCR4) 지원
// - HREADY 기반 웨이트 스테이트 처리
//=============================================================================
module ahb_master
   import ahb_pkg::*;
(
   // 글로벌 신호
   input  logic                       hclk,       // AHB 클럭
   input  logic                       hreset_n,   // 비동기 리셋 (액티브 로우)

   // 캐시 인터페이스 (요청 측)
   input  logic                       cache_miss,    // 캐시 미스 발생
   input  logic [AHB_ADDR_WIDTH-1:0]  miss_addr,     // 미스 주소 (워드 정렬)
   input  logic                       miss_write,    // 쓰기 요청 (write-back)
   input  logic [AHB_DATA_WIDTH-1:0]  miss_wdata,    // 쓰기 데이터
   input  logic                       burst_req,     // 버스트 전송 요청
   output logic [AHB_DATA_WIDTH-1:0]  fill_data,     // 읽기 데이터
   output logic                       fill_valid,    // 읽기 데이터 유효
   output logic                       bus_busy,      // 버스 사용 중

   // AHB-Lite 마스터 출력
   output logic [AHB_ADDR_WIDTH-1:0]  haddr,      // 주소
   output htrans_t                    htrans,     // 전송 타입
   output logic                       hwrite,     // 쓰기 신호
   output hsize_t                     hsize,      // 전송 크기
   output hburst_t                    hburst,     // 버스트 타입
   output logic [AHB_DATA_WIDTH-1:0]  hwdata,     // 쓰기 데이터

   // AHB-Lite 슬레이브 응답
   input  logic [AHB_DATA_WIDTH-1:0]  hrdata,     // 읽기 데이터
   input  logic                       hready,     // 전송 완료
   input  hresp_t                     hresp       // 응답 상태
);

   //--------------------------------------------------------------------------
   // FSM 상태 정의
   //--------------------------------------------------------------------------
   typedef enum logic [2:0] {
      ST_IDLE  = 3'b000,   // 유휴 — 캐시 미스 대기
      ST_ADDR  = 3'b001,   // 주소 페이즈 — HADDR 출력
      ST_DATA  = 3'b010,   // 데이터 페이즈 — HWDATA 출력 또는 HRDATA 수신
      ST_BURST = 3'b011,   // 버스트 연속 — SEQ 전송
      ST_DONE  = 3'b100    // 완료 — 캐시에 알림
   } state_t;

   state_t state, next_state;

   //--------------------------------------------------------------------------
   // 내부 레지스터
   //--------------------------------------------------------------------------
   logic [AHB_ADDR_WIDTH-1:0] addr_r;      // 현재 주소 레지스터
   logic                      write_r;     // 쓰기 방향 래치
   logic [AHB_DATA_WIDTH-1:0] wdata_r;     // 쓰기 데이터 래치
   logic [1:0]                beat_cnt;    // 버스트 비트 카운터 (0~3)
   logic                      burst_mode;  // 버스트 모드 플래그

   //--------------------------------------------------------------------------
   // FSM 상태 레지스터
   //--------------------------------------------------------------------------
   always_ff @(posedge hclk or negedge hreset_n) begin
      if (!hreset_n)
         state <= ST_IDLE;
      else
         state <= next_state;
   end

   //--------------------------------------------------------------------------
   // FSM 다음 상태 로직
   //--------------------------------------------------------------------------
   always_comb begin
      next_state = state;
      case (state)
         ST_IDLE: begin
            if (cache_miss)
               next_state = ST_ADDR;
         end

         ST_ADDR: begin
            // 주소 페이즈 완료 시 데이터 페이즈로 전이
            if (hready)
               next_state = burst_mode ? ST_BURST : ST_DATA;
         end

         ST_DATA: begin
            // 데이터 페이즈 완료
            if (hready)
               next_state = ST_DONE;
         end

         ST_BURST: begin
            if (hready) begin
               if (beat_cnt == 2'd0)
                  next_state = ST_DATA;  // 마지막 비트의 데이터 수신
               else
                  next_state = ST_BURST; // 연속 전송
            end
         end

         ST_DONE: begin
            next_state = ST_IDLE;
         end

         default: next_state = ST_IDLE;
      endcase
   end

   //--------------------------------------------------------------------------
   // 주소 및 데이터 레지스터 관리
   //--------------------------------------------------------------------------
   always_ff @(posedge hclk or negedge hreset_n) begin
      if (!hreset_n) begin
         addr_r     <= '0;
         write_r    <= 1'b0;
         wdata_r    <= '0;
         beat_cnt   <= 2'd0;
         burst_mode <= 1'b0;
      end else begin
         case (state)
            ST_IDLE: begin
               if (cache_miss) begin
                  addr_r     <= miss_addr;
                  write_r    <= miss_write;
                  wdata_r    <= miss_wdata;
                  burst_mode <= burst_req;
                  beat_cnt   <= burst_req ? 2'd3 : 2'd0;
               end
            end

            ST_BURST: begin
               if (hready) begin
                  addr_r   <= addr_r + 32'd4;  // 워드 단위 증분
                  beat_cnt <= beat_cnt - 2'd1;
               end
            end

            default: ;
         endcase
      end
   end

   //--------------------------------------------------------------------------
   // AHB 출력 신호 생성
   //--------------------------------------------------------------------------
   always_comb begin
      // 기본값
      haddr  = '0;
      htrans = HTRANS_IDLE;
      hwrite = 1'b0;
      hsize  = HSIZE_WORD;
      hburst = HBURST_SINGLE;
      hwdata = '0;

      case (state)
         ST_ADDR: begin
            haddr  = addr_r;
            htrans = HTRANS_NONSEQ;
            hwrite = write_r;
            hsize  = HSIZE_WORD;
            hburst = burst_mode ? HBURST_INCR4 : HBURST_SINGLE;
         end

         ST_DATA: begin
            // 데이터 페이즈: 쓰기 시 HWDATA 출력
            hwdata = wdata_r;
         end

         ST_BURST: begin
            haddr  = addr_r;
            htrans = HTRANS_SEQ;
            hwrite = write_r;
            hsize  = HSIZE_WORD;
            hburst = HBURST_INCR4;
            hwdata = wdata_r;
         end

         default: ;
      endcase
   end

   //--------------------------------------------------------------------------
   // 캐시 인터페이스 출력
   //--------------------------------------------------------------------------
   assign fill_data  = hrdata;
   assign fill_valid = (state == ST_DATA || state == ST_BURST) && hready;
   assign bus_busy   = (state != ST_IDLE) && (state != ST_DONE);

endmodule
