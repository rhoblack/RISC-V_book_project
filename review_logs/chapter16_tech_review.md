# Ch16 기술 리뷰

리뷰어: 기술 리뷰어 (Technical Reviewer)
리뷰 기준: ARM IHI0033A AHB-Lite 스펙, SystemVerilog IEEE 1800-2017
작성일: 2026-03-13

---

## Critical 이슈 (🔴)

### C1: ahb_master_bridge — M_ADDR 상태에서의 addr_lat 래치 조건 오류 (AHB 프로토콜 위반)

- **위치**: 16.5절, ahb_master_bridge.sv, always_ff 래치 블록 (라인 575~579)
- **문제**:
  ```systemverilog
  if (state == M_ADDR && HREADY) begin
     addr_lat  <= cache_addr;
     write_lat <= cache_write;
     wdata_lat <= cache_wdata;
  end
  ```
  M_ADDR 상태에서 `HREADY=1`이면 다음 클록 엣지에 `state`는 M_DATA로 전이한다.
  그런데 래치 조건이 `state == M_ADDR && HREADY`이므로, HREADY=1인 사이클에 addr_lat가 갱신된다.
  그 다음 사이클(M_DATA)에서 M_WAIT 상태 없이 곧바로 데이터 페이즈에 돌입하는 경우
  `addr_lat`는 해당 전송의 주소를 올바르게 보유하고 있지만, **M_WAIT 상태를 거치는 경우**에는
  M_ADDR → M_WAIT 전이 시점(HREADY=0)에 래치가 갱신되지 않으므로 addr_lat에 이전 전송의 쓰레기 값이 남을 수 있다.

  더 근본적인 문제는 **M_WAIT 상태 진입 조건**이다.
  M_ADDR 상태에서 `HREADY=0`이면 M_WAIT으로 전이하는데,
  이때 래치 조건 `state == M_ADDR && HREADY`가 False이므로 addr_lat가 *갱신되지 않는다.*
  초기 리셋 후 첫 전송이라면 addr_lat = 0이므로 M_WAIT에서 `HADDR = addr_lat = 0`이 구동된다.
  **이는 실제 요청 주소가 아닌 0을 버스에 올리는 AHB 프로토콜 위반이다.**

  올바른 래치 시점은 **M_ADDR 진입 직전**, 즉 M_IDLE → M_ADDR 전이가 결정되는 사이클,
  다시 말해 `state == M_IDLE && cache_req` 조건이어야 한다.
  또는 M_ADDR 상태에 진입하는 첫 번째 상승 엣지에서 무조건 래치해야 한다
  (`state == M_ADDR` 조건만으로, HREADY 무관하게).

- **수정안**:
  ```systemverilog
  // 수정: M_IDLE → M_ADDR 전이 결정 사이클에 래치 (HREADY 조건 제거)
  if (state == M_IDLE && cache_req) begin
     addr_lat  <= cache_addr;
     write_lat <= cache_write;
     wdata_lat <= cache_wdata;
  end
  ```
  이렇게 하면 M_ADDR 상태에 진입하기 직전(M_IDLE 마지막 사이클)에 래치되므로,
  M_ADDR에서 HREADY=0이 되어 M_WAIT으로 전이되더라도 addr_lat/write_lat/wdata_lat가
  올바른 값을 보유하게 된다.

---

### C2: ahb_master_bridge — HWDATA가 M_ADDR 상태에서 0으로 구동됨 (Write 전송 타이밍 오류)

- **위치**: 16.5절, ahb_master_bridge.sv, M_ADDR 출력 로직 (라인 642~647)
- **문제**:
  M_ADDR 상태의 출력 로직에서 HWDATA가 기본값(32'h0)으로 구동된다.
  이것 자체는 AHB-Lite에서 HWDATA는 데이터 페이즈에서 유효해야 하므로 의도적이다.
  **그러나 M_ADDR → M_DATA 직행(HREADY=1) 경로에서 문제가 발생한다.**

  M_ADDR에서 HREADY=1이면 다음 사이클은 M_DATA이다. M_DATA 출력 로직:
  ```systemverilog
  M_DATA: begin
     HTRANS = HTRANS_IDLE;
     HWDATA = wdata_lat;   // Write 시 데이터 구동
  end
  ```
  C1에서 지적한 것처럼, M_ADDR 진입 시 HREADY=1이면 래치 조건 `state == M_ADDR && HREADY`가
  참이 되어 wdata_lat가 갱신되므로 이 경로는 정상 동작한다.

  **그러나 M_ADDR에서 HREADY=0 → M_WAIT → HREADY=1 → M_DATA 경로에서:**
  C1 수정 없이는 wdata_lat = 0(리셋 초기값)이 M_DATA의 HWDATA에 구동된다.
  슬레이브는 HREADY=1인 M_DATA 사이클에서 HWDATA를 캡처하므로 **0이 메모리에 기록**된다.

  C1을 수정하면 이 이슈는 자동으로 해소된다. 단, 이 이슈의 독립적 중요성을 명시한다.

- **수정안**: C1의 수정안 적용으로 해소됨.

---

### C3: ahb_sram_slave — Wait State FSM에서 S_DONE 상태의 HREADY_out 동작이 AHB 슬레이브 HREADY 프로토콜과 불일치

- **위치**: 16.6절, ahb_sram_slave.sv, Wait State FSM 및 HREADY_out 생성 (라인 784~795)
- **문제**:
  현재 `HREADY_out = (wstate != S_WAIT)` 이므로:
  - S_IDLE: HREADY_out = 1
  - S_WAIT: HREADY_out = 0
  - S_DONE: HREADY_out = 1

  S_DONE에서 HREADY_out=1이 되면 **그 사이클에 다음 전송의 주소가 유효하게 간주**된다.
  그런데 S_DONE의 next_wstate = S_IDLE이고, S_IDLE에서는
  `next_wstate = (valid_transfer && WAIT_CYCLES > 0) ? S_WAIT : S_IDLE`이다.

  **핵심 문제**: S_DONE → S_IDLE 전이 사이클(HREADY_out=1)에서 마스터가 다음 NONSEQ를 구동하면,
  valid_transfer가 참이 되어 S_WAIT으로 진입한다. 이때 실제 Write 데이터(HWDATA)를 캡처해야 하는
  `sel_lat && write_lat && HREADY_out` 조건의 쓰기 동작이 **S_DONE 사이클(HREADY_out=1)에 트리거**된다.
  이는 이전 전송의 HWDATA가 이미 지나간 상태이거나, 새 전송의 HWDATA가 아직 미도착 상태일 수 있다.

  ARM AHB Slave 설계 가이드에 따르면, 슬레이브가 처리를 완료하고 HREADY_out=1을 올리는 사이클이
  데이터 페이즈 완료 사이클이어야 한다. S_DONE이 별도로 존재하여 1사이클을 추가 소비하는 구조는
  Wait State 수가 실제로 `WAIT_CYCLES + 1`이 됨을 의미한다.
  교재에서 "WAIT_CYCLES=1이면 1사이클 Wait"이라고 설명하지만,
  실제 동작은 S_WAIT 1사이클 + S_DONE 1사이클 = **총 2사이클 지연**이 발생한다.
  (S_IDLE에서 valid_transfer 감지 → S_WAIT 1사이클 → S_DONE 1사이클 → S_IDLE 복귀)

  이는 교재 설명과 실제 회로 동작의 불일치이며, 학습자가 시뮬레이션 결과를 이해할 때 혼란을 야기한다.

- **수정안**:
  S_DONE 상태를 제거하고 S_WAIT 마지막 사이클에서 HREADY_out=1을 구동하도록 단순화:
  ```systemverilog
  assign HREADY_out = !((wstate == S_IDLE && valid_transfer && WAIT_CYCLES > 0) ||
                         (wstate == S_WAIT && wait_cnt < WAIT_CYCLES - 1));
  ```
  또는 교재 설명을 "WAIT_CYCLES=1이면 2사이클 지연(1사이클 Wait + 1사이클 Done)"으로 수정하고
  WAIT_CYCLES 파라미터의 의미를 재정의.

---

### C4: ahb_sram_slave — 쓰기 동작 always_ff에 HRESETn 없음 (합성 경고 및 X-propagation 위험)

- **위치**: 16.6절, ahb_sram_slave.sv, 쓰기 동작 (라인 801~805)
- **문제**:
  ```systemverilog
  always_ff @(posedge HCLK) begin
     if (sel_lat && write_lat && HREADY_out) begin
        mem[addr_lat[($clog2(MEM_DEPTH)-1):0]] <= HWDATA;
     end
  end
  ```
  메모리 배열 `mem`에 대한 리셋이 없다. Vivado에서 합성 시 BRAM으로 추론될 경우
  초기화 없는 BRAM은 X 상태에서 시작하므로, 최초 읽기 전에 쓰기가 수행되지 않으면
  시뮬레이션에서 X를 반환한다. 이는 테스트벤치 시나리오 3(IMEM Read)에서
  `mem`이 초기화되지 않아 `read_data = X`가 될 수 있음을 의미한다.

  또한 `always_ff` 키워드는 순차 블록을 의미하므로, 리셋 없는 `always_ff`는
  IEEE 1800-2017 린트 도구에서 경고를 발생시키고, Vivado는 이를 inferred latch 또는
  flip-flop without reset으로 처리하여 타이밍 분석에 영향을 줄 수 있다.

- **수정안**:
  ```systemverilog
  // 방법 1: initial 블록으로 시뮬레이션 초기화 (합성 무시)
  initial begin
     for (int i = 0; i < MEM_DEPTH; i++) mem[i] = 32'h0;
  end

  // 방법 2: always_ff에 reset 조건 추가 (합성 시 레지스터 배열로 추론)
  always_ff @(posedge HCLK or negedge HRESETn) begin
     if (!HRESETn) begin
        // BRAM 추론 시 이 블록은 합성 도구가 무시할 수 있음 — 주석으로 명시
     end else if (sel_lat && write_lat && HREADY_out) begin
        mem[addr_lat[($clog2(MEM_DEPTH)-1):0]] <= HWDATA;
     end
  end
  ```
  Basys 3(Artix-7) BRAM 초기화는 `$readmemh`로 처리하는 것이 권장사항임을 본문에 추가.

---

## Major 이슈 (🟡)

### M1: ahb_master_bridge — M_DATA 상태에서 HREADY 미확인 후 M_DONE 진입 (단일 Wait 가정)

- **위치**: 16.5절, ahb_master_bridge.sv, 다음 상태 로직 (라인 615~618)
- **문제**:
  ```systemverilog
  M_DATA: begin
     next_state = M_DONE;
  end
  ```
  M_DATA 상태에서 HREADY 확인 없이 무조건 M_DONE으로 전이한다.
  AHB-Lite 스펙에 따르면, 데이터 페이즈에서도 슬레이브가 HREADY=0을 구동하여
  추가 Wait State를 요청할 수 있다. 이 경우 마스터는 HWDATA를 유지해야 하며
  M_DATA 상태를 유지해야 한다.

  현재 구현은 슬레이브가 항상 WAIT_CYCLES 사이클 만에 응답한다는 가정 하에만 동작한다.
  (실제 Ch16 예제의 슬레이브는 Wait FSM이 정해진 사이클만 대기하므로 현재 테스트벤치에서는
  문제가 드러나지 않지만, 다른 슬레이브와 연동 시 프로토콜 위반이 발생한다.)

  교재 대상인 파이프라인 캐시 미스 처리에서는 슬레이브(SRAM)가 복수 사이클 Wait을
  요구할 수 있으므로, 이 가정은 실습 확장 시 오류를 야기한다.

- **수정안**:
  ```systemverilog
  M_DATA: begin
     if (HREADY)
        next_state = M_DONE;
     // HREADY=0이면 M_DATA 유지 (HWDATA 동결)
  end
  ```
  M_DATA 출력 로직에서도 HREADY=0 동안 HWDATA = wdata_lat 유지 조건은
  현재 코드에서 이미 처리되고 있으므로 출력 로직은 수정 불필요.

---

### M2: ahb_interconnect — HREADY MUX에서 이전 슬레이브의 전송 완료 여부 미처리 (데이터 페이즈 HREADY 누락)

- **위치**: 16.7절, ahb_interconnect.sv, HREADY MUX (라인 929~936)
- **문제**:
  ```systemverilog
  always_comb begin
     if      (HSEL_imem && HTRANS[1]) HREADY = HREADY_imem;
     else if (HSEL_dmem && HTRANS[1]) HREADY = HREADY_dmem;
     else if (HSEL_apb  && HTRANS[1]) HREADY = HREADY_apb;
     else                              HREADY = 1'b1;
  end
  ```
  이 MUX는 **현재 주소 페이즈의 HSEL**을 기준으로 HREADY를 선택한다.
  그러나 AHB의 파이프라인 구조에서 데이터 페이즈(T2)의 HREADY는
  **T1에서 선택된 슬레이브**(HSEL_d 기준)의 HREADY_out이어야 한다.

  예를 들어, T1에서 IMEM이 선택되고(HSEL_imem=1), T2에서 DMEM이 선택되면(HSEL_dmem=1),
  T2의 HREADY는 T1의 전송을 처리 중인 IMEM의 HREADY_out이어야 하는데,
  현재 구현은 DMEM의 HREADY를 반환한다.

  **단, 이 설계는 단일 전송(NONSEQ-IDLE 패턴)만 사용하는 현재 예제에서는 문제가 없다.**
  마스터가 M_DONE → M_IDLE → M_ADDR 순서로 전이하므로,
  데이터 페이즈(M_DATA)에서 HTRANS=IDLE이 구동되어 HSEL_xxx가 모두 0이 되고
  HREADY=1(기본값)이 반환된다. 현재 예제에서는 기능적으로 동작하지만,
  연속 전송(back-to-back transfer) 시나리오에서는 오동작한다.

  교재 설명(16.7절 본문)에서 이 제한사항을 명시하지 않으면 독자가 이 인터커넥트를
  범용으로 사용하려 할 때 오류를 유발한다.

- **수정안**: 코드 수정보다는 본문에 다음 주석 추가 권장:
  ```
  // 주의: 이 HREADY MUX는 단일 전송(NONSEQ→IDLE) 패턴에만 올바르게 동작합니다.
  // 연속 전송(back-to-back NONSEQ) 또는 버스트 전송 시에는
  // hsel_imem_d/hsel_dmem_d/hsel_apb_d 기반의 HREADY MUX로 변경해야 합니다.
  ```

---

### M3: ahb_master_bridge — M_WAIT 상태에서 HBURST 신호 누락 (HREADY=0 동결 불완전)

- **위치**: 16.5절, ahb_master_bridge.sv, M_WAIT 출력 로직 (라인 648~655)
- **문제**:
  16.4절 표("HREADY=0 시 각 신호의 마스터 의무")에서 HBURST를 포함한 모든 신호를
  동결해야 한다고 명시하였다. 그러나 M_WAIT 상태의 출력 로직에서
  HBURST는 기본값(3'b000, SINGLE)으로만 구동되며,
  래치된 값을 사용하지 않는다.

  현재 예제에서는 항상 SINGLE(3'b000) 전송만 사용하므로 동작상 문제는 없지만,
  교재가 프로토콜 설명에서 HBURST 동결을 강조하고 있음에도 코드에서 이를 누락한 것은
  교육적 일관성을 해친다. 향후 버스트 전송(연습문제 4번) 구현 시 오류가 발생할 수 있다.

- **수정안**:
  ```systemverilog
  // M_ADDR 래치에 hburst_lat 추가
  logic [2:0] hburst_lat;
  // M_IDLE에서 래치 (C1 수정 기준):
  if (state == M_IDLE && cache_req) begin
     ...
     hburst_lat <= cache_burst_type; // 또는 현재 예제에서는 3'b000 고정
  end

  // M_WAIT 출력에서:
  M_WAIT: begin
     HADDR  = addr_lat;
     HTRANS = HTRANS_NONSEQ;
     HWRITE = write_lat;
     HWDATA = wdata_lat;
     HBURST = hburst_lat;   // 추가
  end
  ```

---

### M4: ahb_sram_slave — addr_lat 비트폭 오류 (32비트 전체 저장 후 인덱싱)

- **위치**: 16.6절, ahb_sram_slave.sv, addr_lat 선언 및 래치 (라인 742, 759)
- **문제**:
  ```systemverilog
  logic [31:0] addr_lat;   // 32비트로 선언
  ...
  addr_lat <= HADDR[31:2]; // 30비트 값을 32비트에 저장 (상위 2비트 = 0)
  ```
  `HADDR[31:2]`는 30비트이므로 32비트 addr_lat에 저장 시 상위 2비트가 0으로 패딩된다.
  이후 인덱싱에서 `addr_lat[($clog2(MEM_DEPTH)-1):0]`를 사용하는데,
  MEM_DEPTH=256이면 `addr_lat[7:0]`이 선택된다.
  `HADDR[31:2]`의 비트 0~7이 원래 HADDR의 비트 2~9에 해당하므로,
  0x0001_0000 접근 시 `addr_lat = 0x0004_0000 >> 2 = 0x0001_0000`가 아니라
  `addr_lat = HADDR[31:2] = 32'h0000_4000`이 저장된다.
  이를 인덱싱하면 `addr_lat[7:0] = 8'h00`이 되어 주소 0으로 접근한다.

  다음 주소를 예로 들면:
  - HADDR=0x0001_0000 → HADDR[31:2]=30'h00_04000 → addr_lat=32'h00_04000 → addr_lat[7:0]=8'h00 ✓
  - HADDR=0x0001_0004 → HADDR[31:2]=30'h00_04001 → addr_lat=32'h00_04001 → addr_lat[7:0]=8'h01 ✓
  - HADDR=0x0001_03FC → HADDR[31:2]=30'h00_040FF → addr_lat=32'h00_040FF → addr_lat[7:0]=8'hFF ✓

  위 계산으로는 현재 구현이 올바르게 동작하는 것처럼 보이지만,
  **addr_lat의 선언 의미가 불명확하다.** "워드 주소를 저장한다"고 주석에 명시되어 있으나
  실제로는 "바이트 주소의 하위 2비트를 제거한 값(= 워드 주소)"이 32비트 변수에 저장된다.
  혼란 방지를 위해 addr_lat을 워드 주소 비트폭으로 선언하거나,
  HADDR 전체를 저장하고 인덱싱 시 [31:2]를 사용하도록 변경해야 한다.

- **수정안 (방법 1 — 명확한 비트폭)**:
  ```systemverilog
  logic [$clog2(MEM_DEPTH)-1:0] addr_lat;  // 워드 인덱스만 저장
  ...
  addr_lat <= HADDR[$clog2(MEM_DEPTH)+1:2]; // 워드 인덱스 비트만 추출
  ...
  mem[addr_lat] <= HWDATA;      // 인덱싱 단순화
  assign HRDATA = mem[addr_lat];
  ```

---

### M5: SVA 어서션 p_addr_stable_on_wait — 선행 조건 오류 (현재 사이클 HREADY 사용)

- **위치**: 16.8절, ahb_tb.sv, SVA 1번 (라인 1152~1157)
- **문제**:
  ```systemverilog
  property p_addr_stable_on_wait;
     @(posedge HCLK) disable iff (!HRESETn)
     (HTRANS[1] && !HREADY) |=> $stable(HADDR);
  endproperty
  ```
  `|=>` 연산자는 "선행 조건이 참인 사이클 다음 사이클에 후행 조건이 참이어야 한다"는 의미다.
  이 어서션은 "현재 사이클에 HTRANS[1]=1이고 HREADY=0이면, 다음 사이클에 HADDR이 안정적이어야 한다"를 의미한다.

  그러나 AHB 스펙의 요구사항은 "HREADY=0인 동안(현재 사이클) HADDR을 변경하면 안 된다"이다.
  즉, **현재 사이클에서 HADDR이 이미 안정적이어야** 하는 것이지,
  다음 사이클에서 안정적이면 되는 것이 아니다.

  올바른 어서션은 `|->` (overlapping implication) 또는
  현재 사이클 대비 값 변화를 검사하는 `$changed` 사용이 적합하다.

- **수정안**:
  ```systemverilog
  // 방법 1: 현재 사이클 내 안정성 검사
  property p_addr_stable_on_wait;
     @(posedge HCLK) disable iff (!HRESETn)
     (HTRANS[1] && !HREADY) |-> $stable(HADDR);
  endproperty

  // 방법 2: Wait State 진입 후 다음 사이클 동결 검사 (더 엄밀)
  property p_addr_stable_on_wait;
     @(posedge HCLK) disable iff (!HRESETn)
     (HTRANS[1] && !HREADY) |=> ($stable(HADDR) && $stable(HTRANS));
  endproperty
  ```
  SVA 2번(p_htrans_stable_on_wait)도 동일한 문제를 가지고 있으므로 함께 수정 필요.

---

### M6: 16.3절 타이밍 다이어그램 참조 오류 — SVG 파일명과 figcaption 불일치

- **위치**: 16.3절, figure 태그 (라인 332~334)
- **문제**:
  ```html
  <img src="../../figures/ch16_sec04_ahb_timing.svg" ...>
  <figcaption>그림 16-3: ...</figcaption>
  ```
  16.3절에 위치한 그림의 SVG 파일명이 `ch16_sec04_ahb_timing.svg`이다.
  파일명의 `sec04`는 16.4절을 의미하지만, 이 그림은 16.3절에 배치되어 있다.
  CLAUDE.md의 네이밍 규칙(`chNN_secNN_설명`)에 따르면 `ch16_sec03_ahb_timing.svg`이어야 한다.
  SVG 파일이 실제로 `sec04` 경로에 있다면 문제없지만, 16.3절 내용과의 대응이 혼란스럽다.

- **수정안**: SVG 파일명을 `ch16_sec03_ahb_timing.svg`로 변경하거나,
  현재 파일명을 유지한다면 해당 그림을 16.4절로 이동하여 Wait State 설명과 함께 배치한다.

---

## Minor 이슈 (🟢)

### N1: HBURST 인코딩 표에서 INCR(3'b001) 누락

- **위치**: 16.2절 본문 (라인 215)
- **문제**:
  "3'b000=SINGLE, 3'b011=INCR4, 3'b101=INCR8 등"으로 열거되어 있으나
  INCR(undefined length increment burst, 3'b001)이 누락되어 있다.
  ARM IHI0033A 표 3-2에 INCR=3'b001이 명시되어 있으며,
  연습문제 4번(버스트 전송 구현)에서 학습자가 INCR을 사용할 가능성이 있다.

- **수정안**: "3'b000=SINGLE, 3'b001=INCR, 3'b011=INCR4, 3'b101=INCR8"로 수정.

---

### N2: 학습 목표 신호 수 불일치 (11개 vs 실제 9개 독립 신호)

- **위치**: 학습 목표 섹션 (라인 30)
- **문제**:
  "11개 핵심 신호(HCLK, HRESETn, HADDR, HTRANS, HSIZE, HBURST, HWRITE, HWDATA, HRDATA, HREADY, HRESP)"
  라고 명시되어 있으나, 실제로 나열된 신호는 정확히 11개가 맞다.
  문제는 16.9절 요약 표에서 "HCLK, HRESETn"을 "주소/제어 그룹"에 포함시키는데,
  일반적으로 HCLK/HRESETn은 버스 신호가 아닌 시스템 신호로 분류한다.
  ARM IHI0033A에서는 이 둘을 "Global Signals"로 별도 분류한다.
  교재 설명과 ARM 스펙의 분류가 미묘하게 다르지만 기능 설명은 정확하다.
  단, 학습자가 ARM 스펙 원문을 참조할 때 혼란이 생길 수 있다.

- **수정안**: 16.9절 요약 표의 분류를 "주소/제어(A그룹): HADDR, HTRANS, HSIZE, HBURST, HWRITE / 시스템(S): HCLK, HRESETn"으로 구분하거나, 주석으로 분류 기준의 차이를 명시.

---

### N3: ahb_sram_slave — `wire` 키워드 사용 (SystemVerilog 스타일 비권장)

- **위치**: 16.6절, ahb_sram_slave.sv (라인 749)
- **문제**:
  ```systemverilog
  wire valid_transfer = HSEL && HTRANS[1] && HREADY_in;
  ```
  SystemVerilog IEEE 1800-2017에서는 `wire` 대신 `logic`을 사용하는 것이 권장된다.
  교재 전체(Ch09~Ch15)에서 `logic`을 일관되게 사용했으나 이 줄만 `wire`를 사용하고 있다.

- **수정안**: `logic valid_transfer = HSEL && HTRANS[1] && HREADY_in;`

---

### N4: ahb_master_bridge — M_DONE 상태의 HTRANS 구동 불필요

- **위치**: 16.5절, ahb_master_bridge.sv, M_DONE 출력 로직 (라인 662~665)
- **문제**:
  ```systemverilog
  M_DONE: begin
     cache_ack = 1'b1;
     HTRANS    = HTRANS_IDLE;   // 불필요 — 기본값과 동일
  end
  ```
  `HTRANS = HTRANS_IDLE`은 always_comb 블록의 기본값과 동일하므로 중복이다.
  코드의 명확성을 위해 유지할 수 있으나, 이 패턴이 일관되지 않게 적용되면
  (다른 상태에서는 기본값과 동일한 신호를 명시적으로 쓰지 않음)
  코드 스타일 불일치가 생긴다.

- **수정안**: 제거하거나 모든 상태에서 명시적 구동 스타일을 일관되게 적용.

---

### N5: 16.1절 AHB-Lite 버전 표기 — IHI0033A vs IHI0033B

- **위치**: 16.1절 본문 (라인 90)
- **문제**:
  "ARM IHI0033A 스펙"으로 표기되어 있다. ARM은 이후 IHI0033B를 발행하였으며,
  두 버전 간 AHB-Lite 핵심 신호 정의에는 차이가 없으나,
  스펙 번호를 명시할 때는 최신 버전인 IHI0033B를 참조하거나
  "IHI0033A/B"로 병기하는 것이 더 정확하다.

- **수정안**: "ARM IHI0033A/B 스펙" 또는 "ARM AMBA AHB-Lite 스펙(IHI0033)"으로 표기.

---

## 종합 평가

### 잘된 점
1. HTRANS 인코딩(IDLE=2'b00, BUSY=2'b01, NONSEQ=2'b10, SEQ=2'b11) 정확함
2. HBURST 인코딩(SINGLE=3'b000, INCR4=3'b011, INCR8=3'b101) 정확함
3. HRESETn 액티브 로우 비동기 리셋 처리 올바름 (`always_ff @(posedge HCLK or negedge HRESETn)`)
4. HSEL 디코더 조합 논리, HRDATA MUX 1사이클 지연(HSEL_d), HREADY MUX 구현 원리 정확
5. 슬레이브 주소 래치 조건(HSEL && HTRANS[1] && HREADY_in) 정확하고 교육적으로 잘 설명됨
6. SVA를 `ifdef SIMULATION` 으로 합성 분리 — 프로토콜 준수 ✓
7. HWDATA 1사이클 지연 원리 설명이 명확하고 파이프라인 비유와 잘 연결됨
8. 주소 맵(IMEM: 0x0000_xxxx, DMEM: 0x0001_xxxx, APB: 0xFFFF_xxxx)이 Ch17 예약 영역과 충돌 없음

### 수정 우선순위
- **즉시 수정 필수**: C1, C2 (래치 타이밍 오류 — 잘못된 주소/데이터 전송 가능)
- **수정 권장**: C3 (Wait State 수 불일치), C4 (메모리 초기화)
- **보완 권장**: M1~M5
- **선택 수정**: N1~N5

---

## 승인 조건

- **Critical**: 4개 (C1~C4)
- **Major**: 6개 (M1~M6)
- **Minor**: 5개 (N1~N5)

**현재 상태**: 미승인 (Critical 4건 해소 후 재검토 필요)

**재검토 조건**:
- C1 수정 완료 (addr_lat 래치 타이밍 — M_IDLE 진입 시점으로 이동)
- C2는 C1 수정으로 자동 해소 확인
- C3 수정 또는 교재 설명과 실제 Wait 사이클 수 일치 확인
- C4 수정 (메모리 초기화 추가 또는 초기화 한계 명시)
- M1 수정 (M_DATA에서 HREADY 확인) — 연습문제 4번(버스트) 구현 전 필수
- M5 수정 (SVA |=> → |-> 수정) — 어서션 교육 효과를 위해 중요
