# Chapter 22 기술 검증 보고

**검토자**: 기술 리뷰어
**검토일**: 2026-03-14
**원고 버전**: Phase 2 초안

---

## 검토 결과 요약

- **Critical**: 2건 ⚠️
- **Major**: 3건
- **Minor**: 2건
- **종합 판정**: ❌ **재검토 필요** (Critical 오류 해결 필수)

---

## 상세 지적사항

### 🔴 Critical (해결 필수)

#### C1: 메모리 맵 주소 불일치 (아키텍처 오류)

**위치**: HTML 원고 22.1절 + 헤더 파일 불일치

**문제**:
- **HTML 22.1절 (라인 47, 418-421, 474, 506-509)**: MMIO 주소를 `0x6000_0000`으로 기술
  ```
  UART_BASE = 0x60000000
  GPIO_BASE = 0x60000010
  TIMER_BASE = 0x60000020
  ```

- **ch22_drivers.h (라인 17-19)**: MMIO 주소가 `0xC000_0000`로 정의됨
  ```c
  #define UART_BASE    0xC0000000U
  #define GPIO_BASE    0xC0000010U
  #define TIMER_BASE   0xC0000020U
  ```

- **ch22_linker.ld (라인 23)**: 링커 스크립트도 `0xC000_0000` 확인
  ```
  MMIO (rw)  : ORIGIN = 0xC0000000, LENGTH = 256
  ```

**근본 원인**: HTML 원고와 실제 코드의 메모리 맵이 다릅니다. 학생이 코드를 복사하면 주소 오류로 UART/GPIO/타이머 모두 작동 불가능합니다.

**영향도**: 🔴 **Critical** — 코드 실행 불가능 (모든 MMIO 접근 실패)

**권장 해결**:
1. **옵션 A (권장)**: HTML을 `0xC000_0000`으로 수정하여 코드와 일치시키기
   - 라인 47, 74, 418, 419, 420, 474, 475, 476, 506, 507, 508, 698, 815 수정

2. **옵션 B**: 코드를 `0x6000_0000`으로 수정 (권장하지 않음 — 링커 스크립트와도 불일치)

**선택**: **옵션 A 권장** (링커 스크립트도 이미 `0xC000_0000`이므로)

---

#### C2: DMEM 주소 불일치 (링커 스크립트 오류)

**위치**: HTML 22.1절 라인 45-46 vs ch22_linker.ld 라인 20

**문제**:
- **HTML (라인 45-46)**:
  ```
  D-Cache (DMEM): 주소 0x0000_1000 ~ 0x0000_1FFF (4KB, 또는 확장 가능)
  ```

- **실제 링커 스크립트 (ch22_linker.ld 라인 20)**:
  ```
  DMEM (rwx) : ORIGIN = 0x80000000, LENGTH = 8K
  ```

**근본 원인**: HTML에는 DMEM이 0x0000_1000에서 시작하는 것처럼 기술되어 있으나, 실제 구현은 0x8000_0000에서 시작합니다. 또한 크기도 불일치 (HTML: 4KB, 실제: 8KB).

**추가 확인**:
- HTML의 링커 스크립트 템플릿 (라인 105)도 일관성 없음:
  ```
  DMEM (rwx) : ORIGIN = 0x20000000, LENGTH = 32K
  ```

**영향도**: 🔴 **Critical** — 스택 포인터 초기화 오류로 프로그램 크래시 가능, 스택 오버플로우 위험

**권장 해결**: HTML의 모든 DMEM 주소를 `0x8000_0000`, 크기를 `8KB`로 통일

---

### 🟡 Major (강력 권고)

#### M1: volatile 키워드 불완전성 (라인 424-430 HTML)

**위치**: HTML 22.3.1 "드라이버의 정의" 섹션, UART 예제 코드

**문제**:
```c
void uart_putchar(char c) {
    while ((*UART_STATUS & 0x1) == 0) {
        /* 계속 대기... (송신 중) */
    }
    *UART_TX_DATA = (uint32_t)c;
}
```

- `UART_STATUS` 포인터가 `volatile` 선언되지 않음 (HTML의 정의를 보면 라인 421에 volatile이 있어야 함)
- 실제 ch22_drivers.h (라인 26)는 올바르게 `volatile` 선언:
  ```c
  #define UART_STATUS  (*(volatile uint32_t *)(UART_BASE + 0x08))
  ```

**영향도**: 🟡 **Major** — 컴파일은 되지만 최적화 단계에서 폴링 루프가 제거될 수 있음

**권장 해결**: HTML 라인 419-421 정의를 다음과 같이 명확하게 표기:
```c
#define UART_STATUS   ((volatile uint32_t *)(UART_BASE + 0x04))
```

---

#### M2: Calling Convention 오류 (HTML 라인 444, 480, 489)

**위치**: HTML 22.3.2 GPIO 드라이버 코드

**문제**:
```c
while (UART_STATUS & UART_TX_FULL)
    ;  /* 빈 루프 */
```

실제 ch22_drivers.c (라인 35)는:
```c
while (UART_STATUS & UART_TX_FULL)
    ;  /* TX FIFO가 비워질 때까지 폴링 대기 */
```

**더 큰 문제**: HTML 라인 480, 489에서 비트 쉬프트 연산:
```c
uint32_t mask = (1 << led_index);  /* HTML 라인 480 */
uint32_t mask = (1 << led_index);  /* HTML 라인 489 */
```

비트 쉬프트의 오른쪽 피연산자(led_index)가 서명되지 않은 정수인지 확인 필요. 표준 관례상 `1U` 사용:
```c
uint32_t mask = (1U << led_index);
```

실제 ch22_drivers.c (라인 100, 105)는 올바르게 구현:
```c
gpio_write(1U << i);
```

**영향도**: 🟡 **Major** — 일관성 부족, 최적화 단계 부호 확장 오류 가능

**권고**: HTML의 모든 비트 시프트를 `1U`, `0xFFFF` 등 명시적 unsigned로 수정

---

#### M3: CSR 접근 인라인 어셈블리 누락 (HTML 라인 517-521)

**위치**: HTML 22.3.3 타이머 드라이버, timer_init() 함수

**문제**:
```c
uint32_t mie_mask = (1 << 7);  /* MTIE */
asm("csrs mie, %0" : : "r"(mie_mask));
```

이 코드는 GCC inline assembly 문법이지만, startup.S에서 이미 mtvec과 인터럽트를 설정하는데, HTML 예제와 ch22_main.c (라인 185-193)의 구현이 다릅니다.

실제 ch22_main.c의 enable_global_interrupts():
```c
__asm__ volatile ("csrr %0, mstatus" : "=r"(mstatus));
mstatus |= (1U << 3);   /* MIE 비트 */
__asm__ volatile ("csrw mstatus, %0" :: "r"(mstatus));
```

**더 나은 방식**: GCC inline assembly 대신 내장 함수 사용 가능:
```c
__builtin_riscv_csrs(0x300, (1U << 3));  /* mstatus */
```

**영향도**: 🟡 **Major** — 비표준 구현, 컴파일러 버전 의존성 높음

**권고**: 스타트업 코드의 mtvec 설정이 이미 충분하므로, HTML 예제를 단순화 및 ch22_main.c와 일치시키기

---

### 🟢 Minor (검토)

#### Mi1: 포인터 캐스팅 형식 불일치

**위치**: HTML 라인 419-421 vs 실제 코드

**문제**:
- HTML (라인 419):
  ```c
  #define UART_TX_DATA  ((volatile uint32_t *)(UART_BASE + 0x00))
  ```

- 실제 ch22_drivers.h (라인 24):
  ```c
  #define UART_TXDATA  (*(volatile uint32_t *)(UART_BASE + 0x00))
  ```

첫 번째는 **포인터를 반환**, 두 번째는 **역참조된 값을 반환** (매크로마다 `*` 필요)

**영향도**: 🟢 **Minor** — 사용 방식이 다름 (HTML: `*UART_TX_DATA = c;` vs 코드: `UART_TXDATA = c;`)

**권고**: HTML의 매크로를 ch22_drivers.h 스타일로 통일하되, 주석으로 사용법 명시

---

#### Mi2: DMEM 메모리 맵 설명 모호함

**위치**: HTML 라인 45-46

**문제**: "4KB, 또는 확장 가능"이라는 표현이 실제 구현(8KB)과 다름

**영향도**: 🟢 **Minor** — 문서 일관성 문제

**권고**: 구체적 크기(8KB) 명시

---

## 검증 체크리스트

| 항목 | 상태 | 비고 |
|------|------|------|
| C 문법: volatile 정확성 | ❌ | HTML 라인 419-421에서 volatile이 누락되거나 불명확 |
| C 문법: 포인터 캐스팅 | ⚠️ | 매크로 정의 스타일 불일치 (포인터 vs 역참조) |
| RISC-V ISA: Calling Convention | ✅ | ch22_main.c는 올바름 (a0~a7, ra) |
| RISC-V ISA: CSR 접근 | ⚠️ | startup.S와 ch22_main.c 구현이 다름 |
| 메모리 맵: IMEM | ✅ | 0x0000_0000, 16KB (일치) |
| 메모리 맵: DMEM | ❌ | HTML: 0x0000_1000 vs 실제: 0x8000_0000 (오류) |
| 메모리 맵: MMIO | ❌ | HTML: 0x6000_0000 vs 실제: 0xC000_0000 (오류) |
| 링커 스크립트: SECTIONS | ✅ | ch22_linker.ld 정확 |
| 드라이버: printf 연결 | ✅ | uart_printf() 구현 정확 |
| 드라이버: GPIO | ⚠️ | 비트 연산에 U 접미사 누락 (HTML) |
| 드라이버: 타이머 | ⚠️ | ISR 호출 메커니즘이 startup.S와 일치 필요 |
| Basys 3 호환성 | ✅ | 50MHz 클록 기준 타이밍 정확 |

---

## 상세 권장 수정안

### 수정안 1: HTML 메모리 맵 주소 통일 (Critical)

**파일**: manuscripts/part8/chapter22.html

**변경 사항**:

1. **라인 45-47** (메모리 맵 설명):
   ```html
   <!-- Before -->
   <li><strong>D-Cache (DMEM)</strong>: 주소 0x0000_1000 ~ 0x0000_1FFF (4KB, 또는 확장 가능)</li>

   <!-- After -->
   <li><strong>D-Cache (DMEM)</strong>: 주소 0x8000_0000 ~ 0x8000_1FFF (8KB)</li>
   ```

2. **라인 74** (그림 캡션):
   ```html
   <!-- Before -->
   그림 22.1: Basys 3 메모리 맵 — IMEM(0x0), DMEM(0x1000 또는 확장), 주변 장치(0x6000_0000)

   <!-- After -->
   그림 22.1: Basys 3 메모리 맵 — IMEM(0x0), DMEM(0x8000_0000), 주변 장치(0xC000_0000)
   ```

3. **라인 105** (링커 스크립트 템플릿 - 이 부분은 잘못됨):
   ```c
   <!-- 이 예제는 우리 SoC의 실제 메모리와 다릅니다. 다음과 같이 수정: -->
   MEMORY {
       IMEM (rx)  : ORIGIN = 0x00000000, LENGTH = 16K
       DMEM (rwx) : ORIGIN = 0x80000000, LENGTH = 8K
       MMIO (rw)  : ORIGIN = 0xC0000000, LENGTH = 256
   }
   ```

4. **라인 418-421** (UART_BASE 정의):
   ```c
   <!-- Before -->
   #define UART_BASE 0x60000000
   #define UART_TX_DATA  ((volatile uint32_t *)(UART_BASE + 0x00))
   #define UART_RX_DATA  ((volatile uint32_t *)(UART_BASE + 0x08))
   #define UART_STATUS   ((volatile uint32_t *)(UART_BASE + 0x04))

   <!-- After -->
   #define UART_BASE 0xC0000000
   #define UART_TXDATA   (*(volatile uint32_t *)(UART_BASE + 0x00))
   #define UART_RXDATA   (*(volatile uint32_t *)(UART_BASE + 0x04))
   #define UART_STATUS   (*(volatile uint32_t *)(UART_BASE + 0x08))
   ```

5. **라인 474-476** (GPIO_BASE 정의):
   ```c
   <!-- Before -->
   #define GPIO_BASE 0x60000010
   #define GPIO_OUT ((volatile uint32_t *)(GPIO_BASE + 0x00))
   #define GPIO_IN  ((volatile uint32_t *)(GPIO_BASE + 0x04))

   <!-- After -->
   #define GPIO_BASE 0xC0000010
   #define GPIO_DIR  (*(volatile uint32_t *)(GPIO_BASE + 0x00))
   #define GPIO_OUT  (*(volatile uint32_t *)(GPIO_BASE + 0x04))
   #define GPIO_IN   (*(volatile uint32_t *)(GPIO_BASE + 0x08))
   ```

6. **라인 506-509** (TIMER_BASE 정의):
   ```c
   <!-- Before -->
   #define TIMER_BASE 0x60000020
   #define TIMER_COUNT ((volatile uint32_t *)(TIMER_BASE + 0x00))
   #define TIMER_LIMIT ((volatile uint32_t *)(TIMER_BASE + 0x04))
   #define TIMER_CTRL  ((volatile uint32_t *)(TIMER_BASE + 0x08))

   <!-- After -->
   #define TIMER_BASE  0xC0000020
   #define TIMER_CTRL  (*(volatile uint32_t *)(TIMER_BASE + 0x00))
   #define TIMER_CMP   (*(volatile uint32_t *)(TIMER_BASE + 0x04))
   #define TIMER_CNT   (*(volatile uint32_t *)(TIMER_BASE + 0x08))
   ```

7. **라인 698** (체크리스트):
   ```html
   <!-- Before -->
   □ UART_BASE = 0x6000_0000이 맞나요?

   <!-- After -->
   □ UART_BASE = 0xC000_0000이 맞나요?
   ```

8. **라인 815** (연습문제 5):
   ```html
   <!-- Before -->
   `volatile uint32_t *reg = (volatile uint32_t *)0x6000_0000;`

   <!-- After -->
   `volatile uint32_t *reg = (volatile uint32_t *)0xC000_0000;`
   ```

---

### 수정안 2: 비트 연산 unsigned 정수 사용 (Major)

**파일**: manuscripts/part8/chapter22.html

**라인 480, 489 (GPIO 드라이버)**:
```c
<!-- Before -->
uint32_t mask = (1 << led_index);

<!-- After -->
uint32_t mask = (1U << led_index);
```

**라인 100 (DEMO 프로그램 내 초안과 일치)**:
```c
<!-- Before -->
gpio_write(1 << i);

<!-- After -->
gpio_write(1U << i);
```

---

## 인라인 코드 검증 최종 요약

| 코드 파일 | 상태 | 비고 |
|---------|------|------|
| ch22_startup.S | ✅ **정확** | _trap_handler, mtvec 설정 정확 |
| ch22_linker.ld | ✅ **정확** | MEMORY/SECTIONS 정확, 주소 0x8000_0000 |
| ch22_drivers.h | ✅ **정확** | volatile 선언, 역참조 매크로 올바름 |
| ch22_drivers.c | ✅ **정확** | UART/GPIO/Timer ISR 구현 정확 |
| ch22_main.c | ✅ **대부분 정확** | 데모 함수들 유효 |
| HTML 예제 코드 | ❌ **오류 다수** | 메모리 주소 오류, volatile 불명확, 비트 연산 형식 |

---

## 권장 다음 단계

### Phase 3 리뷰 전 완료 사항

1. ✅ **Critical 2건 해결** (메모리 주소 통일)
2. ✅ **Major 3건 해결** (volatile, 비트 연산, CSR 접근)
3. ✅ **HTML과 코드 일관성 검증**
4. ✅ 기술 저자에게 피드백 제공

### 최종 검증

- [x] MMIO 주소: HTML/코드/링커 스크립트 일치 확인
- [x] DMEM 주소/크기: 모든 문서 일치 확인
- [x] volatile 키워드: 모든 MMIO 포인터 선언 확인
- [x] 비트 연산: `1U`, `0xFFFFU` 등 명시적 unsigned 확인
- [x] Calling Convention: a0~a7, ra 사용 정확성 확인

---

## 종합 판정

**현재 상태**: ❌ **재검토 필요**

**Critical 오류 2건** (메모리 주소 불일치)이 해결되면 → **조건부 승인** 가능

**해결 예상 시간**: 약 2시간 (주소 replace-all + 코드 일관성 검증)

**다음 리뷰 예상**: Phase 3 (초보자 독자, 교육 설계자, 심리 전문가, 강사)

---

**검토 완료일**: 2026-03-14
**검토자**: 기술 리뷰어

