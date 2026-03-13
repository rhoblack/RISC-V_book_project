# Ch09 기획 리뷰 — 기술 리뷰어

**챕터**: Chapter 09 — 파이프라인 기초: 스테이지 분할
**리뷰어**: 기술 리뷰어 (Technical Reviewer)
**작성일**: 2026-03-11
**검토 기반**: TABLE_OF_CONTENTS.md, chapter08_plan_tech.md, chapter08_final_approval.md, RISC-V Unprivileged ISA Spec v20191213, IEEE 1800-2017

---

## 개요

Chapter 09는 Part 4(5단계 파이프라인)의 첫 챕터로, 멀티사이클 FSM CPU에서 파이프라인 프로세서로 개념적·구조적 전환이 이루어지는 핵심 교량 챕터다. 기술 리뷰어 관점에서 이 챕터의 성패는 세 가지 설계 결정에 달려 있다:

1. **파이프라인 레지스터 필드 완전성**: IF/ID, ID/EX, EX/MEM, MEM/WB 레지스터에 담겨야 할 모든 필드를 Ch10(포워딩)까지 내다보고 설계해야 함.
2. **리셋 전략 확정**: 동기/비동기 리셋을 이 챕터에서 결정하고 이후 모든 챕터에서 일관성 유지.
3. **Enable/Flush 신호 예약**: Ch10에서 추가될 스톨/플러시 인프라를 9.4절 레지스터 선언 시점에 예약해 두어야 Ch10에서 재설계 없이 기능 추가 가능.

---

## 1. 절별 기술 검토

### 9.1절 기술 요구사항 — 멀티사이클에서 파이프라인으로

**핵심 기술 메시지**:
"멀티사이클 FSM의 각 상태가 동시에 실행될 수 있다면 그것이 파이프라인이다."

이 전환에서 기술적으로 반드시 짚어야 할 내용:

#### (1) FSM 상태 → 파이프라인 스테이지 1:1 대응 관계
Ch08 FSM의 S0(IF), S1(ID), S_EX_*, S_MEM_*, S_WB_*가 파이프라인의 IF/ID/EX/MEM/WB 스테이지와 대응된다. 단, 멀티사이클에서는 한 명령어가 순차적으로 상태를 이동하고, 파이프라인에서는 서로 다른 명령어가 동시에 각 스테이지를 점유한다는 근본적 차이를 명시해야 한다.

#### (2) 파이프라인이 가능한 이유: 스테이지 간 데이터 독립성
멀티사이클 FSM에서는 중간 레지스터(A, B, ALUOut, MDR, IR)가 한 명령어의 중간 결과를 보관했다. 파이프라인에서는 이 역할을 파이프라인 레지스터(IF/ID, ID/EX, EX/MEM, MEM/WB)가 담당하며, 각 스테이지의 출력이 다음 스테이지 입력으로 전달된다. 이 구조적 차이가 동시 실행을 가능하게 한다.

#### (3) 공유 메모리 문제: Princeton → Harvard 구조 전환 필수
Ch07~08의 멀티사이클은 Princeton(통합 메모리) 구조를 사용했다. 파이프라인에서는 IF 스테이지(명령어 인출)와 MEM 스테이지(데이터 읽기/쓰기)가 동시에 메모리에 접근하므로, 단일 메모리로는 **구조적 해저드(Structural Hazard)**가 발생한다. 9.3절에서 하버드(Harvard) 구조(IMEM/DMEM 분리)로 전환하는 이유를 명확히 설명해야 한다.

> **기술 리뷰어 주의**: 이 전환(Princeton → Harvard)이 하드웨어 면적 증가를 의미한다는 점도 언급할 것. Basys 3에서 IMEM용 BRAM 1~2개 + DMEM용 BRAM 1~2개로 분리.

#### (4) CPI=1 목표의 조건
이상적 파이프라인의 CPI=1은 **해저드가 없을 때**만 성립한다. 9.1절에서 "CPI=1"을 제시할 때 "해저드 없음을 가정"이라는 조건을 반드시 명시해야 한다. 해저드 처리로 인한 실제 CPI는 Ch10~11에서 분석됨을 예고할 것.

#### (5) 클럭 주기 결정 방식의 변화
멀티사이클: 클럭 주기 = 가장 짧은 스테이지 지연 (각 사이클마다 다름, 하나의 클럭으로 고정)
파이프라인: 클럭 주기 = **가장 긴 스테이지 지연** (5개 스테이지 중 최대값)

Basys 3에서 가장 느린 스테이지는 EX(ALU 연산 + 데이터 경로)이며, 이것이 파이프라인의 클럭 주기를 결정한다. 멀티사이클 대비 클럭 주기가 짧아질 수 있지만, 단일 사이클 대비 유사하거나 약간 길어질 수 있다는 트레이드오프를 설명해야 한다.

---

### 9.2절 기술 요구사항 — 파이프라인 성능 분석

#### 처리량(Throughput) vs 지연(Latency) 공식

**정확한 공식**:

```
처리량(Throughput) = 명령어 수 / 전체 실행 시간
이상적 처리량    = 1 명령어 / (1 클럭 주기)  [CPI=1 가정]

지연(Latency)    = 명령어 1개가 완료되는 데 걸리는 시간
이상적 지연      = N_stages × (1 클럭 주기)  [N=5이면 5 클럭 주기]
```

**타이밍 분석 공식**:
```
단일 사이클 실행 시간 = N_instr × T_single_cycle
파이프라인 실행 시간  = (N_instr + N_stages - 1) × T_clk_pipeline
```

N_instr이 충분히 크면 `T_clk_pipeline ≈ T_single_cycle / N_stages`에 수렴한다.

> **기술 리뷰어 주의**: 교재에서 "파이프라인이 N배 빠르다"는 표현은 이상적 조건에서만 성립한다. 실제로는 해저드, 스톨, 파이프라인 오버헤드(레지스터 셋업/홀드 타임)로 인해 성능 이득이 N배에 미치지 못함을 명시해야 한다.

#### 성능 분석에서 확인해야 할 수치 (Basys 3 기준)
- 단일 사이클 최대 주파수: ~20~30 MHz (Ch06.5 측정값)
- 멀티사이클 최대 주파수: ~50 MHz (Ch08 측정값)
- 파이프라인 목표 주파수: ~100 MHz (이상적), 실제 ~50~80 MHz 예상
- 각 스테이지의 예상 지연: IF(BRAM 읽기 ~2ns), ID(레지스터 파일 ~1ns), EX(ALU ~3ns), MEM(BRAM 읽기/쓰기 ~2ns), WB(MUX + 레지스터 파일 쓰기 ~1ns)

---

### 9.3절 기술 요구사항 — 5단계 스테이지 정의

각 스테이지의 담당 작업을 RV32I 명령어 관점에서 정확히 정의해야 한다:

| 스테이지 | 하드웨어 모듈 | 담당 작업 | 출력 |
|----------|-------------|----------|------|
| IF | IMEM, PC 레지스터 | PC를 사용하여 명령어 인출, PC+4 계산 | 명령어 워드(32비트), PC+4 |
| ID | 레지스터 파일, 즉치수 생성기, 제어 유닛 | 명령어 디코딩, rs1/rs2 읽기, 즉치수 생성, 제어 신호 생성 | rs1_data, rs2_data, imm_ext, 제어 신호 묶음 |
| EX | ALU, 브랜치 비교기, 포워딩 MUX | ALU 연산, 메모리 주소 계산, 분기 조건 판단, 분기 목표 주소 계산 | ALU 결과, 분기 여부(branch_taken) |
| MEM | DMEM | Load/Store 메모리 접근 | 읽기 데이터(rd_data) |
| WB | MUX, 레지스터 파일 | 결과를 rd에 기록 | (없음, 레지스터 파일에 기록) |

**기술적으로 반드시 명시할 사항**:

1. **PC+4 계산 위치**: IF 스테이지에서 계산하여 IF/ID 레지스터에 저장. EX 스테이지까지 전달되어 JAL/JALR의 복귀 주소, 분기 목표 주소 계산(BEQ 등)에 활용.

2. **제어 신호 생성 위치**: ID 스테이지에서 생성. 파이프라인 레지스터를 통해 각 스테이지로 전달. EX 스테이지에서는 EX용 신호를 사용하고 나머지를 다음 레지스터로 전달.

3. **WB-ID 포워딩 경로**: WB 스테이지에서 레지스터 파일에 쓰는 동시에, ID 스테이지에서 같은 레지스터를 읽는 경우를 위한 레지스터 파일 내부 포워딩. Ch12에서 상세 처리하지만, 9.3절에서 구조도에 이 경로를 점선으로 표시할 것.

4. **분기 목표 주소 계산 스테이지 결정**: EX 스테이지에서 계산하는 것이 표준. ID 스테이지로 올리면 1사이클 페널티를 줄일 수 있으나 포워딩 복잡성이 증가한다(Ch11 주제). 9.3절에서는 EX 스테이지 기준으로 설명하고, Ch11에서 최적화를 다룸을 예고.

---

### 9.4절 기술 요구사항 — 파이프라인 레지스터 설계 (가장 상세히)

#### (1) 동기 리셋 vs 비동기 리셋 선택

**선택: 동기 리셋 권장 (파이프라인 레지스터 한정)**

| 항목 | 동기 리셋 | 비동기 리셋 |
|------|----------|------------|
| 구현 패턴 | `always_ff @(posedge clk)` | `always_ff @(posedge clk or negedge rst_n)` |
| Vivado 추론 | FDRE (flip-flop with synchronous reset) | FDCE (flip-flop with asynchronous clear) |
| 타이밍 | 리셋이 클럭 경로에 포함 → 약간 느림 | 리셋이 비동기 → 셋업 타임 마진 확보 |
| 플러시 동작 | 동기 플러시와 동일 메커니즘 → 일관성 높음 | 비동기 플러시 구현 시 글리치 위험 |
| FPGA 권장 | Xilinx FPGA는 동기 리셋/Enable 더 효율적 | 일부 설계에서 비동기 리셋 필요 |

**근거**: 파이프라인 레지스터의 플러시(flush) 동작이 동기 리셋과 동일한 메커니즘이므로, 동기 리셋을 사용하면 플러시 로직과 리셋 로직을 동일한 `if (rst | flush)` 조건으로 통합할 수 있다. Xilinx Artix-7에서 FDRE는 FDCE보다 타이밍 분석이 단순하다.

> **중요**: PC 레지스터(파이프라인의 IF 스테이지 상태 요소)는 비동기 리셋이 적합할 수 있다. 시스템 리셋 시 PC가 즉시 0으로 초기화되어야 하는 요구사항이 있을 때. 교재에서 이 구분을 명시할 것.

**코딩 패턴 확정**:
```systemverilog
// 파이프라인 레지스터: 동기 리셋 + Enable 패턴
always_ff @(posedge clk) begin
   if (rst) begin
      // 리셋 값 설정 (NOP 버블)
   end else if (enable) begin
      // 다음 스테이지 값 래치
   end
   // else: 홀드 (스톨)
end
```

#### (2) 각 파이프라인 레지스터의 필드 목록

**IF/ID 레지스터 (IF 스테이지 출력 → ID 스테이지 입력)**

| 필드 | 비트폭 | 설명 | Ch10 활용 |
|------|--------|------|-----------|
| `instr` | 32 | 명령어 워드 | ID에서 디코딩 |
| `pc` | 32 | 현재 명령어 PC (IF 스테이지 PC) | EX에서 분기 목표 주소 계산, JAL/AUIPC |
| `pc_plus4` | 32 | PC+4 | WB에서 JAL/JALR 복귀 주소 |

> **설계 주의**: `pc`와 `pc_plus4`를 모두 저장하거나, `pc`만 저장하고 각 스테이지에서 +4를 재계산하는 방법도 있다. 재계산 방식은 하드웨어를 줄이지만 가산기가 여러 스테이지에 분산된다. 교재에서는 **명시적 전달 방식**(`pc`와 `pc_plus4` 모두 저장)을 권장한다 — 파이프라인 동작의 가시성이 높기 때문.

**ID/EX 레지스터 (ID 스테이지 출력 → EX 스테이지 입력)**

| 필드 | 비트폭 | 설명 | Ch10 활용 |
|------|--------|------|-----------|
| `rs1_data` | 32 | rs1 읽기 데이터 | EX ALU 입력 A, 포워딩 MUX 입력 |
| `rs2_data` | 32 | rs2 읽기 데이터 | EX ALU 입력 B, MEM Store 데이터 |
| `imm_ext` | 32 | 부호 확장 즉치수 | EX ALU 입력 B (I/S/B/U/J 타입) |
| `pc` | 32 | 현재 명령어 PC | EX 분기 목표 주소 계산 (PC + imm_B), AUIPC |
| `pc_plus4` | 32 | PC+4 | WB JAL/JALR 복귀 주소로 전달 |
| `rs1_addr` | 5 | rs1 레지스터 번호 | **포워딩 조건 판단 필수** |
| `rs2_addr` | 5 | rs2 레지스터 번호 | **포워딩 조건 판단 필수** |
| `rd_addr` | 5 | rd 레지스터 번호 | WB에서 쓰기 주소, 포워딩 소스 |
| *제어 신호* | — | EX, MEM, WB용 제어 신호 묶음 | — |

**ID/EX 제어 신호 필드** (Ch10 포워딩/스톨 설계까지 고려):

| 제어 신호 | 비트폭 | 사용 스테이지 |
|----------|--------|-------------|
| `alu_src_a` | 1 | EX: ALU A 입력 선택 (rs1 vs PC) |
| `alu_src_b` | 1 | EX: ALU B 입력 선택 (rs2 vs imm) |
| `alu_control` | 4 | EX: ALU 연산 코드 |
| `branch` | 1 | EX: 분기 명령어 여부 (flush 제어) |
| `mem_read` | 1 | MEM: 메모리 읽기 인에이블 (Load-Use 해저드 감지) |
| `mem_write` | 1 | MEM: 메모리 쓰기 인에이블 |
| `reg_write` | 1 | WB: 레지스터 파일 쓰기 인에이블 (포워딩 조건) |
| `mem_to_reg` | 2 | WB: WB MUX 선택 (ALU결과/MDR/PC+4) |
| `jump` | 1 | WB: JAL/JALR 식별 (복귀 주소 저장) |

> **Ch10 준비 핵심**: `rs1_addr`, `rs2_addr`, `rd_addr`, `reg_write`, `mem_read` 필드가 ID/EX 레지스터에 있어야 포워딩 유닛과 해저드 감지 유닛이 동작할 수 있다. 이 필드를 9.4절에서 선언하지 않으면 Ch10에서 파이프라인 레지스터를 재설계해야 한다.

**EX/MEM 레지스터 (EX 스테이지 출력 → MEM 스테이지 입력)**

| 필드 | 비트폭 | 설명 | Ch10 활용 |
|------|--------|------|-----------|
| `alu_result` | 32 | ALU 연산 결과 (메모리 주소 또는 연산 결과) | MEM 주소, WB 데이터, **MEM→EX 포워딩 소스** |
| `rs2_data` | 32 | rs2 데이터 (Store 데이터) | MEM Store 쓰기 데이터 |
| `pc_plus4` | 32 | PC+4 | WB JAL/JALR 복귀 주소 전달 |
| `rd_addr` | 5 | rd 레지스터 번호 | WB 쓰기 주소, **포워딩 소스 식별** |
| `zero` | 1 | ALU 제로 플래그 | BEQ 분기 조건 판단 (Ch11 사용) |
| `branch_taken` | 1 | 분기 성립 여부 | MEM에서 PC 플러시 제어 (Ch11) |
| *제어 신호* | — | MEM, WB용 제어 신호 (mem_read, mem_write, reg_write, mem_to_reg) | — |

**MEM/WB 레지스터 (MEM 스테이지 출력 → WB 스테이지 입력)**

| 필드 | 비트폭 | 설명 | Ch10 활용 |
|------|--------|------|-----------|
| `read_data` | 32 | DMEM 읽기 데이터 (Load 결과) | WB MUX 입력 |
| `alu_result` | 32 | EX ALU 결과 (R/I-type WB 데이터) | WB MUX 입력, **WB→EX 포워딩 소스** |
| `pc_plus4` | 32 | PC+4 | WB JAL/JALR 복귀 주소 |
| `rd_addr` | 5 | rd 레지스터 번호 | WB 쓰기 주소, **포워딩 소스 식별** |
| *제어 신호* | — | WB용 (reg_write, mem_to_reg) | — |

#### (3) Enable 신호 (스톨/플러시용, Ch10 준비)

각 파이프라인 레지스터에 다음 신호를 **9.4절에서 선언**하되, 9.5절에서는 항상 `enable=1`, `flush=0`으로 연결하여 단순 동작으로 검증한다:

| 레지스터 | Enable | Flush | Ch10 동작 |
|---------|--------|-------|-----------|
| IF/ID | `if_id_en` | `if_id_flush` | Load-Use 스톨 시 홀드, 분기 플러시 |
| ID/EX | `id_ex_en` | `id_ex_flush` | Load-Use 스톨 시 버블 삽입, 분기 플러시 |
| EX/MEM | `ex_mem_en` | `ex_mem_flush` | (보통 항상 enable) |
| MEM/WB | `mem_wb_en` | — | (플러시 불필요) |
| PC | `pc_en` | — | Load-Use 스톨 시 PC 홀드 |

**스톨(Stall) 구현 패턴**:
```systemverilog
// Load-Use 해저드 스톨 시:
// pc_en = 0       → PC 홀드 (같은 명령어 재인출)
// if_id_en = 0    → IF/ID 홀드 (같은 명령어 보존)
// id_ex_flush = 1 → ID/EX에 NOP 버블 삽입
// ex_mem_en = 1   → 정상 진행
// mem_wb_en = 1   → 정상 진행
```

**플러시(Flush) 구현 패턴**:
```systemverilog
// 분기 성립(branch taken) 플러시 시:
// if_id_flush = 1  → IF/ID를 NOP으로 클리어
// id_ex_flush = 1  → ID/EX를 NOP으로 클리어
// pc를 분기 목표 주소로 변경
```

**NOP 버블 값**: `if_id_flush` 또는 `id_ex_flush` 인가 시 레지스터를 다음 값으로 초기화:
- `instr` = 32'h0000_0013 (ADDI x0, x0, 0 — 공식 NOP)
- 제어 신호: 모두 0 (reg_write=0, mem_read=0, mem_write=0)
- `rd_addr` = 5'b00000 (x0, 포워딩 조건 오동작 방지)

---

### 9.5절 기술 요구사항 — 해저드 없는 기본 파이프라인

#### NOP 삽입 방식의 기술적 검증 방법

**테스트 프로그램 구조**:
```asm
# 각 명령어 사이에 NOP(ADDI x0, x0, 0)을 4개 삽입
# → 파이프라인 깊이(5단계) - 1 = 4개 NOP이면 모든 해저드 방지
ADDI x1, x0, 10    # x1 = 10
NOP                 # (4개 반복)
NOP
NOP
NOP
ADDI x2, x0, 20    # x2 = 20
NOP (×4)
ADD  x3, x1, x2    # x3 = 30 (해저드 없음)
```

**파형에서 확인해야 할 항목**:

1. **파이프라인 채움(Fill) 단계**: 첫 5사이클 동안 IF/ID/EX/MEM/WB 스테이지가 순서대로 채워지는 파형 확인.
2. **제어 신호 전파**: ID에서 생성된 제어 신호가 EX/MEM/WB 스테이지까지 올바른 스테이지에서 사용되는지 확인.
3. **레지스터 파일 쓰기 타이밍**: WB 스테이지 클럭 에지에서 rd에 데이터가 기록되는지.
4. **IMEM/DMEM 포트 분리**: IF와 MEM이 동시에 동작할 때 두 메모리가 독립적으로 응답하는지.
5. **PC 증가**: 매 사이클 PC가 +4씩 증가하는지.

**최소 검증 명령어 집합** (NOP 없이 해저드가 발생하지 않는 조합으로 구성):
```asm
ADDI x1, x0, 1    # x1 = 1
ADDI x2, x0, 2    # x2 = 2 (x1과 rd/rs1 충돌 없음)
ADDI x3, x0, 3    # x3 = 3
ADDI x4, x0, 4    # x4 = 4
ADD  x5, x1, x2   # x5 = 3 (NOP 없이도 x1/x2가 WB 완료)
SW   x5, 0(x0)    # mem[0] = 3
NOP (×5)
LW   x6, 0(x0)    # x6 = 3 (Load 결과 확인)
```

**시뮬레이션 검증 절차**:
1. Vivado 시뮬레이터 또는 VCS에서 100ns 이상 시뮬레이션.
2. `if_id_instr`, `id_ex_ctrl`, `ex_mem_alu_result`, `mem_wb_rd_data` 신호를 파형으로 관찰.
3. 각 명령어가 5 클럭 사이클 후 WB를 완료하는지 확인.
4. `x5`의 최종 값이 3인지, `x6`의 최종 값이 3인지 `$display`로 확인.

---

### 9.6절 기술 요구사항 — 요약 및 다음 단계

자가 점검 질문 (기술 리뷰어 제안):
1. 파이프라인 레지스터 IF/ID에 `pc`와 `pc_plus4`를 모두 저장하는 이유는?
2. ID/EX 레지스터에 `rs1_addr`, `rs2_addr`를 저장해야 하는 이유는?
3. `flush` 신호가 인가될 때 파이프라인 레지스터에 저장되는 NOP의 공식 인코딩은?
4. 파이프라인에서 Harvard 구조가 필요한 이유는?
5. 이상적 CPI=1이 실현되려면 어떤 조건이 충족되어야 하는가?

---

## 2. 필수 SVG 목록

### SVG-1: FSM 상태도 ↔ 파이프라인 타이밍 다이어그램 비교
**파일명**: `figures/ch09_sec01_fsm_vs_pipeline.svg`
**위치**: 9.1절

**구성 요소**:
- **왼쪽 패널 (FSM 멀티사이클)**:
  - 가로축: 클럭 사이클 (Cycle 1~12)
  - 세로 행: 단일 명령어 Instr_A의 상태 전이 (S_IF → S_ID → S_EX → S_WB)
  - 각 사이클에 상태 이름 표시 (색상: Ch08 FSM 상태 색상과 일치)
  - 사이클 12까지 Instr_B가 시작되지 않음 (순차 실행)
  - 하단에 "한 번에 하나의 명령어만 실행 중" 주석

- **오른쪽 패널 (파이프라인)**:
  - 가로축: 클럭 사이클 (Cycle 1~9)
  - 세로 행: Instr_A, Instr_B, Instr_C, Instr_D, Instr_E (5개 명령어)
  - 각 명령어가 한 칸씩 오른쪽으로 이동하며 IF/ID/EX/MEM/WB 스테이지 표시
  - Cycle 5부터 5개 명령어가 동시에 실행 중인 구간 강조 (노란색 배경)
  - 하단에 "Cycle 5부터 매 사이클 1개 명령어 완료" 주석

- **중앙 비교 화살표**:
  - FSM: "3명령어 완료 = 12사이클"
  - 파이프라인: "3명령어 완료 = 7사이클 (NOP 없는 이상적 조건)"

- **색상 코드**: IF=#DBEAFE(연청), ID=#BBF7D0(연녹), EX=#FEF3C7(연노랑), MEM=#FCE7F3(연분홍), WB=#F3E8FF(연보라)

### SVG-2: 파이프라인 데이터패스 전체 블록 다이어그램
**파일명**: `figures/ch09_sec03_pipeline_datapath.svg`
**위치**: 9.3절

**구성 요소**:
- 5개 스테이지를 세로 점선으로 구분 (IF | ID | EX | MEM | WB)
- 각 스테이지 내 핵심 하드웨어 모듈: IMEM(IF), 레지스터파일+즉치수생성기(ID), ALU+MUX(EX), DMEM(MEM), WB MUX(WB)
- 파이프라인 레지스터 4개를 세로 회색 블록으로 표시: IF/ID, ID/EX, EX/MEM, MEM/WB
- 각 파이프라인 레지스터 내 주요 필드 레이블: `instr`, `pc`, `rs1_data`, `rs2_data`, `rd_addr`, `alu_result` 등
- 제어 신호 버스: ID 스테이지에서 파이프라인 레지스터를 통해 WB까지 전달되는 경로 (회색 점선 화살표)
- WB→ID 피드백 경로: 레지스터 파일 쓰기 포트 → ID 읽기 포트 (Ch12 WB-ID 포워딩 예고, 점선 표시)
- 상단 범례: 색상 의미 (데이터 경로 = 파란색, 제어 경로 = 회색, 파이프라인 레지스터 = 진회색)

### SVG-3: 파이프라인 레지스터 필드 상세도
**파일명**: `figures/ch09_sec04_pipeline_regs_detail.svg`
**위치**: 9.4절

**구성 요소**:
- IF/ID, ID/EX, EX/MEM, MEM/WB 4개 레지스터를 사각형 테이블로 표시
- 각 레지스터의 모든 필드를 행으로 나열 (필드명, 비트폭)
- Enable/Flush 신호 입력을 레지스터 좌측에 표시
- 각 필드의 "사용 스테이지"를 색상으로 구분 (EX용=노랑, MEM용=분홍, WB용=보라)
- Ch10에서 추가될 포워딩 관련 필드(`rs1_addr`, `rs2_addr`, `rd_addr`)를 점선 테두리로 강조하며 "Ch10 포워딩 유닛이 이 필드를 참조" 주석 추가

---

## 3. 필수 코드 예제 목록

### 코드-1: 파이프라인 레지스터 IF/ID 선언 및 동작
**위치**: 9.4절
**핵심 패턴**:
```systemverilog
// IF/ID 파이프라인 레지스터
// 동기 리셋, Enable(스톨), Flush(NOP 삽입) 지원
module if_id_reg (
   input  logic        clk,
   input  logic        rst,
   // 스톨/플러시 제어 (Ch10에서 실제 연결)
   input  logic        en,       // 1=정상 동작, 0=홀드(스톨)
   input  logic        flush,    // 1=NOP 버블 삽입
   // IF 스테이지 입력
   input  logic [31:0] if_instr,
   input  logic [31:0] if_pc,
   input  logic [31:0] if_pc_plus4,
   // ID 스테이지 출력
   output logic [31:0] id_instr,
   output logic [31:0] id_pc,
   output logic [31:0] id_pc_plus4
);
   localparam NOP = 32'h0000_0013; // ADDI x0, x0, 0

   always_ff @(posedge clk) begin
      if (rst || flush) begin
         id_instr    <= NOP;
         id_pc       <= 32'd0;
         id_pc_plus4 <= 32'd0;
      end else if (en) begin
         id_instr    <= if_instr;
         id_pc       <= if_pc;
         id_pc_plus4 <= if_pc_plus4;
      end
      // en=0이면 값 유지 (스톨)
   end
endmodule
```
**교육 포인트**:
- `rst || flush` 조건에서 NOP 삽입: 리셋과 플러시를 동일 메커니즘으로 처리
- `else if (en)`: Enable 없이 홀드(스톨) 구현
- `NOP = 32'h0000_0013`: 공식 ADDI x0, x0, 0 인코딩 (단순 32'd0 금지 이유 설명 필요)

### 코드-2: ID/EX 파이프라인 레지스터 — 제어 신호 포함
**위치**: 9.4절
**핵심 패턴**: 제어 신호를 구조체 또는 개별 필드로 전달하는 두 가지 패턴을 모두 제시할 것.

```systemverilog
// 방법 A: 개별 필드 나열 (교육 목적 — 가시성 높음)
// 방법 B: struct packed 사용 (실무 — 유지보수성 높음)

// 방법 B 예시:
typedef struct packed {
   logic       alu_src_a;    // EX용
   logic       alu_src_b;    // EX용
   logic [3:0] alu_control;  // EX용
   logic       branch;       // EX용
   logic       mem_read;     // MEM용 (해저드 감지에 사용)
   logic       mem_write;    // MEM용
   logic       reg_write;    // WB용 (포워딩 조건에 사용)
   logic [1:0] mem_to_reg;   // WB용
   logic       jump;         // WB용
} ctrl_t;
```

> **합성 주의**: `typedef struct packed`는 IEEE 1800-2017 표준이며 Vivado에서 합성 가능. 단, 구조체가 파이프라인 레지스터 경계를 넘을 때 Vivado의 구조체 분해 방식을 검증해야 함.

### 코드-3: 파이프라인 최상위(Top) 연결 골격
**위치**: 9.5절
**핵심 패턴**: 5개 스테이지 모듈과 4개 파이프라인 레지스터를 연결하는 최상위 모듈의 신호 선언 및 연결 구조. (Ch10에서 포워딩/스톨 로직이 추가되는 자리 표시)

```systemverilog
module rv32i_pipeline_top (
   input  logic        clk,
   input  logic        rst,
   // IMEM 인터페이스 (Harvard 구조)
   output logic [31:0] imem_addr,
   input  logic [31:0] imem_rdata,
   // DMEM 인터페이스
   output logic [31:0] dmem_addr,
   output logic [31:0] dmem_wdata,
   output logic        dmem_wen,
   input  logic [31:0] dmem_rdata
);
   // 파이프라인 레지스터 간 신호 선언
   // IF/ID
   logic [31:0] if_id_instr, if_id_pc, if_id_pc_plus4;
   // ID/EX
   logic [31:0] id_ex_rs1_data, id_ex_rs2_data, id_ex_imm_ext;
   logic [31:0] id_ex_pc, id_ex_pc_plus4;
   logic [4:0]  id_ex_rs1_addr, id_ex_rs2_addr, id_ex_rd_addr;
   ctrl_t       id_ex_ctrl;
   // EX/MEM, MEM/WB ...

   // 스톨/플러시 제어 (Ch10에서 연결 — 현재는 디폴트)
   logic pc_en       = 1'b1;  // TODO: Ch10 해저드 감지 유닛 연결
   logic if_id_en    = 1'b1;  // TODO
   logic if_id_flush = 1'b0;  // TODO
   logic id_ex_flush = 1'b0;  // TODO
   // ...
endmodule
```

### 코드-4: IMEM 및 DMEM — Harvard 구조 분리 구현
**위치**: 9.3절 또는 9.5절
**핵심 패턴**:
```systemverilog
// 명령어 메모리: 읽기 전용, 조합 논리 출력 (단일 사이클 지연 없음)
module imem (
   input  logic [31:0] addr,
   output logic [31:0] instr
);
   logic [31:0] mem [0:1023]; // 4KB
   initial $readmemh("program.hex", mem);
   assign instr = mem[addr[11:2]]; // 조합 논리 읽기
endmodule

// 데이터 메모리: 동기 읽기/쓰기
module dmem (
   input  logic        clk,
   input  logic [31:0] addr,
   input  logic [31:0] wdata,
   input  logic        wen,
   output logic [31:0] rdata
);
   logic [31:0] mem [0:1023]; // 4KB
   always_ff @(posedge clk)
      if (wen) mem[addr[11:2]] <= wdata;
   assign rdata = mem[addr[11:2]]; // 비동기 읽기 (LUTRAM 추론)
endmodule
```

> **합성 주의**: IMEM을 조합 논리로 구현하면 Vivado가 LUTRAM으로 추론한다. 4KB = 1024×32비트 LUTRAM은 Basys 3의 LUT 자원을 상당량 소모한다. BRAM으로 추론하려면 동기 읽기(`always_ff`)로 변경해야 하나, 1사이클 지연이 발생하여 클럭 주파수 계획에 영향을 준다. 교재에서 이 트레이드오프를 설명할 것.

---

## 4. 기술적 위험 요소 (Critical/Major)

### 🔴 Critical

**[C1] 파이프라인 레지스터 NOP 버블 값 오류**
- **문제**: 초보자가 flush 시 파이프라인 레지스터를 단순히 `0`으로 클리어하면, opcode=0은 RISC-V에서 `LOAD` 계열 명령어(opcode=0000000은 예약/불법)로 잘못 디코딩되거나 제어 신호가 예상치 못한 값이 된다.
- **올바른 NOP**: `32'h0000_0013` (ADDI x0, x0, 0). 이 인코딩의 opcode=7'b0010011(I-type 연산), rd=5'b00000(x0), funct3=3'b000(ADDI), rs1=5'b00000(x0), imm=12'd0.
- **왜 중요한가**: NOP을 올바르게 설정하지 않으면 Ch10에서 포워딩 유닛이 잘못된 rd_addr(0이 아닌 값)를 포워딩 소스로 감지하거나, 제어 신호 오류로 예상치 못한 메모리 쓰기가 발생할 수 있다.
- **예방**: 9.4절 코드에서 `localparam NOP = 32'h0000_0013;`을 명시적으로 선언하고, 이유를 설명하는 aside 박스 추가.

**[C2] ID/EX 레지스터에 rs1_addr, rs2_addr 미포함**
- **문제**: 포워딩 유닛(Ch10)은 EX 스테이지의 rs1_addr, rs2_addr와 EX/MEM, MEM/WB의 rd_addr를 비교하여 포워딩 여부를 결정한다. 9.4절에서 ID/EX 레지스터에 이 필드를 선언하지 않으면 Ch10에서 파이프라인 레지스터 구조를 전면 수정해야 한다.
- **예방**: 9.4절 ID/EX 레지스터 설계에 `rs1_addr`, `rs2_addr` 필드를 명시적으로 포함시키고, "이 필드는 Ch10 포워딩 유닛에서 사용됩니다"라는 주석 추가.

**[C3] Harvard 구조 전환 미설명**
- **문제**: Ch07~08의 Princeton 구조(통합 메모리)에서 파이프라인으로 전환 시 IF와 MEM 스테이지가 동시에 메모리에 접근하므로 구조적 해저드 발생. 이를 설명하지 않고 단순히 IMEM/DMEM을 분리하면 "왜 분리했는가?"가 불명확하다.
- **예방**: 9.3절에서 "IF와 MEM이 동시에 메모리를 사용하면?"이라는 FAQ aside를 배치하고, 구조적 해저드를 타이밍 다이어그램으로 시각화.

**[C4] 동기 리셋 vs 비동기 리셋 혼용 금지**
- **문제**: 일부 레지스터에 동기 리셋, 다른 레지스터에 비동기 리셋을 혼용하면 Vivado 타이밍 분석에서 리셋 경로가 두 도메인으로 분리되어 복잡성 증가. 더 심각하게는, 비동기 리셋의 글리치(glitch)가 파이프라인 레지스터를 예기치 않은 시점에 리셋시킬 수 있다.
- **예방**: 9.4절에서 "이 교재의 모든 파이프라인 레지스터는 동기 리셋을 사용합니다"를 명시하고, PC 레지스터만 비동기 리셋이 허용되는 예외 케이스임을 설명.

---

### 🟡 Major

**[M1] IMEM 조합 논리 읽기 vs 동기 BRAM 읽기 결정**
- **문제**: IMEM을 조합 논리로 구현하면 Basys 3에서 LUTRAM으로 추론되어 LUT 자원을 많이 사용하고, 읽기 지연이 길어 클럭 주파수에 영향을 준다. 동기 BRAM으로 구현하면 1사이클 지연이 생겨 IF 스테이지가 2사이클이 되거나, PC 레지스터와 IF/ID 레지스터 사이에 버퍼 사이클이 필요하다.
- **교재 권장**: 9장에서는 교육적 단순성을 위해 조합 논리 IMEM(LUTRAM 추론)을 사용하고, Ch20(합성 최적화)에서 BRAM 기반 IMEM으로 교체하는 과정을 설명.

**[M2] 파이프라인 레지스터 필드 버스 폭 계산**
- IF/ID: 32+32+32 = 96비트 (NOP 포함 시 그대로)
- ID/EX: 32+32+32+32+32+5+5+5+제어신호 ≈ 160~180비트 + 제어 신호
- EX/MEM: 32+32+32+5+1+1+제어신호 ≈ 100~120비트
- MEM/WB: 32+32+32+5+제어신호 ≈ 100비트

이 버스 폭이 Vivado 합성 시 FF 자원을 얼마나 소모하는지 확인 필요. Basys 3의 FF 41,600개 기준으로 파이프라인 레지스터 전체 약 600~700 FF → 문제없음. 교재에서 간략히 언급.

**[M3] `typedef struct packed` 사용 여부 결정**
- 제어 신호를 구조체로 전달하는 방식은 코드 가독성을 높이나, 초보자에게는 낯설 수 있음. 개별 필드 나열과 구조체 방식을 모두 제시하고 교재에서 하나를 선택하여 일관성 유지.
- **권장**: 9.4절에서 개별 필드 방식으로 먼저 설명하고, `struct` 방식을 선택적 심화로 제시.

**[M4] PC 레지스터 위치 — IF 스테이지 상태 요소**
- PC 레지스터는 파이프라인의 "IF 스테이지 상태"이며, 파이프라인 레지스터(IF/ID)와 구분된다. 많은 초보자가 PC를 IF/ID 레지스터의 일부로 오해한다.
- 9.3절 SVG에서 PC 레지스터를 IF/ID 파이프라인 레지스터 **외부**(IF 스테이지 내부)에 명확히 표시할 것.

**[M5] 분기 처리 위치 결정 — 9.5절 범위**
- 9.5절의 "NOP 삽입으로 우선 동작 확인" 범위에서 분기 명령어(B-type)를 어떻게 처리할 것인지 명시해야 한다.
- **권장**: 9.5절에서는 분기 명령어를 테스트 프로그램에서 제외하거나, 분기 판정을 WB 스테이지로 미루는 단순 구현(4사이클 NOP 필요)으로 처리하고 실제 분기 처리는 Ch11에서 다룸을 명시.
- 분기 명령어가 NOP 없이 실행되면 3~4사이클 페널티가 발생하는데, 9.5절에서는 이를 NOP 4개 삽입으로 우회하는 방식 설명.

---

## 5. 권장사항

### 5.1 Ch08 → Ch09 연속성 확보

Ch08 FSM의 중간 레지스터(IR, A, B, ALUOut, MDR)와 Ch09 파이프라인 레지스터의 대응 관계를 9.1절에서 명확히 표로 제시할 것:

| Ch08 FSM 중간 레지스터 | Ch09 파이프라인 레지스터 | 역할 |
|----------------------|----------------------|------|
| IR (Instruction Register) | IF/ID.instr | 명령어 보관 |
| A 레지스터 (rs1_data) | ID/EX.rs1_data | rs1 값 보관 |
| B 레지스터 (rs2_data) | ID/EX.rs2_data | rs2 값 보관 |
| ALUOut 레지스터 | EX/MEM.alu_result | EX 결과 보관 |
| MDR (Memory Data Register) | MEM/WB.read_data | 메모리 읽기 결과 보관 |
| PC 레지스터 | PC 레지스터 + IF/ID.pc | PC 전파 |

### 5.2 코드 예제 순서

9.4절 코드 제시 순서:
1. PC 레지스터 (가장 단순)
2. IF/ID 레지스터 (NOP, Enable, Flush 패턴 도입)
3. ID/EX 레지스터 (제어 신호 포함, 필드 많음)
4. EX/MEM 레지스터 (ALU 결과, 분기 신호)
5. MEM/WB 레지스터 (최단순)
6. 최상위 연결 골격

### 5.3 면접 연결 (TABLE_OF_CONTENTS.md 기준 1위 면접 주제)

"5단계 파이프라인 그리기 (IF/ID/EX/MEM/WB)"는 반도체 면접 빈출 1위. 9.3절 또는 9.4절에 `<aside class="interview">` 배치:
- 각 스테이지의 담당 작업 (한 문장씩)
- 각 파이프라인 레지스터의 주요 필드 (5~6개만)
- "파이프라인 레지스터는 왜 필요한가?" 답변 요령

### 5.4 멀티사이클 Princeton 메모리와의 명시적 단절

Ch07~08에서 사용한 `ch07_multicycle_datapath.sv`의 통합 메모리는 Ch09부터 사용하지 않는다. 9.1절 또는 9.3절 시작 부분에 "이 챕터부터는 명령어 메모리(IMEM)와 데이터 메모리(DMEM)를 분리합니다" 박스를 배치하고, 분리 이유를 구조적 해저드와 연결하여 설명.

### 5.5 Ch10 준비 aside 박스

9.4절 파이프라인 레지스터 코드 설명 이후에 `<aside class="tip">` 박스:
> "지금 선언한 `en`, `flush` 신호는 9.5절에서 항상 `en=1`, `flush=0`으로 연결합니다. Ch10에서 포워딩 유닛과 해저드 감지 유닛이 이 신호를 실제로 제어하게 됩니다. 지금은 '자리만 마련해 두는' 것이라고 이해하면 됩니다."

### 5.6 검증 순서 권장

9.5절 테스트벤치 작성 순서:
1. **R-type 전용**: ADD, SUB, AND, OR만 포함, NOP 4개 삽입
2. **I-type 포함**: ADDI, SLTI 추가
3. **Load/Store 포함**: LW, SW 추가 (메모리 접근 검증)
4. **전체 타입**: JAL, LUI, AUIPC, AUIPC까지 포함

각 단계에서 시뮬레이션 파형을 Verdi 또는 Vivado 파형 뷰어로 확인하여 순서대로 검증.

---

*작성: 기술 리뷰어 (Technical Reviewer)*
*검토 기반: RISC-V Unprivileged ISA Spec v20191213, IEEE 1800-2017 SystemVerilog, Xilinx Basys 3 Reference Manual, Chapter 08 확정 설계 (chapter08_final_approval.md)*
*다음 단계: 교육 설계자, 교육심리전문가, 교육전문강사 병렬 기획 리뷰 후 chapter09_meeting.md 종합 회의*
