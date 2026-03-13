# Chapter 14 기술 리뷰

리뷰어: 기술 리뷰어 (Technical Reviewer)
날짜: 2026-03-12

---

## 요약

- 🔴 Critical: **0건**
- 🟡 Major: **0건**
- 🟢 Minor: **4건**

전체적으로 코드의 기능 정확성은 높습니다. CLAUDE.md 파라미터와의 일관성, FSM 설계 논리, LRU 교체 정책, Write-Back 정책 구현 모두 올바릅니다. Minor 이슈 4건은 코드 명확성과 교육 자료 완성도에 관한 사항입니다.

---

## Critical 이슈

**없음.**

---

## Major 이슈

**없음.**

---

## Minor 이슈

### m-1: word_cnt — overflow 기반 암묵적 리셋 (코드 명확성)

- **위치**: `ch14_dcache_direct_mapped_wb.sv` 줄 143~155, `ch14_dcache_2way_wb.sv` 줄 160~172
- **문제**: `S_WRITE_BACK → S_REFILL` 전이 시점에 word_cnt가 명시적으로 0으로 리셋되지 않는다. 현재 코드는 `word_cnt == BLOCK_WORDS-1 && mem_ready_i`가 참일 때 카운터를 +1하면서 3비트 오버플로우(7+1=8→0)로 자연스럽게 0이 된다.

  동작 분석:
  - `word_cnt_done` 발생 클럭: 상태 전이(WRITE_BACK→REFILL) AND word_cnt +1(오버플로우→0) 동시 발생
  - 다음 클럭(S_REFILL): word_cnt=0부터 시작 → 기능적으로 올바름
  - `BLOCK_WORDS=8`에서만 3비트 오버플로우가 정확히 0이 됨. `BLOCK_WORDS`가 2의 거듭제곱이 아닌 값으로 변경되면 잠재적 버그 발생

- **교육적 문제**: 초보자가 word_cnt가 언제 리셋되는지 추적하기 어려움. "default: word_cnt <= 0"이 적용되는 것은 state가 S_IDLE/S_TAG_CHECK/S_UPDATE일 때이므로, S_WRITE_BACK→S_REFILL 전이 시의 리셋은 오버플로우에 의존함.

- **권장 수정 방안**: word_cnt 제어 로직에서 S_REFILL 시작 조건을 명시적으로 추가:

  ```systemverilog
  always_ff @(posedge clk or negedge rst_n) begin
     if (!rst_n) begin
        word_cnt <= 3'b0;
     end else begin
        case (state)
           S_WRITE_BACK: begin
              if (word_cnt_done)
                 word_cnt <= 3'b0;  // 명시적 리셋 (REFILL 시작 대비)
              else if (mem_ready_i)
                 word_cnt <= word_cnt + 3'b1;
           end
           S_REFILL: begin
              if (word_cnt_done)
                 word_cnt <= 3'b0;  // 명시적 리셋 (UPDATE 진입 대비)
              else if (mem_ready_i)
                 word_cnt <= word_cnt + 3'b1;
           end
           default: word_cnt <= 3'b0;
        endcase
     end
  end
  ```

  이 방식이 의도를 명확히 하고 BLOCK_WORDS 파라미터 변경에도 안전함.

---

### m-2: FENCE.I 코드 예제 — 합성 불가 미완성 코드 (교육 자료 완성도)

- **위치**: `manuscripts/part5/chapter14.html` 줄 743~757 (14.6절 FENCE.I 구현 코드 블록)
- **문제**: 코드 예제에 다음과 같은 미완성 분기가 포함되어 있음:

  ```systemverilog
  end else if (/* 정상 Refill */) begin
     // ...
  end
  ```

  `/* 정상 Refill */`은 SystemVerilog 표현식이 아니므로 합성 불가능한 코드이다. 이 코드가 의사코드(pseudocode)임을 명시하는 주석이나 설명이 없어, 독자가 실제 구현 가능한 코드로 오해할 수 있음.

- **수정 방안**: 해당 코드 블록 앞에 "// 의사코드 (Pseudocode) — 실제 구현은 전체 소스 참조" 주석을 추가하거나, 주석 분기를 실제 합성 가능한 코드(`else if (icache_refill_done)` 등)로 교체하여 완성된 예제를 제공.

---

### m-3: 14.4절 — dcache_stall과 flush 동시 발생 코너 케이스 미설명

- **위치**: `manuscripts/part5/chapter14.html` 줄 500~535 (14.4절 파이프라인 제어 로직)
- **문제**: 14.4절의 파이프라인 제어 코드에서 `dcache_stall`과 `flush_if_id`가 동시에 활성화되는 케이스가 설명되지 않는다.

  현재 코드:
  ```systemverilog
  else if (flush_if_id)
     if_id_reg <= '0;    // Flush 우선
  else if (!pipeline_stall)
     if_id_reg <= if_id_next;
  ```

  MEM 스테이지에서 D-Cache 미스가 발생하여 파이프라인이 홀드된 상태에서, EX 스테이지의 분기 판정 결과가 flush를 요구하는 상황이 이론적으로 가능하다. 이 경우 `flush_if_id=1`과 `dcache_stall=1`이 동시에 활성화된다.

  동작 분석:
  - `flush_if_id=1`이면 `if_id_reg <= 0` (flush 우선, 올바름)
  - 그러나 `pipeline_stall=1` 상태에서 flush가 수행되면, IF 단계에서 인출된 명령어가 버려지면서도 PC는 홀드됨 → 다음 클럭에 같은 PC에서 재인출 → 재인출된 명령어를 다시 플러시해야 할 가능성

  이 코너 케이스는 Ch09~Ch13의 스톨/플러시 우선순위 설계와 연결되므로, 원고에서 간략히 언급하거나 aside로 처리하는 것이 바람직함.

- **수정 방안**: 14.4절 "icache_stall과 dcache_stall의 우선순위" 소제목 아래에, flush와 stall 동시 발생 시 동작에 대한 설명 추가:

  > "D-Cache 스톨 중에 분기 플러시가 동시에 요청되면, 플러시가 우선 처리됩니다(`flush_if_id` 우선). 이 경우 스톨이 해제된 후 IF 스테이지에서 분기 타겟을 재인출합니다. `pipeline_stall`이 PC 진행을 막고 있으므로, 동일 PC에서 재인출이 일어나지 않도록 분기 타겟 PC를 래치해야 합니다. 이 설계는 Ch11의 분기 처리 구현에서 이미 보장되어 있습니다."

---

### m-4: 원고 14.2절 — 직접 매핑 D-Cache 파라미터 표와 CLAUDE.md 비교 표기

- **위치**: `manuscripts/part5/chapter14.html` 줄 143~175 (표 14.1)
- **문제**: 원고 표 14.1에서 D-Cache Tag가 "20비트"로 표기됨. 이는 직접 매핑(128 라인) 기준 (32-7-5=20비트)으로 올바름. 그런데 CLAUDE.md의 Part 5 파라미터 표에는 "Tag [31:11] = 21비트"로 표기되어 있어 2-Way 기준과 직접 매핑 기준이 혼재되어 있음.

  CLAUDE.md 표는 2-Way 기준으로 모두 표기되었으므로 Tag 21비트가 맞음. 직접 매핑의 20비트와 2-Way의 21비트가 두 다른 설계를 나타내는 것임. 원고 표 14.1과 14.3절 표 14.2에서 두 설계의 파라미터가 각각 올바르게 제시됨.

  그러나 독자가 CLAUDE.md만 참조했을 때 "직접 매핑도 Tag 21비트"로 오해할 가능성이 있음. CLAUDE.md의 파라미터 표에 "2-Way 기준"임을 명시하거나, 직접 매핑 파라미터를 별도로 표기하면 명확성이 높아짐.

- **수정 방안**: CLAUDE.md의 Part 5 파라미터 표 캡션에 "(이하 2-Way D-Cache 기준)" 주석 추가. 직접 매핑 D-Cache 파라미터는 원고 표 14.1을 참조하도록 안내.

---

## 검토 항목별 결과

### 1. CLAUDE.md 파라미터 일관성

| 파라미터 | CLAUDE.md | dcache_2way_wb.sv | 일치 |
|---------|-----------|-------------------|------|
| 구조 | 2-Way 세트 연관 | `NUM_WAYS=2` | ✅ |
| 총 용량 | 4KB | 64 × 2 × 32B = 4KB | ✅ |
| 세트 수 | 64 | `NUM_SETS=64` | ✅ |
| 블록 크기 | 32B (8워드) | `BLOCK_WORDS=8` | ✅ |
| Tag | [31:11] = 21비트 | `TAG_WIDTH=32-6-5=21` | ✅ |
| Index | [10:5] = 6비트 | `INDEX_WIDTH=6` | ✅ |
| Offset | [4:0] = 5비트 | `OFFSET_WIDTH=5` | ✅ |
| dcache_stall 신호 | 명시 | `dcache_stall_o` | ✅ |

### 2. dcache_direct_mapped_wb.sv 검토

| 검토 항목 | 결과 |
|-----------|------|
| 주소 비트 슬라이싱 | ✅ 올바름 (tag[31:12], index[11:5], offset[4:2]) |
| dirty_array 갱신 | ✅ Write Hit → dirty=1, S_UPDATE(clean) → dirty=0, Store Miss → dirty=1 |
| word_cnt_done 조건 | ✅ 기능 올바름, 명시적 리셋 부재 (m-1) |
| S_WRITE_BACK mem_addr | ✅ `tag_array[addr_index]` (기존 tag 사용) |
| S_REFILL mem_addr | ✅ `addr_tag` (새 tag 사용) |
| dcache_stall_o 로직 | ✅ Hit 시 0, 나머지 1 |

### 3. dcache_2way_wb.sv 검토

| 검토 항목 | 결과 |
|-----------|------|
| replace_dirty 판정 | ✅ `valid[replace_way_sel][idx] && dirty[replace_way_sel][idx]` |
| replace_way_sel과 latched_replace_way | ✅ TAG_CHECK에서 래치, 이후 상태에서 일관 사용 |
| S_WRITE_BACK mem_addr | ✅ `tag_array[latched_replace_way][addr_index]` |
| cpu_rdata_o (미스 후) | ✅ 미스 후 IDLE 전이 시 Refill된 Way에서 올바르게 반환 |
| LRU 갱신 로직 | ✅ Hit/Refill 시 접근된 Way의 반대편을 LRU로 표시 |
| word_cnt overflow | ✅ 기능 올바름, 명시적 리셋 부재 (m-1) |
| S_TAG_CHECK에서 replace_dirty race condition | ✅ 없음 (TAG_CHECK에서 LRU 갱신 없음) |

### 4. 테스트벤치 검토

| 검토 항목 | 결과 |
|-----------|------|
| 시나리오 5 주소 세트 매핑 | ✅ 세 주소 모두 index=8에 매핑됨 |
| Dirty Eviction LRU 흐름 | ✅ 시나리오 1~4 후 Way 0이 LRU가 되어 시나리오 5에서 Way 0 eviction 발생 |
| Write-Back 검증 타이밍 | ✅ stall 해제 후 main_memory 직접 검증 가능 |
| 바이트 인에이블 테스트 | ✅ SB 시뮬레이션 (byte_en=4'b0001) 포함 |

#### 테스트벤치 세트 매핑 상세 (2-Way, INDEX_WIDTH=6, addr[10:5])

| 주소 | addr_index | Tag |
|------|-----------|-----|
| 0x0000_0100 | 8 (0b001000) | 0x0 |
| 0x0010_0100 | 8 (0b001000) | 0x200 |
| 0x0020_0100 | 8 (0b001000) | 0x400 |

세 주소 모두 동일 세트(index=8)에 매핑되므로 시나리오 4, 5에서 Way 할당 충돌이 올바르게 발생함.

### 5. 원고 기술 내용 검토

| 검토 항목 | 결과 |
|-----------|------|
| Write-Through vs Write-Back 설명 | ✅ 정확함 |
| 표 14.2 Index 6비트, Tag 21비트 | ✅ 올바름 |
| dcache_stall 파이프라인 동결 설명 | ✅ PC와 전체 레지스터 Hold 설명 |
| FENCE.I (I-Cache valid 전체 리셋) | ✅ 적절함, 코드 예제 완성도 문제 (m-2) |
| CPI 계산 (1.0 + 0.30 × 0.05 × 18 = 1.27) | ✅ 수치 정확 |
| FSM 상태 표 (stall 값) | ✅ 올바름 |

---

## 합성 가능성 검토 (Basys 3 XC7A35T 기준)

### dcache_direct_mapped_wb.sv

- `typedef enum`: ✅ SystemVerilog 합성 지원
- `$clog2()` 파라미터: ✅ Vivado 합성 지원
- `data_array [128][8]` = 128 × 8 × 32비트 = 32Kbit → Basys 3 BRAM18 2개로 구현 가능 ✅
- `tag_array [128]` = 128 × 20비트 = 2.5Kbit → LUTRAM 추론 ✅
- 초기화 `for` 루프 in `always_ff reset`: ✅ 합성 가능

### dcache_2way_wb.sv

- `data_array [2][64][8]` = 2 × 64 × 8 × 32비트 = 32Kbit → BRAM18 2개 ✅
- `tag_array [2][64]` = 2 × 64 × 21비트 = 2.7Kbit → LUTRAM ✅
- `lru_array [64]` = 64비트 → FF 배열 ✅
- 중첩 `for` 루프 초기화: ✅ 합성 가능

---

## 승인 여부

- [x] Critical 0건 조건 충족
- [x] Major 0건 조건 충족

**기술 리뷰 결과: 조건부 통과** (Minor 4건 수정 권장)

Minor 이슈는 기능 오류가 아닌 코드 명확성 및 교육 자료 완성도에 관한 사항입니다. Critical/Major 이슈가 없으므로 편집장 승인 요건(Critical 0건, Major 0건)을 충족합니다. Minor 이슈는 다음 리뷰 사이클에서 수정을 권장합니다.
