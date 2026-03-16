#!/bin/bash
# ============================================================================
# app_e_toolchain_asm_to_hex.sh
# RISC-V 어셈블리/C → .hex 파일 변환 스크립트
# ============================================================================
# 사용법:
#   chmod +x app_e_toolchain_asm_to_hex.sh
#   ./app_e_toolchain_asm_to_hex.sh sample.c
#   ./app_e_toolchain_asm_to_hex.sh test.s
# ============================================================================

# --- 설정 ---
TOOLCHAIN_PREFIX="riscv64-unknown-elf"
MARCH="rv32i"
MABI="ilp32"

# --- 입력 파일 확인 ---
if [ $# -eq 0 ]; then
    echo "사용법: $0 <소스파일.c|소스파일.s>"
    echo ""
    echo "예시:"
    echo "  $0 sample.c      # C 파일 → .hex"
    echo "  $0 test.s         # 어셈블리 파일 → .hex"
    exit 1
fi

SOURCE_FILE="$1"
BASENAME="${SOURCE_FILE%.*}"
EXT="${SOURCE_FILE##*.}"

# 파일 존재 확인
if [ ! -f "$SOURCE_FILE" ]; then
    echo "오류: '$SOURCE_FILE' 파일을 찾을 수 없습니다."
    exit 1
fi

echo "========================================="
echo " RISC-V 크로스 컴파일 시작"
echo " 소스: $SOURCE_FILE"
echo " 아키텍처: $MARCH / $MABI"
echo "========================================="

# --- Step 1: 컴파일 (C 또는 어셈블리 → ELF) ---
echo ""
echo "[Step 1] 컴파일: $SOURCE_FILE → ${BASENAME}.elf"

if [ "$EXT" = "c" ]; then
    # C 파일 컴파일
    ${TOOLCHAIN_PREFIX}-gcc \
        -march=${MARCH} \
        -mabi=${MABI} \
        -nostartfiles \
        -nostdlib \
        -static \
        "$SOURCE_FILE" -o "${BASENAME}.elf"
elif [ "$EXT" = "s" ] || [ "$EXT" = "S" ]; then
    # 어셈블리 파일 컴파일
    ${TOOLCHAIN_PREFIX}-gcc \
        -march=${MARCH} \
        -mabi=${MABI} \
        -nostartfiles \
        -nostdlib \
        -static \
        "$SOURCE_FILE" -o "${BASENAME}.elf"
else
    echo "오류: 지원하지 않는 파일 형식 (.$EXT)"
    echo "지원 형식: .c, .s, .S"
    exit 1
fi

if [ $? -ne 0 ]; then
    echo "오류: 컴파일 실패!"
    exit 1
fi
echo "  → ${BASENAME}.elf 생성 완료"

# --- Step 2: ELF → Hex 변환 ---
echo ""
echo "[Step 2] 변환: ${BASENAME}.elf → ${BASENAME}.hex"

${TOOLCHAIN_PREFIX}-objcopy \
    -O verilog \
    "${BASENAME}.elf" "${BASENAME}.hex"

if [ $? -ne 0 ]; then
    echo "오류: hex 변환 실패!"
    exit 1
fi
echo "  → ${BASENAME}.hex 생성 완료"

# --- Step 3: 디스어셈블리 생성 (참고용) ---
echo ""
echo "[Step 3] 디스어셈블리: ${BASENAME}.elf → ${BASENAME}.dis"

${TOOLCHAIN_PREFIX}-objdump \
    -d -M no-aliases \
    "${BASENAME}.elf" > "${BASENAME}.dis"

echo "  → ${BASENAME}.dis 생성 완료"

# --- Step 4: 결과 요약 ---
echo ""
echo "========================================="
echo " 빌드 완료!"
echo "========================================="
echo " ELF 파일:  ${BASENAME}.elf  ($(wc -c < "${BASENAME}.elf") bytes)"
echo " Hex 파일:  ${BASENAME}.hex  ($(wc -c < "${BASENAME}.hex") bytes)"
echo " 디스어셈블리: ${BASENAME}.dis"
echo ""
echo " Vivado에서 로드:"
echo '   $readmemh("'"${BASENAME}.hex"'", imem);'
echo "========================================="
