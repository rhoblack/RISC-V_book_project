// =============================================================================
// APB 타이머/카운터 (APB Timer/Counter)
// Chapter 17.5 — APB 브리지와 주변 장치 연결
// RISC-V 프로세서 설계 완전정복
// =============================================================================
// 32비트 업카운터 + 비교 레지스터 기반 타이머.
// 프리스케일러로 카운트 속도를 조절하며, COUNT == CMP 시 인터럽트 발생.
// 자동 재시작(auto-reload) 모드를 지원하여 주기적 인터럽트 생성 가능.
// 이 인터럽트 신호는 Chapter 19에서 프로세서의 mip.MTIP와 연결됩니다.
// =============================================================================

module apb_timer (
   // APB 인터페이스
   input  logic        pclk,          // APB 클럭
   input  logic        preset_n,      // 비동기 리셋
   input  logic        psel,          // 슬레이브 선택
   input  logic        penable,       // 전송 활성화
   input  logic        pwrite,        // 쓰기(1) / 읽기(0)
   input  logic [4:0]  paddr,         // 주소 (바이트 단위)
   input  logic [31:0] pwdata,        // 쓰기 데이터
   output logic [31:0] prdata,        // 읽기 데이터
   output logic        pready,        // 항상 1

   // 인터럽트 출력
   output logic        timer_irq      // 타이머 인터럽트 요청
);

   // =========================================================================
   // 레지스터 맵 정의
   // =========================================================================
   localparam ADDR_TIM_CTRL      = 5'h00;   // 제어 레지스터
   localparam ADDR_TIM_COUNT     = 5'h04;   // 현재 카운터 값
   localparam ADDR_TIM_CMP       = 5'h08;   // 비교 값 (목표)
   localparam ADDR_TIM_PRESCALE  = 5'h0C;   // 프리스케일러 분주 값
   localparam ADDR_TIM_INT_STAT  = 5'h10;   // 인터럽트 상태 (W1C)

   // 제어 레지스터 비트 정의
   // [0]: EN           — 타이머 활성화
   // [1]: AUTO_RELOAD  — 자동 재시작 (CMP 도달 시 COUNT=0으로 리셋)
   // [2]: IE           — 인터럽트 활성화

   // =========================================================================
   // 내부 레지스터
   // =========================================================================
   logic [31:0] ctrl_reg;
   logic [31:0] count_reg;
   logic [31:0] cmp_reg;
   logic [31:0] prescale_reg;
   logic        int_pending;       // 인터럽트 펜딩 비트

   // 제어 비트 추출
   logic        timer_en;
   logic        auto_reload;
   logic        int_enable;

   assign timer_en    = ctrl_reg[0];
   assign auto_reload = ctrl_reg[1];
   assign int_enable  = ctrl_reg[2];

   // =========================================================================
   // APB 읽기/쓰기
   // =========================================================================
   logic apb_write, apb_read;
   assign apb_write = psel && penable && pwrite;
   assign apb_read  = psel && penable && !pwrite;

   // 레지스터 쓰기
   always_ff @(posedge pclk or negedge preset_n) begin
      if (!preset_n) begin
         ctrl_reg     <= 32'h0;
         cmp_reg      <= 32'hFFFF_FFFF;   // 기본값: 최대
         prescale_reg <= 32'h0;            // 분주 없음 (매 클럭 카운트)
      end else if (apb_write) begin
         case (paddr)
            ADDR_TIM_CTRL:     ctrl_reg     <= pwdata;
            ADDR_TIM_COUNT:    ;            // 카운터 직접 쓰기는 아래 별도 처리
            ADDR_TIM_CMP:      cmp_reg      <= pwdata;
            ADDR_TIM_PRESCALE: prescale_reg <= pwdata;
            ADDR_TIM_INT_STAT: ;            // W1C 처리는 아래 별도
            default: ;
         endcase
      end
   end

   // 레지스터 읽기
   always_comb begin
      prdata = 32'h0;
      case (paddr)
         ADDR_TIM_CTRL:     prdata = ctrl_reg;
         ADDR_TIM_COUNT:    prdata = count_reg;
         ADDR_TIM_CMP:      prdata = cmp_reg;
         ADDR_TIM_PRESCALE: prdata = prescale_reg;
         ADDR_TIM_INT_STAT: prdata = {31'h0, int_pending};
         default:           prdata = 32'h0;
      endcase
   end

   assign pready = 1'b1;

   // =========================================================================
   // 프리스케일러
   // =========================================================================
   // prescale_reg 값에 도달하면 tick 생성 (0이면 매 클럭)
   logic [31:0] prescale_cnt;
   logic        prescale_tick;

   always_ff @(posedge pclk or negedge preset_n) begin
      if (!preset_n) begin
         prescale_cnt <= '0;
      end else if (timer_en) begin
         if (prescale_cnt >= prescale_reg) begin
            prescale_cnt <= '0;
         end else begin
            prescale_cnt <= prescale_cnt + 1;
         end
      end else begin
         prescale_cnt <= '0;
      end
   end

   assign prescale_tick = timer_en && (prescale_cnt >= prescale_reg);

   // =========================================================================
   // 32비트 업카운터
   // =========================================================================
   logic count_match;
   assign count_match = (count_reg == cmp_reg);

   always_ff @(posedge pclk or negedge preset_n) begin
      if (!preset_n) begin
         count_reg <= '0;
      end else if (apb_write && paddr == ADDR_TIM_COUNT) begin
         // 소프트웨어가 카운터 값을 직접 설정
         count_reg <= pwdata;
      end else if (prescale_tick) begin
         if (count_match) begin
            if (auto_reload)
               count_reg <= '0;        // 자동 재시작
            // auto_reload=0이면 카운터 정지 (count 유지)
         end else begin
            count_reg <= count_reg + 1;
         end
      end
   end

   // =========================================================================
   // 인터럽트 로직
   // =========================================================================
   always_ff @(posedge pclk or negedge preset_n) begin
      if (!preset_n) begin
         int_pending <= 1'b0;
      end else begin
         // W1C: 소프트웨어가 1을 쓰면 클리어
         if (apb_write && paddr == ADDR_TIM_INT_STAT && pwdata[0])
            int_pending <= 1'b0;
         // 비교 일치 시 펜딩 세트
         else if (prescale_tick && count_match)
            int_pending <= 1'b1;
      end
   end

   // 인터럽트 출력: 펜딩 AND 활성화
   assign timer_irq = int_pending & int_enable;

endmodule
