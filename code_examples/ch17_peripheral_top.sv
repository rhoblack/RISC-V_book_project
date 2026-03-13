// =============================================================================
// 주변 장치 통합 Top 모듈 (Peripheral Subsystem Top)
// Chapter 17.6 — APB 브리지와 주변 장치 연결
// RISC-V 프로세서 설계 완전정복
// =============================================================================
// AHB-to-APB 브리지 + UART + GPIO + Timer를 하나의 서브시스템으로 통합.
// AHB 인터페이스를 통해 프로세서 코어와 연결되며,
// 각 APB 슬레이브에서 발생한 인터럽트 신호를 OR 결합하여 출력합니다.
// =============================================================================

module peripheral_top #(
   parameter CLK_FREQ   = 100_000_000,   // 시스템 클럭 (Hz)
   parameter GPIO_WIDTH = 32             // GPIO 핀 수
)(
   // 시스템 신호
   input  logic        hclk,             // AHB/APB 클럭
   input  logic        hreset_n,         // 비동기 리셋

   // AHB Slave 인터페이스 (프로세서 → 브리지)
   input  logic [31:0] haddr,
   input  logic [1:0]  htrans,
   input  logic        hwrite,
   input  logic [2:0]  hsize,
   input  logic [31:0] hwdata,
   output logic [31:0] hrdata,
   output logic        hready_out,
   output logic        hresp,

   // UART 물리 핀
   output logic        uart_tx,
   input  logic        uart_rx,

   // GPIO 물리 핀
   output logic [GPIO_WIDTH-1:0] gpio_out,
   input  logic [GPIO_WIDTH-1:0] gpio_in,
   output logic [GPIO_WIDTH-1:0] gpio_oe,

   // 인터럽트 출력 (프로세서의 외부 인터럽트 입력으로 연결)
   output logic        uart_irq,
   output logic        timer_irq,
   output logic        gpio_irq
);

   // =========================================================================
   // 브리지 → APB 슬레이브 연결 신호
   // =========================================================================
   logic [31:0] paddr;
   logic [3:0]  psel;
   logic        penable;
   logic        pwrite;
   logic [31:0] pwdata;

   // 각 슬레이브 응답 신호
   logic [31:0] prdata_uart, prdata_gpio, prdata_timer;
   logic        pready_uart, pready_gpio, pready_timer;

   // 읽기 데이터 멀티플렉서 — 선택된 슬레이브의 PRDATA를 브리지에 전달
   logic [31:0] prdata_mux;
   logic        pready_mux;

   always_comb begin
      prdata_mux = 32'h0;
      pready_mux = 1'b1;

      if (psel[0]) begin           // UART
         prdata_mux = prdata_uart;
         pready_mux = pready_uart;
      end else if (psel[1]) begin  // GPIO
         prdata_mux = prdata_gpio;
         pready_mux = pready_gpio;
      end else if (psel[2]) begin  // Timer
         prdata_mux = prdata_timer;
         pready_mux = pready_timer;
      end
   end

   // =========================================================================
   // AHB-to-APB 브리지 인스턴스
   // =========================================================================
   ahb_to_apb_bridge #(
      .ADDR_WIDTH (32),
      .DATA_WIDTH (32),
      .NUM_SLAVES (4)
   ) u_bridge (
      .hclk       (hclk),
      .hreset_n   (hreset_n),

      // AHB 측
      .haddr      (haddr),
      .htrans     (htrans),
      .hwrite     (hwrite),
      .hsize      (hsize),
      .hwdata     (hwdata),
      .hrdata     (hrdata),
      .hready_out (hready_out),
      .hresp      (hresp),

      // APB 측
      .paddr      (paddr),
      .psel       (psel),
      .penable    (penable),
      .pwrite     (pwrite),
      .pwdata     (pwdata),
      .prdata     (prdata_mux),
      .pready     (pready_mux)
   );

   // =========================================================================
   // APB Slave 0: UART 컨트롤러
   // =========================================================================
   apb_uart #(
      .CLK_FREQ   (CLK_FREQ),
      .FIFO_DEPTH (8)
   ) u_uart (
      .pclk       (hclk),
      .preset_n   (hreset_n),
      .psel       (psel[0]),
      .penable    (penable),
      .pwrite     (pwrite),
      .paddr      (paddr[4:0]),
      .pwdata     (pwdata),
      .prdata     (prdata_uart),
      .pready     (pready_uart),
      .uart_tx    (uart_tx),
      .uart_rx    (uart_rx),
      .uart_irq   (uart_irq)
   );

   // =========================================================================
   // APB Slave 1: GPIO 컨트롤러
   // =========================================================================
   apb_gpio #(
      .GPIO_WIDTH (GPIO_WIDTH)
   ) u_gpio (
      .pclk       (hclk),
      .preset_n   (hreset_n),
      .psel       (psel[1]),
      .penable    (penable),
      .pwrite     (pwrite),
      .paddr      (paddr[4:0]),
      .pwdata     (pwdata),
      .prdata     (prdata_gpio),
      .pready     (pready_gpio),
      .gpio_out   (gpio_out),
      .gpio_in    (gpio_in),
      .gpio_oe    (gpio_oe),
      .gpio_irq   (gpio_irq)
   );

   // =========================================================================
   // APB Slave 2: 타이머/카운터
   // =========================================================================
   apb_timer u_timer (
      .pclk       (hclk),
      .preset_n   (hreset_n),
      .psel       (psel[2]),
      .penable    (penable),
      .pwrite     (pwrite),
      .paddr      (paddr[4:0]),
      .pwdata     (pwdata),
      .prdata     (prdata_timer),
      .pready     (pready_timer),
      .timer_irq  (timer_irq)
   );

endmodule
