# ============================================================================
# app_e_vivado_tcl_script.tcl
# Vivado Tcl 자동화 스크립트: Basys 3 LED 깜박이기 프로젝트
# ============================================================================
# 사용법: Vivado Tcl Console에서 실행
#   vivado -mode batch -source app_e_vivado_tcl_script.tcl
# ============================================================================

# --- 1단계: 프로젝트 생성 ---
# Basys 3 보드의 Artix-7 FPGA (xc7a35tcpg236-1) 대상
set project_name "led_blink_test"
set project_dir  "C:/vivado_projects/${project_name}"

# 기존 프로젝트 폴더가 있으면 삭제 (주의: 기존 작업 유실)
if {[file exists $project_dir]} {
    file delete -force $project_dir
}

create_project $project_name $project_dir -part xc7a35tcpg236-1
set_property board_part digilentinc.com:basys3:part0:1.2 [current_project]

# --- 2단계: RTL 소스 파일 추가 ---
# led_blink.sv: 100MHz 클록 → 1Hz LED 토글
set sv_content {
module led_blink(
    input  clk,        // 100 MHz (Basys 3 보드 클록)
    input  rst_n,      // 능동 저전압 리셋 (BTN3)
    output led_out     // LED[0] 출력
);
    logic [26:0] counter;  // 27비트 카운터 (~1.34초 주기)

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            counter <= 27'd0;
        else
            counter <= counter + 1'b1;
    end

    // counter[26]: 약 0.67초 ON / 0.67초 OFF → 1Hz 깜박임
    assign led_out = counter[26];
endmodule
}

# 임시 파일 생성 후 프로젝트에 추가
set sv_file "${project_dir}/led_blink.sv"
set fp [open $sv_file w]
puts $fp $sv_content
close $fp
add_files $sv_file
set_property file_type SystemVerilog [get_files $sv_file]

# --- 3단계: XDC 제약 파일 추가 ---
# Basys 3 핀 매핑 (클록, 리셋, LED)
set xdc_content {
## 100 MHz 클록 (Basys 3)
set_property -dict {PACKAGE_PIN W5 IOSTANDARD LVCMOS33} [get_ports clk]
create_clock -add -name sys_clk -period 10.00 -waveform {0 5} [get_ports clk]

## 리셋 (BTN3, 능동 저전압)
set_property -dict {PACKAGE_PIN U18 IOSTANDARD LVCMOS33} [get_ports rst_n]

## LED[0] 출력
set_property -dict {PACKAGE_PIN V17 IOSTANDARD LVCMOS33} [get_ports led_out]
}

set xdc_file "${project_dir}/basys3.xdc"
set fp [open $xdc_file w]
puts $fp $xdc_content
close $fp
add_files -fileset constrs_1 $xdc_file

# --- 4단계: 합성 (Synthesis) ---
puts "========================================="
puts " 합성 시작..."
puts "========================================="
launch_runs synth_1 -jobs 4
wait_on_run synth_1
if {[get_property STATUS [get_runs synth_1]] != "synth_design Complete!"} {
    puts "오류: 합성 실패!"
    exit 1
}
puts "합성 완료!"

# --- 5단계: 구현 (Implementation) ---
puts "========================================="
puts " 구현(P&R) 시작..."
puts "========================================="
launch_runs impl_1 -jobs 4
wait_on_run impl_1
if {[get_property STATUS [get_runs impl_1]] != "route_design Complete!"} {
    puts "오류: 구현 실패!"
    exit 1
}
puts "구현 완료!"

# --- 6단계: 비트스트림 생성 ---
puts "========================================="
puts " 비트스트림 생성 시작..."
puts "========================================="
launch_runs impl_1 -to_step write_bitstream -jobs 4
wait_on_run impl_1

set bit_file "${project_dir}/${project_name}.runs/impl_1/led_blink.bit"
if {[file exists $bit_file]} {
    puts "비트스트림 생성 성공: $bit_file"
} else {
    puts "오류: 비트스트림 파일을 찾을 수 없습니다!"
    exit 1
}

puts ""
puts "========================================="
puts " 모든 단계 완료!"
puts " 비트스트림: $bit_file"
puts " 다음 단계: Tools → Program Device에서"
puts "            이 .bit 파일을 FPGA에 로드하세요."
puts "========================================="
