## ============================================================================
## 파일명  : ch01_basys3.xdc
## 설명    : Basys 3 FPGA 보드용 XDC 제약 파일 (LED 점멸 실습)
##           Xilinx Design Constraints 형식
## 대상 보드: Digilent Basys 3 (Artix-7 XC7A35TCPG236-1)
## 참고    : Digilent Basys 3 Reference Manual의 핀 배치 기준
## ============================================================================

## ---------------------------------------------------------------------------
## 클록 신호 (100MHz 온보드 오실레이터)
## ---------------------------------------------------------------------------
## Basys 3의 100MHz 클록은 W5 핀에 연결
set_property -dict { PACKAGE_PIN W5   IOSTANDARD LVCMOS33 } [get_ports {clk}]
create_clock -add -name sys_clk_pin -period 10.00 -waveform {0 5} [get_ports {clk}]

## ---------------------------------------------------------------------------
## 리셋 신호 (센터 푸시 버튼 — 능동 저 리셋)
## ---------------------------------------------------------------------------
## Basys 3 센터 버튼은 U18 핀에 연결
## 주의: 버튼을 누르면 HIGH, 떼면 LOW이므로
##       능동 저(Active-Low) 리셋으로 사용 시 반전 필요
##       본 실습에서는 btnC를 rst_n으로 직접 연결 (눌러서 리셋)
set_property -dict { PACKAGE_PIN U18  IOSTANDARD LVCMOS33 } [get_ports {rst_n}]

## ---------------------------------------------------------------------------
## LED 출력 (4개)
## ---------------------------------------------------------------------------
## Basys 3 LED[0] ~ LED[3]
set_property -dict { PACKAGE_PIN U16  IOSTANDARD LVCMOS33 } [get_ports {led[0]}]
set_property -dict { PACKAGE_PIN E19  IOSTANDARD LVCMOS33 } [get_ports {led[1]}]
set_property -dict { PACKAGE_PIN U19  IOSTANDARD LVCMOS33 } [get_ports {led[2]}]
set_property -dict { PACKAGE_PIN V19  IOSTANDARD LVCMOS33 } [get_ports {led[3]}]

## ---------------------------------------------------------------------------
## 비트스트림 설정
## ---------------------------------------------------------------------------
## SPI 플래시 프로그래밍을 위한 설정 (선택 사항)
set_property CFGBVS VCCO [current_design]
set_property CONFIG_VOLTAGE 3.3 [current_design]
set_property BITSTREAM.GENERAL.COMPRESS TRUE [current_design]
