# Ch17 기술 기획안 — 기술 리뷰어 검토

리뷰어: 기술 리뷰어 (Technical Reviewer)
작성일: 2026-03-13
대상: Chapter 17 — APB 브리지와 주변 장치 연결 (집필 예정)
참조: ch17_ahb_to_apb_bridge.sv, ch17_apb_uart.sv, ch17_apb_gpio.sv, ch17_apb_timer.sv, ch17_peripheral_top.sv, ch17_peripheral_tb.sv, chapter16_tech_review.md

---

## 0. 사전 점검: Ch16 수정 사항과의 연계

Ch17 집필 전 반드시 확인해야 할 Ch16 미해결 이슈:

| 항목 | 내용 | Ch17 영향 |
|------|------|-----------|
| C1 수정 완료 여부 | addr_lat 래치 조건이 `state == M_IDLE && cache_req`로 변경되었는지 | AHB-to-APB 브리지의 래치 전략 설계 기준 |
| 인터커넥트 APB 슬롯 주소 | Ch16 인터커넥트에서 `HSEL_apb = (HADDR[31:16] == 16'hFFFF)` 로 예약됨 | **주소 불일치 Critical 이슈 존재 (아래 §1 참조)** |
| HREADY MUX 한계 | 단일 NONSEQ-IDLE 패턴 전용 | 브리지 설계 범위 설정에 영향 |

---

## 1. APB 신호 정의 목록 (절 17.1)

### 1.1 APB 신호 전체 목록

ARM IHI0024C (AMBA APB Protocol Specification) 기준.

| 신호명 | 방향 (마스터→슬레이브 기준) | 폭 | 설명 |
|--------|---------------------------|-----|------|
| PCLK | 입력 | 1 | APB 클럭. 모든 전송은 상승 에지 기준 |
| PRESETn | 입력 | 1 | 비동기 리셋. 액티브 로우 |
| PADDR | 마스터→슬레이브 | 32 | APB 주소 버스 |
| PSEL | 마스터→슬레이브 | 1 (슬레이브별) | 슬레이브 선택. 전송 기간 내내 HIGH |
| PENABLE | 마스터→슬레이브 | 1 | 전송 활성화. Setup Phase에서 0, Enable Phase에서 1 |
| PWRITE | 마스터→슬레이브 | 1 | 쓰기(1) / 읽기(0) |
| PWDATA | 마스터→슬레이브 | 32 | 쓰기 데이터 |
| PRDATA | 슬레이브→마스터 | 32 | 읽기 데이터 |
| PREADY | 슬레이브→마스터 | 1 | 슬레이브 준비. 0이면 Wait State 삽입 |
| PSLVERR | 슬레이브→마스터 | 1 | 슬레이브 오류 응답 (0=OKAY) |

> **집필 주의**: PSTRB(바이트 스트로브), PPROT(보호 속성)은 APB4 신호임.
> 본 챕터는 APB3 기반으로 작성하고, APB4 확장 신호는 aside 박스로 별도 언급.

### 1.2 Setup Phase / Enable Phase 타이밍 정의

```
          ___     ___     ___     ___     ___
PCLK  ___|   |___|   |___|   |___|   |___|   |___

      IDLE          SETUP     ENABLE/ACCESS
              _______________
PSEL  _______|               |_____________________

                      _______
PENABLE ______________|       |___________________

PADDR  -------<  VALID_ADDR  >--------------------
PWRITE -------<  W or R      >--------------------
PWDATA -------<  VALID_DATA  >(write only)--------
```

**Setup Phase (T_SETUP)**: PSEL=1, PENABLE=0인 1사이클.
- PADDR, PWRITE, PWDATA(쓰기 시)를 슬레이브에 제시한다.
- 슬레이브가 디코딩할 시간을 준다.

**Enable Phase (T_ACCESS)**: PSEL=1, PENABLE=1인 사이클.
- PREADY=1이면 이 사이클에 전송 완료.
- PREADY=0이면 PREADY=1이 될 때까지 Enable Phase 연장 (Wait State).

**집필 핵심 강조점**: PENABLE은 Setup Phase 다음 사이클에만 1이 된다.
"PSEL=1인 순간부터 PENABLE=1"이 되는 코드는 **APB 프로토콜 위반**이다.

### 1.3 AHB vs APB 비교표

| 비교 항목 | AHB-Lite (Ch16) | APB (Ch17) |
|-----------|-----------------|------------|
| ARM 스펙 | IHI0033A/B | IHI0024C |
| 클럭 도메인 | HCLK | PCLK (= HCLK in 동기 브리지) |
| 파이프라인 | 2단계 (주소/데이터 오버랩) | 비파이프라인 (순차적) |
| 버스트 전송 | 지원 (HBURST) | 미지원 |
| 최소 전송 사이클 | 2사이클 (주소+데이터) | 2사이클 (Setup+Enable) |
| Wait State 삽입 | HREADY=0 | PREADY=0 |
| 오류 응답 | HRESP (2사이클) | PSLVERR (1사이클) |
| 대표 적용 대상 | 메모리, 캐시, 고속 DMA | UART, GPIO, 타이머, SPI |
| 데이터 폭 | 32/64비트 | 8/16/32비트 |
| 설계 복잡도 | 높음 (파이프라인 고려) | 낮음 (비파이프라인, 상태 단순) |

---

## 2. AHB-to-APB 브리지 FSM 설계 (절 17.2)

### 2.1 FSM 상태 정의 및 전이 조건

**확정 설계: 3상태 FSM** (ST_IDLE → ST_SETUP → ST_ACCESS)

```systemverilog
typedef enum logic [1:0] {
   ST_IDLE   = 2'b00,   // 유휴: APB 전송 없음, HREADY=1
   ST_SETUP  = 2'b01,   // Setup Phase: PSEL=1, PENABLE=0, HREADY=0
   ST_ACCESS = 2'b10    // Enable Phase: PSEL=1, PENABLE=1, HREADY=PREADY
} state_t;
```

**상태 전이 조건**:

| 현재 상태 | 전이 조건 | 다음 상태 |
|-----------|-----------|-----------|
| ST_IDLE | `htrans == NONSEQ && hready_out` | ST_SETUP |
| ST_IDLE | 그 외 | ST_IDLE |
| ST_SETUP | 항상 (1사이클 고정) | ST_ACCESS |
| ST_ACCESS | `pready && !next_valid` | ST_IDLE |
| ST_ACCESS | `pready && next_valid` | ST_SETUP |
| ST_ACCESS | `!pready` | ST_ACCESS (Wait 유지) |

`next_valid`: ST_ACCESS 처리 중 새 AHB 전송이 대기 중인 경우.

### 2.2 HREADY 처리 전략 (가장 중요한 설계 포인트)

브리지는 AHB 슬레이브이므로 HREADY_out으로 AHB 마스터를 제어한다.

| FSM 상태 | HREADY_out | 이유 |
|----------|-----------|------|
| ST_IDLE | 1 | 새 전송 수신 가능 |
| ST_SETUP | 0 | APB 전송 진행 중 — AHB 마스터 대기 |
| ST_ACCESS | PREADY | APB 슬레이브 완료 여부에 따라 결정 |

**집필 필수 강조**: ST_SETUP에서 HREADY=0을 반드시 구동해야 한다.
ST_SETUP → ST_ACCESS 전이 사이클(PENABLE=1 되는 순간)에 PREADY=1이면
HREADY=1을 바로 올릴 수 있다. 이 경우 브리지는 총 2사이클 지연
(ST_SETUP 1사이클 + ST_ACCESS 1사이클 = AHB 마스터 관점 2사이클 Wait).

### 2.3 AHB 주소/데이터 래치 전략

```systemverilog
// AHB 주소 단계 캡처: HREADY=1이고 유효한 전송이 들어올 때
// (현재 브리지가 IDLE이거나, ACCESS 완료 시점)
always_ff @(posedge hclk or negedge hreset_n) begin
   if (!hreset_n) begin
      addr_reg  <= '0;
      write_reg <= 1'b0;
      valid_reg <= 1'b0;
   end else if (hready_out && (htrans == HTRANS_NONSEQ)) begin
      // hready_out=1인 사이클에 NONSEQ 감지 → 주소/제어 래치
      addr_reg  <= haddr;
      write_reg <= hwrite;
      valid_reg <= 1'b1;
   end else if (state == ST_ACCESS && pready) begin
      // APB 전송 완료 → valid 해제
      valid_reg <= 1'b0;
   end
end
```

**핵심**: `hready_out`이 1인 사이클에만 AHB 주소를 래치한다.
브리지가 ST_SETUP/ST_ACCESS 상태에서 `hready_out=0`이므로,
이 기간 동안 들어오는 새 NONSEQ는 무시된다(마스터가 Wait 중이므로 정상).

HWDATA는 별도 래치 없이 `pwdata = hwdata`로 직결한다.
AHB 쓰기 데이터 페이즈(HWDATA 유효)와 APB Enable Phase가 일치하기 때문이다.

> **검증 포인트**: 브리지가 ST_ACCESS에서 PREADY를 기다리는 동안
> AHB 마스터는 HWDATA를 유지(동결)한다. AHB 스펙에 의해 보장됨.

### 2.4 APB 슬레이브 선택 디코더

**현재 코드의 주소 맵 (ch17_ahb_to_apb_bridge.sv 기준)**:
```
Slave 0 (UART):   0x4000_0000 ~ 0x4000_0FFF  (addr_reg[13:12] = 2'b00)
Slave 1 (GPIO):   0x4000_1000 ~ 0x4000_1FFF  (addr_reg[13:12] = 2'b01)
Slave 2 (Timer):  0x4000_2000 ~ 0x4000_2FFF  (addr_reg[13:12] = 2'b10)
Slave 3 (예약):   0x4000_3000 ~ 0x4000_3FFF  (addr_reg[13:12] = 2'b11)
```

**⚠️ Critical: Ch16 인터커넥트 주소와 불일치 (집필 전 반드시 조정 필요)**

Ch16 인터커넥트 코드(`ch16_ahb_interconnect.sv`)의 APB 슬롯:
```systemverilog
HSEL_apb = (HADDR[31:16] == 16'hFFFF);   // 0xFFFF_0000 ~ 0xFFFF_FFFF
```

Ch17 브리지 코드는 APB 내부 슬레이브 주소를 `0x4000_xxxx`로 설정했는데,
AHB 인터커넥트는 APB 슬롯을 `0xFFFF_xxxx`로 정의한다.
이 두 주소 공간은 서로 다른 레벨의 주소 맵이므로 기술적으로 충돌은 아니지만,
독자가 혼란을 겪지 않도록 **일관된 주소 체계**를 선택해야 한다.

**권장 해결안**:
- APB 기저 주소를 `0xFFFF_0000`으로 통일하여 Ch16 인터커넥트와 일치시킨다.
- PSEL 디코더 조건: `addr_reg[13:12]` 기준 유지 (APB 내부 오프셋)
- 각 슬레이브 절대 주소:
  ```
  UART:  0xFFFF_0000 ~ 0xFFFF_0FFF
  GPIO:  0xFFFF_1000 ~ 0xFFFF_1FFF
  Timer: 0xFFFF_2000 ~ 0xFFFF_2FFF
  예약:  0xFFFF_3000 ~ 0xFFFF_3FFF
  ```
- 브리지 코드의 주석만 수정하면 됨 (디코더 로직 `addr_reg[13:12]`는 동일).

---

## 3. UART 컨트롤러 레지스터 맵 (절 17.3)

### 3.1 레지스터 맵 전체

기저 주소: 0xFFFF_0000 (APB 버스 주소 기준)

| 오프셋 | 이름 | 접근 | 비트 | 설명 |
|--------|------|------|------|------|
| 0x00 | TX_DATA | WO | [7:0] | TX FIFO에 송신 데이터 push |
| 0x04 | RX_DATA | RO | [7:0] | RX FIFO에서 수신 데이터 pop |
| 0x08 | STATUS | RO | [3:0] | 상태 플래그 (아래 참조) |
| 0x0C | CTRL | R/W | [1:0] | TX_EN[0], RX_EN[1] |
| 0x10 | BAUD_DIV | R/W | [15:0] | 보드레이트 분주 값 |
| 0x14 | INT_EN | R/W | [1:0] | 인터럽트 활성화 |
| 0x18 | INT_STATUS | R/W1C | [1:0] | 인터럽트 상태 (쓰기 1로 클리어) |

**STATUS 레지스터 비트**:
```
[3]: RX FIFO 가득 참 (rx_full)
[2]: RX FIFO 데이터 있음 (rx_valid = !rx_empty)
[1]: TX FIFO 가득 참 (tx_full)
[0]: TX FIFO 비어있음 (tx_empty)
```

**INT_EN / INT_STATUS 비트**:
```
[0]: TX_EMPTY_IE  — TX FIFO 비어있을 때 인터럽트
[1]: RX_VALID_IE  — RX FIFO 데이터 있을 때 인터럽트
```

### 3.2 보드레이트 생성기 설계

**16× 오버샘플링 방식** (수신 잡음 내성 확보):

```
baud_tick 주파수 = CLK_FREQ / BAUD_DIV
baud_rate        = baud_tick_freq / 16
→ BAUD_DIV = CLK_FREQ / (baud_rate × 16)
```

**Basys 3 기준 주요 보드레이트 분주비 (100 MHz 클럭)**:

| baud_rate | BAUD_DIV 계산값 | 정수화 | 실제 baud_rate | 오차율 |
|-----------|----------------|--------|----------------|--------|
| 9,600 | 651.04 | 651 | 9,601.8 | +0.02% |
| 115,200 | 54.25 | 54 | 115,740.7 | +0.47% |
| 230,400 | 27.13 | 27 | 231,481.5 | +0.47% |
| 460,800 | 13.56 | 14 | 446,428.6 | -3.12% |

**집필 핵심**: 115,200 baud 기본값 BAUD_DIV=54, 오차율 0.47%.
UART 수신 허용 오차는 통상 ±2~3%이므로 실용상 문제없다.
집필 시 분주비 계산 과정을 단계별로 보여주어 학습자가 다른 보드레이트도 스스로 계산할 수 있게 한다.

**집필 경고 박스 필수 포함**:
```
BAUD_DIV=0으로 설정하면 baud_counter가 매 클럭 오버플로우하여
기대와 전혀 다른 보드레이트가 생성된다.
하드웨어 보호: BAUD_DIV 최솟값 1 검사 추가 권장.
```

### 3.3 TX FIFO 설계 (Basys 3 BRAM 예산)

**현재 코드 설계**: FIFO_DEPTH=8 (8바이트, 분산 LUTRAM)

| 항목 | 값 |
|------|-----|
| FIFO 깊이 | 8엔트리 |
| 메모리 구조 | `logic [7:0] tx_fifo_mem [0:7]` → LUTRAM 추론 |
| 포인터 방식 | (N+1)비트 포인터 wrap-around (N=$clog2(DEPTH)) |
| 만가득 판정 | MSB 다르고 하위 비트 동일 조건 |
| 빈 판정 | wr_ptr == rd_ptr |
| BRAM 소모 | 0개 (LUTRAM 기반, 8×1바이트) |

**Basys 3 BRAM 예산 분석**:
- XC7A35T 총 BRAM: 50×36Kbit = 1,800Kbit
- FIFO를 BRAM으로 구현 시: 36Kbit BRAM 1개 = 4,096×9비트 (ECC 포함)
- 8엔트리 FIFO를 BRAM으로 구현하는 것은 극도의 낭비 → LUTRAM 설계가 올바름
- TX/RX 각 8엔트리 FIFO: LUT 8×8 = 64 LUT (Basys 3 20,800 LUT 중 0.3%)

### 3.4 Basys 3 UART 핀 연결

Basys 3 보드의 USB-UART 브리지는 **CP2102** (Silicon Laboratories 제품) 이다.

> **집필 주의**: 기존 코드 파일 헤더에 "FTDI FT2232"로 기재되어 있으나
> Basys 3 회로도 기준 USB-UART 칩은 CP2102이다. 수정 필요.

**XDC 제약 파일 (Basys 3 기준)**:
```tcl
# UART TX (FPGA → PC via CP2102)
set_property PACKAGE_PIN A18 [get_ports uart_tx]
set_property IOSTANDARD LVCMOS33 [get_ports uart_tx]

# UART RX (PC → FPGA via CP2102)
set_property PACKAGE_PIN B18 [get_ports uart_rx]
set_property IOSTANDARD LVCMOS33 [get_ports uart_rx]
```

---

## 4. GPIO 레지스터 맵 (절 17.4)

### 4.1 레지스터 맵 전체

기저 주소: 0xFFFF_1000 (APB 버스 주소 기준)

| 오프셋 | 이름 | 접근 | 비트 | 설명 |
|--------|------|------|------|------|
| 0x00 | GPIO_DIR | R/W | [GPIO_WIDTH-1:0] | 방향 레지스터 (1=출력, 0=입력) |
| 0x04 | GPIO_OUT | R/W | [GPIO_WIDTH-1:0] | 출력 데이터 레지스터 |
| 0x08 | GPIO_IN | RO | [GPIO_WIDTH-1:0] | 동기화된 입력 데이터 (읽기 전용) |
| 0x0C | GPIO_INT_EN | R/W | [GPIO_WIDTH-1:0] | 인터럽트 활성화 (상승 에지 감지) |

### 4.2 Basys 3 GPIO 핀 매핑

**LED 16개 (출력, GPIO_DIR[15:0]=1로 설정)**:
```tcl
# LED [15:0] — JA 헤더가 아닌 보드 LED
set_property PACKAGE_PIN U16 [get_ports {gpio_out[0]}]   # LD0
set_property PACKAGE_PIN E19 [get_ports {gpio_out[1]}]   # LD1
# ... (LD0~LD15, LVCMOS33)
```

**스위치 16개 (입력, GPIO_DIR[31:16]=0 기본값)**:
```tcl
# SW [15:0]
set_property PACKAGE_PIN V17 [get_ports {gpio_in[16]}]   # SW0
set_property PACKAGE_PIN V16 [get_ports {gpio_in[17]}]   # SW1
# ... (SW0~SW15, LVCMOS33)
```

**GPIO_WIDTH 파라미터 설정**:
- LED 16개 + 스위치 16개 = 32비트 → GPIO_WIDTH=32 (현재 코드 기본값과 일치)
- [15:0]: LED (방향=출력)
- [31:16]: 스위치 (방향=입력)

### 4.3 방향 레지스터(GPIO_DIR) 기본값

```systemverilog
// 리셋 시 기본값: 모든 핀 입력 (0)
dir_reg <= '0;
```

**교육 포인트**: 리셋 직후 GPIO_DIR=0(전체 입력)이므로
LED를 켜려면 반드시 `GPIO_DIR[15:0] = 16'hFFFF`를 먼저 써야 한다.
이 순서를 빠뜨리면 LED가 켜지지 않는 흔한 실수 → aside 박스 필수.

### 4.4 메타안정성 방지 (2단 동기화기)

```systemverilog
// 외부 비동기 입력(스위치) → 2단 동기화 필수
always_ff @(posedge pclk or negedge preset_n) begin
   if (!preset_n) begin
      gpio_in_sync_0 <= '0;
      gpio_in_sync_1 <= '0;
   end else begin
      gpio_in_sync_0 <= gpio_in;       // 1단: 메타안정성 흡수
      gpio_in_sync_1 <= gpio_in_sync_0; // 2단: 안정화된 값
   end
end
```

**집필 필수**: 스위치 입력처럼 비동기 외부 신호는 반드시 동기화해야 한다.
동기화 누락 시 시뮬레이션에서는 정상 동작하지만
FPGA 실제 동작에서 X-propagation 및 기능 오류가 발생한다.

---

## 5. 타이머 레지스터 맵 (절 17.5)

### 5.1 레지스터 맵 전체

기저 주소: 0xFFFF_2000 (APB 버스 주소 기준)

| 오프셋 | 이름 | 접근 | 비트 | 설명 |
|--------|------|------|------|------|
| 0x00 | TIM_CTRL | R/W | [2:0] | EN[0], AUTO_RELOAD[1], IE[2] |
| 0x04 | TIM_COUNT | R/W | [31:0] | 현재 카운터 값 (읽기/직접 쓰기 가능) |
| 0x08 | TIM_CMP | R/W | [31:0] | 비교 값 (COUNT == CMP 시 인터럽트) |
| 0x0C | TIM_PRESCALE | R/W | [31:0] | 프리스케일러 분주 값 |
| 0x10 | TIM_INT_STAT | R/W1C | [0] | 인터럽트 펜딩 (1로 쓰면 클리어) |

**TIM_CTRL 비트 정의**:
```
[0]: EN          — 타이머 활성화 (0=정지, 1=동작)
[1]: AUTO_RELOAD — CMP 도달 시 COUNT를 0으로 자동 리셋 (주기적 인터럽트)
[2]: IE          — 인터럽트 활성화 (0이면 timer_irq 출력 억제)
```

### 5.2 주기적 인터럽트 생성 계산

**1ms 주기 인터럽트 설정 (100 MHz 클럭, 프리스케일러 없음)**:
```
TIM_PRESCALE = 0        (매 클럭마다 COUNT 증가)
TIM_CMP      = 99,999   (0부터 99,999까지 = 100,000 클럭 = 1ms)
TIM_CTRL     = 3'b111   (EN=1, AUTO_RELOAD=1, IE=1)
```

**프리스케일러 사용 시 (100분주 후 1µs 틱)**:
```
TIM_PRESCALE = 99       (100클럭마다 tick 1회 → 1µs 분해능)
TIM_CMP      = 999      (1µs × 1000 = 1ms)
```

**집필 포인트**: 프리스케일러 = 0이면 매 클럭 카운트(최고 분해능),
= N이면 N+1 클럭마다 카운트(실제 분주비는 N+1임을 명시).

### 5.3 인터럽트 신호 Ch18/19 연결

```systemverilog
// timer_irq → 프로세서의 mip.MTIP (Machine Timer Interrupt Pending)
// Chapter 19에서 CSR 레지스터 파일에 연결됨
assign timer_irq = int_pending & int_enable;
```

**집필 예고**: 이 인터럽트 신호는 Ch18(인터럽트 컨트롤러)과 Ch19(CSR)에서
RISC-V `mip.MTIP` 비트와 연결된다. Ch17에서는 신호 정의와 생성까지만 다루고,
연결 방법은 Ch18/19 예고로 남긴다.

---

## 6. Critical 이슈 사전 경고 목록 (집필 시 반드시 포함)

### [W-C1] PENABLE 타이밍 오류 — 가장 흔한 APB 실수

**오류 패턴**:
```systemverilog
// 잘못된 구현: PSEL=1이 되는 즉시 PENABLE=1 구동
always_comb begin
   if (valid_transfer) begin
      psel    = 1'b1;
      penable = 1'b1;   // SETUP Phase 없이 바로 ENABLE ← APB 위반!
   end
end
```

**올바른 구현**:
```systemverilog
// SETUP Phase (1사이클) → ACCESS Phase
ST_SETUP:  begin psel = 1'b1; penable = 1'b0; end   // Setup
ST_ACCESS: begin psel = 1'b1; penable = 1'b1; end   // Enable
```

**집필 필수 설명**: ARM APB 스펙은 "PENABLE must be deasserted for one cycle
(Setup Phase) before the Enable Phase"를 명시한다.
PENABLE=1이 PSEL과 동시에 올라가면 Setup Phase가 없는 것이므로 프로토콜 위반이다.
실제 슬레이브 IP가 이를 허용하는 경우도 있으나(PREADY로 보완),
교재에서는 프로토콜 준수 구현을 원칙으로 한다.

### [W-C2] 브리지 HREADY 처리 오류

**오류 패턴**:
```systemverilog
// 잘못된 구현: APB 전송 중에도 HREADY=1 유지 → 마스터가 새 전송 시작
assign hready_out = 1'b1;   // ← APB 전송 완료 전에 마스터가 다음 주소를 구동!
```

**결과**: HADDR이 갱신되면 addr_reg가 덮어써지고, APB 슬레이브에는 잘못된 주소가 구동된다.

**올바른 구현**: ST_SETUP에서 HREADY=0, ST_ACCESS에서 HREADY=PREADY.

**집필 필수**: HREADY=0이 브리지의 "나는 아직 처리 중이니 다음 전송을 보내지 마라"는
AHB 흐름 제어 신호임을 명확히 설명한다.

### [W-C3] 보드레이트 분주비 계산 오류

**오류 패턴 1**: 16× 오버샘플링 팩터 누락
```
잘못된 계산: BAUD_DIV = CLK_FREQ / baud_rate = 100,000,000 / 115,200 ≈ 868
올바른 계산: BAUD_DIV = CLK_FREQ / (baud_rate × 16) = 100,000,000 / 1,843,200 ≈ 54
```

BAUD_DIV=868로 설정하면 실제 보드레이트는 115,200/16 = 7,200 baud가 된다.
PC와 통신이 전혀 이루어지지 않는 원인이 된다.

**오류 패턴 2**: 반올림 없는 정수 절사
```
54.25 → 54로 절사 시: 실제 baud_rate = 100,000,000/(54×16) = 115,740.7 (+0.47%)
54.25 → 54로 반올림도 동일 결과 (반올림하면 더 정확한 경우도 있음)
```

**집필 권장**: 기본값 `baud_div = 16'd54`에 주석으로
"// 100MHz / (115200 × 16) ≈ 54, 오차 0.47% (허용 범위: ±3%)"를 명시한다.

### [W-C4] APB Slave에서 PREADY 없는(또는 상시 0) 구현의 위험성

**오류 패턴**: PREADY를 출력 포트에 연결하지 않거나 0으로 고정
```systemverilog
// 잘못된 구현: PREADY 포트 없음 → 브리지가 영원히 ST_ACCESS 유지
module apb_uart_bad (
   ...
   // output pready 누락!
);
   // 브리지의 pready 입력이 X 또는 0으로 구동됨
```

**결과**: 브리지의 ST_ACCESS → ST_IDLE 전이 조건이 `pready=1`인데,
슬레이브가 PREADY를 구동하지 않으면 브리지는 영구적으로 ST_ACCESS에 갇힌다.
AHB 마스터는 HREADY=0이 되어 전체 시스템이 deadlock 상태가 된다.

**교재 설계**: 3개 슬레이브 모두 `assign pready = 1'b1` (즉시 응답)으로 구현.
향후 PREADY=0 사용 시 `while (!(STATUS & PREADY_bit))` 폴링이 필요함을 설명.

---

## 7. 추가 기술 이슈 및 집필 주의사항

### 7.1 PRDATA MUX 동시 구동 방지

peripheral_top.sv의 PRDATA MUX는 always_comb에서 PSEL 기반으로 선택:
```systemverilog
// 한 번에 하나의 PSEL만 1이어야 함
if      (psel[0]) prdata_mux = prdata_uart;
else if (psel[1]) prdata_mux = prdata_gpio;
else if (psel[2]) prdata_mux = prdata_timer;
else              prdata_mux = 32'h0;
```

APB 스펙상 둘 이상의 PSEL이 동시에 1이 되면 안 된다.
브리지의 PSEL 디코더가 one-hot 인코딩임을 검증 시 확인해야 한다.

**집필 추가**: 디코더에 `$onehot0(psel_decoded)` 어서션 추가 권장:
```systemverilog
`ifdef SIMULATION
assert property (@(posedge pclk) $onehot0(psel));
`endif
```

### 7.2 UART TX FSM에서 FIFO POP 타이밍

현재 코드에서 `tx_fifo_pop`이 `always_ff` 내부에서 레지스터로 구현됨:
```systemverilog
tx_fifo_pop <= 1'b1;   // 다음 클럭에 POP 실행
```
POP 신호가 1사이클 지연되어 실제 FIFO 포인터 갱신이 발생한다.
TX_IDLE에서 `tx_shift_reg <= tx_fifo_rdata`와 `tx_fifo_pop <= 1'b1`이
같은 사이클에 실행되므로, tx_fifo_rdata는 POP 전의 값(현재 헤드)임.
이는 올바른 동작이다 — 집필 시 "FIFO 읽기 → 시프트 레지스터 적재 → POP" 순서를 명확히 설명할 것.

### 7.3 RX 동기화기와 시작 비트 감지

```systemverilog
// 2단 동기화 후 시작 비트 감지 (하강 에지)
if (!rx_sync_1 && ctrl_reg[1]) begin   // rx_sync_1=0: 시작 비트
```
`rx_sync_1=0`이면 RX가 LOW이므로 시작 비트일 수 있다.
그러나 이 조건은 에지(edge)가 아닌 레벨(level) 감지이므로,
SHORT 노이즈가 들어오면 오작동할 수 있다.
현재 코드는 RX_START 상태에서 8번째 baud_tick(시작 비트 중앙)에서
다시 rx_sync_1=0을 확인하여 노이즈를 걸러낸다 — 올바른 구현.
집필 시 이 2단계 검증 과정을 명확히 설명할 것.

### 7.4 타이머 프리스케일러 동작 검증

```systemverilog
assign prescale_tick = timer_en && (prescale_cnt >= prescale_reg);
```
`prescale_reg=0`이면 항상 `prescale_cnt(0) >= prescale_reg(0)`이 참이므로
매 클럭마다 prescale_tick=1이 된다 (최고 분해능). 올바른 동작.

`prescale_reg=N`이면 prescale_cnt가 0, 1, ..., N까지 N+1 값을 거친 후
리셋되므로, COUNT는 N+1 클럭마다 1씩 증가한다. 집필 시 명시 필요.

### 7.5 INT_STATUS 경쟁 조건 (Race Condition)

UART `int_status_reg`가 두 개의 always_ff 블록에서 쓰여지고 있음:
```systemverilog
// 블록 1: W1C 클리어
always_ff ... if (apb_write && paddr==ADDR_INT_STATUS)
   int_status_reg <= int_status_reg & ~pwdata[7:0];

// 블록 2: 이벤트 세트
always_ff ... if (tx_fifo_empty)
   int_status_reg[0] <= 1'b1;
```

동일 신호를 두 개의 always_ff에서 구동하는 것은 IEEE 1800-2017에서
**다중 구동(multiple driver)**으로 합성 경고 또는 오류를 유발한다.

**수정 필요**: 하나의 always_ff로 통합:
```systemverilog
always_ff @(posedge pclk or negedge preset_n) begin
   if (!preset_n) begin
      int_status_reg <= '0;
   end else begin
      // 클리어 우선 (W1C)
      if (apb_write && paddr == ADDR_INT_STATUS)
         int_status_reg <= int_status_reg & ~pwdata[7:0];
      // 세트 (이벤트 발생)
      else begin
         if (tx_fifo_empty)    int_status_reg[0] <= 1'b1;
         if (!rx_fifo_empty)   int_status_reg[1] <= 1'b1;
      end
   end
end
```

클리어와 세트가 동일 사이클에 발생하면 클리어를 우선한다 (W1C 규칙).

### 7.6 FIFO 가득 참 판정 로직 검증

```systemverilog
// 비어있음: wr_ptr == rd_ptr (상위 비트 포함 전체 일치)
assign tx_fifo_empty = (tx_wr_ptr == tx_rd_ptr);

// 가득 참: 상위 비트(MSB) 다르고 하위 비트 동일
assign tx_fifo_full  = (tx_wr_ptr[$clog2(FIFO_DEPTH)] != tx_rd_ptr[$clog2(FIFO_DEPTH)]) &&
                        (tx_wr_ptr[$clog2(FIFO_DEPTH)-1:0] == tx_rd_ptr[$clog2(FIFO_DEPTH)-1:0]);
```

FIFO_DEPTH=8이면 포인터 비트폭 = $clog2(8)+1 = 4비트.
- 빈 상태: wr_ptr=rd_ptr=4'b0000
- 1개 원소: wr_ptr=4'b0001, rd_ptr=4'b0000
- 가득 참: wr_ptr=4'b1000, rd_ptr=4'b0000 (MSB 다름, 하위 3비트 동일)
- 올바른 구현 확인 ✓

**집필 포인트**: 이 "(N+1)비트 포인터 FIFO" 패턴을 설명하면서
단순 모듈러 비교(`wr_ptr % DEPTH == rd_ptr % DEPTH`)의 모호성 문제를 함께 설명할 것.

### 7.7 Basys 3 UART 칩 오류 수정 필요

ch17_apb_uart.sv 파일 헤더 주석에:
```
// Basys 3 USB-UART (FTDI FT2232) 연결 기준
```
으로 기재되어 있으나, Basys 3 회로도(Rev. E) 기준 USB-UART 칩은
**Silicon Laboratories CP2102**이다. (FTDI 칩은 Cmod A7 등 다른 Digilent 보드에 사용)
집필 원고 및 코드 주석에서 정확한 칩 모델명으로 수정 필요.

---

## 8. SVG 다이어그램 계획

| SVG 파일명 | 절 | 내용 |
|-----------|-----|------|
| ch17_sec01_apb_timing.svg | 17.1 | APB Setup/Enable Phase 타이밍 다이어그램 (PCLK, PSEL, PENABLE, PADDR, PWDATA, PRDATA, PREADY) |
| ch17_sec01_ahb_apb_compare.svg | 17.1 | AHB-Lite vs APB 구조 비교 (파이프라인 vs 순차) |
| ch17_sec02_bridge_fsm.svg | 17.2 | 브리지 FSM (ST_IDLE→ST_SETUP→ST_ACCESS, HREADY/PREADY 신호 매핑) |
| ch17_sec02_bridge_timing.svg | 17.2 | 브리지 동작 타이밍: AHB 주소 페이즈 → APB Setup → APB Enable 흐름 |
| ch17_sec06_system_block.svg | 17.6 | 전체 시스템 블록도 (프로세서→AHB→인터커넥트→APB 브리지→UART/GPIO/Timer) |

---

## 9. 코드 파일 현황 및 수정 사항 정리

| 파일 | 상태 | 주요 수정 사항 |
|------|------|---------------|
| ch17_ahb_to_apb_bridge.sv | 기본 구조 완성, 주소 수정 필요 | APB 슬레이브 기저 주소 주석을 `0xFFFF_0000` 기준으로 수정 |
| ch17_apb_uart.sv | 대부분 완성, 버그 수정 필요 | ① 헤더 CP2102로 수정 ② int_status_reg 다중 구동 오류 수정 (§7.5) |
| ch17_apb_gpio.sv | 완성 | 추가 수정 불필요 |
| ch17_apb_timer.sv | 완성 | 추가 수정 불필요 |
| ch17_peripheral_top.sv | 완성 | PRDATA MUX 어서션 추가 권장 (§7.1) |
| ch17_peripheral_tb.sv | 구조 완성, 내용 검토 필요 | 시나리오 상세 구현 필요 |

---

## 10. 집필 우선순위 요약

### 즉시 수정 (집필 전 코드 수정 완료 필수)
1. **ch17_apb_uart.sv**: `int_status_reg` 다중 구동 오류 → always_ff 단일 블록으로 통합 (§7.5)
2. **ch17_ahb_to_apb_bridge.sv**: APB 슬레이브 주소 주석 `0xFFFF_0000` 기준으로 수정 (§2.4)
3. **ch17_apb_uart.sv**: 헤더 주석 "FTDI FT2232" → "CP2102"로 수정 (§7.7)

### 집필 시 반드시 포함 (aside 박스 권장)
- [W-C1] PENABLE 타이밍 오류 경고 (§6)
- [W-C2] HREADY 처리 오류 경고 (§6)
- [W-C3] 보드레이트 분주비 오류 경고 (§6)
- [W-C4] PREADY 누락 deadlock 경고 (§6)
- GPIO_DIR 초기 설정 누락 경고 (§4.3)
- 타이머 프리스케일러 분주비 N+1 명시 (§7.4)

### 집필 권장 (품질 향상)
- FIFO (N+1)비트 포인터 패턴 설명 (§7.6)
- PRDATA MUX PSEL one-hot 어서션 추가 (§7.1)
- UART TX FIFO POP 타이밍 순서 설명 (§7.2)
- RX 노이즈 거부 2단계 검증 설명 (§7.3)

---

*작성 완료: 2026-03-13, 기술 리뷰어*
