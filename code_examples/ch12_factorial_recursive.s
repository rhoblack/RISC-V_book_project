# =============================================================================
# 재귀 팩토리얼 (Recursive Factorial) — RV32I 어셈블리
# Chapter 12 검증용 테스트 프로그램
#
# 기능: factorial(7) = 5040 계산
# 해저드 검증 포인트:
#   - 스택 연산 (SW/LW + SP 조작 → Load-Use + 포워딩)
#   - JAL/JALR (서브루틴 호출/리턴 → 제어 해저드)
#   - WB-ID 포워딩 (LW 직후 레지스터 사용)
# =============================================================================

.text
.globl _start

_start:
   # ----- 스택 포인터 초기화 -----
   li    sp, 0x1000        # sp = 스택 시작 주소 (4KB)

   # ----- factorial(7) 호출 -----
   li    a0, 7             # a0 = n = 7
   jal   ra, factorial     # 함수 호출 → 제어 해저드 (JAL)

   # ----- 결과를 메모리에 저장 -----
   sw    a0, 0(zero)       # MEM[0] = factorial(7) = 5040

   ecall                   # 프로그램 종료

# =============================================================================
# factorial(n) — 재귀 함수
# 입력: a0 = n
# 출력: a0 = n!
# 사용: ra, a0, s0 (callee-saved)
# =============================================================================
factorial:
   # ----- 프롤로그: 레지스터 저장 -----
   addi  sp, sp, -8        # 스택 프레임 할당 (2워드)
   sw    ra, 4(sp)         # 리턴 주소 저장   ← 포워딩 (sp 연속 사용)
   sw    s0, 0(sp)         # s0 저장

   # ----- 기저 조건 (base case) -----
   mv    s0, a0            # s0 = n (보존)
   li    t0, 1
   ble   a0, t0, base_case # n <= 1이면 기저 조건 → 제어 해저드

   # ----- 재귀 호출 -----
   addi  a0, a0, -1        # a0 = n - 1    ← 데이터 포워딩
   jal   ra, factorial     # factorial(n-1) → 제어 해저드 (JAL)

   # ----- 결과 계산 -----
   mul   a0, s0, a0        # a0 = n * factorial(n-1)
                            # 주의: MUL은 M 확장. RV32I만 구현 시
                            # 아래 곱셈 루프로 대체
   j     epilogue

base_case:
   li    a0, 1             # return 1

epilogue:
   # ----- 에필로그: 레지스터 복원 -----
   lw    s0, 0(sp)         # s0 복원      ← Load-Use 해저드
   lw    ra, 4(sp)         # 리턴 주소 복원 ← Load-Use 해저드
   addi  sp, sp, 8         # 스택 프레임 해제
   jalr  zero, ra, 0       # 리턴 (ret)    ← 제어 해저드 (JALR)
