// ============================================================
// ch22_soc_top.sv — 최종 SoC 최상위 모듈 (Basys 3 래퍼)
// RISC-V 프로세서 설계 완전정복 | Chapter 22
// ============================================================
// 이 모듈은 Chapter 20~21에서 완성한 SoC를 Basys 3 보드의
// 물리적 핀에 연결하는 최상위 래퍼입니다.
// ============================================================

module soc_top (
   // 시스템 클록 및 리셋
   input  logic        CLK100MHZ,     // Basys 3 100 MHz 오실레이터
   input  logic        BTNC,          // 중앙 버튼 (리셋)

   // UART (USB-UART 브리지)
   input  logic        UART_TXD_IN,   // UART RX (FPGA 입장)
   output logic        UART_RXD_OUT,  // UART TX (FPGA 입장)

   // LED
   output logic [15:0] LED,

   // 슬라이드 스위치
   input  logic [15:0] SW,

   // 7-세그먼트 디스플레이 (선택적 디버그용)
   output logic [6:0]  SEG,
   output logic [3:0]  AN,
   output logic        DP
);

   // -------------------------------------------------------
   // 클록 분주: 100 MHz → 50 MHz
   // -------------------------------------------------------
   logic clk_50mhz;
   logic locked;

   // 간단한 토글 분주기 (프로토타입용)
   // 실제 구현에서는 Xilinx MMCM/PLL IP 사용 권장
   logic clk_div;
   always_ff @(posedge CLK100MHZ or posedge BTNC) begin
      if (BTNC)
         clk_div <= 1'b0;
      else
         clk_div <= ~clk_div;
   end
   assign clk_50mhz = clk_div;
   assign locked = 1'b1;  // 프로토타입: 항상 잠김 상태

   // -------------------------------------------------------
   // 리셋 동기화 (2단계 동기화기)
   // -------------------------------------------------------
   logic rst_n;
   logic [1:0] rst_sync;

   always_ff @(posedge clk_50mhz or posedge BTNC) begin
      if (BTNC)
         rst_sync <= 2'b00;
      else
         rst_sync <= {rst_sync[0], locked};
   end
   assign rst_n = rst_sync[1];

   // -------------------------------------------------------
   // 스위치 디바운서 (간략화 — 실제는 Ch01 참조)
   // -------------------------------------------------------
   logic [15:0] sw_debounced;
   assign sw_debounced = SW;  // 프로토타입: 디바운싱 생략

   // -------------------------------------------------------
   // RV32I SoC 인스턴스
   // -------------------------------------------------------
   // 이 모듈은 Ch09~Ch21에서 설계한 전체 SoC 계층을 포함:
   //   - RV32I 5단계 파이프라인 CPU
   //   - L1 I-Cache / D-Cache
   //   - AHB-Lite 버스
   //   - APB 브리지 + 주변 장치 (UART, GPIO, Timer)
   //   - SRAM (BRAM 기반 IMEM/DMEM)

   logic        uart_tx;
   logic        uart_rx;
   logic [15:0] gpio_out;
   logic [15:0] gpio_in;

   rv32i_soc #(
      .CLK_FREQ    (50_000_000),
      .BAUD_RATE   (115200),
      .IMEM_SIZE_KB(16),
      .DMEM_SIZE_KB(8)
   ) u_soc (
      .clk_i       (clk_50mhz),
      .rst_ni      (rst_n),

      // UART
      .uart_rx_i   (uart_rx),
      .uart_tx_o   (uart_tx),

      // GPIO
      .gpio_in_i   ({16'b0, sw_debounced}),
      .gpio_out_o  (gpio_out),

      // 디버그 포트 (선택)
      .dbg_pc_o    (),
      .dbg_instr_o ()
   );

   // -------------------------------------------------------
   // 핀 매핑
   // -------------------------------------------------------
   assign UART_RXD_OUT = uart_tx;
   assign uart_rx      = UART_TXD_IN;
   assign LED          = gpio_out;
   assign gpio_in      = {sw_debounced};

   // 7-세그먼트: 미사용 시 소등
   assign SEG = 7'b111_1111;
   assign AN  = 4'b1111;
   assign DP  = 1'b1;

endmodule
