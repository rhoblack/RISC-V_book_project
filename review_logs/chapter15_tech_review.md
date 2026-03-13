# Ch15 기술 리뷰

검토자: 기술 리뷰어 (Technical Reviewer)
검토 일자: 2026-03-12
검토 대상:
- `manuscripts/part5/chapter15.html`
- `code_examples/ch15_mem_controller.sv`
- `code_examples/ch15_cache_system.sv`
- `code_examples/ch15_cache_tb.sv`

---

## 🔴 Critical 이슈

### C1. beat_cnt 카운터가 버스트 완료 직전 사이클에 IDLE로 복귀하며 마지막 beat를 놓칠 가능성

**위치**: `ch15_mem_controller.sv` L108~115, L75~76

**문제**:
```systemverilog
assign burst_done = (beat_cnt == BURST_LEN - 1);  // beat_cnt == 7

always_ff @(posedge clk or negedge rst_n) begin
   ...
   else if (arb_state == ARB_IDLE)
      beat_cnt <= 3'b0;              // IDLE에서 0으로 초기화
   else if (arb_state == ARB_SERVE_D || arb_state == ARB_SERVE_I)
      beat_cnt <= beat_cnt + 1'b1;  // 매 사이클 증가
end
```

`burst_done`이 `beat_cnt == 7`인 순간 `arb_next = ARB_IDLE`로 전이하고, 다음 사이클에 `arb_state == ARB_IDLE`이 되어 `beat_cnt`가 0으로 리셋된다. 이 구조에서 `ARB_SERVE_x` 상태는 `beat_cnt = 0, 1, ... 7`까지 총 **8사이클** 동안 유지된 후 IDLE로 복귀하는 것이 맞다.

그러나 문제는 **ACK 출력 경로**에 있다. `serve_i_q / serve_d_q`는 현재 상태를 1사이클 지연 래치하므로:
- 사이클 T0: `arb_state = ARB_SERVE_I`, `beat_cnt = 0` → BRAM 읽기 주소 = base+0
- 사이클 T1: `serve_i_q = 1`(ACK 유효), `mem_rdata_reg` = base+0 데이터, `beat_cnt = 1`
- ...
- 사이클 T7: `arb_state = ARB_SERVE_I`, `beat_cnt = 7`, `burst_done = 1`, `arb_next = ARB_IDLE`
- 사이클 T8: `arb_state = ARB_IDLE`, `beat_cnt = 0` (리셋), `serve_i_q = 0` (ACK 종료)

이 경우 BRAM에서 beat_cnt = 7에 해당하는 주소(base+7)를 읽는 클록 엣지(T7)에서 동기 읽기가 시작되고, T8에서 `mem_rdata_reg`에 데이터가 들어온다. 그런데 T8에서는 이미 `serve_i_q = 0`(IDLE 진입)이므로 **beat_cnt=7에 해당하는 마지막 데이터가 ACK 없이 사라진다.**

결과: **캐시에 8번째 워드(인덱스 7)가 채워지지 않아 캐시 라인이 불완전하게 적재된다.**

**수정 방향**: `burst_done` 조건을 `(beat_cnt == BURST_LEN - 1)` 에서 ACK 지연을 고려하여 조정하거나, BRAM 읽기를 비동기(조합 논리) 방식으로 변경하거나, `ARB_SERVE` 상태를 9사이클(beat_cnt 0~7 + 1사이클 데이터 배출) 유지해야 한다.

---

### C2. D-Cache `mem_wdata_o` 조합 경로에 BRAM 비동기 읽기 의존 — 합성 불가

**위치**: `ch15_cache_system.sv` L516~517

```systemverilog
assign mem_wdata_o = data_array[latched_replace_way]
                               [{addr_index, word_cnt}];
```

`data_array`는 `(* ram_style = "block" *)` 어트리뷰트가 적용된 BRAM이다(L414~415). Xilinx BRAM은 **동기 읽기만 지원**하며, 조합 논리(assign)로 읽을 경우 Vivado는 BRAM 대신 LUTRAM으로 강제 추론한다. Basys 3(Artix-7)에서 LUTRAM으로 추론되면 LUT 리소스가 과도하게 소비된다(128세트 × 8워드 × 32비트 = 32768비트 = 256 LUT6 이상).

**수정 방향**: Write-Back 데이터를 출력하려면 BRAM 읽기에 1사이클 등록(registered read)이 필요하며, WRITE_BACK 상태 진입 전 사이클에 미리 읽기를 시작하는 파이프라인 구조가 필요하다.

---

### C3. I-Cache `beat_cnt` 초기화 타이밍 — DONE 상태에서 초기화되면 FILL→DONE 전이 시 마지막 beat 카운트 정합성 문제

**위치**: `ch15_cache_system.sv` L301~304

```systemverilog
if (state == S_IDLE || state == S_DONE)
   beat_cnt <= '0;
else if (state == S_FILL && mem_ack_i)
   beat_cnt <= beat_cnt + 1'b1;
```

FILL 상태에서 `beat_cnt == 7`이고 `mem_ack_i == 1`이면 `next_state = S_DONE`으로 전이하는 동시에 `beat_cnt <= 8`(= 3'b000 오버플로우)이 된다. 다음 사이클 S_DONE에서 `beat_cnt <= '0`으로 다시 초기화되므로 최종 값 자체는 문제없지만, FILL 마지막 beat에서 beat_cnt가 `3'b111 → 3'b000` 오버플로우 후 즉시 리셋되는 불명확한 동작이 발생한다.

더 중요한 문제: `state == S_FILL && mem_ack_i && beat_cnt == 3'd7`일 때 `next_state = S_DONE`으로 전이하지만, **동일 클록 엣지**에서 `data_array` 쓰기(L336~342)와 `tag_array/valid_array` 갱신(L338~341)이 함께 일어난다. S_DONE 상태에서는 `icache_stall_o`가 0이 되므로 CPU는 다음 사이클 즉시 캐시를 읽을 수 있다. 이 때 `valid_array`가 DONE 진입 사이클(S_FILL 마지막 beat)에서 이미 1로 갱신되므로 `cache_hit`가 S_DONE에서 1이 된다. 정상 동작 범위이지만 **S_DONE에서 `icache_stall_o = 0`이고 `cache_hit = 1`이 보장되는지 설계 문서에 명시되어야 한다.**

---

### C4. 원고 내 코드 발췌와 실제 코드 파일 사이의 `burst_done` 정의 불일치

**위치**: `chapter15.html` L276 (원고 설명) vs `ch15_mem_controller.sv` L75 (실제 코드)

원고에서는:
```
assign burst_done = (beat_cnt == BURST_LEN - 1); // BURST_LEN=8
```

실제 코드에서도 동일하게 작성되어 있으나, **원고 본문 버스트 카운터 설명**에서:
> "beat_cnt == 7이 되면 버스트가 완료됩니다"

라고 기술하며, 미스 페널티 테이블(L338~349)에서:
> "1 MISS + 1 WAIT_GRANT + 8 FILL + 1 DONE = 11사이클"

이라고 명시한다. C1에서 지적한 바와 같이 BRAM 1사이클 지연 때문에 실제 ACK 유효 사이클은 8이 아닌 최대 7이 될 수 있어 **페널티 계산 근거가 코드 구현과 불일치**한다. 교재의 핵심 수치인 "11사이클/19사이클"의 정확성이 훼손된다.

---

## 🟡 Major 이슈

### M1. ARB_SERVE 상태에서 req 신호가 유지되지 않아도 버스트가 지속되는 설계 의도 불명확

**위치**: `ch15_mem_controller.sv` L95~105

중재기가 `ARB_SERVE_D` 또는 `ARB_SERVE_I` 상태에 진입한 이후에는 `dcache_req_i` / `icache_req_i` 신호와 무관하게 `beat_cnt`가 증가하며 버스트가 지속된다. 이는 버스트 무결성(burst integrity) 보장 측면에서는 올바른 설계이나, **캐시 FSM이 WAIT_GRANT → FILL 전이 후 req 신호를 계속 유지해야 하는지 여부**가 코드와 원고 모두에서 명확히 기술되지 않았다.

`ch15_cache_system.sv` L330의 I-Cache에서:
```systemverilog
assign mem_req_o = (state == S_MISS) || (state == S_WAIT_GRANT);
```

`S_FILL` 상태에서 `mem_req_o = 0`이다. 따라서 중재기가 `ARB_SERVE_I`로 전이한 직후에는 `icache_req_i = 0`이 된다. 이 상태에서도 중재기는 `burst_done`까지 버스트를 계속하므로 기능상 문제는 없지만, 원고의 신호 표에서 "버스트 중 req 신호 유지 여부"를 명시해야 한다.

---

### M2. 중재기 버스트 완료 후 ARB_IDLE 복귀 — 동시 대기 중인 icache_req에 대한 grant 발생 타이밍 1사이클 지연

**위치**: `ch15_mem_controller.sv` L86~105, L119~120

D-Cache 버스트 완료(T_done) 사이클에서:
- T_done: `arb_state = ARB_SERVE_D`, `burst_done = 1`, `arb_next = ARB_IDLE`
- T_done+1: `arb_state = ARB_IDLE`, `icache_req_i = 1`이면 `arb_next = ARB_SERVE_I`
- T_done+1: `icache_grant_o = 1` (ARB_IDLE && icache_req_i && !dcache_req_i)

그런데 I-Cache FSM의 `S_WAIT_GRANT`에서 `mem_grant_i = 1`을 수신하면 `next_state = S_FILL`로 전이, 다음 사이클에서 `state = S_FILL`. 동시에 T_done+1에서 `arb_state = ARB_IDLE`이고 `arb_next = ARB_SERVE_I`이므로, T_done+2에 `arb_state = ARB_SERVE_I`가 된다. 이 때 I-Cache는 이미 S_FILL 상태이고, 중재기는 ARB_SERVE_I 상태이므로 동기가 1사이클 어긋난다.

`icache_base_addr` 래치는 `icache_grant_o` 시점에 갱신되므로(L133~135), T_done+1에서 `icache_base_addr`가 래치된다. T_done+2부터 중재기가 BRAM 주소 생성을 시작하므로 beat_cnt = 0의 BRAM 읽기는 T_done+2에 시작되고 T_done+3에 `mem_rdata_reg`가 유효해진다. I-Cache FSM은 T_done+2부터 S_FILL이고 `mem_ack_i` = T_done+3부터 유효하다. 이 관계가 성립하는지는 `serve_i_q` 지연과 맞물려 검증이 필요하다.

**권장**: 타이밍 다이어그램(그림 15.2)에 D-Cache 종료 후 I-Cache 서비스 시작 구간을 추가하여 독자가 핸드오버 타이밍을 시각적으로 확인할 수 있도록 해야 한다.

---

### M3. D-Cache `latched_wb_addr` 계산에서 Tag 비트 폭 불일치 위험

**위치**: `ch15_cache_system.sv` L469

```systemverilog
latched_wb_addr <= {tag_array[replace_way_sel][addr_index], addr_index, 5'b0};
```

이 연결의 비트 폭:
- `tag_array[replace_way_sel][addr_index]` = `TAG_W` = 21비트
- `addr_index` = `INDEX_W` = 6비트
- `5'b0` = 5비트
- 합계 = 32비트 ✓ (ADDR_WIDTH = 32)

D-Cache 파라미터: `Tag[31:11] = 21비트, Index[10:5] = 6비트, Offset[4:0] = 5비트`

이 계산은 정확하다. 단, **원고 15.1절 본문에서 ch14의 D-Cache 파라미터를 "Tag[31:11]=21비트, Index[10:5]=6비트"라고 명시하지 않고 "Ch14 설계 참조"로 처리**하고 있어, 독자가 코드를 보면서 주소 필드 분해를 자가 검증하기 어렵다. 원고에 D-Cache 주소 필드 분해표를 추가할 것을 권장한다.

---

### M4. 테스트벤치 `thrash_miss`, `opt_miss` 변수를 `$display`에서 사용하지만 `initial` 블록 내 `for` 루프 밖에서 선언 — 일부 시뮬레이터에서 스코프 오류

**위치**: `ch15_cache_tb.sv` L278~279, L306~307, L365

```systemverilog
integer thrash_miss = 0;   // for 루프 내부에서 선언
integer thrash_access = 0;
...
integer opt_miss = 0;
integer opt_hit  = 0;
integer opt_access = 0;
```

SystemVerilog에서 `initial` 블록 내부의 변수 선언은 IEEE 1800-2017 표준상 허용되지만, **VCS는 지원하고 Vivado 시뮬레이터(xsim)는 버전에 따라 블록 내 변수 선언에 제한**이 있다. `$display`의 L365에서:

```systemverilog
$display("  I-Cache 미스 횟수   : %0d회", icache_miss_count + thrash_miss + opt_miss);
```

`thrash_miss`와 `opt_miss`가 `initial` 블록 내 로컬로 선언되어 있으면 이 라인에서 스코프 오류가 발생할 수 있다. 모듈 레벨 변수로 상단에 선언할 것을 권장한다.

---

### M5. 성능 카운터 `instr_cnt`의 정확도 한계 — 원고에서 "완료된 명령어 수"로 오인될 수 있음

**위치**: `ch15_cache_system.sv` L189~194

```systemverilog
always_ff @(posedge clk or negedge rst_n) begin
   if (!rst_n)
      instr_cnt <= '0;
   else if (!pipeline_stall)
      instr_cnt <= instr_cnt + 1'b1;
end
```

이 카운터는 `pipeline_stall = 0`인 사이클마다 증가한다. 그러나 파이프라인에서 실제로 "명령어가 완료(retire)"되는 시점은 WB 스테이지이며, IF 스테이지에서 버블(NOP)이 진행 중이어도 스톨이 없으면 카운트된다. 즉, **분기 플러시로 삽입된 버블(NOP)도 명령어로 계산**되어 실효 CPI가 실제보다 낮게 측정된다.

원고 본문에서 이 한계를 "간단화(Simplification)"로 명시하고 있지 않으므로 독자가 오해할 수 있다. 원고에 "이 카운터는 WB 스테이지 은퇴 카운터가 아니라 파이프라인 진행 사이클 카운터이며, 분기 버블이 포함되어 실제 CPI보다 낮게 표시될 수 있다"는 주의 사항이 필요하다.

---

### M6. `synthesis translate_off/on` 가드 없는 `$readmemh` — 합성 경고 발생

**위치**: `ch15_mem_controller.sv` L56~58

```systemverilog
initial begin
   $readmemh("mem_init.hex", mem);
end
```

Vivado에서 `initial` 블록 내 `$readmemh`는 BRAM 초기화 파일로 인식되어 합성이 가능하나, 합성 도구가 인식하지 못하면 경고(Warning)를 생성한다. 교육용 코드이므로 Critical 수준은 아니지만, Basys 3 실습에서 `mem_init.hex` 파일 경로 지정 방법을 원고에서 안내해야 한다. 현재 원고에는 관련 설명이 없다.

---

## 🟢 Minor 이슈

### m1. `burst_done` 조건의 파라미터 타입 불일치 — lint 경고 가능성

**위치**: `ch15_mem_controller.sv` L75

```systemverilog
assign burst_done = (beat_cnt == BURST_LEN - 1);
```

`BURST_LEN`은 `parameter` (기본값 8, 정수형), `beat_cnt`는 `logic [2:0]`이다. `BURST_LEN - 1 = 7`은 3비트로 표현 가능하나 파라미터 타입이 명시되지 않아 lint 도구에서 부호 비교 경고가 발생할 수 있다. `3'(BURST_LEN - 1)` 또는 `beat_cnt == 3'd7`로 명시적 캐스팅을 권장한다.

---

### m2. I-Cache `flush_i` 처리 — `S_WAIT_GRANT` 상태에서 flush 시 `icache_stall_o` 즉시 해제 확인 필요

**위치**: `ch15_cache_system.sv` L317~318, L327

```systemverilog
S_WAIT_GRANT: if (flush_i)   next_state = S_IDLE;
              else if (mem_grant_i) next_state = S_FILL;
...
assign icache_stall_o = (state == S_MISS) || (state == S_WAIT_GRANT) || (state == S_FILL);
```

`flush_i = 1`이면 `next_state = S_IDLE`이지만, 현재 사이클에서는 여전히 `state == S_WAIT_GRANT`이므로 `icache_stall_o = 1`이다. 다음 사이클 `state == S_IDLE`이 되면 `icache_stall_o = 0`이 된다. 이 1사이클 지연이 분기 플러시 타이밍과 상호작용하는 경우를 원고에서 언급하면 좋다. (기능 오류는 아니므로 Minor)

---

### m3. `ch15_cache_system.sv`에서 `flush_i = 1'b0` 고정 처리

**위치**: `ch15_cache_system.sv` L101

```systemverilog
.flush_i      (1'b0),           // 분기 플러시 (간단화)
```

Ch11에서 설계한 분기 플러시 신호가 연결되지 않아 FENCE.I 동작이 Ch14 설계 의도(valid bit 전체 리셋)와 단절되어 있다. 교육 목적 단순화이므로 Critical은 아니나, 원고에 "실제 구현에서는 파이프라인의 분기 플러시 신호를 연결해야 한다"는 설명이 필요하다.

---

### m4. 원고 15.1절 스톨 신호 발췌 코드 내 상태명 불일치

**위치**: `chapter15.html` L165

원고 발췌:
```systemverilog
(state == S_WAIT_REFILL_GNT)  ||
```

실제 코드(`ch15_cache_system.sv` L503):
```systemverilog
(state == S_WAIT_REFILL_GNT)  ||
```

일치하나, 원고 15.3절(L162~163)의 주석에서 상태 이름을 `S_WAIT_REFILL_GNT`로 표기하고 있는 반면 D-Cache FSM 선언부(ch15_cache_system.sv L446)에서도 동일하게 `S_WAIT_REFILL_GNT`를 사용한다. 다만 원고 15.1절 본문(L135~136)에서는 `WAIT_REFILL_GRANT`로 기술하여 상태명 표기가 혼용된다. 독자에게 혼란을 줄 수 있으므로 통일이 필요하다.

---

### m5. 테스트벤치 클록 생성 — 정수 나눗셈 정밀도 문제

**위치**: `ch15_cache_tb.sv` L78

```systemverilog
localparam CLK_PERIOD = 15;
always #(CLK_PERIOD/2) clk = ~clk;
```

`CLK_PERIOD/2 = 7`(정수 나눗셈 절사)이 되어 실제 클록 주기가 14ns(71.4MHz)가 된다. 65MHz를 목표로 한다면 `CLK_PERIOD = 16` 또는 `#7.5` 실수 지연을 사용해야 한다. 기능 시뮬레이션에는 영향이 없으나 타이밍 시뮬레이션에서 부정확하다.

---

### m6. `ch15_cache_tb.sv` 내 `burst_read_icache` 태스크의 WAIT_GRANT 구현 — 실제 FSM과 불일치

**위치**: `ch15_cache_tb.sv` L106~112

```systemverilog
@(posedge clk);      // WAIT_GRANT 사이클
cyc++;
while (!icache_grant) begin
   @(posedge clk);
   cyc++;
end
```

이 구현은 WAIT_GRANT를 최소 1사이클로 처리한다. 그러나 실제 `icache_grant_o`는 `(arb_state == ARB_IDLE) && icache_req_i && !dcache_req_i`로 조합 논리로 생성되므로, ARB_IDLE 상태에 진입한 사이클과 동일 사이클에 grant가 발생한다. 테스트벤치에서 icache_req를 어서트하고 다음 클록 엣지를 기다리는 사이에 grant가 이미 발생했을 수 있어 `while (!icache_grant)` 루프가 오동작할 수 있다. 비동기 신호 샘플링 타이밍을 `@(posedge clk)` 직후로 정확히 맞출 것을 권장한다.

---

## ✅ 통과 항목

### P1. BRAM 어트리뷰트 적용 확인

`ch15_mem_controller.sv` L52: `(* ram_style = "block" *)` 어트리뷰트가 Main SRAM에 정확히 적용되어 있다. Vivado에서 Block RAM으로 올바르게 추론된다.

`ch15_cache_system.sv` L267, L414: I-Cache와 D-Cache의 데이터 배열에도 `(* ram_style = "block" *)` 어트리뷰트가 적용되어 있다.

### P2. 중재기 FSM D-Cache 우선 로직

`ch15_mem_controller.sv` L89~93: `dcache_req_i`를 먼저 확인하고 `icache_req_i`를 후순위로 처리하는 고정 우선순위 로직이 정확히 구현되어 있다.

### P3. D-Cache FSM 상태 전이 — Dirty Miss vs Clean Miss 분기

`ch15_cache_system.sv` L484~488: `replace_dirty` 조건에 따라 `S_WAIT_WB_GRANT`와 `S_WAIT_REFILL_GNT`로 올바르게 분기한다.

### P4. D-Cache 주소 필드 분해 — Ch14 연속성 확인

`ch15_cache_system.sv` L393~403: `Tag[31:11]=21비트, Index[10:5]=6비트, Offset[4:2]=3비트`로 Ch14 설계와 일치한다.

### P5. I-Cache 주소 필드 분해 — Ch13 연속성 확인

`ch15_cache_system.sv` L251~260: `Tag[31:12]=20비트, Index[11:5]=7비트, Offset[4:2]=3비트`로 Ch13 설계와 일치한다.

### P6. D-Cache `latched_replace_way` 래치 패턴

`ch15_cache_system.sv` L467~471: TAG_CHECK 상태에서 교체 Way와 Write-Back 주소를 래치하여 WRITE_BACK/REFILL 상태에서 일관된 Way를 사용한다. Ch14의 핵심 설계 원칙이 올바르게 유지되어 있다.

### P7. Byte Enable 적용

`ch15_cache_system.sv` L544~549: `cpu_be_i`(funct3 기반, SW=4'b1111, SH=4'b0011, SB=4'b0001) 기반 바이트 단위 쓰기가 올바르게 구현되어 있다.

### P8. `pipeline_stall` 연결

`ch15_cache_system.sv` L48: `pipeline_stall = load_use_stall || icache_stall || dcache_stall`이 CLAUDE.md의 우선순위 규칙과 일치한다.

### P9. LRU 갱신 로직

`ch15_cache_system.sv` L554~558: 히트 시 `~hit_way_sel`, UPDATE 완료 시 `~latched_replace_way`로 LRU 비트를 갱신한다. Ch14 설계와 일치하며 논리적으로 정확하다.

### P10. 원고 내 HTML 이스케이프 처리

`chapter15.html`: `<pre><code>` 내 `<`, `>`, `&&` 등이 `&lt;`, `&gt;`, `&amp;`로 올바르게 이스케이프 처리되어 있다.

### P11. 원고 내 비유 한계 명시

15.1절 및 15.2절의 비유 박스에 `<small>※ 비유의 한계:...</small>` 형태로 기술적 한계가 명시되어 있다. Ch14에서 요구된 교육심리 피드백이 반영되어 있다.

### P12. NOP 정의

원고 및 코드에서 NOP 처리가 별도로 필요한 부분이 없으며, `32'h0000_0013` 정의는 Ch09~12 파이프라인 모듈 내부에서 처리되는 것으로 일관성이 유지된다.

---

## 종합 판정

| 분류 | 건수 |
|------|------|
| 🔴 Critical | 4건 |
| 🟡 Major | 6건 |
| 🟢 Minor | 6건 |

**편집장 승인 조건 미충족**: Critical 4건 존재.

### 최우선 수정 사항

1. **C1 (burst 마지막 beat 누락)**: BRAM 동기 읽기 1사이클 지연과 ACK 출력 경로 설계를 재검토하여 8워드 전체가 캐시에 정확히 적재되도록 수정 필요.
2. **C2 (D-Cache BRAM 비동기 읽기)**: `mem_wdata_o`를 조합 논리로 BRAM에서 직접 읽는 구조를 동기 읽기 + 파이프라인 구조로 변경 필요.
3. **C3 (beat_cnt 오버플로우 및 valid_array 타이밍)**: DONE 상태에서의 스톨 해제와 valid_array 갱신 타이밍이 정확히 1사이클 이내임을 코드와 원고 모두에서 명확히 검증 및 기술 필요.
4. **C4 (원고 미스 페널티 수치)**: C1 수정 후 실제 사이클 수를 재측정하여 원고의 "11사이클/19사이클" 근거를 업데이트 필요.
