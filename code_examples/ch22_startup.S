# ============================================================
# ch22_startup.S — RV32I 스타트업 어셈블리 코드
# RISC-V 프로세서 설계 완전정복 | Chapter 22
# ============================================================
# 리셋 벡터에서 실행되어 C 런타임 환경을 초기화한 뒤
# main() 함수를 호출합니다.
# ============================================================

   .section .text.startup, "ax", @progbits
   .globl _start
   .type  _start, @function

_start:
   # -------------------------------------------------------
   # 1단계: 인터럽트 비활성화 (초기화 중 인터럽트 방지)
   # -------------------------------------------------------
   csrw   mie, zero           # mie = 0: 모든 인터럽트 비활성화

   # -------------------------------------------------------
   # 2단계: 스택 포인터(sp) 초기화
   # -------------------------------------------------------
   la     sp, _stack_top       # sp = DMEM 최상위 주소
                               # 스택은 높은 주소 → 낮은 주소로 성장

   # -------------------------------------------------------
   # 3단계: 글로벌 포인터(gp) 초기화
   # -------------------------------------------------------
   .option push
   .option norelax             # gp 자체를 설정할 때는 relaxation 비활성화
   la     gp, __global_pointer$
   .option pop

   # -------------------------------------------------------
   # 4단계: .bss 섹션 제로 클리어
   # -------------------------------------------------------
   la     t0, _bss_start       # t0 = .bss 시작 주소
   la     t1, _bss_end         # t1 = .bss 끝 주소
bss_clear_loop:
   bge    t0, t1, bss_clear_done
   sw     zero, 0(t0)          # 4바이트 단위로 0 기록
   addi   t0, t0, 4
   j      bss_clear_loop
bss_clear_done:

   # -------------------------------------------------------
   # 5단계: .data 섹션 복사 (IMEM → DMEM)
   # -------------------------------------------------------
   # 링커 스크립트에서 _data_load(LMA), _data_start(VMA),
   # _data_end를 제공합니다.
   la     t0, _data_load       # t0 = .data의 IMEM 내 로드 주소 (LMA)
   la     t1, _data_start      # t1 = .data의 DMEM 내 실행 주소 (VMA)
   la     t2, _data_end        # t2 = .data 끝 주소
data_copy_loop:
   bge    t1, t2, data_copy_done
   lw     t3, 0(t0)            # IMEM에서 4바이트 로드
   sw     t3, 0(t1)            # DMEM에 4바이트 스토어
   addi   t0, t0, 4
   addi   t1, t1, 4
   j      data_copy_loop
data_copy_done:

   # -------------------------------------------------------
   # 6단계: 트랩 핸들러 벡터 설정
   # -------------------------------------------------------
   la     t0, _trap_handler
   csrw   mtvec, t0            # mtvec = 트랩 핸들러 주소

   # -------------------------------------------------------
   # 7단계: main() 호출
   # -------------------------------------------------------
   call   main                 # main() 함수 진입
                               # main()의 반환값은 a0에 저장됨

   # -------------------------------------------------------
   # 8단계: main() 복귀 후 무한 루프
   # -------------------------------------------------------
halt:
   wfi                         # Wait For Interrupt (저전력 대기)
   j      halt                 # main()이 리턴하면 영원히 대기

   # -------------------------------------------------------
   # 기본 트랩 핸들러 (Ch19에서 구현한 핸들러로 교체 가능)
   # -------------------------------------------------------
   .globl _trap_handler
   .type  _trap_handler, @function
   .align 4                    # mtvec은 4바이트 정렬 필수
_trap_handler:
   # --- 레지스터 저장 (caller-saved) ---
   addi   sp, sp, -64
   sw     ra,  0(sp)
   sw     t0,  4(sp)
   sw     t1,  8(sp)
   sw     t2, 12(sp)
   sw     a0, 16(sp)
   sw     a1, 20(sp)
   sw     a2, 24(sp)
   sw     a3, 28(sp)
   sw     a4, 32(sp)
   sw     a5, 36(sp)
   sw     a6, 40(sp)
   sw     a7, 44(sp)
   sw     t3, 48(sp)
   sw     t4, 52(sp)
   sw     t5, 56(sp)
   sw     t6, 60(sp)

   # --- 예외 원인 확인 ---
   csrr   a0, mcause           # a0 = 예외/인터럽트 원인
   csrr   a1, mepc             # a1 = 예외 발생 PC

   # 인터럽트 비트(bit 31) 확인
   bltz   a0, _is_interrupt    # mcause[31] == 1이면 인터럽트

   # --- 동기 예외 처리 ---
   # mepc를 다음 명령어로 전진 (4바이트)
   addi   a1, a1, 4
   csrw   mepc, a1
   j      _trap_return

_is_interrupt:
   # --- 비동기 인터럽트 처리 ---
   andi   a0, a0, 0x7FF        # 인터럽트 코드 추출 (하위 11비트)
   li     t0, 7                # 7 = 타이머 인터럽트
   beq    a0, t0, _timer_irq
   j      _trap_return          # 기타 인터럽트는 무시

_timer_irq:
   call   timer_isr             # 타이머 ISR 호출 (C 함수)

_trap_return:
   # --- 레지스터 복원 ---
   lw     ra,  0(sp)
   lw     t0,  4(sp)
   lw     t1,  8(sp)
   lw     t2, 12(sp)
   lw     a0, 16(sp)
   lw     a1, 20(sp)
   lw     a2, 24(sp)
   lw     a3, 28(sp)
   lw     a4, 32(sp)
   lw     a5, 36(sp)
   lw     a6, 40(sp)
   lw     a7, 44(sp)
   lw     t3, 48(sp)
   lw     t4, 52(sp)
   lw     t5, 56(sp)
   lw     t6, 60(sp)
   addi   sp, sp, 64

   mret                         # 트랩에서 복귀
