## ============================================================================
## XDC 제약 파일: RV32I 파이프라인 프로세서 — Basys 3 (XC7A35T)
## Chapter 20: FPGA 합성 최적화와 타이밍 클로저
## ============================================================================

## ---------------------------------------------------------------------------
## 1. 클록 제약 (Clock Constraint)
## ---------------------------------------------------------------------------
## Basys 3 온보드 클록: 100MHz (W5 핀)
## 목표 동작 주파수: 50MHz → 주기 20ns
## MMCM/PLL을 사용하여 100MHz → 50MHz 분주 후 내부 클록으로 사용
## ---------------------------------------------------------------------------

# 온보드 100MHz 클록 정의
set_property -dict { PACKAGE_PIN W5  IOSTANDARD LVCMOS33 } [get_ports { clk_100mhz }]
create_clock -name sys_clk -period 10.000 [get_ports { clk_100mhz }]

# MMCM 출력 50MHz 클록 (Clocking Wizard IP 사용 시 자동 생성됨)
# 수동으로 생성된 클록을 정의하는 경우:
# create_generated_clock -name cpu_clk -source [get_ports clk_100mhz] \
#   -divide_by 2 [get_pins clk_gen/clk_out1]

## ---------------------------------------------------------------------------
## 2. 리셋 제약
## ---------------------------------------------------------------------------
## Basys 3 Center Button (U18)을 리셋으로 사용
## 비동기 리셋이므로 false path 설정
## ---------------------------------------------------------------------------

set_property -dict { PACKAGE_PIN U18  IOSTANDARD LVCMOS33 } [get_ports { rst_n }]
set_false_path -from [get_ports { rst_n }]

## ---------------------------------------------------------------------------
## 3. LED 출력 핀 매핑
## ---------------------------------------------------------------------------

set_property -dict { PACKAGE_PIN U16  IOSTANDARD LVCMOS33 } [get_ports { led[0]  }]
set_property -dict { PACKAGE_PIN E19  IOSTANDARD LVCMOS33 } [get_ports { led[1]  }]
set_property -dict { PACKAGE_PIN U19  IOSTANDARD LVCMOS33 } [get_ports { led[2]  }]
set_property -dict { PACKAGE_PIN V19  IOSTANDARD LVCMOS33 } [get_ports { led[3]  }]
set_property -dict { PACKAGE_PIN W18  IOSTANDARD LVCMOS33 } [get_ports { led[4]  }]
set_property -dict { PACKAGE_PIN U15  IOSTANDARD LVCMOS33 } [get_ports { led[5]  }]
set_property -dict { PACKAGE_PIN U14  IOSTANDARD LVCMOS33 } [get_ports { led[6]  }]
set_property -dict { PACKAGE_PIN V14  IOSTANDARD LVCMOS33 } [get_ports { led[7]  }]
set_property -dict { PACKAGE_PIN V13  IOSTANDARD LVCMOS33 } [get_ports { led[8]  }]
set_property -dict { PACKAGE_PIN V3   IOSTANDARD LVCMOS33 } [get_ports { led[9]  }]
set_property -dict { PACKAGE_PIN W3   IOSTANDARD LVCMOS33 } [get_ports { led[10] }]
set_property -dict { PACKAGE_PIN U3   IOSTANDARD LVCMOS33 } [get_ports { led[11] }]
set_property -dict { PACKAGE_PIN P3   IOSTANDARD LVCMOS33 } [get_ports { led[12] }]
set_property -dict { PACKAGE_PIN N3   IOSTANDARD LVCMOS33 } [get_ports { led[13] }]
set_property -dict { PACKAGE_PIN P1   IOSTANDARD LVCMOS33 } [get_ports { led[14] }]
set_property -dict { PACKAGE_PIN L1   IOSTANDARD LVCMOS33 } [get_ports { led[15] }]

## ---------------------------------------------------------------------------
## 4. 슬라이드 스위치 입력 핀 매핑
## ---------------------------------------------------------------------------

set_property -dict { PACKAGE_PIN V17  IOSTANDARD LVCMOS33 } [get_ports { sw[0]  }]
set_property -dict { PACKAGE_PIN V16  IOSTANDARD LVCMOS33 } [get_ports { sw[1]  }]
set_property -dict { PACKAGE_PIN W16  IOSTANDARD LVCMOS33 } [get_ports { sw[2]  }]
set_property -dict { PACKAGE_PIN W17  IOSTANDARD LVCMOS33 } [get_ports { sw[3]  }]
set_property -dict { PACKAGE_PIN W15  IOSTANDARD LVCMOS33 } [get_ports { sw[4]  }]
set_property -dict { PACKAGE_PIN V15  IOSTANDARD LVCMOS33 } [get_ports { sw[5]  }]
set_property -dict { PACKAGE_PIN W14  IOSTANDARD LVCMOS33 } [get_ports { sw[6]  }]
set_property -dict { PACKAGE_PIN W13  IOSTANDARD LVCMOS33 } [get_ports { sw[7]  }]
set_property -dict { PACKAGE_PIN V2   IOSTANDARD LVCMOS33 } [get_ports { sw[8]  }]
set_property -dict { PACKAGE_PIN T3   IOSTANDARD LVCMOS33 } [get_ports { sw[9]  }]
set_property -dict { PACKAGE_PIN T2   IOSTANDARD LVCMOS33 } [get_ports { sw[10] }]
set_property -dict { PACKAGE_PIN R3   IOSTANDARD LVCMOS33 } [get_ports { sw[11] }]
set_property -dict { PACKAGE_PIN W2   IOSTANDARD LVCMOS33 } [get_ports { sw[12] }]
set_property -dict { PACKAGE_PIN U1   IOSTANDARD LVCMOS33 } [get_ports { sw[13] }]
set_property -dict { PACKAGE_PIN T1   IOSTANDARD LVCMOS33 } [get_ports { sw[14] }]
set_property -dict { PACKAGE_PIN R2   IOSTANDARD LVCMOS33 } [get_ports { sw[15] }]

## ---------------------------------------------------------------------------
## 5. UART 핀 매핑 (USB-UART 브리지)
## ---------------------------------------------------------------------------

set_property -dict { PACKAGE_PIN B18  IOSTANDARD LVCMOS33 } [get_ports { uart_rxd }]
set_property -dict { PACKAGE_PIN A18  IOSTANDARD LVCMOS33 } [get_ports { uart_txd }]

## ---------------------------------------------------------------------------
## 6. I/O 타이밍 제약
## ---------------------------------------------------------------------------
## 스위치/버튼은 비동기 입력이므로 false path 또는 넉넉한 input delay 설정
## LED 출력은 사람이 관찰하므로 타이밍이 느슨해도 무방
## ---------------------------------------------------------------------------

# 스위치 입력: 비동기이므로 false path
set_false_path -from [get_ports { sw[*] }]

# LED 출력: 타이밍 비관련
set_false_path -to [get_ports { led[*] }]

# UART I/O: 115200 baud 기준, 비트 주기 ~8.68us → 내부 클록 대비 매우 느림
set_input_delay  -clock sys_clk -max 3.0 [get_ports { uart_rxd }]
set_input_delay  -clock sys_clk -min 0.0 [get_ports { uart_rxd }]
set_output_delay -clock sys_clk -max 3.0 [get_ports { uart_txd }]
set_output_delay -clock sys_clk -min 0.0 [get_ports { uart_txd }]

## ---------------------------------------------------------------------------
## 7. 거짓 경로 및 멀티사이클 경로 (선택)
## ---------------------------------------------------------------------------
## CSR 레지스터 간 경로처럼 1사이클 내에 도달할 필요 없는 경로가 있으면
## set_multicycle_path를 사용하여 타이밍 여유를 확보할 수 있음
## ---------------------------------------------------------------------------

# 예시: CSR 쓰기 후 다음 사이클에 읽기 허용 (2사이클 경로)
# set_multicycle_path 2 -setup -from [get_cells cpu/csr_reg*] \
#                               -to   [get_cells cpu/csr_reg*]
# set_multicycle_path 1 -hold  -from [get_cells cpu/csr_reg*] \
#                               -to   [get_cells cpu/csr_reg*]

## ---------------------------------------------------------------------------
## 8. 비트스트림 설정
## ---------------------------------------------------------------------------

set_property CFGBVS VCCO [current_design]
set_property CONFIG_VOLTAGE 3.3 [current_design]
set_property BITSTREAM.GENERAL.COMPRESS TRUE [current_design]
set_property BITSTREAM.CONFIG.CONFIGRATE 33 [current_design]
set_property CONFIG_MODE SPIx4 [current_design]
