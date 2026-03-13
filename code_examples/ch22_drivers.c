/* ============================================================
 * ch22_drivers.c — 주변 장치 드라이버 구현
 * RISC-V 프로세서 설계 완전정복 | Chapter 22
 * ============================================================
 * UART printf, GPIO 제어, 타이머 인터럽트 드라이버
 * ============================================================ */

#include "ch22_drivers.h"
#include <stdarg.h>

/* ============================================================
 * 시스템 클록 주파수 (Basys 3: 50 MHz 가정)
 * ============================================================ */
#define SYS_CLK_HZ   50000000U

/* ============================================================
 * UART 드라이버 구현
 * ============================================================ */

/* uart_init: UART 컨트롤러 초기화
 * - 보드레이트: 115200 bps (하드웨어에서 설정 가정)
 * - TX/RX 활성화
 */
void uart_init(void)
{
   UART_CTRL = UART_TX_EN | UART_RX_EN;
}

/* uart_putc: 단일 문자 전송
 * - TX FIFO가 가득 차면 빈 공간이 생길 때까지 대기 (폴링)
 */
void uart_putc(char c)
{
   /* TX FIFO가 비워질 때까지 폴링 대기 */
   while (UART_STATUS & UART_TX_FULL)
      ;  /* 빈 루프 — 하드웨어가 FIFO를 비울 때까지 */

   UART_TXDATA = (uint32_t)c;
}

/* uart_getc: 단일 문자 수신
 * - RX FIFO에 데이터가 도착할 때까지 블로킹 대기
 */
char uart_getc(void)
{
   /* RX FIFO에 데이터가 들어올 때까지 폴링 대기 */
   while (UART_STATUS & UART_RX_EMPTY)
      ;

   return (char)(UART_RXDATA & 0xFF);
}

/* uart_puts: 문자열 전송
 * - '\n'을 만나면 '\r\n' (CR+LF)으로 변환
 */
void uart_puts(const char *s)
{
   while (*s) {
      if (*s == '\n')
         uart_putc('\r');   /* 줄바꿈 전 캐리지 리턴 삽입 */
      uart_putc(*s);
      s++;
   }
}

/* uart_put_hex: 32비트 값을 16진수 문자열로 출력
 * - 예: 0xDEADBEEF → "0xDEADBEEF"
 */
void uart_put_hex(uint32_t val)
{
   static const char hex_chars[] = "0123456789ABCDEF";

   uart_putc('0');
   uart_putc('x');

   for (int i = 28; i >= 0; i -= 4) {
      uart_putc(hex_chars[(val >> i) & 0xF]);
   }
}

/* uart_printf: 간이 printf 구현
 * - 지원 형식 지정자: %d, %u, %x, %s, %c, %%
 * - 표준 라이브러리 없이 베어메탈 환경에서 동작
 */
int uart_printf(const char *fmt, ...)
{
   va_list args;
   va_start(args, fmt);

   int count = 0;

   while (*fmt) {
      if (*fmt == '%') {
         fmt++;
         switch (*fmt) {
            case 'd': {
               /* 부호 있는 10진수 */
               int val = va_arg(args, int);
               if (val < 0) {
                  uart_putc('-');
                  count++;
                  val = -val;
               }
               /* 자릿수 추출을 위한 버퍼 */
               char buf[12];
               int idx = 0;
               if (val == 0) {
                  buf[idx++] = '0';
               } else {
                  while (val > 0) {
                     buf[idx++] = '0' + (val % 10);
                     val /= 10;
                  }
               }
               /* 역순 출력 */
               for (int i = idx - 1; i >= 0; i--) {
                  uart_putc(buf[i]);
                  count++;
               }
               break;
            }
            case 'u': {
               /* 부호 없는 10진수 */
               unsigned int val = va_arg(args, unsigned int);
               char buf[12];
               int idx = 0;
               if (val == 0) {
                  buf[idx++] = '0';
               } else {
                  while (val > 0) {
                     buf[idx++] = '0' + (val % 10);
                     val /= 10;
                  }
               }
               for (int i = idx - 1; i >= 0; i--) {
                  uart_putc(buf[i]);
                  count++;
               }
               break;
            }
            case 'x': {
               /* 16진수 */
               uint32_t val = va_arg(args, uint32_t);
               uart_put_hex(val);
               count += 10;
               break;
            }
            case 's': {
               /* 문자열 */
               const char *s = va_arg(args, const char *);
               while (*s) {
                  uart_putc(*s++);
                  count++;
               }
               break;
            }
            case 'c': {
               /* 단일 문자 */
               char c = (char)va_arg(args, int);
               uart_putc(c);
               count++;
               break;
            }
            case '%': {
               uart_putc('%');
               count++;
               break;
            }
            default:
               uart_putc('%');
               uart_putc(*fmt);
               count += 2;
               break;
         }
      } else {
         if (*fmt == '\n') {
            uart_putc('\r');
            count++;
         }
         uart_putc(*fmt);
         count++;
      }
      fmt++;
   }

   va_end(args);
   return count;
}

/* ============================================================
 * GPIO 드라이버 구현
 * ============================================================ */

/* gpio_init: GPIO 초기화
 * - 하위 16비트: LED 출력
 * - 상위 16비트: 스위치 입력
 */
void gpio_init(void)
{
   GPIO_DIR = 0x0000FFFF;  /* [15:0] = 출력(LED), [31:16] = 입력(SW) */
   GPIO_OUT = 0x00000000;  /* LED 모두 끔 */
}

/* gpio_set_dir: GPIO 방향 개별 설정
 * - mask: 대상 비트 마스크
 * - dir: 0=입력, 1=출력
 */
void gpio_set_dir(uint32_t mask, uint32_t dir)
{
   if (dir == GPIO_DIR_OUTPUT)
      GPIO_DIR |= mask;
   else
      GPIO_DIR &= ~mask;
}

/* gpio_write: LED 출력 값 설정 */
void gpio_write(uint32_t val)
{
   GPIO_OUT = val;
}

/* gpio_read: 스위치 입력 값 읽기 */
uint32_t gpio_read(void)
{
   return GPIO_IN;
}

/* ============================================================
 * Timer 드라이버 구현
 * ============================================================ */

/* 타이머 인터럽트 발생 횟수 (ISR에서 증가) */
volatile uint32_t timer_tick_count = 0;

/* timer_init: 타이머 초기화
 * - compare_val: 비교 레지스터 값 (이 값에 도달하면 인터럽트)
 *   예: 50MHz 클록에서 1ms 인터럽트 → compare_val = 50000
 */
void timer_init(uint32_t compare_val)
{
   TIMER_CTRL = 0;               /* 타이머 정지 */
   TIMER_CNT  = 0;               /* 카운터 초기화 */
   TIMER_CMP  = compare_val;     /* 비교 값 설정 */
   timer_tick_count = 0;
}

/* timer_start: 타이머 시작 (자동 리로드 + 인터럽트 활성화) */
void timer_start(void)
{
   TIMER_CTRL = TIMER_EN | TIMER_IE | TIMER_AUTO_RL;
}

/* timer_stop: 타이머 정지 */
void timer_stop(void)
{
   TIMER_CTRL = 0;
}

/* timer_isr: 타이머 인터럽트 서비스 루틴
 * - startup.S의 _trap_handler에서 호출됨
 * - 인터럽트 펜딩 비트를 클리어하고 tick 카운터를 증가
 */
void timer_isr(void)
{
   /* 인터럽트 펜딩 클리어: 카운터를 0으로 리셋 */
   TIMER_CNT = 0;

   /* tick 카운터 증가 */
   timer_tick_count++;
}

/* ============================================================
 * 시스템 유틸리티
 * ============================================================ */

/* delay_ms: 밀리초 단위 소프트웨어 지연
 * - 타이머 tick을 기반으로 정확한 지연 구현
 * - timer_init()에서 1ms 주기로 설정했다고 가정
 */
void delay_ms(uint32_t ms)
{
   uint32_t start = timer_tick_count;
   while ((timer_tick_count - start) < ms)
      ;  /* tick이 누적될 때까지 폴링 대기 */
}
