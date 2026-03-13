// ============================================================================
// 모듈: clk_wizard_wrapper
// 설명: Basys 3 100MHz → 50MHz 클록 분주 래퍼
//       Vivado Clocking Wizard IP 대신 수동 구현 예제
// Chapter 20: FPGA 합성 최적화와 타이밍 클로저
// ============================================================================

module clk_wizard_wrapper (
   input  logic clk_100mhz,  // Basys 3 온보드 100MHz 클록
   input  logic rst_n,       // 비동기 리셋 (액티브 로우)
   output logic clk_50mhz,   // 50MHz 출력 클록
   output logic locked        // PLL 잠금 상태 (안정화 완료)
);

   // -----------------------------------------------------------------------
   // 방법 1: 간단한 토글 분주기 (교육용, 합성 가능)
   //         실무에서는 MMCM/PLL IP를 사용하는 것이 권장됨
   // -----------------------------------------------------------------------

   logic clk_div2;
   logic [3:0] lock_cnt;  // 잠금 카운터 (안정화 대기)

   // 100MHz → 50MHz: 매 상승 에지마다 토글
   always_ff @(posedge clk_100mhz or negedge rst_n) begin
      if (!rst_n) begin
         clk_div2 <= 1'b0;
      end else begin
         clk_div2 <= ~clk_div2;
      end
   end

   // 잠금 카운터: 리셋 해제 후 16사이클 대기
   always_ff @(posedge clk_100mhz or negedge rst_n) begin
      if (!rst_n) begin
         lock_cnt <= 4'd0;
      end else if (!lock_cnt[3]) begin
         lock_cnt <= lock_cnt + 4'd1;
      end
   end

   assign clk_50mhz = clk_div2;
   assign locked     = lock_cnt[3];  // 8사이클 후 안정화 완료

endmodule

// ============================================================================
// 모듈: sync_reset
// 설명: 비동기 리셋을 동기 리셋으로 변환
//       FPGA에서 비동기 리셋의 해제 시점(deassertion)이
//       클록 에지와 겹치면 메타스테이빌리티(metastability) 발생 가능.
//       2단 동기화기를 사용하여 안전하게 해제함.
// ============================================================================

module sync_reset (
   input  logic clk,
   input  logic rst_async_n,  // 비동기 리셋 (액티브 로우)
   output logic rst_sync_n    // 동기화된 리셋 (액티브 로우)
);

   logic rst_meta;  // 메타스테이빌리티 완화용 중간 레지스터

   // (* ASYNC_REG = "TRUE" *) — Vivado에 이 레지스터가
   // 비동기 입력을 받는다는 것을 알려, 배치 시 물리적으로
   // 인접하게 배치하도록 유도하는 합성 속성(attribute)
   (* ASYNC_REG = "TRUE" *)
   always_ff @(posedge clk or negedge rst_async_n) begin
      if (!rst_async_n) begin
         rst_meta   <= 1'b0;
         rst_sync_n <= 1'b0;
      end else begin
         rst_meta   <= 1'b1;
         rst_sync_n <= rst_meta;
      end
   end

endmodule

// ============================================================================
// 모듈: fpga_top
// 설명: Basys 3 최상위 모듈 — 클록 분주 + 리셋 동기화 + CPU 코어
//       합성 시 이 모듈이 XDC 제약의 대상이 됨
// ============================================================================

module fpga_top (
   input  logic        clk_100mhz,  // Basys 3 100MHz
   input  logic        rst_n,       // Center Button (액티브 로우)
   input  logic [15:0] sw,          // 슬라이드 스위치
   output logic [15:0] led,         // LED
   input  logic        uart_rxd,    // UART 수신
   output logic        uart_txd     // UART 송신
);

   // 내부 신호 선언
   logic clk_cpu;       // 50MHz CPU 클록
   logic pll_locked;    // PLL 잠금 상태
   logic rst_sync_n;    // 동기화된 리셋

   // -----------------------------------------------------------------------
   // 클록 생성: 100MHz → 50MHz
   // -----------------------------------------------------------------------
   clk_wizard_wrapper u_clk_wiz (
      .clk_100mhz (clk_100mhz),
      .rst_n       (rst_n),
      .clk_50mhz  (clk_cpu),
      .locked      (pll_locked)
   );

   // -----------------------------------------------------------------------
   // 리셋 동기화: 비동기 리셋 → 동기 리셋
   // PLL 잠금 전에는 리셋 상태 유지
   // -----------------------------------------------------------------------
   sync_reset u_sync_rst (
      .clk         (clk_cpu),
      .rst_async_n (rst_n & pll_locked),
      .rst_sync_n  (rst_sync_n)
   );

   // -----------------------------------------------------------------------
   // CPU 코어 인스턴스 (이전 챕터에서 설계한 모듈)
   // -----------------------------------------------------------------------
   // riscv_soc u_soc (
   //    .clk      (clk_cpu),
   //    .rst_n    (rst_sync_n),
   //    .gpio_in  (sw),
   //    .gpio_out (led),
   //    .uart_rx  (uart_rxd),
   //    .uart_tx  (uart_txd)
   // );

   // 임시: LED에 스위치 값 반영 (SoC 통합 전 I/O 테스트용)
   assign led     = sw;
   assign uart_txd = 1'b1;  // UART 유휴 상태

endmodule
