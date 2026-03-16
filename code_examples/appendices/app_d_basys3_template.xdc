# Appendix D: Basys 3 XDC 타이밍 제약 템플릿
# SystemVerilog - Vivado 합성 & 구현

# ============================================================
# 1. 시스템 클록 정의
# ============================================================
# Basys 3: 100 MHz 크리스탈 오실레이터
# 핀: E3

create_clock -period 10.000 -name sys_clk [get_ports clk_100mhz]

# 클록 지연 (선택사항)
set_clock_latency -source 0.500 [get_clocks sys_clk]
set_clock_jitter -setup 0.100 [get_clocks sys_clk]
set_clock_jitter -hold 0.050 [get_clocks sys_clk]

# ============================================================
# 2. 입력 포트 타이밍 제약
# ============================================================

# 일반 입력 (스위치, 버튼): 스위치는 느림 (debounce 고려)
set_input_delay -clock sys_clk -min 2.0 [get_ports sw_*]
set_input_delay -clock sys_clk -max 5.0 [get_ports sw_*]

set_input_delay -clock sys_clk -min 1.0 [get_ports btn_*]
set_input_delay -clock sys_clk -max 3.0 [get_ports btn_*]

# UART 입력 (RX): 보드 UART 칩 지연
set_input_delay -clock sys_clk -min 1.5 [get_ports uart_rx]
set_input_delay -clock sys_clk -max 4.0 [get_ports uart_rx]

# ============================================================
# 3. 출력 포트 타이밍 제약
# ============================================================

# LED 출력: 가변 지연 허용
set_output_delay -clock sys_clk -min -0.5 [get_ports led_*]
set_output_delay -clock sys_clk -max 2.0 [get_ports led_*]

# 7-세그먼트 출력: 느린 주변장치
set_output_delay -clock sys_clk -min -1.0 [get_ports seg_*]
set_output_delay -clock sys_clk -max 3.0 [get_ports seg_*]

set_output_delay -clock sys_clk -min -1.0 [get_ports an_*]
set_output_delay -clock sys_clk -max 3.0 [get_ports an_*]

# UART 출력 (TX): 보드 UART 칩 지연
set_output_delay -clock sys_clk -min -0.5 [get_ports uart_tx]
set_output_delay -clock sys_clk -max 2.0 [get_ports uart_tx]

# ============================================================
# 4. 비동기 신호 제약 (리셋)
# ============================================================

# 리셋은 클록과 비동기, 타이밍 제약 불필요
set_false_path -from [get_ports rst_n]

# ============================================================
# 5. 거짓 경로 (False Paths)
# ============================================================

# 클록 도메인 간 경로 (동기화 없음):
# 예: Clk1 → Clk2 (아무 관계 없음)
set_false_path -from [get_clocks clk1] -to [get_clocks clk2]

# 특정 신호 그룹 간 거짓 경로:
# 예: Config 신호는 느려도 됨
set_false_path -from [get_ports cfg_*] -to [get_ports data_*]

# ============================================================
# 6. 멀티사이클 경로 (Multi-Cycle Paths)
# ============================================================

# 느린 주변장치 (UART, SPI): 여러 사이클 허용
set_multicycle_path 4 -from [get_ports uart_*]
set_multicycle_path 4 -to [get_ports uart_*]

# 메모리 인터페이스 (느린 외부 SRAM):
set_multicycle_path 3 -from [get_ports mem_*]
set_multicycle_path 3 -to [get_ports mem_*]

# ============================================================
# 7. 최대 지연 제약
# ============================================================

# 전체 조합 경로의 최대 지연 (5ns 예):
# set_max_delay 5.0 -datapath_only

# 특정 경로의 최대 지연:
set_max_delay 3.0 -from [get_pins alu/sum_reg] -to [get_ports data_out]

# ============================================================
# 8. 시간 윈도우 (Timing Windows)
# ============================================================

# Setup time (데이터가 클록 이전에 안정)
set_setup_time 2.0

# Hold time (데이터가 클록 이후에 안정)
set_hold_time 1.0

# ============================================================
# 9. 전력 제약 (선택사항)
# ============================================================

# 최대 전력 소비
# set_property POWER_BUDGET 100 [current_design]

# ============================================================
# 10. 위치 제약 (Placement) — FPGA 물리 설계
# ============================================================

# Basys 3 핀 정의 (선택)
# set_property LOC E3 [get_ports clk_100mhz]
# set_property LOC D9 [get_ports rst_n]
# set_property LOC A17 [get_ports led[0]]
# ... (전체 핀 배치는 constraints.xdc에서)

# ============================================================
# 11. 입출력 기준 (I/O Voltage Standard)
# ============================================================

# Basys 3: 모든 I/O는 LVCMOS33 (3.3V)
# set_property IOSTANDARD LVCMOS33 [get_ports *]

# ============================================================
# 12. 합성 옵션 (Synthesis Directives)
# ============================================================

# (XDC에서는 제한적, 대부분 Tcl)
# Vivado 합성: tcl 스크립트로 관리

# ============================================================
# 기본 제약 규칙 (Best Practices)
# ============================================================

/*
1. 클록 정의는 항상 첫 번째
   create_clock -period ... [get_ports clk]

2. 입출력 지연은 실제 보드 지연 고려
   set_input_delay -clock clk -min 1.0 [get_ports sw_*]

3. 비동기 신호는 거짓 경로 설정
   set_false_path -from [get_ports rst_n]

4. 클록 도메인 신호는 동기화 또는 거짓 경로
   set_false_path -from [get_clocks clk1] -to [get_clocks clk2]

5. 느린 주변장치는 멀티사이클 경로
   set_multicycle_path 4 -to [get_ports uart_*]

6. 임계 경로 확인:
   report_timing -slack_lesser_than 0.0
*/
