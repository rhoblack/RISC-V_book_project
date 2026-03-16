#!/bin/bash
# app_f_riscv_tests_build.sh
# riscv-tests 빌드 및 Spike 검증 자동화 스크립트
# 사용법: bash app_f_riscv_tests_build.sh

set -e  # 오류 발생 시 중단

echo "=========================================="
echo "RISC-V 공식 테스트 스위트 빌드"
echo "=========================================="

# Step 1: riscv-tests 클론
if [ ! -d "riscv-tests" ]; then
  echo "[Step 1] GitHub에서 riscv-tests 클론 중..."
  git clone https://github.com/riscv-software-src/riscv-tests.git
  cd riscv-tests
else
  echo "[Step 1] riscv-tests 이미 존재"
  cd riscv-tests
fi

# Step 2: 환경 변수 확인
echo ""
echo "[Step 2] 환경 변수 확인"
if [ -z "$RISCV" ]; then
  echo "⚠️  RISCV 환경변수가 설정되지 않음"
  echo "   설정 방법: export RISCV=/path/to/riscv"
  exit 1
else
  echo "✅ RISCV=$RISCV"
fi

# Step 3: riscv-tests 빌드
echo ""
echo "[Step 3] riscv-tests 빌드 중..."
echo "         (이 단계는 2~10분 소요됨)"

make XLEN=32 rv32ui

if [ $? -eq 0 ]; then
  echo "✅ 빌드 성공"
else
  echo "❌ 빌드 실패"
  exit 1
fi

# Step 4: 생성된 파일 확인
echo ""
echo "[Step 4] 생성된 테스트 파일 확인"
test_count=$(find isa/rv32ui -name "*-p-*.elf" | wc -l)
echo "✅ 생성된 rv32ui 테스트: $test_count개"

# Step 5: Spike에서 단일 테스트 실행
echo ""
echo "[Step 5] Spike에서 add-p-add 테스트 실행"

if command -v spike &> /dev/null; then
  spike pk isa/rv32ui/add-p-add.elf
  if [ $? -eq 0 ]; then
    echo "✅ Spike 테스트 성공!"
  else
    echo "⚠️  테스트 실패 (Spike 또는 pk 문제)"
  fi
else
  echo "⚠️  Spike가 설치되지 않음"
  echo "   Spike 설치: https://github.com/riscv-software-src/riscv-isa-sim"
fi

# Step 6: 전체 rv32ui 테스트 실행 및 로그 수집 (선택)
echo ""
echo "[Step 6] 전체 rv32ui 테스트 실행 (선택사항)"
read -p "전체 40개 테스트를 실행하시겠습니까? (y/n) " -n 1 -r
echo

if [[ $REPLY =~ ^[Yy]$ ]]; then
  mkdir -p test_logs

  passed=0
  failed=0

  for test in isa/rv32ui/*-p-*.elf; do
    name=$(basename "$test")
    echo -n "Testing $name ... "

    if spike pk "$test" > test_logs/${name}.log 2>&1; then
      echo "✅ PASSED"
      ((passed++))
    else
      echo "❌ FAILED"
      ((failed++))
    fi
  done

  total=$((passed + failed))
  percentage=$((passed * 100 / total))

  echo ""
  echo "=========================================="
  echo "최종 결과"
  echo "=========================================="
  echo "Passed:  $passed / $total"
  echo "Failed:  $failed / $total"
  echo "Percentage: $percentage%"
  echo ""
  echo "로그 위치: test_logs/*.log"
fi

cd ..

echo ""
echo "=========================================="
echo "✅ 완료!"
echo "=========================================="
echo ""
echo "다음 단계:"
echo "1. F.2: HTIF 프로토콜 이해하기"
echo "2. F.3: 회귀 테스트 자동화 (Makefile)"
echo "3. F.4: 테스트 실패 원인 분석"
