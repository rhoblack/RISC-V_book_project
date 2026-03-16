// ============================================================
// 클록 생성기 — Basys 3 (100MHz → 50MHz)
// ============================================================
// 방법 1: Vivado Clocking Wizard IP 사용 (권장)
// 방법 2: MMCME2_BASE 프리미티브 직접 인스턴스 (아래)
// ============================================================
module clk_gen (
   input  logic clk_100mhz,   // Basys 3 온보드 100MHz (핀 W5)
   input  logic rst_raw,       // 비동기 리셋 (btnC)
   output logic clk_50mhz,    // 시스템 클록 50MHz
   output logic locked         // PLL 잠금 상태
);

   logic clk_fb;               // 피드백 클록
   logic clk_out0_unbuf;       // 버퍼 전 출력

   // MMCME2_BASE: Artix-7 Mixed-Mode Clock Manager
   // 입력 100MHz × (CLKFBOUT_MULT_F / DIVCLK_DIVIDE) / CLKOUT0_DIVIDE_F
   // = 100 × (10.0 / 1) / 20.0 = 50MHz
   MMCME2_BASE #(
      .CLKIN1_PERIOD    (10.000),     // 100MHz = 10ns 주기
      .CLKFBOUT_MULT_F  (10.000),     // VCO = 100 × 10 = 1000MHz
      .DIVCLK_DIVIDE    (1),          // VCO 분주 없음
      .CLKOUT0_DIVIDE_F (20.000),     // 1000 / 20 = 50MHz
      .CLKOUT0_PHASE    (0.000)       // 위상 오프셋 없음
   ) mmcm_inst (
      .CLKIN1   (clk_100mhz),
      .RST      (rst_raw),
      .CLKFBIN  (clk_fb),
      .CLKFBOUT (clk_fb),
      .CLKOUT0  (clk_out0_unbuf),
      .LOCKED   (locked),
      // 미사용 출력
      .CLKOUT0B (),
      .CLKOUT1  (), .CLKOUT1B (),
      .CLKOUT2  (), .CLKOUT2B (),
      .CLKOUT3  (), .CLKOUT3B (),
      .CLKOUT4  (), .CLKOUT5  (), .CLKOUT6  (),
      .CLKFBOUTB(), .PWRDWN   (1'b0)
   );

   // 글로벌 클록 버퍼
   BUFG bufg_inst (
      .I (clk_out0_unbuf),
      .O (clk_50mhz)
   );

endmodule