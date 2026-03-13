# Chapter 13 기술 리뷰 보고서

**리뷰어**: 기술 리뷰어 (Technical Reviewer)
**리뷰 일자**: 2026-03-12
**대상 챕터**: Ch13 — 캐시 기초와 L1 명령어 캐시

---

## 검토 대상 파일

| 파일 | 경로 |
|------|------|
| 원고 | manuscripts/part5/chapter13.html |
| 코어 캐시 모듈 | code_examples/ch13_icache_direct_mapped.sv |
| 파이프라인 래퍼 | code_examples/ch13_pipeline_with_icache.sv |
| 테스트벤치 | code_examples/ch13_icache_tb.sv |
| 주소 분해 검증 | code_examples/ch13_addr_decode_check.sv |

---

## 요약

| 등급 | 건수 |
|------|------|
| 🔴 Critical | 3 |
| 🟡 Major | 5 |
| 🟢 Minor | 4 |

---

## 🔴 Critical (기술 오류 / 합성 불가)

---

### C-1. BRAM 쓰기 주소 타이밍 오류 — MISS 상태에서 fill_cnt=0이 아닌 상태로 쓸 수 있음

**파일**: `code_examples/ch13_icache_direct_mapped.sv`, 줄 122~126, 174~180

**문제 내용**:

FSM에서 MISS → FILL 전환과 `fill_cnt` 초기화 로직은 다음과 같다:

```systemverilog
// 줄 122~126
if (state == MISS && mem_ready) begin
   fill_cnt <= 3'b0;        // FILL 시작 시 리셋
end else if (state == FILL && mem_ready) begin
   fill_cnt <= fill_cnt + 1'b1;
end
```

그리고 BRAM 쓰기는:
```systemverilog
// 줄 176~180
always_ff @(posedge clk) begin
   if ((state == MISS || state == FILL) && mem_ready) begin
      data_mem[fill_word_addr] <= mem_rdata;  // fill_word_addr = {miss_addr_reg[11:5], fill_cnt}
   end
end
```

**핵심 문제**: `fill_cnt <= 3'b0`은 클록 엣지에서 레지스터에 적용되므로, `state == MISS && mem_ready` 사이클에서 BRAM에 쓸 때 `fill_cnt`는 아직 이전 값(0이 아닐 수 있음)이다. 다만 MISS 진입 시 FSM 리셋 과정에서 `fill_cnt`가 이미 0으로 유지되고 있다면 문제가 없을 수 있다. 그러나 다음 미스 발생 시 DONE→IDLE→MISS 전환 중 fill_cnt가 7에서 리셋되지 않은 상태로 MISS에 mem_ready가 도달하면 fill_word_addr = {index, 3'd7}이 되어 워드 7번 슬롯에 쓰고, 다음 사이클에 fill_cnt가 0으로 리셋된다. 즉, **2번째 이후 미스에서 첫 번째 수신 워드가 fill_cnt=7 주소에 저장되는 오류**가 발생한다.

**올바른 설계**: `fill_cnt`를 IDLE/DONE 진입 시 명시적으로 0으로 초기화하거나, MISS 상태 진입 시(next_state == MISS 전환 순간)에 리셋해야 한다. 또는 BRAM 쓰기 주소를 `fill_cnt` 대신 별도의 write_ptr 카운터로 분리하고, FILL 상태 진입 후 첫 사이클에 0부터 시작함을 보장해야 한다.

**교육 영향**: 2번째 이후 캐시 미스 시 블록이 잘못된 순서로 저장되어 실제 시뮬레이션에서 캐시 히트 후 잘못된 명령어가 출력될 수 있다. 테스트벤치 시나리오 3(루프 접근)에서 2회차 히트가 비정상 데이터를 반환할 위험이 있다.

---

### C-2. mem_addr 생성 시 miss_addr_reg가 래치되기 전 사이클에 잘못된 주소 구동

**파일**: `code_examples/ch13_icache_direct_mapped.sv`, 줄 104, 128~131

**문제 내용**:

```systemverilog
// 줄 104
assign mem_addr = {miss_addr_reg[31:5], fill_cnt, 2'b00};

// 줄 128~131
if (state == IDLE && cpu_req && !cache_hit) begin
   miss_addr_reg <= cpu_addr;  // 다음 클록에서 래치됨
end
```

FSM 전환: IDLE → MISS는 `always_comb`에서 즉시 결정되고 `state <= next_state`에 의해 다음 클록에서 반영된다. MISS 상태에서 `mem_req = 1`이 활성화된다.

그런데 `miss_addr_reg`도 같은 클록 엣지에서 래치된다. 즉, IDLE에서 미스가 감지된 **바로 그 클록에서** state가 MISS로 전환되고 `miss_addr_reg`도 동시에 업데이트된다. 이 경우 MISS 상태 첫 사이클에서 `miss_addr_reg`는 올바른 값을 가지므로 기능은 정상이다.

그러나 **DONE 상태에서 IDLE로 복귀한 직후** 새로운 미스가 발생하면, DONE→IDLE→MISS 전환이 2클록에 걸쳐 일어난다. DONE 상태에서 icache_stall = 0이고 파이프라인이 재개되므로 새 cpu_addr이 변할 수 있다. IDLE 상태에서 미스가 감지되면 `miss_addr_reg <= cpu_addr`이 래치되는데, 조합 논리 `assign mem_addr`은 MISS 진입 직후부터 `miss_addr_reg`를 사용한다. 래치가 올바르게 캡처되므로 이 부분은 실제로는 정상 동작한다.

**실제 Critical 문제**: `cpu_req`가 항상 1로 연결되어 있을 때 (`ch13_pipeline_with_icache.sv`, 줄 121: `.cpu_req(1'b1)`), DONE 상태에서 IDLE로 전환되는 사이클에 `cpu_req && !cache_hit` 조건이 평가된다. 이때 cache_hit은 DONE 사이클에서는 올바른 값이지만, DONE 직후 IDLE에서 새 cpu_addr에 대한 valid/tag 체크가 조합 논리로 이루어지므로 기능상 문제는 없다. 단, **파이프라인 래퍼에서 `cpu_req = 1'b1`로 고정**하면, 파이프라인이 stall된 상태(icache_stall=1)에서도 cpu_addr이 변경될 경우(예: flush 발생 시 PC가 변경) IDLE 복귀 직후 엉뚱한 주소로 miss_addr_reg가 래치될 수 있다. flush와 icache_stall이 동시에 발생하는 코너 케이스에 대한 처리가 없다.

**수정 권고**: flush 발생 시 현재 채움 중인 블록을 중단하고 FSM을 IDLE로 강제 복귀시키는 `flush_req` 입력 또는 내부 처리를 추가해야 한다. 현재 설계는 flush 발생 시 FILL 중이던 블록이 캐시에 채워진 후 파이프라인이 재개되므로, 5사이클 불필요한 지연이 발생한다 (교재에서 언급한 "flush가 캐시 스톨보다 우선"이 코드에서 구현되지 않음).

---

### C-3. DONE 상태에서 cpu_rdata 출력 시 mem_rdata 직접 연결의 문제

**파일**: `code_examples/ch13_icache_direct_mapped.sv`, 줄 196

**문제 내용**:

```systemverilog
assign cpu_rdata = (state == DONE) ? mem_rdata : bram_rdata_reg;
```

DONE 상태에서 `mem_rdata`를 직접 출력하는 의도는 마지막 채움 워드를 즉시 사용하려는 것이다. 그러나 다음 두 가지 문제가 있다:

1. **어느 워드를 출력하는가**: DONE 전환은 `fill_cnt == 3'd7 && mem_ready` 조건에서 이루어진다. 이 시점에서 BRAM에는 7번 워드까지 채워졌다. DONE 상태에서 mem_rdata는 마지막으로 수신된 데이터(fill_cnt=7번 워드)이다. 그러나 CPU가 요청한 워드는 `word_offset = cpu_addr[4:2]`로 결정되며, 이는 0~7 중 임의의 값이다. **CPU가 word_offset=2를 요청했는데 DONE에서 word_offset=7의 데이터를 출력하는 오류**가 발생한다.

2. **DONE 상태 지속 기간**: DONE 상태는 1사이클만 유지(즉시 IDLE로 복귀)되므로, 파이프라인이 DONE 사이클에 명령어를 수신할 수 있으려면 icache_stall이 이미 0이어야 한다. 그러나 `icache_stall = (state == MISS) || (state == FILL)`이므로 DONE 상태에서는 stall=0이다. 따라서 파이프라인은 DONE 사이클에 명령어를 수신하려 하지만 BRAM은 동기 읽기이므로 DONE 사이클에는 이전 사이클의 read_word_addr에 대한 결과를 출력한다. DONE에서 mem_rdata를 직접 쓰는 것이 의도적이나, word_offset 불일치 문제가 치명적이다.

**올바른 설계**: DONE 상태에서 BRAM 동기 읽기 결과를 사용하거나, FILL 완료 직전 사이클(fill_cnt=7, mem_ready=1)에 BRAM 읽기를 트리거하고 DONE에서 bram_rdata_reg를 사용해야 한다. 또는 블록 채움 완료 후 DONE을 2사이클로 늘려 BRAM 읽기 레이턴시를 흡수해야 한다.

---

## 🟡 Major (비효율 / 표준 미준수 / 기능 불완전)

---

### M-1. FILL 상태 진입 시 fill_cnt 초기화 타이밍 — 첫 번째 워드 저장 주소 불일치

**파일**: `code_examples/ch13_icache_direct_mapped.sv`, 줄 122~125, 174~180

**문제 내용**:

MISS 상태에서 `mem_ready=1`이 되면:
- 같은 클록에서 `fill_cnt <= 3'b0` (다음 클록에 적용)
- 같은 클록에서 BRAM 쓰기: `data_mem[{miss_addr_reg[11:5], fill_cnt}] <= mem_rdata`

이 클록에서 `fill_cnt`의 현재값은 이전 FILL 사이클에서 마지막으로 설정된 값이다. 리셋 직후 첫 번째 미스에서는 fill_cnt = 0이므로 정상이지만, 이후 미스에서는 fill_cnt가 불확정 값이 될 수 있다 (C-1과 연관).

초기화 방식: FSM 진입 시 `fill_cnt <= 3'b0`를 DONE 상태에서 명시적으로 수행하거나, IDLE 상태에서 초기화하는 것이 더 안전하다.

---

### M-2. Tag 배열 LUTRAM 동기 쓰기와 비동기 읽기 혼재 — Vivado 추론 가능성 검토 필요

**파일**: `code_examples/ch13_icache_direct_mapped.sv`, 줄 57~58, 136~137

**문제 내용**:

```systemverilog
(* ram_style = "distributed" *)
logic [TAG_WIDTH-1:0] tag_mem [0:NUM_ENTRIES-1];  // LUTRAM

// 비동기 읽기 (조합 논리)
assign cache_hit = valid[addr_index] && (tag_mem[addr_index] == addr_tag);

// 동기 쓰기 (always_ff 내부)
tag_mem[miss_addr_reg[11:5]] <= miss_addr_reg[31:12];
```

Vivado에서 `(* ram_style = "distributed" *)`와 비동기 읽기(always_comb/assign)는 LUTRAM으로 올바르게 추론된다. 그러나 **Vivado 2020 이후 일부 버전에서 복잡한 조건부 always_ff 쓰기와 비동기 읽기 혼합 시 BRAM으로 잘못 추론될 수 있다**는 보고가 있다. 합성 후 반드시 Utilization Report에서 `RAM32M` 또는 `RAM64M` 프리미티브 사용 여부를 확인해야 한다.

권고사항: 합성 결과 검증 절차를 교재에 명시적으로 안내하고, 만약 BRAM으로 추론된다면 항상 `(* ram_style = "distributed" *)` 속성을 별도 always 블록과 함께 사용하는 예제를 추가하는 것이 좋다.

---

### M-3. valid 배열 loop 초기화 — Vivado 합성 불가 경고 가능성

**파일**: `code_examples/ch13_icache_direct_mapped.sv`, 줄 114~117

**문제 내용**:

```systemverilog
always_ff @(posedge clk) begin
   if (!rst_n) begin
      state    <= IDLE;
      fill_cnt <= 3'b0;
      for (int i = 0; i < NUM_ENTRIES; i++) begin
         valid[i] <= 1'b0;
      end
   end
```

`for` 루프를 `always_ff` 내부에서 사용하는 것은 IEEE 1800-2017 표준에서 합성 가능하다. Vivado는 이를 128개 FF의 동기 리셋으로 올바르게 추론한다. 기능상 문제는 없다.

그러나 **Vivado의 합성 경고**: 일부 버전에서 loop unrolling 시 "multi-driven" 경고 또는 레이턴시 경고가 발생할 수 있다. 학생들이 이 경고를 보고 혼란스러울 수 있으므로, 교재에 "이 경고는 정상이며 합성 결과는 올바르다"는 안내를 aside로 추가하는 것을 권고한다.

---

### M-4. 파이프라인 래퍼에서 if_id_flush 우선순위 적용 불완전

**파일**: `code_examples/ch13_pipeline_with_icache.sv`, 줄 56~61

**문제 내용**:

```systemverilog
assign pc_en_final    = if_id_flush  ? 1'b1  :
                        icache_stall ? 1'b0  :
                        hdu_pc_en;

assign if_id_en_final = icache_stall ? 1'b0 : hdu_if_id_en;
```

`pc_en_final`에서 `if_id_flush`가 최우선으로 처리되는 것은 올바르다. 그러나 `if_id_en_final`에서 flush 조건이 빠져 있다. 분기 플러시 시 IF/ID 레지스터를 flush해야 하는데, `if_id_en_final`에 flush 조건이 없으면 분기 플러시와 icache_stall이 동시에 발생했을 때 IF/ID 레지스터가 홀드(en=0)되어 플러시가 적용되지 않는다.

Ch11의 원래 설계에서 flush는 enable 신호와 별도로 처리되었을 것이므로, rv32i_pipeline_complete 내부에서 flush가 독립적으로 처리된다면 괜찮다. 그러나 래퍼에서 `ext_if_id_en`이 플러시 역할까지 담당한다면 이는 중요한 버그이다.

**권고**: 주석에 "flush는 rv32i_pipeline_complete 내부에서 별도 처리됨"이라는 명시적 설명을 추가하고, 래퍼 인터페이스 설계 의도를 교재에서 더 명확히 설명해야 한다.

---

### M-5. 메모리 지연 모델의 단순화 — FILL 중 매 사이클 1워드 응답 가정이 명시되지 않음

**파일**: `code_examples/ch13_pipeline_with_icache.sv`, 줄 80~105; `code_examples/ch13_icache_tb.sv`, 줄 70~95

**문제 내용**:

메모리 지연 모델은 `mem_req` 첫 수신 후 5사이클 뒤에 `mem_ready=1` 한 번만 펄스를 보낸다. 그러나 `ch13_icache_direct_mapped.sv`의 FILL 상태는 `mem_ready`가 매 사이클 활성화될 것을 기대한다 (`fill_cnt`가 mem_ready마다 증가). 현재 메모리 모델은 `mem_ready`를 1사이클만 high로 보내므로:

- FILL 상태에서 fill_cnt = 0이 한 번 증가하고, 다시 mem_req=0, mem_ready=0이 되어 FSM이 FILL에서 멈춘다.
- fill_cnt가 7에 도달하지 않으므로 DONE으로 전환되지 않아 **무한 스톨** 가능성이 있다.

실제 동작을 위해서는 메모리 모델이 `mem_req=1`을 수신한 후 8사이클 동안 매 사이클 `mem_ready=1`과 함께 각 워드를 순서대로 응답해야 한다. 또는 캐시 FSM이 FILL 중 자체적으로 `mem_req`를 사용하여 매 워드를 개별 요청해야 한다.

현재 설계는 두 가지 방식이 혼재되어 기능적으로 작동하지 않을 수 있다. 테스트벤치와 래퍼의 메모리 모델 모두 단일 ready 펄스만 생성하므로, 8워드 블록 채움이 완료되지 않는 심각한 문제이다.

---

## 🟢 Minor (스타일 / 교육적 개선 권고)

---

### m-1. HTML 코드 이스케이프 — 전반적으로 올바르게 처리됨

**파일**: `manuscripts/part5/chapter13.html`, 줄 285, 600, 618, 626, 980, 983, 993 등

`<pre><code>` 블록 내부의 `<`, `>`, `&&` 등이 `&lt;`, `&gt;`, `&amp;&amp;`로 올바르게 이스케이프되어 있다. 특히 줄 285 (`assign cache_hit = valid[addr_index] &amp;&amp; ...`), 줄 600 (`IDLE = 2'b00` 블록), 줄 618~631 (우선순위 로직) 모두 정상이다. 다만 전체 소스 코드 섹션(줄 942~1062)에서 이스케이프를 체계적으로 확인해야 한다.

줄 993~994에서 `state &lt;= IDLE;`, `fill_cnt &lt;= 3'b0;` 등 이스케이프가 올바르다. 줄 979 `assign cache_hit = valid[addr_index] &amp;&amp; ...`도 정상이다.

**경미한 이슈**: 줄 1024에서 `if ((state == MISS || state == FILL) &amp;&amp; mem_ready)` — 정상 이스케이프 확인. 전반적으로 이스케이프는 올바르게 처리되었으나, 일관성을 위해 HTML 렌더링 후 시각적으로 재확인 권고.

---

### m-2. ch13_addr_decode_check.sv — 블록 크기 64바이트 Index 범위 오류

**파일**: `code_examples/ch13_addr_decode_check.sv`, 줄 125

**문제 내용**:

```systemverilog
$display("  log2(64) = 6비트 → Offset[5:0], Index[12:6], Tag[31:13]");
```

블록 크기 64바이트(Offset[5:0] = 6비트), 엔트리 수 64개(Index = 6비트)일 때:
- Index = addr[11:6] (6비트)
- Tag = addr[31:12] (20비트)

주석에 표시된 `Index[12:6]`은 7비트이므로 오류이다. 올바른 값은 `Index[11:6]`이다. 연습문제 Q3 설명과 일치하지 않으며, 학생들이 혼란을 겪을 수 있다.

---

### m-3. 테스트벤치 access_addr 태스크 — 히트 집계 시점 불일치

**파일**: `code_examples/ch13_icache_tb.sv`, 줄 107~121

**문제 내용**:

```systemverilog
task automatic access_addr(...);
   @(posedge clk);
   cpu_addr = addr;
   cpu_req  = 1'b1;
   #1;  // 조합 논리 안정화 대기

   if (cache_hit) begin
      total_hit++;
      ...
   end
   total_access++;
```

`cache_hit`은 조합 논리이므로 `#1` 후에 평가하면 이전 사이클의 cpu_addr에 대한 히트 판정이 반영된다. 이것이 의도적이라면 올바르지만, `@(posedge clk)`와 `#1` 사이에서 cpu_addr이 업데이트된 직후 cache_hit이 새 주소에 대한 히트 여부를 반영하는지 타이밍이 불명확하다. 시뮬레이터에 따라 race condition 발생 가능성이 있다.

권고: `@(posedge clk); #1;` 다음에 cpu_addr을 설정하고, `@(negedge clk);`에서 cache_hit을 샘플링하거나, clocking block을 사용하는 것이 더 안전하다.

---

### m-4. 교재 HTML 내 fill_cnt 오버플로우 설명 부재

**파일**: `manuscripts/part5/chapter13.html`, 13.4절

**문제 내용**:

3비트 fill_cnt가 3'd7에서 멈추는 조건(`fill_cnt == 3'd7`)은 FSM 코드에 있지만, HTML 교재에서 "fill_cnt가 7에서 8로 넘어가지 않는 이유"에 대한 설명이 없다. 교육 목적상 "3비트 카운터의 최대값 = 7 = 2³-1 = 8워드 중 마지막 워드"를 명시적으로 설명하면 학생들의 이해를 돕는다.

또한 fill_cnt == 3'd7 조건이 DONE 전환과 동시에 valid 설정까지 수행하는 것이 교재 코드(줄 1002~1005)에서 설명 없이 등장하여, 단일 사이클에 두 가지 작업이 이루어짐을 강조하는 aside가 필요하다.

---

## 주소 분해 정확성 검증

| 항목 | 설계값 | 검증 결과 |
|------|--------|-----------|
| Tag [31:12] | 20비트 | ✅ 정확 |
| Index [11:5] | 7비트 | ✅ 정확 |
| Offset [4:0] | 5비트 | ✅ 정확 |
| word_offset [4:2] | 3비트 | ✅ 정확 |
| 0x0000_0000 → Index=0 | 0 | ✅ 정확 |
| 0x0001_0000 → Index=0, Tag≠0 | 충돌 | ✅ 정확 |
| 0x0000_0020 → Index=1 | 1 | ✅ 정확 |
| 충돌 패턴 4KB 배수 | ✅ 정확 | ✅ 정확 |

---

## FSM 상태 전환 검증

| 전환 | 조건 | 검증 결과 |
|------|------|-----------|
| IDLE → MISS | cpu_req && !cache_hit | ✅ 정확 |
| MISS → FILL | mem_ready | ✅ 정확 |
| FILL → DONE | mem_ready && fill_cnt==7 | ✅ 정확 (타이밍 이슈 C-1 참조) |
| DONE → IDLE | 항상 (무조건) | ✅ 정확 |

---

## 테스트벤치 시나리오 히트율 수치 검증

| 시나리오 | 예상 히트율 | 계산 근거 | 검증 결과 |
|----------|-------------|-----------|-----------|
| 1. Cold Start (3접근) | 0% (0/3) | 모두 다른 캐시 라인, 최초 접근 | ✅ 정확 |
| 2. Sequential (8접근) | 87.5% (7/8) | 1회 MISS + 7회 동일 블록 HIT | ✅ 정확 |
| 3. Loop (9접근) | 66.7% (6/9) | 1회차 3 MISS, 2~3회차 6 HIT | ✅ 정확 |
| 4. Conflict (4접근) | 0% (0/4) | A↔B 번갈아, 매번 Tag 불일치 | ✅ 정확 |

---

## Basys 3 FPGA 리소스 적합성 검토

| 자원 | 사용량 | Basys 3 한도 | 여유 |
|------|--------|-------------|------|
| BRAM36 (Data 배열) | 1개 (32Kbit) | 50개 | 49개 (98%) |
| LUTRAM (Tag 배열) | 2,560비트 = ~40개 LUT | 5,200개 | 충분 |
| FF (Valid 배열) | 128개 | 41,600개 | 충분 |
| FF (fill_cnt, miss_addr_reg 등) | ~40개 | 41,600개 | 충분 |

FPGA 리소스 관점에서 설계 파라미터는 Basys 3에 적합하다.

---

## 우선 수정 권고 순서

1. **C-3 (최우선)**: DONE 상태 cpu_rdata 출력 오류 — word_offset 불일치로 잘못된 명령어 반환
2. **M-5 (최우선)**: 메모리 모델 단순화 오류 — 8워드 순차 ready 펄스 없음으로 FILL 완료 불가
3. **C-1**: fill_cnt 초기화 타이밍 — 2번째 이후 미스에서 첫 워드 저장 주소 오류
4. **C-2**: flush 발생 시 FILL 중단 메커니즘 부재 — 교재 설명과 코드 불일치
5. **M-4**: 파이프라인 래퍼 if_id_en_final flush 우선순위 명확화
6. **m-2**: addr_decode_check.sv Index 범위 오기 수정 (Index[12:6] → Index[11:6])

---

*리뷰 완료: 2026-03-12*
