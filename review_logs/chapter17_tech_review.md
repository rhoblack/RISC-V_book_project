# Chapter 17 기술 리뷰 보고서

날짜: 2026-03-13
리뷰어: 기술 리뷰어

---

## 요약

- 🔴 Critical: 3건
- 🟡 Major: 5건
- 🟢 Minor: 4건

전체적으로 설계 구조는 건전하고 교육용으로 잘 구성되어 있습니다. FSM 로직, 프로토콜 준수, FIFO 구현 모두 합성 가능한 수준입니다. 그러나 AHB-to-APB 브리지의 FSM 전이 조건에 잠재적 논리 오류, UART TX FSM의 FIFO POP 타이밍 문제, 테스트벤치 AHB 태스크의 타이밍 오류가 Critical 수준으로 확인되었습니다.

---

## Critical 이슈

### C1: AHB-to-APB 브리지 — ST_ACCESS에서 valid_reg 기반 SETUP 재진입 논리 오류

**파일**: `ch17_ahb_to_apb_bridge.sv:107~113`

**문제**:
ST_ACCESS 상태에서 `pready`가 어서트되면, `valid_reg`를 검사하여 ST_SETUP으로 재진입 여부를 결정합니다. 그러나 `valid_reg`는 같은 클럭 엣지에서 `always_ff`로 클리어됩니다 (74~76줄).

```systemverilog
// valid_reg 래치 블록
end else if (state == ST_ACCESS && pready) begin
    valid_reg <= 1'b0;   // 74~76줄: 동일 클럭에 클리어
end

// FSM 전이 블록 (조합 논리)
ST_ACCESS: begin
    if (pready) begin
        if (valid_reg)           // 현재 사이클의 valid_reg 참조
            next_state = ST_SETUP;
        else
            next_state = ST_IDLE;
    end
end
```

`always_comb`에서 참조하는 `valid_reg`는 현재 사이클의 값(클리어 전)이므로 조합 논리 자체는 맞습니다. 그러나 문제는 **연속적 전송 파이프라이닝**: `hready_out && htrans==NONSEQ` 조건으로 `valid_reg`가 세트되는 것은 ST_ACCESS에서 HREADY=pready인 경우입니다. 즉, pready=1인 동일 사이클에 새 전송이 들어올 때, `valid_reg`는 그 사이클에 1로 세트되고 동시에 같은 블록 하단에서 0으로 클리어됩니다. SystemVerilog `always_ff` 블록에서 동일 신호에 대한 두 개의 비차단 대입이 존재하면 **후행 대입이 우선**되어 valid_reg는 0이 됩니다.

결과: 연속 전송 시 valid_reg=0으로 평가 → FSM이 ST_IDLE로 이동 → 새 전송 놓침.

**수정안**:
`valid_reg` 세트/클리어 우선순위를 명시적으로 처리합니다:

```systemverilog
always_ff @(posedge hclk or negedge hreset_n) begin
    if (!hreset_n) begin
        addr_reg  <= '0;
        write_reg <= 1'b0;
        valid_reg <= 1'b0;
    end else begin
        // 새 전송 캡처: ST_ACCESS 완료 사이클에서도 세트 가능 (우선순위 高)
        if (hready_out && (htrans == HTRANS_NONSEQ)) begin
            addr_reg  <= haddr;
            write_reg <= hwrite;
            valid_reg <= 1'b1;
        end else if (state == ST_ACCESS && pready) begin
            valid_reg <= 1'b0;
        end
    end
end
```

if-else 체인으로 세트(새 전송 캡처)를 클리어보다 높은 우선순위로 배치하면 동일 사이클에 새 전송이 도착했을 때 valid_reg=1이 유지됩니다.

---

### C2: UART TX FSM — TX_IDLE에서 FIFO POP과 TX_START 전이가 동일 사이클 발생

**파일**: `ch17_apb_uart.sv:123~131`

**문제**:
```systemverilog
TX_IDLE: begin
    uart_tx <= 1'b1;
    if (!tx_fifo_empty && ctrl_reg[0]) begin
        tx_shift_reg <= tx_fifo_rdata;   // 현재 사이클 rdata 캡처
        tx_fifo_pop  <= 1'b1;            // 동일 사이클에 POP 요청
        tx_state     <= TX_START;        // 동일 사이클에 상태 전이
        tx_bit_cnt   <= '0;
    end
end
```

`tx_fifo_rdata`는 조합 논리로 `tx_rd_ptr`을 인덱스로 즉시 출력됩니다 (282줄: `assign tx_fifo_rdata = tx_fifo_mem[tx_rd_ptr[...]];`). 그런데 `tx_fifo_pop`이 세트되면 같은 사이클에 `tx_rd_ptr`이 증가하는 것이 아니라 **다음 클럭**에 증가합니다 (293~294줄: `always_ff`에서 처리). 따라서 이번 사이클에 `tx_fifo_rdata`를 `tx_shift_reg`에 올바르게 캡처할 수 있습니다.

그러나 **실제 문제**는 `tx_fifo_pop`이 `always_ff` 내부에서 비차단 대입으로 관리된다는 점입니다(118, 120줄). `tx_fifo_pop <= 1'b1`이 이 사이클에 어서트되어도, FIFO의 `always_ff` 블록이 동일 사이클에 `tx_rd_ptr`을 증가시키지는 않습니다. 단, TX_START 진입 후 다음 클럭에도 `tx_fifo_pop`이 자동으로 0으로 클리어(120줄 기본값)되므로 이중 POP 문제는 없습니다.

하지만 보다 중요한 문제: `baud_div`가 초기값 54이고 리셋 직후 `baud_counter`는 0에서 시작합니다. `baud_div = 2`로 TB에서 설정하기 전, baud_div가 0으로 로드되는 엣지 케이스를 확인해야 합니다. `baud_div = 0`이면 `baud_counter >= baud_div - 1`은 `>= 16'hFFFF`가 되어 **baud_tick이 수만 사이클 동안 발생하지 않는** 상황이 됩니다. baud_div=0 방어 코드가 없습니다.

**수정안**:
```systemverilog
// baud_div 최솟값 보호
if (baud_counter >= (baud_div < 2 ? 16'd1 : baud_div - 1)) begin
```
또는 APB 쓰기 시 최솟값 클램프:
```systemverilog
ADDR_BAUD_DIV: baud_div <= (pwdata[15:0] < 16'd2) ? 16'd2 : pwdata[15:0];
```

---

### C3: 테스트벤치 — AHB 쓰기 태스크의 타이밍이 AHB-Lite 사양 불일치

**파일**: `ch17_peripheral_tb.sv:90~106`

**문제**:
```systemverilog
task ahb_write(input logic [31:0] addr, input logic [31:0] data);
    @(posedge hclk);
    // 주소 단계
    haddr  <= addr;
    htrans <= HTRANS_NONSEQ;
    hwrite <= 1'b1;
    hsize  <= 3'b010;

    @(posedge hclk);
    // 데이터 단계
    hwdata <= data;
    htrans <= HTRANS_IDLE;

    // HREADY 대기
    @(posedge hclk);
    while (!hready_out) @(posedge hclk);
endtask
```

AHB-Lite 사양에서 마스터는 **HREADY=1일 때만** 새 주소를 구동해야 합니다. 하지만 이 태스크는 이전 트랜잭션의 HREADY를 확인하지 않고 무조건 다음 클럭에 새 주소를 구동합니다. 브리지가 ST_SETUP/ST_ACCESS 중에 HREADY=0을 구동하고 있는데 마스터가 다시 HTRANS=NONSEQ를 구동하면, 브리지의 래치 조건 `hready_out && htrans==NONSEQ`가 만족되지 않아 새 전송이 무시됩니다.

현재 테스트에서는 각 태스크 호출 후 HREADY를 대기하므로 연속 호출 간 충돌은 없으나, 태스크 내부의 데이터 단계 처리가 부정확합니다. 데이터 단계(`@(posedge hclk); hwdata <= data; htrans <= HTRANS_IDLE;`)에서 HREADY 대기 없이 다음 클럭으로 진행하면, HREADY=0인 상황에서도 진행할 수 있습니다.

**수정안**:
```systemverilog
task ahb_write(input logic [31:0] addr, input logic [31:0] data);
    // 이전 트랜잭션 완료 대기 후 주소 단계 구동
    @(posedge hclk);
    while (!hready_out) @(posedge hclk);  // 이전 완료 확인
    haddr  <= addr;
    htrans <= HTRANS_NONSEQ;
    hwrite <= 1'b1;
    hsize  <= 3'b010;

    // 데이터 단계: HREADY 대기 후 데이터 구동
    @(posedge hclk);
    while (!hready_out) @(posedge hclk);
    hwdata <= data;
    htrans <= HTRANS_IDLE;

    @(posedge hclk);
endtask
```

---

## Major 이슈

### M1: UART — TX_IDLE에서 baud_tick과 무관하게 즉시 TX_START 전이

**파일**: `ch17_apb_uart.sv:123~131`

**문제**:
TX_IDLE → TX_START 전이 시 `baud_tick` 동기화를 거치지 않습니다. FIFO에 데이터가 들어오는 순간 `baud_tick`의 위상과 무관하게 TX_START가 시작됩니다. TX_START 진입 직후 `baud_tick`이 곧바로 오면 시작 비트가 16× 오버샘플링 카운터를 1~2 카운트만에 넘어가는 경우가 발생할 수 있습니다.

실용적 영향: `baud_tick`이 매 54사이클에 1회 발생하므로 위상 오차는 최대 53사이클(< 1 비트 주기)입니다. 시작 비트는 16× 오버샘플링이므로 최대 1/16 비트 오차가 발생하며, 실습 목적에서 허용 가능하지만 표준 UART 구현에서는 `baud_tick`에 동기화하여 전송을 시작하는 것이 권장됩니다.

**수정안**:
```systemverilog
TX_IDLE: begin
    uart_tx <= 1'b1;
    if (!tx_fifo_empty && ctrl_reg[0] && baud_tick) begin  // baud_tick 동기
        tx_shift_reg <= tx_fifo_rdata;
        tx_fifo_pop  <= 1'b1;
        tx_state     <= TX_START;
        tx_bit_cnt   <= '0;
    end
end
```

---

### M2: 타이머 — prescale_tick 조합 논리와 always_ff 카운터 갱신의 1사이클 불일치

**파일**: `ch17_apb_timer.sv:121, 135~144`

**문제**:
```systemverilog
assign prescale_tick = timer_en && (prescale_cnt >= prescale_reg);
```

`prescale_tick`은 조합 논리로 `prescale_cnt >= prescale_reg`인 사이클에 즉시 어서트됩니다. 동일 클럭 엣지에서 `always_ff`가 `prescale_cnt <= '0`으로 리셋합니다. 이는 올바른 동작입니다.

그러나 `count_match` 판정도 조합 논리입니다:
```systemverilog
assign count_match = (count_reg == cmp_reg);
```

`prescale_tick && count_match`가 동시에 참인 사이클에 인터럽트 세트와 카운터 리로드가 모두 발생합니다. `count_reg`가 `cmp_reg`에 도달한 사이클에 `prescale_tick`도 동시에 어서트되어야 하는데, `prescale_cnt >= prescale_reg`가 성립하는 것은 카운터가 목표값에 이미 도달한 사이클이므로 인터럽트는 **카운터가 목표 카운트에 정확히 도달하는 사이클**에 발생합니다. 이는 의도대로 동작합니다.

다만 `prescale_reg = 0`인 경우 `prescale_cnt >= 0`은 항상 참이므로 `prescale_tick`이 **매 사이클** 어서트됩니다. prescale_reg=0은 "분주 없음(매 클럭 카운트)" 의도이나, 이 경우 `prescale_cnt`는 0에서 리셋 → 다시 0에서 `>= 0` 조건 성립 → 매 사이클 카운트 증가가 됩니다. prescale_tick이 매 클럭 어서트되고 count 블록의 분기에서 prescale_tick && !count_match인 경우 count_reg가 매 클럭 증가하므로 동작은 올바릅니다. 단, **문서화**에서 "분주값 0 = 매 클럭"임을 명시해야 합니다 (현재 주석: "0이면 매 클럭 카운트"는 있으나 prescale_tick 로직 설명 누락).

---

### M3: AHB-to-APB 브리지 — psel이 IDLE에서만 '0, SETUP 진입 전 1사이클 유효 주소 없이 psel 구동 가능성

**파일**: `ch17_ahb_to_apb_bridge.sv:146~167`

**문제**:
APB 출력은 `state`(현재 상태) 기반 조합 논리입니다. FSM 상태 레지스터가 다음 클럭에 업데이트되므로 APB 신호는 1사이클 지연 없이 즉시 반영됩니다.

현재 ST_IDLE에서 `htrans==NONSEQ`가 들어오면:
- 현재 클럭: state=ST_IDLE → psel='0 (정상)
- 다음 클럭: state=ST_SETUP → psel=psel_decoded (addr_reg 기반)

그런데 `addr_reg`는 `hready_out && htrans==NONSEQ` 조건에서 래치됩니다. ST_IDLE에서 `hready_out=1`이므로 조건이 성립하여 `addr_reg <= haddr`이 다음 클럭에 적용됩니다. 따라서 ST_SETUP 사이클에는 addr_reg에 유효 주소가 들어 있습니다. 논리적으로 올바릅니다.

단, `psel_decoded`는 `addr_reg`를 기반으로 하는데, 리셋 직후 addr_reg='0인 상태에서 ST_SETUP이 될 경우 `addr_reg[13:12]=2'b00` → `psel_decoded[0]=1` (UART 선택)이 발생합니다. 리셋 직후에는 ST_IDLE 상태이므로 psel='0이 보장되지만, 이 초기값 의존성에 대한 주석이 부족합니다.

**수정안**: 주석 보완 권장:
```systemverilog
// 주의: addr_reg 초기값='0 → psel_decoded[0]=UART 선택이나,
// ST_IDLE에서 psel='0으로 강제되므로 의도치 않은 UART 선택은 없음
```

---

### M4: GPIO — gpio_irq가 조합 논리로 글리치 가능성

**파일**: `ch17_apb_gpio.sv:117~121`

**문제**:
```systemverilog
logic [GPIO_WIDTH-1:0] rising_edge;
assign rising_edge = gpio_in_sync_1 & ~gpio_in_prev;
assign gpio_irq = |(rising_edge & int_en_reg & ~dir_reg);
```

`rising_edge`는 순수 조합 논리로, `gpio_in_sync_1`과 `gpio_in_prev`의 전파 지연 차이로 인해 클럭 엣지 직후 순간적인 글리치가 발생할 수 있습니다. `gpio_irq`는 CPU의 인터럽트 컨트롤러로 연결되는 신호이므로 글리치에 의한 오인터럽트 발생 가능성이 있습니다.

교육용으로는 허용 가능한 수준이나, 실무 구현에서는 `rising_edge`를 레지스터(always_ff)로 래치하거나, 인터럽트 상태 레지스터(int_status_reg)를 별도 도입하여 W1C 패턴을 적용하는 것이 권장됩니다.

**수정안 (실습 수준)**:
```systemverilog
// 인터럽트 상태를 FF로 래치 (글리치 방지)
logic gpio_irq_r;
always_ff @(posedge pclk or negedge preset_n) begin
    if (!preset_n) gpio_irq_r <= 1'b0;
    else           gpio_irq_r <= |(rising_edge & int_en_reg & ~dir_reg);
end
assign gpio_irq = gpio_irq_r;
```

---

### M5: UART — TX_DATA 상태에서 tx_bit_cnt 리셋과 tx_data_idx 증가의 순서 문제

**파일**: `ch17_apb_uart.sv:146~159`

**문제**:
```systemverilog
TX_DATA: begin
    uart_tx <= tx_shift_reg[tx_data_idx];
    if (baud_tick) begin
        if (tx_bit_cnt == 4'd15) begin
            tx_bit_cnt <= '0;
            if (tx_data_idx == 3'd7) begin
                tx_state <= TX_STOP;
            end else begin
                tx_data_idx <= tx_data_idx + 1;
            end
        end else begin
            tx_bit_cnt <= tx_bit_cnt + 1;
        end
    end
end
```

`tx_bit_cnt == 15`에서 `tx_bit_cnt <= '0`으로 리셋하고 즉시 다음 비트(`tx_data_idx+1`)로 이동합니다. 다음 사이클에 `uart_tx <= tx_shift_reg[tx_data_idx+1]`로 새 비트가 출력되므로 타이밍은 올바릅니다. 다만 최초 TX_DATA 진입 시 `tx_bit_cnt='0`이고 `uart_tx <= tx_shift_reg[0]`이 즉시 출력됩니다. 이것은 TX_START에서 `tx_bit_cnt='0`으로 리셋 후 TX_DATA 진입 직후 첫 비트가 출력되는 구조이므로 의도에는 부합합니다.

실제 문제: TX_DATA에서 마지막 비트(`tx_data_idx==7`, `tx_bit_cnt==15`)에서 `tx_state <= TX_STOP`으로 전이할 때 `tx_bit_cnt`는 다음 사이클에 0으로 리셋됩니다. TX_STOP에서 `baud_tick` 대기 시 `tx_bit_cnt`가 0에서 시작하므로 정지 비트 길이는 정확히 16× baud_tick (= 1 비트 주기)입니다. 이는 올바른 8N1 구현입니다.

분류 재고: 이 항목은 동작상 오류가 없으나 tx_data_idx 증가와 tx_bit_cnt 리셋을 같은 if 블록에서 처리하는 구조가 독자에게 혼란을 줄 수 있으므로 Minor로 하향 조정 가능합니다. Major로 유지하는 이유는 코드 리뷰 시 의도 파악이 어렵기 때문입니다.

---

## Minor 이슈

### N1: AHB-to-APB 브리지 — `hsize` 포트가 래치되지 않고 미사용

**파일**: `ch17_ahb_to_apb_bridge.sv:24`

**문제**:
`hsize` 포트는 선언되어 있으나 모듈 내에서 전혀 사용되지 않습니다. APB는 32비트 고정 전송이므로 크기 정보가 불필요하나, 선언만 하고 사용하지 않으면 합성 도구에서 경고가 발생합니다.

**수정안**: `hsize`를 포트에서 제거하거나, `/* unused */` 주석을 추가하여 의도적 미사용임을 명시합니다.

---

### N2: UART — `tx_fifo_wdata` 신호명이 두 곳에서 assign으로 이중 구동될 여지

**파일**: `ch17_apb_uart.sv:62, 329`

**문제**:
`tx_fifo_wdata`는 62줄에서 `logic [7:0]`으로 선언되고, 329줄에서 `assign tx_fifo_wdata = pwdata[7:0];`로 구동됩니다. 단일 driver이므로 합성 상 문제는 없습니다. 그러나 선언 시 `tx_fifo_wdata`와 `tx_fifo_rdata`를 동일 줄(`logic [7:0] tx_fifo_wdata, tx_fifo_rdata;`)에 선언하면 독자가 두 신호의 드라이버를 추적하기 어렵습니다. 교육용 코드에서는 분리 선언이 가독성에 유리합니다.

---

### N3: 타이머 — `count_reg` 직접 쓰기와 `prescale_tick` 조건 우선순위 충돌 가능

**파일**: `ch17_apb_timer.sv:129~144`

**문제**:
```systemverilog
always_ff @(posedge pclk or negedge preset_n) begin
    ...
    end else if (apb_write && paddr == ADDR_TIM_COUNT) begin
        count_reg <= pwdata;
    end else if (prescale_tick) begin
        ...
    end
end
```

`apb_write`가 `prescale_tick`보다 높은 우선순위를 갖습니다. 소프트웨어가 ADDR_TIM_COUNT에 쓰는 사이클과 `prescale_tick`이 동시에 발생하면 소프트웨어 쓰기가 우선됩니다. 이는 의도된 동작이지만 주석이 없습니다.

**수정안**: 주석 추가:
```systemverilog
// 소프트웨어 카운터 설정이 prescale_tick보다 우선 (하드웨어 카운트 억제)
end else if (apb_write && paddr == ADDR_TIM_COUNT) begin
```

---

### N4: 테스트벤치 — UART 수신 데이터 검증 코드 부재

**파일**: `ch17_peripheral_tb.sv:206~233`

**문제**:
UART 루프백 테스트(`assign uart_rx = uart_tx`)에서 송신한 `'H'(0x48)` 데이터가 RX FIFO에 수신되었는지 확인하는 코드가 없습니다. 테스트 2는 TX FIFO가 비어지는 것(송신 완료)만 확인하고, 루프백으로 수신된 데이터의 올바름을 검증하지 않습니다. 교육 목적에서 루프백의 의미를 살리려면 `UART_RX_DATA` 주소 읽기와 값 비교가 필요합니다.

**권장 추가**:
```systemverilog
// RX FIFO 수신 확인 (루프백)
for (i = 0; i < 1000; i++) begin
    ahb_read(UART_STATUS, read_data);
    if (read_data[2]) break;     // RX 데이터 있음 (bit2: rx_valid)
    repeat (10) @(posedge hclk);
end
ahb_read(UART_RX_DATA, read_data);
if (read_data[7:0] == 8'h48)
    $display("[PASS] UART 루프백 수신 = 0x%02h", read_data[7:0]);
else
    $display("[FAIL] UART 루프백 수신 = 0x%02h (예상: 0x48)", read_data[7:0]);
```

---

## 최종 의견

Chapter 17의 코드 품질은 교육용으로 전반적으로 양호합니다. AHB-to-APB 브리지 FSM 구조, APB 슬레이브 레지스터 패턴, 인터럽트 W1C 처리 방식은 AMBA 표준을 충실히 반영하고 있습니다. 합성 가능성에도 문제가 없습니다.

**반드시 수정이 필요한 항목**:
1. **C1**: 연속 전송 시 valid_reg 이중 비차단 대입 문제 → if-else 우선순위 재정렬
2. **C2**: baud_div=0 방어 코드 추가 (테스트벤치에서 baud_div=2 사용 전 초기화 경로)
3. **C3**: AHB 태스크 타이밍 수정 (HREADY 확인 순서)

**권장 수정 항목**:
- M1: TX 전송 시작 baud_tick 동기화 (UART 정확도)
- M4: gpio_irq 글리치 방지 레지스터화
- N4: UART 루프백 수신 데이터 검증 추가

수정 후 재검토 없이 편집장 판단으로 진행 가능한 수준으로 평가합니다 (Critical 건수가 프로토콜 동작 오류보다 엣지케이스 중심이므로).
