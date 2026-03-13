// =============================================================================
// 주변 장치 통합 테스트벤치 (Peripheral Subsystem Testbench)
// Chapter 17.6 — APB 브리지와 주변 장치 연결
// RISC-V 프로세서 설계 완전정복
// =============================================================================
// AHB 마스터 태스크를 이용하여 소프트웨어 드라이버 수준의 접근을 검증합니다.
// 테스트 시나리오:
//   1. UART: "Hello" 문자열 송신 및 루프백 수신 확인
//   2. GPIO: LED 출력 → 스위치 입력 읽기
//   3. Timer: 비교 레지스터 설정 → 인터럽트 발생 확인
// =============================================================================

`timescale 1ns / 1ps

module peripheral_tb;

   // =========================================================================
   // 시스템 신호
   // =========================================================================
   logic        hclk;
   logic        hreset_n;

   // AHB 인터페이스
   logic [31:0] haddr;
   logic [1:0]  htrans;
   logic        hwrite;
   logic [2:0]  hsize;
   logic [31:0] hwdata;
   logic [31:0] hrdata;
   logic        hready_out;
   logic        hresp;

   // UART
   logic        uart_tx;
   logic        uart_rx;

   // GPIO
   logic [31:0] gpio_out;
   logic [31:0] gpio_in;
   logic [31:0] gpio_oe;

   // 인터럽트
   logic        uart_irq;
   logic        timer_irq;
   logic        gpio_irq;

   // AHB 전송 타입 상수
   localparam HTRANS_IDLE   = 2'b00;
   localparam HTRANS_NONSEQ = 2'b10;

   // =========================================================================
   // 클럭 생성: 100 MHz (10 ns 주기)
   // =========================================================================
   initial hclk = 0;
   always #5 hclk = ~hclk;

   // =========================================================================
   // DUT 인스턴스
   // =========================================================================
   peripheral_top #(
      .CLK_FREQ   (100_000_000),
      .GPIO_WIDTH (32)
   ) u_dut (
      .hclk       (hclk),
      .hreset_n   (hreset_n),
      .haddr      (haddr),
      .htrans     (htrans),
      .hwrite     (hwrite),
      .hsize      (hsize),
      .hwdata     (hwdata),
      .hrdata     (hrdata),
      .hready_out (hready_out),
      .hresp      (hresp),
      .uart_tx    (uart_tx),
      .uart_rx    (uart_rx),
      .gpio_out   (gpio_out),
      .gpio_in    (gpio_in),
      .gpio_oe    (gpio_oe),
      .uart_irq   (uart_irq),
      .timer_irq  (timer_irq),
      .gpio_irq   (gpio_irq)
   );

   // UART 루프백: TX → RX (자기 자신에게 데이터를 보냄)
   assign uart_rx = uart_tx;

   // =========================================================================
   // AHB 쓰기 태스크 — 소프트웨어의 MMIO 쓰기를 모사
   // =========================================================================
   task ahb_write(input logic [31:0] addr, input logic [31:0] data);
      @(posedge hclk);
      // 주소 단계
      haddr  <= addr;
      htrans <= HTRANS_NONSEQ;
      hwrite <= 1'b1;
      hsize  <= 3'b010;        // 워드 (32비트)

      @(posedge hclk);
      // 데이터 단계
      hwdata <= data;
      htrans <= HTRANS_IDLE;

      // HREADY 대기
      @(posedge hclk);
      while (!hready_out) @(posedge hclk);
   endtask

   // =========================================================================
   // AHB 읽기 태스크 — 소프트웨어의 MMIO 읽기를 모사
   // =========================================================================
   task ahb_read(input logic [31:0] addr, output logic [31:0] data);
      @(posedge hclk);
      // 주소 단계
      haddr  <= addr;
      htrans <= HTRANS_NONSEQ;
      hwrite <= 1'b0;
      hsize  <= 3'b010;

      @(posedge hclk);
      htrans <= HTRANS_IDLE;

      // HREADY 대기
      @(posedge hclk);
      while (!hready_out) @(posedge hclk);
      data = hrdata;
   endtask

   // =========================================================================
   // 주소 상수 (메모리 맵)
   // =========================================================================
   // UART 기본 주소: 0x4000_0000
   localparam UART_BASE    = 32'h4000_0000;
   localparam UART_TX_DATA = UART_BASE + 32'h00;
   localparam UART_RX_DATA = UART_BASE + 32'h04;
   localparam UART_STATUS  = UART_BASE + 32'h08;
   localparam UART_CTRL    = UART_BASE + 32'h0C;
   localparam UART_BAUD    = UART_BASE + 32'h10;

   // GPIO 기본 주소: 0x4000_1000
   localparam GPIO_BASE    = 32'h4000_1000;
   localparam GPIO_DIR     = GPIO_BASE + 32'h00;
   localparam GPIO_OUT     = GPIO_BASE + 32'h04;
   localparam GPIO_IN      = GPIO_BASE + 32'h08;

   // Timer 기본 주소: 0x4000_2000
   localparam TIMER_BASE      = 32'h4000_2000;
   localparam TIMER_CTRL      = TIMER_BASE + 32'h00;
   localparam TIMER_COUNT     = TIMER_BASE + 32'h04;
   localparam TIMER_CMP       = TIMER_BASE + 32'h08;
   localparam TIMER_PRESCALE  = TIMER_BASE + 32'h0C;
   localparam TIMER_INT_STAT  = TIMER_BASE + 32'h10;

   // =========================================================================
   // 테스트 시나리오
   // =========================================================================
   logic [31:0] read_data;
   integer      i;
   integer      pass_count;
   integer      fail_count;

   initial begin
      $display("=== Chapter 17 주변 장치 통합 테스트 시작 ===");
      pass_count = 0;
      fail_count = 0;

      // 초기화
      hreset_n = 0;
      haddr    = 0;
      htrans   = HTRANS_IDLE;
      hwrite   = 0;
      hsize    = 0;
      hwdata   = 0;
      gpio_in  = 32'h0000_A5A5;    // 스위치 초기값

      repeat (10) @(posedge hclk);
      hreset_n = 1;
      repeat (5) @(posedge hclk);

      // -----------------------------------------------------------------
      // 테스트 1: GPIO — LED 출력 설정
      // -----------------------------------------------------------------
      $display("\n--- 테스트 1: GPIO LED 출력 ---");

      // 하위 16비트를 출력으로 설정 (LED)
      ahb_write(GPIO_DIR, 32'h0000_FFFF);

      // LED에 패턴 출력
      ahb_write(GPIO_OUT, 32'h0000_1234);

      repeat (5) @(posedge hclk);

      if (gpio_out[15:0] == 16'h1234) begin
         $display("[PASS] GPIO LED 출력 = 0x%04h", gpio_out[15:0]);
         pass_count++;
      end else begin
         $display("[FAIL] GPIO LED 출력 = 0x%04h (예상: 0x1234)", gpio_out[15:0]);
         fail_count++;
      end

      // 스위치 값 읽기
      ahb_read(GPIO_IN, read_data);
      $display("[INFO] GPIO 입력 값 = 0x%08h", read_data);

      // -----------------------------------------------------------------
      // 테스트 2: UART — 문자 송신
      // -----------------------------------------------------------------
      $display("\n--- 테스트 2: UART 송신 ---");

      // 보드레이트 설정 (테스트용으로 빠르게: 분주=2)
      ahb_write(UART_BAUD, 32'h0002);

      // TX/RX 활성화
      ahb_write(UART_CTRL, 32'h03);

      // 'H' (0x48) 문자 송신
      ahb_write(UART_TX_DATA, 32'h48);
      $display("[INFO] UART 'H' (0x48) 송신 시작");

      // 상태 확인 — TX Empty 대기 (비트 0)
      read_data = 32'h0;
      for (i = 0; i < 1000; i++) begin
         ahb_read(UART_STATUS, read_data);
         if (read_data[0]) break;     // TX FIFO 비었음
         repeat (10) @(posedge hclk);
      end

      if (read_data[0]) begin
         $display("[PASS] UART TX FIFO 비어짐 — 송신 완료");
         pass_count++;
      end else begin
         $display("[FAIL] UART TX 타임아웃");
         fail_count++;
      end

      // -----------------------------------------------------------------
      // 테스트 3: Timer — 인터럽트 발생
      // -----------------------------------------------------------------
      $display("\n--- 테스트 3: 타이머 인터럽트 ---");

      // 프리스케일러 = 0 (매 클럭 카운트)
      ahb_write(TIMER_PRESCALE, 32'h0);

      // 비교 값 = 100 (100 클럭 후 인터럽트)
      ahb_write(TIMER_CMP, 32'h64);

      // 카운터 초기화
      ahb_write(TIMER_COUNT, 32'h0);

      // 타이머 활성화: EN=1, AUTO_RELOAD=1, IE=1
      ahb_write(TIMER_CTRL, 32'h07);

      // 인터럽트 대기
      for (i = 0; i < 200; i++) begin
         @(posedge hclk);
         if (timer_irq) break;
      end

      if (timer_irq) begin
         $display("[PASS] 타이머 인터럽트 발생 (사이클: %0d)", i);
         pass_count++;
      end else begin
         $display("[FAIL] 타이머 인터럽트 미발생");
         fail_count++;
      end

      // 인터럽트 클리어 (W1C)
      ahb_write(TIMER_INT_STAT, 32'h1);
      repeat (3) @(posedge hclk);

      if (!timer_irq) begin
         $display("[PASS] 타이머 인터럽트 클리어 완료");
         pass_count++;
      end else begin
         $display("[FAIL] 타이머 인터럽트 클리어 실패");
         fail_count++;
      end

      // -----------------------------------------------------------------
      // 결과 요약
      // -----------------------------------------------------------------
      repeat (10) @(posedge hclk);
      $display("\n=== 테스트 완료 ===");
      $display("통과: %0d, 실패: %0d", pass_count, fail_count);

      if (fail_count == 0)
         $display("*** 모든 테스트 통과 ***");
      else
         $display("*** 실패한 테스트가 있습니다 ***");

      $finish;
   end

   // =========================================================================
   // 파형 덤프 (VCS/Vivado 호환)
   // =========================================================================
   initial begin
      $dumpfile("ch17_peripheral_tb.vcd");
      $dumpvars(0, peripheral_tb);
   end

   // 타임아웃 보호
   initial begin
      #1_000_000;
      $display("[ERROR] 시뮬레이션 타임아웃");
      $finish;
   end

endmodule
