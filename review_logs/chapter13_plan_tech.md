# Chapter 13 기획 회의 — 기술 저자 관점

## 날짜: 2026-03-12
## 작성자: 기술 저자 에이전트

---

## 0. Ch12 완성 상태 요약 (사전 조사 결과)

### 코드 연속성 인계 사항

`code_examples/ch12_rv32i_pipeline_complete.sv` (rv32i_pipeline_complete) 분석 결과:

| 항목 | 상태 |
|------|------|
| 파이프라인 레지스터 4종 | IF/ID / ID/EX / EX/MEM / MEM/WB 완전 구현 |
| 해저드 처리 전체 | EX-EX / MEM-EX 포워딩, Load-Use 스톨, 분기 플러시, WB-ID 포워딩 완성 |
| Harvard 구조 | IMEM (조합 논리 LUTRAM) / DMEM (동기 쓰기 / 비동기 읽기) |
| 파라미터 | DATA_WIDTH=32, ADDR_WIDTH=32, RF_DEPTH=32, IMEM_DEPTH=1024, DMEM_DEPTH=1024 |
| icache_stall | 아직 연결 안 됨 — Ch13에서 연결 예정 |
| pc_en / if_id_en | 홀드 신호 존재 — icache_stall과 연동 가능한 상태 |

### Ch12에서 확정된 성능 수치

| 구현 방식 | Fmax (예상) | CPI |
|----------|:-----------:|:---:|
| 단일 사이클 (Ch06) | ~25 MHz | 1.0 |
| 멀티사이클 (Ch08) | ~50 MHz | ~4.1 |
| 파이프라인 (Ch12) | ~65 MHz | ~1.2 |

### Ch13 진입 동기

12.6절에서 예고된 내용:
> "DRAM 접근은 BRAM보다 10~100배 느립니다. 이 속도 차이를 숨겨주는 것이 캐시(cache)입니다."

독자는 "우리가 만든 65MHz 파이프라인이 DRAM 지연으로 인해 실제로는 훨씬 느려질 수 있다"는 경이감(surprise)을 갖고 Ch13에 진입한다.

---

## 1. 13.1절 — 메모리 계층 구조와 지역성 원리

### 1.1 핵심 메시지

독자가 반드시 이해해야 할 것:
1. 메모리 계층 구조(memory hierarchy)는 "빠르고 작은 메모리 + 느리고 큰 메모리"를 조합하여 둘의 장점을 모두 취하는 전략이다.
2. 이 전략이 효과적인 이유는 실제 프로그램이 **시간적 지역성(temporal locality)**과 **공간적 지역성(spatial locality)**을 갖기 때문이다.
3. 캐시 히트(cache hit)와 캐시 미스(cache miss)의 의미, 그리고 히트율이 성능에 미치는 영향을 이해한다.

### 1.2 필요한 비유 / 실생활 예시

**비유 1 — 책상과 책장 (공간적 계층)**
- 책상 위에는 지금 읽고 있는 책 2~3권 (레지스터, 1사이클)
- 책상 옆 책꽂이에는 자주 참조하는 책 20~30권 (캐시, 5~10사이클)
- 방 구석 책장에는 전체 장서 수백 권 (DRAM, 100~300사이클)
- 도서관에는 수백만 권 (디스크, 수백만 사이클)
- "지금 읽는 책을 책상 위에 꺼내 두면, 다음에도 거기서 바로 찾을 수 있다 → 시간적 지역성"
- "소설을 읽을 때 1페이지를 읽으면 2, 3페이지를 곧 읽게 된다 → 공간적 지역성"

**비유 2 — 냉장고와 식료품 창고**
- 냉장고(캐시): 자주 먹는 식재료를 가까이 보관 → 요리할 때 즉시 꺼낼 수 있음
- 창고(DRAM): 대용량이지만 꺼내오는 데 시간이 걸림
- 냉장고에 없으면(미스) 창고에 가서(메모리 접근) 한 번에 여러 재료(캐시 블록)를 꺼와 냉장고를 채움

**숫자로 체감**:
- 파이프라인 Fmax = 65MHz → 1사이클 = 15.4ns
- 현대 DDR4 DRAM 지연 = 40~60ns (약 3~4사이클)
- 외부 DRAM 접근 = 100~300사이클 (1,540ns~4,620ns)
- 캐시 없이 매 명령어 DRAM 접근 시: CPI = 100이상 → 65MHz가 아니라 실효 <1MHz

### 1.3 필요한 SVG 다이어그램 목록

| 파일명 | 내용 | 우선순위 |
|--------|------|---------|
| `figures/ch13_sec01_memory_hierarchy.svg` | 메모리 계층 구조 피라미드: 레지스터 → L1 캐시 → L2 캐시 → DRAM → 디스크, 용량/속도/비용 표시 | 필수 |
| `figures/ch13_sec01_locality_principle.svg` | 시간적/공간적 지역성 시각화: 접근 패턴 타임라인 (루프의 반복 접근, 배열의 순차 접근) | 필수 |
| `figures/ch13_sec01_hit_miss_concept.svg` | 캐시 히트/미스 흐름도: CPU → 캐시(히트 → 즉시 반환, 미스 → DRAM 접근 → 캐시 채움 → 반환) | 필수 |

**총 SVG: 3개 (모두 필수)**

### 1.4 필요한 SystemVerilog 코드 예제

이 절은 개념 중심이므로 SystemVerilog 코드 불필요. 대신 C 코드 수준의 의사코드(pseudocode)로 지역성 예시 제시:

```c
// 시간적 지역성 예시: 루프 변수 i가 반복 접근됨
for (int i = 0; i < N; i++) sum += a[i];

// 공간적 지역성 예시: 배열 a[]가 순차 접근됨
// a[0], a[1], a[2], ... 가 연속 메모리 주소에 위치
```

**성능 계산 예시** (본문 내 박스):
```
미스율(miss rate) = 1 - 히트율(hit rate)
평균 메모리 접근 시간(AMAT) = 히트 시간 + 미스율 × 미스 페널티
예: AMAT = 1사이클 + 0.05 × 100사이클 = 6사이클
```

### 1.5 aside 박스 배치 계획

| 위치 | aside 종류 | 내용 |
|------|-----------|------|
| 지역성 개념 설명 직후 | `<aside class="faq">` | "캐시는 OS가 관리하나요, 하드웨어가 관리하나요?" — L1/L2는 하드웨어 자동 관리, 소프트웨어 투명(transparent) |
| AMAT 계산 박스 직후 | `<aside class="interview">` | "히트율 95%와 99%의 성능 차이를 AMAT 공식으로 계산하라" — 면접 단골 문제 |
| 절 마지막 | `<aside class="metacognition">` | "지역성 원리가 성립하지 않는 프로그램 패턴을 하나 생각해보라" — 랜덤 접근 패턴 |

---

## 2. 13.2절 — 직접 매핑 캐시 설계

### 2.1 핵심 메시지

독자가 반드시 이해해야 할 것:
1. **직접 매핑(direct-mapped)** 캐시에서 32비트 주소는 Tag / Index / Offset 세 필드로 분리된다.
2. 캐시 엔트리의 구조: Valid 비트 + Tag + 데이터(캐시 블록)로 구성된다.
3. 히트 판정 조건: `valid == 1 && cache_tag == addr_tag`
4. Basys 3의 BRAM을 활용하여 캐시 메모리를 구현하는 방법.

### 2.2 필요한 비유 / 실생활 예시

**비유 — 물품 보관함(라커룸)**
- 128칸짜리 보관함 (Index: 7비트 → 128 엔트리)
- 각 보관함에는 라벨(Tag)이 붙어 있고, 물건 다발(캐시 블록 = 32바이트)이 들어있음
- 물건을 찾을 때: "내 번호(Index)의 칸 → 라벨(Tag) 확인 → 일치하면 히트"
- 새 물건이 들어오면(미스): 그 칸의 기존 물건을 버리고 새 물건을 넣음 (직접 매핑의 제약)

**주소 분해 직관**:
- Offset: "캐시 블록 안에서 몇 번째 바이트인가" (32바이트 블록 → 5비트)
- Index: "몇 번 보관함인가" (128 엔트리 → 7비트)
- Tag: "보관함 주인이 맞는가" (나머지 20비트)

### 2.3 필요한 SVG 다이어그램 목록

| 파일명 | 내용 | 우선순위 |
|--------|------|---------|
| `figures/ch13_sec02_address_decomposition.svg` | 32비트 주소 → Tag[31:12] / Index[11:5] / Offset[4:0] 분해 도식, 비트 폭 레이블 포함 | 필수 |
| `figures/ch13_sec02_cache_structure.svg` | 직접 매핑 캐시 구조: Valid + Tag + Data(32byte) 블록 배열 (128행), 히트/미스 판정 로직 연결 포함 | 필수 |
| `figures/ch13_sec02_bram_mapping.svg` | Basys 3 BRAM에 캐시 배열을 매핑하는 방법: Tag BRAM + Data BRAM 분리, Valid는 레지스터 배열 | 선택 |

**총 SVG: 3개 (필수 2개, 선택 1개)**

### 2.4 필요한 SystemVerilog 코드 예제

**핵심 코드 파일**: `code_examples/ch13_icache_direct_mapped.sv`

모듈 인터페이스:
```systemverilog
module icache_direct_mapped #(
   parameter int CACHE_SIZE   = 4096,    // 4KB
   parameter int BLOCK_SIZE   = 32,      // 32바이트 (8워드)
   parameter int NUM_ENTRIES  = 128,     // CACHE_SIZE / BLOCK_SIZE
   parameter int ADDR_WIDTH   = 32
)(
   input  logic        clk,
   input  logic        rst_n,
   // CPU ↔ 캐시 인터페이스
   input  logic [31:0] cpu_addr,         // PC (명령어 주소)
   input  logic        cpu_req,          // 요청 유효
   output logic [31:0] cpu_rdata,        // 반환 명령어 (32비트)
   output logic        cache_hit,        // 히트 신호
   output logic        icache_stall,     // 파이프라인 홀드 요청
   // 캐시 ↔ IMEM(하위 메모리) 인터페이스
   output logic [31:0] mem_addr,         // 메모리 읽기 주소
   output logic        mem_req,          // 메모리 읽기 요청
   input  logic [31:0] mem_rdata,        // 메모리 읽기 데이터
   input  logic        mem_ready         // 메모리 응답 완료
);
```

내부 구조:
- `logic valid [0:127]`: Valid 비트 배열 (레지스터)
- `logic [19:0] tag_mem [0:127]`: Tag 배열 (LUTRAM 또는 BRAM)
- `logic [31:0] data_mem [0:127][0:7]`: 데이터 배열 (8워드 × 128 엔트리, BRAM)
- 히트 판정: `assign cache_hit = valid[index] && (tag_mem[index] == addr_tag);`

**BRAM 추론 팁**: data_mem을 1D 배열로 평탄화(flatten)하여 Vivado가 BRAM을 추론하도록 유도:
```systemverilog
// 1024워드 × 32비트 = 32Kbit = 1 BRAM36 블록
logic [31:0] data_mem [0:1023]; // [index*8 + offset_word]
```

### 2.5 aside 박스 배치 계획

| 위치 | aside 종류 | 내용 |
|------|-----------|------|
| Tag/Index/Offset 분해 직후 | `<aside class="tip">` | "캐시 크기가 달라지면 비트 폭이 달라진다 — Offset 비트 = log2(블록크기), Index 비트 = log2(엔트리 수)" |
| BRAM 설명 직후 | `<aside class="tip">` | "Vivado에서 BRAM 추론 조건: 배열 크기 ≥ 1K비트, 동기 읽기/쓰기. `(* ram_style = \"block\" *)` 속성으로 강제 지정 가능" |
| 직접 매핑의 한계 언급 후 | `<aside class="faq">` | "같은 Index를 가진 주소들이 번갈아 접근하면 어떻게 되나요?" — 충돌 미스(conflict miss) 소개 → 13.5절에서 실습 |
| 절 마지막 | `<aside class="interview">` | "직접 매핑, 2-way 집합 연관, 완전 연관의 장단점 비교" — 면접 3단계 질문 패턴 |

---

## 3. 13.3절 — 직접 해보기: 캐시 주소 분해 연습

### 3.1 핵심 메시지

독자가 반드시 이해해야 할 것:
1. 임의의 32비트 주소가 주어졌을 때 Tag / Index / Offset을 손으로 계산할 수 있다.
2. 같은 Index를 가진 주소들이 캐시에서 충돌한다는 것을 직접 확인한다.
3. 캐시 히트/미스 판정을 시뮬레이션 파형이 아닌 "종이 계산"으로 예측하고 검증한다.

### 3.2 필요한 비유 / 실생활 예시

**비유 — 주민등록번호와 지역번호**
- 32비트 주소 = 사람의 전화번호
- Offset[4:0] = 같은 건물 안 층수 (블록 내 위치)
- Index[11:5] = 동네 번호 (어느 캐시 엔트리로 가는가)
- Tag[31:12] = 이름+생년월일 (실제로 이 사람이 맞는지 확인)
- "동네 번호(Index)는 같지만 이름(Tag)이 다르면 → 다른 사람(충돌)"

### 3.3 미니 실습 예제 (4KB 캐시, 128 엔트리, 32바이트 블록 기준)

**캐시 파라미터 정리**:
- 캐시 크기: 4KB = 4,096 바이트
- 블록 크기: 32바이트 → Offset = log₂(32) = 5비트 → [4:0]
- 엔트리 수: 4,096 / 32 = 128 → Index = log₂(128) = 7비트 → [11:5]
- Tag = 32 - 7 - 5 = 20비트 → [31:12]

**예제 1: 주소 `0x0000_0000`**
```
이진수:  0000 0000 0000 0000 0000 0000 0000 0000
         [31        12][11    5][4  0]
Tag   = 0x0_0000  (20비트: 0x00000)
Index = 0b000_0000 = 0   (엔트리 #0)
Offset= 0b00000   = 0    (블록 내 바이트 0)
→ 캐시 엔트리 #0의 Tag가 0x00000이고 Valid=1이면 히트
```

**예제 2: 주소 `0x0000_0020`**
```
이진수:  0000 0000 0000 0000 0000 0000 0010 0000
         [31        12][11    5][4  0]
Tag   = 0x00000
Index = 0b000_0001 = 1   (엔트리 #1)
Offset= 0b00000   = 0    (블록 내 바이트 0)
→ 캐시 엔트리 #0과 다른 엔트리(#1)이므로 충돌 없음
→ 첫 접근이면 미스, 이후 같은 블록 내 0x21~0x3F는 히트
```

**예제 3: 주소 `0x0000_0040`**
```
이진수:  0000 0000 0000 0000 0000 0000 0100 0000
         [31        12][11    5][4  0]
Tag   = 0x00000
Index = 0b000_0010 = 2   (엔트리 #2)
Offset= 0b00000   = 0
→ 엔트리 #2, Tag=0x00000
```

**예제 4: 주소 `0x0001_0000`**
```
이진수:  0000 0000 0000 0001 0000 0000 0000 0000
         [31        12][11    5][4  0]
Tag   = 0x00010  (Tag의 비트 0이 1)
Index = 0b000_0000 = 0   (엔트리 #0)
Offset= 0b00000   = 0
→ 엔트리 #0, Tag=0x00010
→ 0x0000_0000과 같은 엔트리(Index=0)를 사용!
→ 0x0000_0000이 캐시에 있었다면 → 충돌 미스(conflict miss) 발생
```

**예제 5: 블록 내 연속 접근 (공간적 지역성 확인)**
```
주소 0x0000_0004:
Tag=0x00000, Index=0, Offset=4  → 0x0000_0000과 같은 블록!
주소 0x0000_0008:
Tag=0x00000, Index=0, Offset=8  → 같은 블록!
주소 0x0000_001C:
Tag=0x00000, Index=0, Offset=28 → 같은 블록! (블록의 마지막 워드)
→ 첫 0x0000_0000 접근이 미스였더라도, 이후 7개 워드는 모두 히트
```

**연습 문제 (독자 풀이용)**:
- Q1: 주소 `0x0000_0060`의 Tag / Index / Offset은?
- Q2: `0x0000_0000`과 충돌하는 주소를 하나 더 구하라.
- Q3: 블록 크기가 64바이트라면 Offset 비트 폭은?

(정답: Q1: Tag=0x00000, Index=3, Offset=0 / Q2: 0x0002_0000 (Index=0, Tag=0x00020) / Q3: 6비트)

### 3.4 필요한 SVG 다이어그램 목록

| 파일명 | 내용 | 우선순위 |
|--------|------|---------|
| `figures/ch13_sec03_address_examples.svg` | 예제 1~4 주소의 비트 분해 시각화: 4개 주소를 나란히 배치, 충돌 관계를 화살표로 표시 | 필수 |
| `figures/ch13_sec03_conflict_illustration.svg` | 예제 1(0x0000_0000)과 예제 4(0x0001_0000)가 같은 캐시 엔트리(Index=0)로 매핑되는 충돌 시각화 | 필수 |

**총 SVG: 2개 (모두 필수)**

### 3.5 필요한 SystemVerilog 코드 예제

이 절은 "종이 계산 + 시뮬레이션 미니 실습" 구성이므로 간단한 검증용 테스트벤치 함수를 제시:

**파일**: `code_examples/ch13_addr_decode_check.sv` (선택적, 시뮬레이션 검증 보조)

```systemverilog
// 주소 분해 함수 — 검증용 (실제 캐시 아님)
function automatic void decode_addr(
   input  logic [31:0] addr,
   output logic [19:0] tag,
   output logic [6:0]  index,
   output logic [4:0]  offset
);
   offset = addr[4:0];
   index  = addr[11:5];
   tag    = addr[31:12];
endfunction
```

### 3.6 aside 박스 배치 계획

| 위치 | aside 종류 | 내용 |
|------|-----------|------|
| 절 시작 | `<aside class="instructor-tip">` | "이 절은 종이와 펜으로 먼저 풀게 한 후 시뮬레이션으로 확인하는 순서를 권장합니다. 손 계산 → 시뮬레이션의 2단계 검증이 캐시 이해에 가장 효과적입니다." |
| 예제 4 (충돌) 직후 | `<aside class="faq">` | "충돌 미스가 자주 발생하면 어떻게 해결하나요?" — 2-way 집합 연관 캐시(Ch14 예고), 또는 배열 정렬(패딩) 최적화 |
| 연습 문제 직후 | `<aside class="metacognition">` | "예제 5에서 첫 접근이 미스였는데도 나머지 7개 접근이 히트인 이유는 무엇인가? 캐시 블록 채움(block fill) 동작과 연결하여 설명해보라." |

---

## 4. 13.4절 — 캐시 미스 처리: Stall 메커니즘

### 4.1 핵심 메시지

독자가 반드시 이해해야 할 것:
1. 캐시 미스 발생 시 파이프라인을 **홀드(hold)**해야 하며, 이를 `icache_stall` 신호로 구현한다.
2. Ch12의 `pc_en`과 `if_id_en` 홀드 메커니즘(Load-Use 스톨에서 사용)을 재활용한다.
3. 미스 처리 FSM: **IDLE → MISS → FILL → DONE** 4개 상태와 각 상태의 동작을 이해한다.
4. 미스 페널티: 1사이클(요청) + 4사이클(채움) = 5사이클 (단순화 모델).

### 4.2 필요한 비유 / 실생활 예시

**비유 — 식당 주방과 냉장고**
- 요리사(CPU)가 요리(명령어 실행)를 하다가 냉장고(캐시)에 재료가 없음(미스)
- 요리사는 잠시 기다리며(파이프라인 스톨) 보조 요리사에게 창고(DRAM)에서 재료를 가져오라고 지시
- 보조 요리사가 재료를 창고에서 가져와(미스 페널티) 냉장고를 채움(캐시 라인 채움)
- 재료가 준비되면(DONE) 요리 재개(파이프라인 재개)

**FSM 상태 직관**:
- IDLE: 냉장고 문을 열어 확인 중 → 히트면 계속, 미스면 MISS로
- MISS: 창고에 주문 신청 → `mem_req = 1`
- FILL: 창고에서 재료 도착 중 → 여러 사이클 대기 (블록 채움)
- DONE: 냉장고 채움 완료 → 파이프라인 재개

### 4.3 필요한 SVG 다이어그램 목록

| 파일명 | 내용 | 우선순위 |
|--------|------|---------|
| `figures/ch13_sec04_miss_fsm.svg` | 미스 처리 FSM 다이어그램: IDLE/MISS/FILL/DONE 4개 상태, 전환 조건(cache_hit, mem_ready), 각 상태에서의 출력 신호(icache_stall, mem_req 등) | 필수 |
| `figures/ch13_sec04_stall_pipeline.svg` | icache_stall 발생 시 파이프라인 홀드 타이밍: PC/IF/ID 레지스터가 동결되는 모습, 5사이클 미스 페널티 파형 | 필수 |
| `figures/ch13_sec04_signal_connection.svg` | rv32i_pipeline_complete ↔ icache 연결 블록 다이어그램: pc_en/if_id_en ← icache_stall 연결 경로 명시 | 선택 |

**총 SVG: 3개 (필수 2개, 선택 1개)**

### 4.4 필요한 SystemVerilog 코드 예제

**핵심 코드 파일**: `code_examples/ch13_icache_direct_mapped.sv` (13.2절에서 모듈 인터페이스 정의, 13.4절에서 FSM 구현)

**FSM 핵심 구현**:

```systemverilog
// 미스 처리 FSM
typedef enum logic [1:0] {
   IDLE = 2'b00,
   MISS = 2'b01,
   FILL = 2'b10,
   DONE = 2'b11
} cache_state_t;

cache_state_t state, next_state;
logic [2:0] fill_cnt;  // 블록 채움 카운터 (8워드 = 8사이클, 단순화시 4사이클)

// 상태 레지스터
always_ff @(posedge clk or negedge rst_n) begin
   if (!rst_n) state <= IDLE;
   else        state <= next_state;
end

// 다음 상태 로직
always_comb begin
   next_state = state;
   case (state)
      IDLE: if (cpu_req && !cache_hit) next_state = MISS;
      MISS: if (mem_ready)             next_state = FILL;
      FILL: if (fill_cnt == 3'd7)      next_state = DONE;  // 8워드 채움 완료
      DONE:                            next_state = IDLE;
   endcase
end

// 출력 로직
assign icache_stall = (state == MISS) || (state == FILL);
assign mem_req      = (state == MISS);
```

**파이프라인 연결** (rv32i_pipeline_complete 수정):
```systemverilog
// icache_stall을 pc_en, if_id_en에 연결
// 기존: pc_en = if_id_flush ? 1'b1 : hdu_pc_en
// 수정: icache_stall이 있으면 pc_en = 0 (캐시 미스 우선순위 추가)
assign pc_en    = if_id_flush ? 1'b1 :
                  icache_stall ? 1'b0 : hdu_pc_en;
assign if_id_en = icache_stall ? 1'b0 : hdu_if_id_en;
```

**우선순위 확정**: flush > icache_stall > load_use_stall

**추가 파일**: `code_examples/ch13_pipeline_with_icache.sv` — rv32i_pipeline_complete에 icache를 연결한 최종 top 모듈 (선택적)

### 4.5 aside 박스 배치 계획

| 위치 | aside 종류 | 내용 |
|------|-----------|------|
| icache_stall 우선순위 설명 직후 | `<aside class="tip">` | "flush > cache_stall > load_stall 우선순위는 실제 ARM Cortex-M, MIPS R4000 설계에서도 동일한 패턴이다. flush는 wrong-path 명령어를 제거하므로 가장 긴급하다." |
| FSM 설계 후 | `<aside class="faq">` | "FILL 상태에서 8사이클 동안 8워드를 전부 채우나요, 아니면 요청한 워드만 먼저 보내주나요?" — Critical Word First(CWF) 최적화 소개, 교재에서는 단순화 |
| 절 마지막 | `<aside class="metacognition">` | "Load-Use 스톨(1사이클)과 캐시 미스 스톨(5사이클)의 차이점을 파이프라인 관점에서 설명할 수 있는가?" |

---

## 5. 13.5절 — L1 명령어 캐시 시뮬레이션

### 5.1 핵심 메시지

독자가 반드시 이해해야 할 것:
1. 4가지 접근 시나리오(Cold start, Sequential, Loop, Conflict)에서 캐시 파형이 어떻게 달라지는지 이해한다.
2. 히트율과 미스 페널티에서 실제 성능 향상을 수치로 확인한다.
3. 직접 매핑의 한계(충돌 미스)를 시뮬레이션으로 직접 관찰한다.

### 5.2 필요한 비유 / 실생활 예시

**비유 — 도서관 대출 기록**
- Cold start = 도서관에서 처음으로 빌리는 책 → 항상 "없음" (MISS)
- Sequential access = 소설책 1권을 장(Chapter) 순서대로 읽기 → 같은 책 안에서 이동 (HIT)
- Loop = 같은 책을 반복해서 읽기 → 이미 집에 있는 책 (HIT)
- Conflict miss = 같은 자리(Index)를 두 사람이 번갈아 요구 → 번갈아 교체 발생 (MISS 반복)

### 5.3 테스트벤치 4가지 시나리오 상세 설계

**시나리오 1: Cold Start (첫 번째 접근 — 항상 MISS)**
```
접근 주소 순서: 0x0000_0000, 0x0000_0020, 0x0000_0040, 0x0000_0060
예상 결과: 모두 MISS → 각각 5사이클 스톨
파형 확인: icache_stall = 1 (5사이클), cache_hit = 0
```

**시나리오 2: Sequential Access (공간적 지역성 — 같은 캐시 라인 내 HIT)**
```
접근 주소 순서:
  0x0000_0000 → MISS (5사이클 스톨, 블록 채움: 0x00~0x1F)
  0x0000_0004 → HIT  (1사이클, 같은 블록)
  0x0000_0008 → HIT
  0x0000_000C → HIT
  0x0000_0010 → HIT
  0x0000_0014 → HIT
  0x0000_0018 → HIT
  0x0000_001C → HIT  (블록의 마지막 워드)
파형 확인: 첫 접근만 stall, 이후 7회 연속 hit
```

**시나리오 3: Loop (시간적 지역성 — 반복 접근 HIT)**
```
루프 3회 반복 시뮬레이션:
  1회차: 0x0000_0000 MISS, 0x0000_0004 HIT, 0x0000_0008 HIT
  2회차: 0x0000_0000 HIT, 0x0000_0004 HIT, 0x0000_0008 HIT
  3회차: 0x0000_0000 HIT, 0x0000_0004 HIT, 0x0000_0008 HIT
파형 확인: 1회차만 미스, 2~3회차는 모두 히트 (캐시에 남아있음)
히트율 계산: 6/9 = 66.7% (루프 9회 접근 중 6회 히트)
```

**시나리오 4: Conflict Miss (직접 매핑 충돌)**
```
같은 Index(=0)를 가진 두 주소 번갈아 접근:
  A = 0x0000_0000 (Tag=0x00000, Index=0)
  B = 0x0001_0000 (Tag=0x00010, Index=0)

접근 패턴: A, B, A, B, A, B (각각 6회)
예상 결과: 모두 MISS → 6 × 5 = 30사이클 스톨
파형 확인: cache_hit = 0 (6회 모두), 캐시 엔트리 #0 계속 교체
비교: 동일 접근 패턴을 2-way 캐시로 하면 2회만 MISS
```

### 5.4 필요한 SVG 다이어그램 목록

| 파일명 | 내용 | 우선순위 |
|--------|------|---------|
| `figures/ch13_sec05_waveform_hit_miss.svg` | 시나리오 2(Sequential) 파형: cpu_addr, cache_hit, icache_stall, 스톨 사이클 수 표시 | 필수 |
| `figures/ch13_sec05_waveform_conflict.svg` | 시나리오 4(Conflict) 파형: A→B→A→B 접근 시 모두 MISS인 파형, 캐시 엔트리 교체 상황 | 필수 |
| `figures/ch13_sec05_hit_rate_comparison.svg` | 4가지 시나리오 히트율 막대 그래프: Cold/Sequential/Loop/Conflict 비교 | 선택 |

**총 SVG: 3개 (필수 2개, 선택 1개)**

### 5.5 필요한 SystemVerilog 코드 예제

**핵심 코드 파일**: `code_examples/ch13_icache_tb.sv`

테스트벤치 구조:
```systemverilog
module icache_tb;
   // DUT 인스턴스: icache_direct_mapped
   // 시뮬레이션 클록: 10ns 주기

   // Task 1: cold_start_test
   // Task 2: sequential_access_test
   // Task 3: loop_access_test
   // Task 4: conflict_miss_test
   // Task 5: check_performance (히트율, 총 스톨 사이클 계산)

   // 히트율 자동 계산
   integer total_access, total_hit;
   always @(posedge clk) begin
      if (cpu_req) begin
         total_access++;
         if (cache_hit) total_hit++;
      end
   end

   // 최종 보고
   // $display("히트율: %0.1f%%", real'(total_hit)/real'(total_access)*100);
   // $display("총 스톨 사이클: %0d", stall_cycles);
endmodule
```

**미스 페널티 측정 코드**:
```systemverilog
// 스톨 사이클 카운터
integer stall_cycles;
always @(posedge clk)
   if (icache_stall) stall_cycles++;
```

**예상 시뮬레이션 출력**:
```
=== 시나리오 1: Cold Start ===
[MISS] 0x00000000  → 5사이클 스톨
[MISS] 0x00000020  → 5사이클 스톨
총 히트율: 0.0%

=== 시나리오 2: Sequential Access ===
[MISS] 0x00000000  → 5사이클 스톨
[HIT ] 0x00000004  → 0사이클
...
총 히트율: 87.5%  (7/8)

=== 시나리오 3: Loop ===
총 히트율: 66.7%  (6/9)

=== 시나리오 4: Conflict Miss ===
[MISS] 0x00000000  → 5사이클 스톨
[MISS] 0x00010000  → 5사이클 스톨
[MISS] 0x00000000  → 5사이클 스톨
...
총 히트율: 0.0%  ← 직접 매핑의 한계
[WARN] Conflict miss detected: Index=0 between Tag=0x00000 and Tag=0x00010
```

### 5.6 aside 박스 배치 계획

| 위치 | aside 종류 | 내용 |
|------|-----------|------|
| Sequential 히트율 결과 직후 | `<aside class="tip">` | "캐시 블록 크기(32바이트)를 키우면 공간적 지역성을 더 많이 활용할 수 있지만, 미스 페널티도 커진다 → 블록 크기 선택은 항상 트레이드오프" |
| Conflict miss 결과 직후 | `<aside class="interview">` | "직접 매핑 캐시의 충돌 미스를 완화하는 방법 3가지: (1) 2-way 집합 연관, (2) 캐시 착색(cache coloring), (3) 소프트웨어 배열 패딩" |
| 절 마지막 | `<aside class="metacognition">` | "loop_access_test에서 히트율이 66.7%인 이유는 루프 크기(3워드)와 캐시 블록 크기(8워드)의 관계 때문이다. 루프가 캐시 블록 2개에 걸쳐있다면 히트율이 어떻게 달라질지 예측해보라." |

---

## 6. 13.6절 — 본 챕터 요약 및 다음 단계

### 6.1 핵심 메시지

이 절은 요약 및 연결 절이므로:
1. Ch13의 핵심 개념 5가지를 표로 정리한다.
2. 자가 점검 질문으로 이해도를 확인한다.
3. Ch14(데이터 캐시 및 쓰기 정책)로의 자연스러운 연결을 제공한다.

### 6.2 핵심 개념 요약 표

| 개념 | 핵심 내용 |
|------|---------|
| 메모리 계층 구조 | 빠르고 작은 캐시 + 느리고 큰 DRAM의 조합 |
| 지역성 원리 | 시간적(반복 접근) + 공간적(연속 접근) — 캐시 효과의 근거 |
| 주소 분해 | Tag[31:12] / Index[11:5] / Offset[4:0] (4KB, 128엔트리, 32바이트 블록 기준) |
| 캐시 미스 처리 | IDLE → MISS → FILL → DONE FSM, icache_stall로 파이프라인 홀드 |
| 직접 매핑의 한계 | 같은 Index → 충돌 미스 → 2-way 집합 연관으로 개선 가능 |

### 6.3 자가 점검 질문

1. 캐시 히트율이 95%일 때 AMAT를 계산하라. (히트 시간 1사이클, 미스 페널티 50사이클)
2. 블록 크기를 64바이트로 늘리면 주소 비트 분해가 어떻게 달라지는가?
3. 충돌 미스가 발생하는 두 주소 쌍을 스스로 만들어보라.
4. icache_stall 신호가 flush와 동시에 발생하면 어떤 신호가 우선해야 하는가?

### 6.4 Ch14 예고

> "이번 챕터에서는 명령어 캐시(I-cache)를 완성했습니다.
> 그런데 RISC-V 파이프라인은 데이터 메모리(DMEM)에도 접근합니다.
> LOAD / STORE 명령어가 DRAM 속도로 실행된다면 아무리 좋은 명령어 캐시도 의미가 없습니다.
> 다음 챕터에서는 데이터 캐시(D-cache)를 추가하고,
> 캐시에 쓰기(STORE)를 어떻게 처리할지 — Write-Through vs Write-Back 정책을 배웁니다."

### 6.5 aside 박스 배치 계획

| 위치 | aside 종류 | 내용 |
|------|-----------|------|
| 자가 점검 질문 직후 | `<aside class="metacognition">` | "위 4개 질문에 모두 답할 수 있다면 Ch13 목표 달성. 막히는 부분이 있다면 해당 절의 SVG 다이어그램을 다시 보라." |
| Ch14 예고 전 | `<aside class="tip">` | "L1 D-cache를 추가하면 Basys 3 BRAM이 2블록 더 필요하다. XC7A35T의 총 BRAM36 = 50블록이므로 아직 여유가 충분하다." |

---

## 7. 전체 SVG 다이어그램 총계

| 절 | 파일명 | 우선순위 |
|----|--------|---------|
| 13.1 | `ch13_sec01_memory_hierarchy.svg` | 필수 |
| 13.1 | `ch13_sec01_locality_principle.svg` | 필수 |
| 13.1 | `ch13_sec01_hit_miss_concept.svg` | 필수 |
| 13.2 | `ch13_sec02_address_decomposition.svg` | 필수 |
| 13.2 | `ch13_sec02_cache_structure.svg` | 필수 |
| 13.2 | `ch13_sec02_bram_mapping.svg` | 선택 |
| 13.3 | `ch13_sec03_address_examples.svg` | 필수 |
| 13.3 | `ch13_sec03_conflict_illustration.svg` | 필수 |
| 13.4 | `ch13_sec04_miss_fsm.svg` | 필수 |
| 13.4 | `ch13_sec04_stall_pipeline.svg` | 필수 |
| 13.4 | `ch13_sec04_signal_connection.svg` | 선택 |
| 13.5 | `ch13_sec05_waveform_hit_miss.svg` | 필수 |
| 13.5 | `ch13_sec05_waveform_conflict.svg` | 필수 |
| 13.5 | `ch13_sec05_hit_rate_comparison.svg` | 선택 |

**총계: 14개 (필수 11개, 선택 3개)**

---

## 8. 전체 SystemVerilog 코드 파일 목록

| 파일명 | 내용 | 절 |
|--------|------|-----|
| `code_examples/ch13_icache_direct_mapped.sv` | 직접 매핑 L1 I-Cache 완전 구현 (FSM 포함) | 13.2 / 13.4 |
| `code_examples/ch13_pipeline_with_icache.sv` | rv32i_pipeline_complete + icache 연결 top | 13.4 |
| `code_examples/ch13_icache_tb.sv` | 4가지 시나리오 테스트벤치 (히트율 자동 계산) | 13.5 |
| `code_examples/ch13_addr_decode_check.sv` | 주소 분해 검증 함수 (선택적, 교육용) | 13.3 |

**총계: 4개 (필수 3개, 선택 1개)**

---

## 9. 절별 핵심 개념 수 제한 확인

| 절 | 신규 개념 | 개수 | 판정 |
|----|---------|:----:|:----:|
| 13.1 메모리 계층 | 메모리 계층 구조, 시간적/공간적 지역성, AMAT | 3 | ✅ |
| 13.2 직접 매핑 설계 | Tag/Index/Offset 분해, Valid 비트, BRAM 활용 | 3 | ✅ |
| 13.3 주소 분해 실습 | (개념 신규 없음, 13.2 적용 실습) | 0 | ✅ |
| 13.4 스톨 메커니즘 | icache_stall 신호, 미스 처리 FSM, 우선순위 결정 | 3 | ✅ |
| 13.5 시뮬레이션 | Cold/Sequential/Loop/Conflict 패턴 | 2 | ✅ |
| 13.6 요약 | (신규 개념 없음) | 0 | ✅ |

---

## 10. 감정 곡선 설계

| 단계 | 절 | 감정 목표 | 안심 장치 |
|------|---|----------|---------|
| 경이감 | 13.1 도입 | "65MHz 파이프라인이 DRAM 지연으로 <1MHz로 추락?!" | "캐시가 이 문제를 해결합니다 — 이 챕터 끝에서 수치로 확인합니다" |
| 이해 | 13.1 지역성 | "실제 프로그램은 지역성이 있으므로 캐시가 효과적이다" | 책상/냉장고 비유로 직관 먼저 제공 |
| 집중 | 13.2 설계 | Tag/Index/Offset 새 개념 3개 — 혼란 가능성 | "비트 분해는 단순한 슬라이싱입니다. 13.3절에서 손으로 직접 풀어봅니다" |
| 성취 | 13.3 실습 | "내가 32비트 주소를 Tag/Index/Offset으로 쪼갤 수 있다!" | 정답을 확인하는 순간의 "맞췄다" 느낌 설계 |
| 긴장 | 13.4 FSM | icache_stall 연결 — 기존 파이프라인 수정 필요 | "pc_en, if_id_en은 Ch10에서 이미 익숙한 신호입니다. 연결만 추가합니다." |
| 검증 | 13.5 시뮬 | 4가지 파형으로 이론과 실제 일치 확인 | Conflict miss 파형에서 "직접 매핑의 한계" 경험 → Ch14 동기 부여 |
| 자긍심 | 13.6 요약 | "나는 이제 캐시가 있는 파이프라인 CPU를 설계할 수 있다" | 핵심 5개 개념 표 + "다음 단계: D-cache" 예고 |

---

## 11. 기술적 주의사항 및 결정 사항

### 11.1 icache_stall 우선순위 결정

**최종 결정**: flush > icache_stall > load_use_stall

근거:
- flush는 wrong-path 명령어 폐기이므로 최긴급
- icache_stall은 IF 스테이지의 데이터 미준비 → ID 이후 스테이지는 NOP으로 처리
- load_use_stall보다 icache_stall이 더 상위 조건 (캐시 미스 중에는 load_use 스톨 불필요)

```systemverilog
assign pc_en    = if_id_flush   ? 1'b1  :  // flush 최우선
                  icache_stall  ? 1'b0  :  // 캐시 미스 홀드
                  hdu_pc_en;               // load_use 스톨

assign if_id_en = icache_stall  ? 1'b0  :  // 캐시 미스 홀드
                  hdu_if_id_en;            // load_use 스톨
```

### 11.2 Basys 3 BRAM 활용 계획

| 캐시 구성 | BRAM 사용 | 여유 |
|---------|---------|-----|
| I-Cache 4KB (data: 128×8×32bit = 32Kbit) | 1 BRAM36 | 49/50 여유 |
| Tag 배열 (128×20bit = 2,560bit) | LUTRAM 추론 가능 | — |
| Valid 배열 (128bit) | FF 배열 | — |
| **I-Cache 합계** | **1 BRAM36** | **49개 여유** |

Ch14에서 D-Cache 추가 시에도 1 BRAM36 추가로 충분.

### 11.3 단순화 결정 목록

| 항목 | 단순화 내용 | 실제 구현과의 차이 |
|------|------------|----------------|
| 미스 페널티 | 고정 5사이클 (1+4) | 실제 DRAM: 가변 지연, CAS Latency 등 |
| 블록 채움 순서 | 순차 채움 (Critical Word First 미적용) | 실제: 요청 워드 먼저 반환 후 나머지 채움 |
| 쓰기 정책 | I-Cache이므로 읽기 전용 (쓰기 정책 불필요) | D-Cache에서 Write-Through/Back 도입 (Ch14) |
| 교체 정책 | 직접 매핑 → 교체 정책 불필요 | 2-way 이상에서는 LRU 등 필요 (Ch14) |
| 멀티워드 버스 | 1워드(32비트)씩 채움 | 실제: 버스트 전송(64bit/128bit 버스) |

### 11.4 코드 연속성 — ch12_rv32i_pipeline_complete.sv와의 연결

Ch13에서 파이프라인 수정 최소화 원칙:
- `rv32i_pipeline_complete` 모듈 내부 수정은 최소한으로
- `icache_stall` 포트를 외부로 노출하거나, wrapper 모듈(`ch13_pipeline_with_icache.sv`)에서 연결
- Ch12 코드의 교육적 완결성 보존 (Ch12만 독립적으로 동작해야 함)

```systemverilog
// ch13_pipeline_with_icache.sv (새 top 모듈)
module pipeline_with_icache #(...)(
   input  logic clk, rst_n
);
   logic icache_stall;
   logic [31:0] pc_from_pipe, instr_to_pipe;

   icache_direct_mapped u_icache (..., .icache_stall(icache_stall));
   rv32i_pipeline_complete u_core (..., .icache_stall(icache_stall));
endmodule
```

---

## 12. 절별 예상 분량

| 절 | 예상 분량 | 난이도 | 비고 |
|----|---------|-------|------|
| 13.1 메모리 계층 | 2,500자 | 낮음 | 개념 + 비유 + 수치 중심 |
| 13.2 직접 매핑 설계 | 3,000자 | 중간 | 코드 인터페이스 + 구조 설명 |
| 13.3 주소 분해 실습 | 2,000자 | 낮음 | 예제 4개 + 연습 문제 |
| 13.4 스톨 메커니즘 | 3,500자 | 높음 | FSM + 파이프라인 연결 코드 |
| 13.5 시뮬레이션 | 3,000자 | 중간 | 4가지 시나리오 + 파형 분석 |
| 13.6 요약 | 1,000자 | 낮음 | 표 + 자가 점검 + Ch14 예고 |
| **합계** | **~15,000자** | — | 기준(2,000~4,000자/절) 내 |

---

## 13. Ch14 연결 예고 (13.6절 예고 내용 상세)

Ch14에서 다룰 내용:
- D-Cache (데이터 캐시): LOAD/STORE 명령어의 캐시 처리
- Write-Through vs Write-Back 쓰기 정책
- Dirty 비트, Write Buffer 개념
- I-Cache + D-Cache 통합 시 Harvard 캐시 구조
- AMAT 개선 수치 측정 (D-Cache 추가 후 vs 추가 전)

Basys 3 BRAM 예산:
- I-Cache: 1 BRAM36 (Ch13)
- D-Cache: 1 BRAM36 (Ch14)
- 코어 IMEM+DMEM: 2 BRAM36 (Ch09부터)
- 총 사용: 4 BRAM36 / 50 BRAM36 → 92% 여유

---

*작성 완료: 2026-03-12*
*기술 저자 에이전트*
