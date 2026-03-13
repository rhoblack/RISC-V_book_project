// =============================================================================
// APB UART 컨트롤러 (APB UART Controller)
// Chapter 17.3 — APB 브리지와 주변 장치 연결
// RISC-V 프로세서 설계 완전정복
// =============================================================================
// 8N1 포맷(8비트 데이터, 패리티 없음, 1 정지 비트) UART 송수신기.
// 송신/수신 각각 8엔트리 FIFO를 보유하며, 보드레이트 분주 레지스터로 설정.
// Basys 3 USB-UART (FTDI FT2232) 연결 기준: 115200 baud @ 100MHz.
// =============================================================================

module apb_uart #(
   parameter CLK_FREQ   = 100_000_000,   // 시스템 클럭 주파수 (Hz)
   parameter FIFO_DEPTH = 8              // TX/RX FIFO 깊이
)(
   // APB 인터페이스
   input  logic        pclk,             // APB 클럭
   input  logic        preset_n,         // 비동기 리셋
   input  logic        psel,             // 슬레이브 선택
   input  logic        penable,          // 전송 활성화
   input  logic        pwrite,           // 쓰기(1) / 읽기(0)
   input  logic [4:0]  paddr,            // 주소 (바이트 단위)
   input  logic [31:0] pwdata,           // 쓰기 데이터
   output logic [31:0] prdata,           // 읽기 데이터
   output logic        pready,           // 항상 1 (웨이트 없음)

   // UART 물리 인터페이스
   output logic        uart_tx,          // 송신 핀 (FPGA → PC)
   input  logic        uart_rx,          // 수신 핀 (PC → FPGA)

   // 인터럽트 출력
   output logic        uart_irq          // 인터럽트 요청
);

   // =========================================================================
   // 레지스터 맵 정의
   // =========================================================================
   localparam ADDR_TX_DATA    = 5'h00;   // [7:0] 송신 데이터 (쓰기 전용)
   localparam ADDR_RX_DATA    = 5'h04;   // [7:0] 수신 데이터 (읽기 전용)
   localparam ADDR_STATUS     = 5'h08;   // 상태 레지스터 (읽기 전용)
   localparam ADDR_CTRL       = 5'h0C;   // 제어 레지스터
   localparam ADDR_BAUD_DIV   = 5'h10;   // 보드레이트 분주 값
   localparam ADDR_INT_EN     = 5'h14;   // 인터럽트 활성화
   localparam ADDR_INT_STATUS = 5'h18;   // 인터럽트 상태 (W1C)

   // 상태 레지스터 비트
   // [0]: TX FIFO 빈 상태 (tx_empty)
   // [1]: TX FIFO 가득 참 (tx_full)
   // [2]: RX FIFO 데이터 있음 (rx_valid)
   // [3]: RX FIFO 가득 참 (rx_full)

   // =========================================================================
   // 내부 레지스터
   // =========================================================================
   logic [15:0] baud_div;          // 보드레이트 분주 값
   logic [7:0]  ctrl_reg;          // 제어 레지스터 [0]=TX_EN, [1]=RX_EN
   logic [7:0]  int_en_reg;        // 인터럽트 활성화 [0]=TX_EMPTY, [1]=RX_VALID
   logic [7:0]  int_status_reg;    // 인터럽트 상태

   // =========================================================================
   // TX FIFO 신호
   // =========================================================================
   logic [7:0]  tx_fifo_wdata, tx_fifo_rdata;
   logic        tx_fifo_push, tx_fifo_pop;
   logic        tx_fifo_empty, tx_fifo_full;

   // =========================================================================
   // RX FIFO 신호
   // =========================================================================
   logic [7:0]  rx_fifo_wdata, rx_fifo_rdata;
   logic        rx_fifo_push, rx_fifo_pop;
   logic        rx_fifo_empty, rx_fifo_full;

   // =========================================================================
   // 보드레이트 생성기
   // =========================================================================
   // 16× 오버샘플링 클럭 생성: baud_tick = CLK_FREQ / (baud_rate × 16)
   // 예: 115200 baud @ 100MHz → baud_div = 100_000_000 / (115200 × 16) ≈ 54
   logic [15:0] baud_counter;
   logic        baud_tick;          // 16× 오버샘플링 틱

   always_ff @(posedge pclk or negedge preset_n) begin
      if (!preset_n) begin
         baud_counter <= '0;
         baud_tick    <= 1'b0;
      end else begin
         if (baud_counter >= baud_div - 1) begin
            baud_counter <= '0;
            baud_tick    <= 1'b1;
         end else begin
            baud_counter <= baud_counter + 1;
            baud_tick    <= 1'b0;
         end
      end
   end

   // =========================================================================
   // TX 송신 FSM
   // =========================================================================
   typedef enum logic [1:0] {
      TX_IDLE  = 2'b00,
      TX_START = 2'b01,
      TX_DATA  = 2'b10,
      TX_STOP  = 2'b11
   } tx_state_t;

   tx_state_t tx_state;
   logic [3:0] tx_bit_cnt;        // 16× 오버샘플링 카운터
   logic [2:0] tx_data_idx;       // 데이터 비트 인덱스 (0~7)
   logic [7:0] tx_shift_reg;      // 송신 시프트 레지스터

   always_ff @(posedge pclk or negedge preset_n) begin
      if (!preset_n) begin
         tx_state     <= TX_IDLE;
         tx_bit_cnt   <= '0;
         tx_data_idx  <= '0;
         tx_shift_reg <= '0;
         uart_tx      <= 1'b1;    // 유휴 상태: HIGH
         tx_fifo_pop  <= 1'b0;
      end else begin
         tx_fifo_pop <= 1'b0;

         case (tx_state)
            TX_IDLE: begin
               uart_tx <= 1'b1;
               if (!tx_fifo_empty && ctrl_reg[0]) begin
                  tx_shift_reg <= tx_fifo_rdata;
                  tx_fifo_pop  <= 1'b1;
                  tx_state     <= TX_START;
                  tx_bit_cnt   <= '0;
               end
            end

            TX_START: begin
               uart_tx <= 1'b0;     // 시작 비트: LOW
               if (baud_tick) begin
                  if (tx_bit_cnt == 4'd15) begin
                     tx_bit_cnt  <= '0;
                     tx_data_idx <= '0;
                     tx_state    <= TX_DATA;
                  end else begin
                     tx_bit_cnt <= tx_bit_cnt + 1;
                  end
               end
            end

            TX_DATA: begin
               uart_tx <= tx_shift_reg[tx_data_idx];  // LSB 먼저
               if (baud_tick) begin
                  if (tx_bit_cnt == 4'd15) begin
                     tx_bit_cnt <= '0;
                     if (tx_data_idx == 3'd7) begin
                        tx_state <= TX_STOP;
                     end else begin
                        tx_data_idx <= tx_data_idx + 1;
                     end
                  end else begin
                     tx_bit_cnt <= tx_bit_cnt + 1;
                  end
               end
            end

            TX_STOP: begin
               uart_tx <= 1'b1;     // 정지 비트: HIGH
               if (baud_tick) begin
                  if (tx_bit_cnt == 4'd15) begin
                     tx_state <= TX_IDLE;
                  end else begin
                     tx_bit_cnt <= tx_bit_cnt + 1;
                  end
               end
            end
         endcase
      end
   end

   // =========================================================================
   // RX 수신 FSM
   // =========================================================================
   typedef enum logic [1:0] {
      RX_IDLE  = 2'b00,
      RX_START = 2'b01,
      RX_DATA  = 2'b10,
      RX_STOP  = 2'b11
   } rx_state_t;

   rx_state_t rx_state;
   logic [3:0] rx_bit_cnt;
   logic [2:0] rx_data_idx;
   logic [7:0] rx_shift_reg;

   // 2단 동기화기 (메타안정성 방지)
   logic rx_sync_0, rx_sync_1;

   always_ff @(posedge pclk or negedge preset_n) begin
      if (!preset_n) begin
         rx_sync_0 <= 1'b1;
         rx_sync_1 <= 1'b1;
      end else begin
         rx_sync_0 <= uart_rx;
         rx_sync_1 <= rx_sync_0;
      end
   end

   always_ff @(posedge pclk or negedge preset_n) begin
      if (!preset_n) begin
         rx_state     <= RX_IDLE;
         rx_bit_cnt   <= '0;
         rx_data_idx  <= '0;
         rx_shift_reg <= '0;
         rx_fifo_push <= 1'b0;
         rx_fifo_wdata <= '0;
      end else begin
         rx_fifo_push <= 1'b0;

         case (rx_state)
            RX_IDLE: begin
               if (!rx_sync_1 && ctrl_reg[1]) begin  // 시작 비트 감지 (하강 에지)
                  rx_state   <= RX_START;
                  rx_bit_cnt <= '0;
               end
            end

            RX_START: begin
               if (baud_tick) begin
                  if (rx_bit_cnt == 4'd7) begin       // 시작 비트 중앙에서 샘플링
                     if (!rx_sync_1) begin             // 여전히 LOW → 유효한 시작 비트
                        rx_bit_cnt  <= '0;
                        rx_data_idx <= '0;
                        rx_state    <= RX_DATA;
                     end else begin
                        rx_state <= RX_IDLE;           // 노이즈 — 무시
                     end
                  end else begin
                     rx_bit_cnt <= rx_bit_cnt + 1;
                  end
               end
            end

            RX_DATA: begin
               if (baud_tick) begin
                  if (rx_bit_cnt == 4'd15) begin       // 비트 중앙에서 샘플링
                     rx_bit_cnt <= '0;
                     rx_shift_reg[rx_data_idx] <= rx_sync_1;  // LSB 먼저
                     if (rx_data_idx == 3'd7) begin
                        rx_state <= RX_STOP;
                     end else begin
                        rx_data_idx <= rx_data_idx + 1;
                     end
                  end else begin
                     rx_bit_cnt <= rx_bit_cnt + 1;
                  end
               end
            end

            RX_STOP: begin
               if (baud_tick) begin
                  if (rx_bit_cnt == 4'd15) begin
                     if (rx_sync_1) begin              // 정지 비트 = HIGH → 유효 프레임
                        rx_fifo_wdata <= rx_shift_reg;
                        rx_fifo_push  <= 1'b1;
                     end
                     rx_state <= RX_IDLE;
                  end else begin
                     rx_bit_cnt <= rx_bit_cnt + 1;
                  end
               end
            end
         endcase
      end
   end

   // =========================================================================
   // 간이 동기 FIFO (TX / RX 공용)
   // =========================================================================
   // 합성 가능한 포인터 기반 원형 버퍼
   logic [7:0]                   tx_fifo_mem [0:FIFO_DEPTH-1];
   logic [$clog2(FIFO_DEPTH):0]  tx_wr_ptr, tx_rd_ptr;

   assign tx_fifo_empty = (tx_wr_ptr == tx_rd_ptr);
   assign tx_fifo_full  = (tx_wr_ptr[$clog2(FIFO_DEPTH)] != tx_rd_ptr[$clog2(FIFO_DEPTH)]) &&
                           (tx_wr_ptr[$clog2(FIFO_DEPTH)-1:0] == tx_rd_ptr[$clog2(FIFO_DEPTH)-1:0]);
   assign tx_fifo_rdata = tx_fifo_mem[tx_rd_ptr[$clog2(FIFO_DEPTH)-1:0]];

   always_ff @(posedge pclk or negedge preset_n) begin
      if (!preset_n) begin
         tx_wr_ptr <= '0;
         tx_rd_ptr <= '0;
      end else begin
         if (tx_fifo_push && !tx_fifo_full) begin
            tx_fifo_mem[tx_wr_ptr[$clog2(FIFO_DEPTH)-1:0]] <= tx_fifo_wdata;
            tx_wr_ptr <= tx_wr_ptr + 1;
         end
         if (tx_fifo_pop && !tx_fifo_empty)
            tx_rd_ptr <= tx_rd_ptr + 1;
      end
   end

   logic [7:0]                   rx_fifo_mem [0:FIFO_DEPTH-1];
   logic [$clog2(FIFO_DEPTH):0]  rx_wr_ptr, rx_rd_ptr;

   assign rx_fifo_empty = (rx_wr_ptr == rx_rd_ptr);
   assign rx_fifo_full  = (rx_wr_ptr[$clog2(FIFO_DEPTH)] != rx_rd_ptr[$clog2(FIFO_DEPTH)]) &&
                           (rx_wr_ptr[$clog2(FIFO_DEPTH)-1:0] == rx_rd_ptr[$clog2(FIFO_DEPTH)-1:0]);
   assign rx_fifo_rdata = rx_fifo_mem[rx_rd_ptr[$clog2(FIFO_DEPTH)-1:0]];

   always_ff @(posedge pclk or negedge preset_n) begin
      if (!preset_n) begin
         rx_wr_ptr <= '0;
         rx_rd_ptr <= '0;
      end else begin
         if (rx_fifo_push && !rx_fifo_full) begin
            rx_fifo_mem[rx_wr_ptr[$clog2(FIFO_DEPTH)-1:0]] <= rx_fifo_wdata;
            rx_wr_ptr <= rx_wr_ptr + 1;
         end
         if (rx_fifo_pop && !rx_fifo_empty)
            rx_rd_ptr <= rx_rd_ptr + 1;
      end
   end

   // =========================================================================
   // APB 레지스터 읽기/쓰기
   // =========================================================================
   logic apb_write, apb_read;
   assign apb_write = psel && penable && pwrite;
   assign apb_read  = psel && penable && !pwrite;

   // TX FIFO 쓰기 신호
   assign tx_fifo_push  = apb_write && (paddr == ADDR_TX_DATA);
   assign tx_fifo_wdata = pwdata[7:0];

   // RX FIFO 읽기 신호
   assign rx_fifo_pop = apb_read && (paddr == ADDR_RX_DATA);

   // 레지스터 쓰기
   always_ff @(posedge pclk or negedge preset_n) begin
      if (!preset_n) begin
         ctrl_reg   <= 8'h03;        // TX_EN=1, RX_EN=1 (기본 활성화)
         baud_div   <= 16'd54;       // 115200 baud @ 100MHz 기본값
         int_en_reg <= '0;
      end else if (apb_write) begin
         case (paddr)
            ADDR_CTRL:     ctrl_reg   <= pwdata[7:0];
            ADDR_BAUD_DIV: baud_div   <= pwdata[15:0];
            ADDR_INT_EN:   int_en_reg <= pwdata[7:0];
            ADDR_INT_STATUS: begin
               // W1C (Write-1-to-Clear) 방식
               int_status_reg <= int_status_reg & ~pwdata[7:0];
            end
            default: ; // 무시
         endcase
      end
   end

   // 레지스터 읽기 멀티플렉서
   always_comb begin
      prdata = 32'h0;
      case (paddr)
         ADDR_TX_DATA:    prdata = 32'h0;    // 쓰기 전용
         ADDR_RX_DATA:    prdata = {24'h0, rx_fifo_rdata};
         ADDR_STATUS:     prdata = {28'h0, rx_fifo_full, ~rx_fifo_empty,
                                    tx_fifo_full, tx_fifo_empty};
         ADDR_CTRL:       prdata = {24'h0, ctrl_reg};
         ADDR_BAUD_DIV:   prdata = {16'h0, baud_div};
         ADDR_INT_EN:     prdata = {24'h0, int_en_reg};
         ADDR_INT_STATUS: prdata = {24'h0, int_status_reg};
         default:         prdata = 32'h0;
      endcase
   end

   // APB는 웨이트 스테이트 없이 즉시 응답
   assign pready = 1'b1;

   // =========================================================================
   // 인터럽트 로직
   // =========================================================================
   // TX FIFO 비면 int_status[0] 세트, RX 데이터 도착 시 int_status[1] 세트
   always_ff @(posedge pclk or negedge preset_n) begin
      if (!preset_n) begin
         int_status_reg <= '0;
      end else begin
         // W1C 쓰기는 위 레지스터 쓰기 블록에서 처리
         if (tx_fifo_empty)
            int_status_reg[0] <= 1'b1;
         if (!rx_fifo_empty)
            int_status_reg[1] <= 1'b1;
      end
   end

   assign uart_irq = |(int_status_reg & int_en_reg);

endmodule
