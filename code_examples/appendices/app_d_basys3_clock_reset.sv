// Appendix D: Basys 3 클록 생성 & 리셋 동기화
// SystemVerilog - Vivado 합성 가능

// ============================================================
// 1. Basys 3 클록 소스
// ============================================================
/*
Basys 3 보드:
- 크리스탈 오실레이터: 100 MHz
- 핀: E3 (CK_100MHZ)
- I/O 전압: LVCMOS33 (3.3V)

다양한 클록 주파수 생성이 필요한 경우:
→ Vivado의 Clock Wizard IP 사용 (권장)
→ 또는 아래 PLL/MMCM 모듈 사용

본 예제: 100MHz → 50MHz, 25MHz 분주
*/

// ============================================================
// 2. 간단한 클록 분주 (Divider)
// ============================================================
module clock_divider #(
    parameter int DIV = 2  // 분주비
) (
    input  logic clk_in,
    input  logic rst_n,
    output logic clk_out
);

    logic [31:0] counter;

    always_ff @(posedge clk_in) begin
        if (!rst_n) begin
            counter <= 0;
            clk_out <= 0;
        end else begin
            if (counter == (DIV / 2 - 1)) begin
                counter <= 0;
                clk_out <= ~clk_out;  // Toggle
            end else begin
                counter <= counter + 1;
            end
        end
    end

endmodule

// ============================================================
// 3. 리셋 동기화 (Synchronizer)
// ============================================================
/*
리셋은 비동기 신호이므로, 클록 도메인에 진입 전 반드시 동기화
목적: 메타스테이블 상태 회피 (metastability)

동기화 단계:
비동기 rst_n (E3 핀) → FF1 → FF2 → 클록 도메인
                     (1 사이클) (1 사이클)
*/

module reset_synchronizer (
    input  logic clk,
    input  logic rst_n_async,
    output logic rst_n_sync
);

    logic ff1, ff2;

    always_ff @(posedge clk or negedge rst_n_async) begin
        if (!rst_n_async) begin
            ff1 <= 0;
            ff2 <= 0;
        end else begin
            ff1 <= 1;
            ff2 <= ff1;
        end
    end

    assign rst_n_sync = ff2;

endmodule

// ============================================================
// 4. Vivado Clock Wizard 대체 코드 (PLL 기초)
// ============================================================
/*
실제 FPGA에서는 Clock Wizard (IP) 권장:
1. Vivado IP Catalog → Clocking Wizard
2. 입력: 100 MHz
3. 출력: 50 MHz, 25 MHz 등
4. Auto-generated IP core 사용

아래는 개념적 예시 (합성 불가):
*/

module pll_example #(
    parameter real INPUT_FREQ = 100.0,   // MHz
    parameter real OUTPUT_FREQ = 50.0    // MHz
) (
    input  logic clk_in,
    input  logic rst_n,
    output logic clk_out,
    output logic locked
);

    // 실제 Vivado Clock Wizard 대신 다음과 같이 사용:
    // 1. Vivado IP Catalog에서 Clocking Wizard 선택
    // 2. INPUT: 100 MHz, OUTPUT: 50 MHz 설정
    // 3. 생성된 IP core를 RTL에 인스턴스화

    // 예시: Clock Wizard 생성 인스턴스
    // clk_wiz_v6_0 clk_wiz (
    //     .clk_in1(clk_in),
    //     .rst(~rst_n),
    //     .clk_out1(clk_out),
    //     .locked(locked)
    // );

endmodule

// ============================================================
// 5. 완전한 시스템: Basys 3 최상위 모듈
// ============================================================
module basys3_top (
    // Basys 3 보드 핀
    input  logic clk_100mhz,      // E3
    input  logic rst_n,            // D9 (버튼)

    // 사용자 로직 출력 (예: LED)
    input  logic [15:0] led_in,
    output logic [15:0] led_out,

    // 내부 클록 신호
    output logic clk_50mhz,
    output logic clk_25mhz,
    output logic rst_n_sync
);

    logic ff1_rst, ff2_rst;
    logic cnt_div;
    logic [1:0] div_counter;

    // ========================================================
    // 단계 1: 리셋 동기화
    // ========================================================
    always_ff @(posedge clk_100mhz or negedge rst_n) begin
        if (!rst_n) begin
            ff1_rst <= 0;
            ff2_rst <= 0;
        end else begin
            ff1_rst <= 1;
            ff2_rst <= ff1_rst;
        end
    end

    assign rst_n_sync = ff2_rst;

    // ========================================================
    // 단계 2: 클록 분주 (100 MHz → 50 MHz)
    // ========================================================
    always_ff @(posedge clk_100mhz) begin
        if (!rst_n_sync) begin
            cnt_div <= 0;
            clk_50mhz <= 0;
        end else begin
            if (cnt_div == 0) begin
                cnt_div <= 1;
                clk_50mhz <= ~clk_50mhz;
            end else begin
                cnt_div <= 0;
            end
        end
    end

    // ========================================================
    // 단계 3: 추가 분주 (100 MHz → 25 MHz)
    // ========================================================
    always_ff @(posedge clk_100mhz) begin
        if (!rst_n_sync) begin
            div_counter <= 0;
            clk_25mhz <= 0;
        end else begin
            if (div_counter == 3) begin
                div_counter <= 0;
                clk_25mhz <= ~clk_25mhz;
            end else begin
                div_counter <= div_counter + 1;
            end
        end
    end

    // ========================================================
    // 단계 4: 사용자 로직 (LED 점등)
    // ========================================================
    always_ff @(posedge clk_50mhz) begin
        if (!rst_n_sync)
            led_out <= 0;
        else
            led_out <= led_in;
    end

endmodule

// ============================================================
// 6. Basys 3 XDC 핀 배치 (참조용)
// ============================================================
/*
# Basys 3 Master XDC
# Xilinx Vivado 프로젝트 생성 시 기본 제공

# 클록
set_property -dict { PACKAGE_PIN E3    IOSTANDARD LVCMOS33 } [get_ports clk_100mhz]

# 리셋 (BTNC)
set_property -dict { PACKAGE_PIN D9    IOSTANDARD LVCMOS33 } [get_ports rst_n]

# LED (16개, LD15~LD0)
set_property -dict { PACKAGE_PIN H17   IOSTANDARD LVCMOS33 } [get_ports {led_out[0]}]
set_property -dict { PACKAGE_PIN K15   IOSTANDARD LVCMOS33 } [get_ports {led_out[1]}]
set_property -dict { PACKAGE_PIN J13   IOSTANDARD LVCMOS33 } [get_ports {led_out[2]}]
set_property -dict { PACKAGE_PIN G4    IOSTANDARD LVCMOS33 } [get_ports {led_out[3]}]
# ... (나머지 12개)

# 스위치 (SW15~SW0)
set_property -dict { PACKAGE_PIN A8    IOSTANDARD LVCMOS33 } [get_ports {sw[0]}]
set_property -dict { PACKAGE_PIN C11   IOSTANDARD LVCMOS33 } [get_ports {sw[1]}]
# ... (나머지 14개)

# 버튼
set_property -dict { PACKAGE_PIN D9    IOSTANDARD LVCMOS33 } [get_ports btnC]    # CENTER
set_property -dict { PACKAGE_PIN C17   IOSTANDARD LVCMOS33 } [get_ports btnU]    # UP
set_property -dict { PACKAGE_PIN D17   IOSTANDARD LVCMOS33 } [get_ports btnL]    # LEFT
set_property -dict { PACKAGE_PIN E18   IOSTANDARD LVCMOS33 } [get_ports btnR]    # RIGHT
set_property -dict { PACKAGE_PIN E17   IOSTANDARD LVCMOS33 } [get_ports btnD]    # DOWN

# UART (USB)
set_property -dict { PACKAGE_PIN A18   IOSTANDARD LVCMOS33 } [get_ports uart_tx] # TX
set_property -dict { PACKAGE_PIN B18   IOSTANDARD LVCMOS33 } [get_ports uart_rx] # RX

# 7-세그먼트 디스플레이 (선택)
set_property -dict { PACKAGE_PIN T10   IOSTANDARD LVCMOS33 } [get_ports {seg[0]}]
# ... (나머지)
*/

// ============================================================
// 7. 시뮬레이션용 테스트 코드
// ============================================================
module tb_basys3_clock;

    logic clk_100mhz, rst_n;
    logic clk_50mhz, clk_25mhz, rst_n_sync;
    logic [15:0] led_in, led_out;

    // DUT 인스턴스
    basys3_top dut (
        .clk_100mhz(clk_100mhz),
        .rst_n(rst_n),
        .led_in(led_in),
        .led_out(led_out),
        .clk_50mhz(clk_50mhz),
        .clk_25mhz(clk_25mhz),
        .rst_n_sync(rst_n_sync)
    );

    // 100 MHz 클록 생성
    initial begin
        clk_100mhz = 0;
        forever #5 clk_100mhz = ~clk_100mhz;  // 5ns = 10ns period = 100MHz
    end

    // 리셋 및 시뮬레이션
    initial begin
        rst_n = 0;
        led_in = 0;
        #50 rst_n = 1;

        #100 led_in = 16'hFFFF;
        #200 led_in = 16'h0F0F;

        #500 $finish;
    end

    // 클록 모니터링
    initial begin
        $monitor("Time: %t | clk_100: %b | clk_50: %b | clk_25: %b | rst: %b | led: %h",
                 $time, clk_100mhz, clk_50mhz, clk_25mhz, rst_n_sync, led_out);
    end

endmodule

// ============================================================
// 요약: 핵심 포인트
// ============================================================
/*
1. Basys 3 입력: 100 MHz 크리스탈 (E3)
2. 리셋: 동기화 필수 (메타스테이블 회피)
3. 클록 생성: 분주 또는 Clock Wizard
4. 핀 배치: Master XDC 사용 (Xilinx 제공)
5. 테스트: 시뮬레이션으로 클록 주파수 확인
*/
