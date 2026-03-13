/* ============================================================
 * ch22_drivers.h — 주변 장치 드라이버 헤더
 * RISC-V 프로세서 설계 완전정복 | Chapter 22
 * ============================================================
 * Basys 3 SoC의 MMIO 주변 장치 레지스터 정의 및
 * 드라이버 함수 프로토타입
 * ============================================================ */

#ifndef _CH22_DRIVERS_H_
#define _CH22_DRIVERS_H_

#include <stdint.h>

/* ============================================================
 * MMIO 기본 주소 정의 (메모리 맵 — Ch05, Ch17 참조)
 * ============================================================ */
#define UART_BASE    0xC0000000U
#define GPIO_BASE    0xC0000010U
#define TIMER_BASE   0xC0000020U

/* ============================================================
 * UART 레지스터 오프셋 (Ch17.3 UART 컨트롤러)
 * ============================================================ */
#define UART_TXDATA  (*(volatile uint32_t *)(UART_BASE + 0x00))
#define UART_RXDATA  (*(volatile uint32_t *)(UART_BASE + 0x04))
#define UART_STATUS  (*(volatile uint32_t *)(UART_BASE + 0x08))
#define UART_CTRL    (*(volatile uint32_t *)(UART_BASE + 0x0C))

/* UART STATUS 비트 필드 */
#define UART_TX_FULL   (1U << 0)   /* TX FIFO 가득 참 */
#define UART_RX_EMPTY  (1U << 1)   /* RX FIFO 비어 있음 */
#define UART_TX_BUSY   (1U << 2)   /* 전송 진행 중 */

/* UART CTRL 비트 필드 */
#define UART_TX_EN     (1U << 0)   /* TX 활성화 */
#define UART_RX_EN     (1U << 1)   /* RX 활성화 */
#define UART_RX_IE     (1U << 2)   /* RX 인터럽트 활성화 */

/* ============================================================
 * GPIO 레지스터 오프셋 (Ch17.4 GPIO 컨트롤러)
 * ============================================================ */
#define GPIO_DIR     (*(volatile uint32_t *)(GPIO_BASE + 0x00))
#define GPIO_OUT     (*(volatile uint32_t *)(GPIO_BASE + 0x04))
#define GPIO_IN      (*(volatile uint32_t *)(GPIO_BASE + 0x08))

/* GPIO 방향 상수 */
#define GPIO_DIR_INPUT   0U
#define GPIO_DIR_OUTPUT  1U

/* ============================================================
 * Timer 레지스터 오프셋 (Ch17.5 타이머/카운터)
 * ============================================================ */
#define TIMER_CTRL   (*(volatile uint32_t *)(TIMER_BASE + 0x00))
#define TIMER_CMP    (*(volatile uint32_t *)(TIMER_BASE + 0x04))
#define TIMER_CNT    (*(volatile uint32_t *)(TIMER_BASE + 0x08))

/* Timer CTRL 비트 필드 */
#define TIMER_EN       (1U << 0)   /* 타이머 활성화 */
#define TIMER_IE       (1U << 1)   /* 인터럽트 활성화 */
#define TIMER_AUTO_RL  (1U << 2)   /* 자동 리로드 모드 */

/* ============================================================
 * 함수 프로토타입
 * ============================================================ */

/* UART 드라이버 */
void     uart_init(void);
void     uart_putc(char c);
char     uart_getc(void);
void     uart_puts(const char *s);
void     uart_put_hex(uint32_t val);
int      uart_printf(const char *fmt, ...);

/* GPIO 드라이버 */
void     gpio_init(void);
void     gpio_set_dir(uint32_t mask, uint32_t dir);
void     gpio_write(uint32_t val);
uint32_t gpio_read(void);

/* Timer 드라이버 */
void     timer_init(uint32_t compare_val);
void     timer_start(void);
void     timer_stop(void);
void     timer_isr(void);

/* 시스템 유틸리티 */
void     delay_ms(uint32_t ms);

#endif /* _CH22_DRIVERS_H_ */
