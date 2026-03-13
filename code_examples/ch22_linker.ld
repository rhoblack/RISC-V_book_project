/* ============================================================
 * ch22_linker.ld — RV32I SoC 링커 스크립트
 * RISC-V 프로세서 설계 완전정복 | Chapter 22
 * ============================================================
 * 대상 보드: Basys 3 (XC7A35T)
 * 메모리 맵: IMEM 0x0000_0000 (16KB)
 *            DMEM 0x8000_0000 (8KB)
 *            MMIO 0xC000_0000 (256B)
 * ============================================================ */

OUTPUT_ARCH("riscv")
ENTRY(_start)

MEMORY
{
   /* 명령어 메모리: BRAM 기반, 읽기 전용 */
   IMEM (rx)  : ORIGIN = 0x00000000, LENGTH = 16K

   /* 데이터 메모리: BRAM 기반, 읽기/쓰기 */
   DMEM (rwx) : ORIGIN = 0x80000000, LENGTH = 8K

   /* MMIO 영역: 주변 장치 레지스터 */
   MMIO (rw)  : ORIGIN = 0xC0000000, LENGTH = 256
}

SECTIONS
{
   /* ---- 코드 섹션 (.text) → IMEM ---- */
   .text :
   {
      . = ALIGN(4);
      _text_start = .;
      *(.text.startup)      /* 스타트업 코드 (최우선 배치) */
      *(.text .text.*)      /* 일반 코드 */
      *(.rodata .rodata.*)  /* 읽기 전용 데이터 (문자열 리터럴 등) */
      . = ALIGN(4);
      _text_end = .;
   } > IMEM

   /* ---- 초기화 데이터 (.data) → DMEM (초기값은 IMEM에 저장) ---- */
   .data :
   {
      . = ALIGN(4);
      _data_start = .;
      *(.data .data.*)
      *(.sdata .sdata.*)    /* 소형 데이터 (gp 상대 접근) */
      . = ALIGN(4);
      _data_end = .;
   } > DMEM AT > IMEM       /* VMA=DMEM, LMA=IMEM */

   /* .data 섹션의 IMEM 내 로드 주소 (startup.S에서 복사 시 사용) */
   _data_load = LOADADDR(.data);

   /* ---- 미초기화 데이터 (.bss) → DMEM ---- */
   .bss (NOLOAD) :
   {
      . = ALIGN(4);
      _bss_start = .;
      *(.bss .bss.*)
      *(.sbss .sbss.*)      /* 소형 BSS */
      *(COMMON)
      . = ALIGN(4);
      _bss_end = .;
   } > DMEM

   /* ---- 스택 영역: DMEM의 최상위에서 아래로 성장 ---- */
   _stack_top = ORIGIN(DMEM) + LENGTH(DMEM);

   /* ---- 글로벌 포인터 (gp): .sdata 영역의 중간점 ---- */
   __global_pointer$ = _data_start + 0x800;

   /* ---- 힙 시작 주소 (선택적 동적 메모리 할당) ---- */
   _heap_start = _bss_end;
   _heap_end   = _stack_top - 1024;  /* 스택 보호 영역 1KB */
}
