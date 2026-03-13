/* ============================================================
 * ch22_main.c — 최종 데모: Basys 3에서 C 프로그램 실행
 * RISC-V 프로세서 설계 완전정복 | Chapter 22
 * ============================================================
 * 데모 시나리오:
 *   1) UART로 "Hello RISC-V!" 메시지 전송
 *   2) LED 나이트 라이더 패턴 표시
 *   3) 스위치 입력을 LED에 반영
 *   4) 타이머 인터럽트 기반 LED 토글
 *   5) UART로 시스템 상태 리포트 출력
 * ============================================================ */

#include "ch22_drivers.h"

/* ============================================================
 * 전역 상수 및 변수
 * ============================================================ */
#define TIMER_1MS     50000U     /* 50MHz 클록 기준 1ms */
#define LED_COUNT     16U        /* Basys 3 LED 개수 */
#define DEMO_DELAY_MS 100U       /* LED 패턴 전환 주기 */

/* 타이머 ISR에서 토글할 LED 비트 */
volatile uint32_t heartbeat_led = 0;

/* ============================================================
 * 데모 함수 프로토타입
 * ============================================================ */
static void demo_uart_hello(void);
static void demo_led_knight_rider(void);
static void demo_switch_mirror(void);
static void demo_timer_heartbeat(void);
static void demo_system_report(void);
static void enable_global_interrupts(void);

/* ============================================================
 * main() — 프로그램 진입점
 * ============================================================ */
int main(void)
{
   /* 1단계: 주변 장치 초기화 */
   uart_init();
   gpio_init();
   timer_init(TIMER_1MS);

   /* 2단계: UART 인사 메시지 */
   demo_uart_hello();

   /* 3단계: LED 나이트 라이더 패턴 (3회 반복) */
   demo_led_knight_rider();

   /* 4단계: 스위치 입력 → LED 미러링 (약 3초) */
   demo_switch_mirror();

   /* 5단계: 타이머 인터럽트 데모 */
   demo_timer_heartbeat();

   /* 6단계: 시스템 리포트 */
   demo_system_report();

   /* 7단계: 완료 메시지 */
   uart_puts("\n========================================\n");
   uart_puts("  All demos completed successfully!\n");
   uart_puts("  Your RISC-V SoC is fully operational.\n");
   uart_puts("========================================\n");

   /* LED 전체 점등으로 완료 표시 */
   gpio_write(0xFFFF);

   return 0;   /* startup.S의 halt(wfi) 루프로 복귀 */
}

/* ============================================================
 * 데모 1: UART 인사 메시지
 * ============================================================ */
static void demo_uart_hello(void)
{
   uart_puts("\n");
   uart_puts("+--------------------------------------+\n");
   uart_puts("|    RISC-V Processor Design Book      |\n");
   uart_puts("|    Chapter 22: Final Demo            |\n");
   uart_puts("|    Hello from Basys 3 FPGA!          |\n");
   uart_puts("+--------------------------------------+\n");
   uart_puts("\n");

   uart_printf("[INFO] System clock: %u Hz\n", 50000000U);
   uart_printf("[INFO] UART baud rate: 115200 bps\n");
   uart_printf("[INFO] IMEM: 16 KB, DMEM: 8 KB\n");
}

/* ============================================================
 * 데모 2: LED 나이트 라이더 (좌우 이동 패턴)
 * ============================================================ */
static void demo_led_knight_rider(void)
{
   uart_puts("\n[DEMO 1] LED Knight Rider pattern...\n");

   for (int round = 0; round < 3; round++) {
      /* 좌측으로 이동 */
      for (int i = 0; i < (int)LED_COUNT; i++) {
         gpio_write(1U << i);
         delay_ms(DEMO_DELAY_MS);
      }
      /* 우측으로 이동 */
      for (int i = (int)LED_COUNT - 2; i > 0; i--) {
         gpio_write(1U << i);
         delay_ms(DEMO_DELAY_MS);
      }
   }

   gpio_write(0);
   uart_puts("[DEMO 1] Knight Rider complete.\n");
}

/* ============================================================
 * 데모 3: 스위치 입력을 LED에 미러링
 * ============================================================ */
static void demo_switch_mirror(void)
{
   uart_puts("\n[DEMO 2] Switch-to-LED mirror (3 sec)...\n");
   uart_puts("         Toggle switches to see LED changes.\n");

   uint32_t start = timer_tick_count;
   while ((timer_tick_count - start) < 3000) {
      uint32_t sw = gpio_read() >> 16;   /* 상위 16비트 = 스위치 */
      gpio_write(sw & 0xFFFF);           /* 하위 16비트 = LED */
   }

   gpio_write(0);
   uart_puts("[DEMO 2] Switch mirror complete.\n");
}

/* ============================================================
 * 데모 4: 타이머 인터럽트 기반 하트비트 LED
 * ============================================================ */
static void demo_timer_heartbeat(void)
{
   uart_puts("\n[DEMO 3] Timer interrupt heartbeat (5 sec)...\n");

   /* 인터럽트 활성화 */
   timer_start();
   enable_global_interrupts();

   uint32_t start = timer_tick_count;
   uint32_t last_toggle = start;

   while ((timer_tick_count - start) < 5000) {
      /* 500ms마다 하트비트 LED 토글 */
      if ((timer_tick_count - last_toggle) >= 500) {
         heartbeat_led ^= 1;
         gpio_write(heartbeat_led ? 0x8001 : 0x0000);
         last_toggle = timer_tick_count;

         uart_printf("  [TICK] count = %u, LED = %s\n",
                     timer_tick_count,
                     heartbeat_led ? "ON" : "OFF");
      }
   }

   timer_stop();
   gpio_write(0);
   uart_puts("[DEMO 3] Heartbeat demo complete.\n");
}

/* ============================================================
 * 데모 5: 시스템 상태 리포트
 * ============================================================ */
static void demo_system_report(void)
{
   uart_puts("\n[REPORT] System Status\n");
   uart_puts("------------------------\n");
   uart_printf("  Timer ticks elapsed: %u\n", timer_tick_count);
   uart_printf("  Stack pointer (sp):  0x%x\n", get_sp());
   uart_printf("  Switch state:        0x%x\n", gpio_read() >> 16);
   uart_puts("------------------------\n");
}

/* ============================================================
 * CSR 접근 유틸리티 (인라인 어셈블리)
 * ============================================================ */

/* 글로벌 인터럽트 활성화 (mstatus.MIE = 1) */
static void enable_global_interrupts(void)
{
   uint32_t mstatus;
   __asm__ volatile ("csrr %0, mstatus" : "=r"(mstatus));
   mstatus |= (1U << 3);   /* MIE 비트 (bit 3) 설정 */
   __asm__ volatile ("csrw mstatus, %0" :: "r"(mstatus));

   /* 타이머 인터럽트 활성화 (mie.MTIE = 1) */
   uint32_t mie;
   __asm__ volatile ("csrr %0, mie" : "=r"(mie));
   mie |= (1U << 7);       /* MTIE 비트 (bit 7) 설정 */
   __asm__ volatile ("csrw mie, %0" :: "r"(mie));
}

/* 스택 포인터 읽기 */
static inline uint32_t get_sp(void)
{
   uint32_t sp;
   __asm__ volatile ("mv %0, sp" : "=r"(sp));
   return sp;
}
