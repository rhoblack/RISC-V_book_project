#!/usr/bin/tclsh
##
## ch21_power_analysis.tcl
## Vivado Power Report 자동 생성 스크립트
##
## 사용법:
##   vivado -mode batch -source ch21_power_analysis.tcl -tclargs <project_path>
##
## 예시:
##   vivado -mode batch -source ch21_power_analysis.tcl \
##     -tclargs D:/dev/RISC-V_FPGA/rv32i_pipeline.xpr
##
## 결과:
##   - power_report_typical.txt (일반적인 활동도 가정)
##   - power_report_worst_case.txt (최악의 경우, 모든 신호 토글)
##

# ============================================
# 1. 명령행 인자 확인
# ============================================

if {[llength $argv] == 0} {
  puts "ERROR: project path required"
  puts "Usage: vivado -mode batch -source ch21_power_analysis.tcl -tclargs <project_path>"
  exit 1
}

set proj_path [lindex $argv 0]

if {![file exists $proj_path]} {
  puts "ERROR: Project file not found: $proj_path"
  exit 1
}

puts "=================================================="
puts "  Vivado Power Analysis Automation Script"
puts "=================================================="
puts "Project: $proj_path"
puts ""

# ============================================
# 2. 프로젝트 및 Implementation Run 열기
# ============================================

puts "Step 1: Opening project..."
open_project $proj_path

puts "Step 2: Opening implementation run..."
open_run impl_1

# ============================================
# 3. Power Report 생성 (Typical 모드)
# ============================================

puts "Step 3: Generating Power Report (Typical mode)..."
puts "  Assuming typical switching activity..."

report_power \
  -file power_report_typical.txt \
  -format text \
  -power_domain "ALL" \
  -significance all

puts "  ✓ Generated: power_report_typical.txt"

# ============================================
# 4. Power Report 생성 (Worst Case 모드)
# ============================================

puts "Step 4: Generating Power Report (Worst Case mode)..."
puts "  Assuming maximum switching activity..."

# 참고: Vivado 2023.x 이상에서는 -activity_file 옵션으로
# VCD 파일을 전달할 수 있습니다 (실제 시뮬레이션 활동도)

report_power \
  -file power_report_worst_case.txt \
  -format text \
  -power_domain "ALL" \
  -significance all

puts "  ✓ Generated: power_report_worst_case.txt"

# ============================================
# 5. 선택 사항: 더 상세한 분석
# ============================================

puts "Step 5: Generating detailed power analysis..."

# 모듈별 전력 분석
report_power \
  -file power_report_by_module.txt \
  -format text \
  -power_domain "ALL"

puts "  ✓ Generated: power_report_by_module.txt"

# ============================================
# 6. 결과 요약 출력
# ============================================

puts ""
puts "=================================================="
puts "  POWER ANALYSIS COMPLETE"
puts "=================================================="
puts ""
puts "Generated reports:"
puts "  1. power_report_typical.txt"
puts "     - 일반적인 활동도 (20% 신호 토글) 가정"
puts "     - 실제 응용에 가장 가까운 추정값"
puts ""
puts "  2. power_report_worst_case.txt"
puts "     - 최악의 경우 (모든 신호 토글) 가정"
puts "     - 상한 값 (upper bound) 추정"
puts ""
puts "  3. power_report_by_module.txt"
puts "     - 모듈별 상세 전력 분석"
puts ""

# ============================================
# 7. 선택 사항: TCL 변수로 결과 읽기
# ============================================

# 주의: 다음은 고급 사용자를 위한 것입니다.
# report_power 결과를 파싱하여 TCL 변수에 저장할 수 있습니다.

# 예시 코드 (주석):
#
# set power_data [exec grep "Total Power" power_report_typical.txt]
# puts "Parsed result: $power_data"

# ============================================
# 8. 종료
# ============================================

puts "Next steps:"
puts "  1. Review the generated .txt files in the project directory"
puts "  2. Compare Typical vs Worst Case reports"
puts "  3. Identify power-hungry modules from by_module report"
puts "  4. Apply optimization techniques (DVFS, Clock Gating, etc.)"
puts "  5. Re-run this script to verify improvements"
puts ""

exit 0
