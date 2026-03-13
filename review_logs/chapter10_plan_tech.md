# Ch10 기획 단계 기술 계획서 — 기술 리뷰어

**챕터**: Chapter 10 — 데이터 해저드와 포워딩
**리뷰어**: 기술 리뷰어 (Technical Reviewer)
**작성일**: 2026-03-11
**검토 기반**: Ch09 확정 설계 (chapter09_final_approval.md), RISC-V Unprivileged ISA Spec v20191213, IEEE 1800-2017, Xilinx Basys 3 Reference Manual, Patterson & Hennessy "Computer Organization and Design" 5th Ed.

---

## 개요

Chapter 10은 Ch09의 파이프라인 기반 위에 **포워딩 유닛(Forwarding Unit)**과 **해저드 감지 유닛(Hazard Detection Unit)**을 추가하여 데이터 해저드를 자동으로 해결하는 챕터이다. 이 챕터의 집필 품질은 세 가지 설계 결정의 정확성에 달려 있다:

1. **포워딩 조건의 완전성**: EX-EX 포워딩과 MEM-EX 포워딩의 조건 논리, x0 예외, 우선순위 규칙이 모두 정확해야 한다.
2. **Load-Use 해저드 감지 조건의 정밀성**: 단 1사이클 스톨을 정확히 감지하는 조건 — `mem_read`, `rd_addr`, `rs1_addr/rs2_addr` 비교의 완전한 논리.
3. **Enable/Flush 우선순위 확정**: `flush`가 `en`보다 항상 우선해야 하는 설계 근거 및 동시 인가 시 처리.

---

## 1. Ch09 설계 연속성 확인

### 활용 가능한 Ch09 인터페이스 (수정 없음)

Ch09에서 확정된 다음 인터페이스를 Ch10에서 그대로 활용한다:

| 파이프라인 레지스터 | 포워딩/스톨 관련 핵심 필드 | Ch10 활용 |
|------------------|------------------------|----------|
| ID/EX | `rs1_addr[4:0]`, `rs2_addr[4:0]`, `rd_addr[4:0]` | 포워딩 조건 비교, 해저드 감지 |
| ID/EX | `mem_read`, `reg_write`, `en`, `flush` | Load-Use 감지, 스톨 삽입 |
| EX/MEM | `alu_result[31:0]`, `rd_addr[4:0]`, `reg_write` | EX→EX 포워딩 소스 |
| MEM/WB | `alu_result[31:0]`, `read_data[31:0]`, `rd_addr[4:0]`, `reg_write`, `mem_to_reg` | MEM→EX 포워딩 소스 |
| PC | `pc_en` (현재 `1'b1` 고정) | Load-Use 스톨 시 PC 홀드 |
| IF/ID | `if_id_en` (현재 `1'b1` 고정) | Load-Use 스톨 시 IF/ID 홀드 |

> **Ch10 작업 범위**: `en=1'b1` 고정 연결 해제 → 해저드 감지 유닛 출력 연결. 파이프라인 레지스터 인터페이스 자체는 변경 없음.

---

## 2. 포워딩 유닛 조건 표 (완전한 정확한 조건)

### 2.1 포워딩 MUX 위치 및 신호 명명

포워딩 MUX는 **EX 스테이지 ALU 입력 앞**에 배치한다.

```
                  ┌─────────────────────────┐
                  │         EX Stage        │
ID/EX.rs1_data ──→│                         │
                  │  forward_a MUX          │
EX/MEM.alu_result→│  2'b01 ──────┐          │──→ ALU input A
MEM/WB.wb_data ──→│  2'b10 ──┐  ├──────────│
                  │           │  │          │
ID/EX.rs2_data ──→│  forward_b MUX          │
EX/MEM.alu_result→│  2'b01 ──────┐          │──→ ALU input B (또는 MEM stage Store data)
MEM/WB.wb_data ──→│  2'b10 ──┐  ├──────────│
                  └─────────────────────────┘
```

| 신호명 | 비트폭 | 2'b00 | 2'b01 | 2'b10 |
|--------|--------|-------|-------|-------|
| `forward_a` | 2 | ID/EX.rs1_data (레지스터 파일 값) | EX/MEM.alu_result (EX 스테이지 포워딩) | MEM/WB 단계의 WB 결과 (WB 스테이지 포워딩) |
| `forward_b` | 2 | ID/EX.rs2_data (레지스터 파일 값) | EX/MEM.alu_result (EX 스테이지 포워딩) | MEM/WB 단계의 WB 결과 (WB 스테이지 포워딩) |

> **중요**: `forward_a/b = 2'b10`일 때 포워딩되는 값은 `MEM/WB` 레지스터의 출력이며, Load 명령어의 경우 `read_data`, ALU 명령어의 경우 `alu_result`이다. 따라서 `mem_to_reg` MUX 이후의 최종 WB 값(`wb_data`)을 포워딩 소스로 사용해야 한다:
>
> ```systemverilog
> assign wb_data = (mem_wb_mem_to_reg == 2'b01) ? mem_wb_read_data :
>                  (mem_wb_mem_to_reg == 2'b10) ? mem_wb_pc_plus4  :
>                                                  mem_wb_alu_result;
> ```

### 2.2 EX-EX 포워딩 (MEM 스테이지에서 EX 스테이지로)

포워딩 경로: `EX/MEM.alu_result` → EX 스테이지 ALU 입력

**조건** (모든 조건을 AND 연결):

```
EX-EX Forward A 조건:
   (ex_mem_reg_write == 1'b1)          // 쓰기 명령어여야 함
   AND (ex_mem_rd_addr != 5'b00000)    // x0 포워딩 방지
   AND (ex_mem_rd_addr == id_ex_rs1_addr)  // 목적지와 소스 일치

→ forward_a = 2'b01
```

```
EX-EX Forward B 조건:
   (ex_mem_reg_write == 1'b1)
   AND (ex_mem_rd_addr != 5'b00000)
   AND (ex_mem_rd_addr == id_ex_rs2_addr)

→ forward_b = 2'b01
```

### 2.3 MEM-EX 포워딩 (WB 스테이지에서 EX 스테이지로)

포워딩 경로: `MEM/WB`의 WB 결과 값(`wb_data`) → EX 스테이지 ALU 입력

**조건** (EX-EX 포워딩이 성립하지 않는 경우에만 적용):

```
MEM-EX Forward A 조건:
   NOT (EX-EX Forward A 조건 성립)    // EX-EX 우선, 미성립 시만
   AND (mem_wb_reg_write == 1'b1)
   AND (mem_wb_rd_addr != 5'b00000)
   AND (mem_wb_rd_addr == id_ex_rs1_addr)

→ forward_a = 2'b10
```

```
MEM-EX Forward B 조건:
   NOT (EX-EX Forward B 조건 성립)
   AND (mem_wb_reg_write == 1'b1)
   AND (mem_wb_rd_addr != 5'b00000)
   AND (mem_wb_rd_addr == id_ex_rs2_addr)

→ forward_b = 2'b10
```

### 2.4 포워딩 우선순위: EX-EX > MEM-EX

**이유**: 동시에 두 포워딩 조건이 성립할 수 있는 경우가 존재한다.

```asm
ADD x1, x2, x3    # C1: EX 스테이지 (rd=x1, EX/MEM에 결과 저장)
ADD x1, x4, x5    # C2: EX 스테이지 (rd=x1, EX/MEM에 결과 저장)
ADD x6, x1, x7    # C3: EX 스테이지 — rs1=x1에 대해
                   # EX-EX: C2의 EX/MEM.alu_result (x1의 최신 값)
                   # MEM-EX: C1의 MEM/WB.alu_result (x1의 구 값)
```

C3가 필요한 x1의 값은 **C2의 결과(최신 값)**이다. 따라서 EX-EX 포워딩이 MEM-EX보다 우선해야 한다.

**구현**: `if-else if` 구조로 EX-EX를 먼저 검사:

```systemverilog
// forward_a 결정 (우선순위: EX-EX > MEM-EX > 레지스터 파일)
always_comb begin
   if (ex_mem_reg_write && (ex_mem_rd_addr != 5'b0) &&
       (ex_mem_rd_addr == id_ex_rs1_addr))
      forward_a = 2'b01;  // EX-EX 포워딩
   else if (mem_wb_reg_write && (mem_wb_rd_addr != 5'b0) &&
            (mem_wb_rd_addr == id_ex_rs1_addr))
      forward_a = 2'b10;  // MEM-EX 포워딩
   else
      forward_a = 2'b00;  // 레지스터 파일 값 사용
end
```

### 2.5 포워딩이 필요하지 않은 경우 (forward_a/b = 2'b00)

- `ex_mem_reg_write == 0` (EX/MEM의 명령어가 레지스터에 쓰지 않음)
- `ex_mem_rd_addr == 5'b00000` (x0에 쓰는 명령어 — RISC-V에서 x0은 항상 0)
- `ex_mem_rd_addr != id_ex_rs1_addr` (목적지-소스 레지스터 불일치)
- 위와 동일한 MEM-EX 조건 미성립

---

## 3. Load-Use 해저드 감지 조건 (완전한 정확한 조건)

### 3.1 Load-Use 해저드 발생 상황

```asm
LW x1, 0(x2)     # C1: ID 스테이지 (결과 x1은 MEM 스테이지인 C4에서야 확보)
ADD x3, x1, x4   # C2: ID 스테이지 — x1이 필요하지만 아직 없음
                   # → 포워딩으로 해결 불가 (데이터가 MEM/WB 이전에 없음)
```

- LW가 EX 스테이지: `load_val`이 DMEM에서 나오는 것은 MEM 스테이지 완료 후
- ADD가 동시에 ID 스테이지: EX 스테이지 진입 전에 데이터가 필요
- EX-EX 포워딩 경로 자체가 없음 (`EX/MEM.alu_result`는 메모리 주소이지 읽은 데이터가 아님)
- **반드시 1사이클 스톨(버블 삽입) 후 MEM-EX 포워딩으로 해결**

### 3.2 해저드 감지 조건 (완전한 조건)

```
Load-Use 해저드 감지 조건:
   (id_ex_mem_read == 1'b1)                           // LW/LH/LB/LHU/LBU 명령어 (Load 계열)
   AND (
      (id_ex_rd_addr == if_id_rs1_addr)               // Load의 목적지 = 다음 명령어의 rs1
      OR
      (id_ex_rd_addr == if_id_rs2_addr)               // Load의 목적지 = 다음 명령어의 rs2
   )
```

> **중요 세부사항**: `if_id_rs1_addr`와 `if_id_rs2_addr`는 IF/ID 레지스터에 보관된 `instr[19:15]`와 `instr[24:20]`을 직접 참조한다. 별도 필드로 저장할 필요는 없으나, 가독성을 위해 해저드 감지 유닛 내부에서 로컬 신호로 명명한다:
>
> ```systemverilog
> logic [4:0] if_id_rs1_addr = if_id_instr[19:15];
> logic [4:0] if_id_rs2_addr = if_id_instr[24:20];
> ```

> **x0 예외 처리**: `id_ex_rd_addr == 5'b00000` (LW x0, ...)인 경우는 실질적으로 아무 의미 없는 명령어이지만, 조건 논리상 감지될 수 있다. `id_ex_rd_addr != 5'b00000` 조건을 해저드 감지에도 추가하는 것이 방어적 설계이다:
>
> ```
> Load-Use 해저드 감지 조건 (방어적 버전):
>    (id_ex_mem_read == 1'b1)
>    AND (id_ex_rd_addr != 5'b00000)        // x0 예외
>    AND (
>       (id_ex_rd_addr == if_id_rs1_addr)
>       OR
>       (id_ex_rd_addr == if_id_rs2_addr)
>    )
> ```

### 3.3 스톨 동작 — 3가지 동시 신호

Load-Use 해저드 감지 시 다음 3가지 신호를 **동시에** 인가한다:

| 신호 | 값 | 동작 | 이유 |
|------|-----|------|------|
| `pc_en` | 0 | PC 홀드 (현재 값 유지) | 다음 클럭에 같은 명령어를 다시 인출 |
| `if_id_en` | 0 | IF/ID 레지스터 홀드 | 현재 IF/ID 내용 (ADD 명령어) 유지 |
| `id_ex_flush` | 1 | ID/EX에 NOP 버블 삽입 | LW 뒤에 1사이클 버블 삽입 (파이프라인 지연) |

**동작 설명**:
- `pc_en=0`: PC가 다음 사이클에 같은 값 유지 → 같은 명령어 재인출
- `if_id_en=0`: IF/ID 레지스터가 현재 ADD를 계속 보유
- `id_ex_flush=1`: ID/EX에 NOP(모든 제어 신호=0, rd_addr=x0) 삽입

**1사이클 스톨 후 상태**:
- 스톨 발생 사이클: LW가 MEM 스테이지 진입, ADD가 ID에서 재실행
- 스톨 해제 다음 사이클: LW가 WB, ADD가 EX 진입 → MEM-EX 포워딩으로 해결

### 3.4 NOP 버블 값 (Load-Use 스톨 시 ID/EX 삽입 값)

`id_ex_flush=1` 인가 시 ID/EX 레지스터에 저장되는 값:

| 필드 | 값 | 설명 |
|------|-----|------|
| `rs1_data`, `rs2_data` | 32'h0 | ALU 연산 없음 |
| `imm_ext` | 32'h0 | 즉치수 없음 |
| `rd_addr` | 5'b00000 (x0) | 포워딩 조건 오동작 방지 |
| `rs1_addr`, `rs2_addr` | 5'b00000 | 포워딩 조건 오동작 방지 |
| `alu_src_a` | 0 | — |
| `alu_src_b` | 0 | — |
| `alu_control` | 4'b0000 | ADD 연산 (ADD x0,x0,x0 = NOP) |
| `branch` | 0 | 분기 없음 |
| `mem_read` | **0** | 연속 Load-Use 해저드 방지 필수 |
| `mem_write` | **0** | 잘못된 메모리 쓰기 방지 필수 |
| `reg_write` | **0** | x0에 쓰기 시도 방지 |
| `mem_to_reg` | 2'b00 | — |
| `jump` | 0 | — |

> **Critical 주의**: `mem_read=0` 설정이 필수이다. 버블에 `mem_read=1`이 남아 있으면 해저드 감지 유닛이 다음 사이클에도 같은 조건을 감지하여 무한 스톨에 빠진다.

---

## 4. 스톨/플러시 우선순위

### 4.1 flush가 en보다 항상 우선

**설계 결정**: `flush`가 `en`보다 우선한다.

```systemverilog
// 파이프라인 레지스터의 우선순위 로직
always_ff @(posedge clk) begin
   if (rst || flush) begin
      // NOP 버블 삽입 (flush > en)
      ...
   end else if (en) begin
      // 정상 진행
      ...
   end
   // else: en=0 → 홀드 (스톨)
end
```

**근거**:
1. **분기 플러시(Ch11)**는 잘못 인출된 명령어를 즉시 무효화해야 한다. 이때 스톨(en=0)이 동시에 인가되더라도 flush가 우선해야 파이프라인이 올바른 상태로 복구된다.
2. **Load-Use 스톨 + 분기 플러시 동시 발생**: 실제로 Load-Use 스톨이 발생한 직후 분기 명령어가 MEM 스테이지에서 `branch_taken=1`을 생성하면 동시 인가가 발생할 수 있다. 이 경우 flush 우선이 올바른 처리이다.
3. **Xilinx FPGA 관점**: Vivado는 `if (rst || flush)` 패턴에서 reset과 동일한 경로로 합성하며, `en`은 `CE(Clock Enable)` 핀에 매핑된다. flush가 reset과 동일 처리되므로 FDRE 타이밍 모델과 일치한다.

### 4.2 Load-Use 스톨 vs 분기 플러시 동시 인가 시나리오

Ch10 범위에서는 분기 플러시를 직접 다루지 않지만, 설계 문서에 미래 충돌 가능성을 명시해야 한다:

| 상황 | `id_ex_flush` | `if_id_en` | `pc_en` | 처리 |
|------|-------------|------------|---------|------|
| 정상 동작 | 0 | 1 | 1 | 정상 진행 |
| Load-Use 스톨 | 1 | 0 | 0 | 버블 삽입 + 홀드 |
| 분기 플러시 (Ch11) | 1 | 1 | 1 | 버블 삽입 (홀드 없음) |
| 동시 발생 | flush 우선 | flush 우선 | 스톨 우선 | flush=1 + en=0 → NOP 삽입 + PC 홀드 |

> **Ch10 집필 범위**: Load-Use 스톨만 구현. `if_id_flush`와 분기 관련 플러시는 Ch11에서 추가. 단, 최상위 모듈에 자리 예약은 Ch10에서 완료.

---

## 5. 포워딩 MUX 위치 및 연결 상세

### 5.1 ALU 입력 A MUX

```
EX Stage 내부:
┌─────────────────────────────────────┐
│  forward_a = 2'b00 → id_ex_rs1_data │
│  forward_a = 2'b01 → ex_mem_alu_result│ → MUX A 출력
│  forward_a = 2'b10 → wb_data        │
│                     (MEM/WB WB MUX 출력)│
└─────────────────────────────────────┘
MUX A 출력 → alu_src_a MUX
  alu_src_a = 0 → MUX A 출력 (rs1 또는 포워딩된 값)
  alu_src_a = 1 → id_ex_pc
```

### 5.2 ALU 입력 B MUX

```
EX Stage 내부:
┌─────────────────────────────────────┐
│  forward_b = 2'b00 → id_ex_rs2_data │
│  forward_b = 2'b01 → ex_mem_alu_result│ → MUX B 출력 (포워딩된 rs2)
│  forward_b = 2'b10 → wb_data        │
└─────────────────────────────────────┘
MUX B 출력 → alu_src_b MUX
  alu_src_b = 0 → MUX B 출력 (rs2 또는 포워딩된 값)
  alu_src_b = 1 → id_ex_imm_ext

MUX B 출력(포워딩된 rs2)은 Store 명령어의 메모리 쓰기 데이터로도 사용:
  EX/MEM.rs2_data = MUX B 출력 (포워딩 포함)
```

> **중요**: Store 명령어에서 rs2의 포워딩 값이 메모리에 쓰여야 한다. EX/MEM 레지스터의 `rs2_data` 필드는 포워딩 MUX 이후의 값을 저장해야 한다. 이를 위해 EX/MEM 레지스터에 저장하는 `rs2_data`를 `id_ex_rs2_data`가 아닌 `forward_b_out` (포워딩 MUX 출력)으로 변경해야 한다.

### 5.3 WB 단계의 포워딩 소스 (`wb_data`) 계산

```systemverilog
// WB 스테이지 — MEM/WB 출력에서 최종 WB 값 계산
logic [31:0] wb_data;
always_comb begin
   case (mem_wb_mem_to_reg)
      2'b00:   wb_data = mem_wb_alu_result;   // R/I-type
      2'b01:   wb_data = mem_wb_read_data;    // Load
      2'b10:   wb_data = mem_wb_pc_plus4;     // JAL/JALR
      default: wb_data = mem_wb_alu_result;
   endcase
end
```

---

## 6. 필수 SVG 다이어그램 목록

### SVG-1: 데이터 해저드 3가지 유형
**파일명**: `figures/ch10_sec01_hazard_types.svg`
**위치**: 10.1절

**구성 요소**:
- 3개 패널: RAW(Read After Write), WAR(Write After Read), WAW(Write After Write)
- 각 패널에 파이프라인 타이밍 다이어그램 (가로=사이클, 세로=명령어 순서)
- RAW: 의존 경로를 빨간 화살표로 강조, "RV32I 5단계 파이프라인에서 발생" 레이블
- WAR: "5단계 파이프라인에서는 발생하지 않음 — ID(읽기)가 항상 WB(쓰기)보다 이전 사이클" 설명
- WAW: "5단계 파이프라인에서는 발생하지 않음 — 한 번에 한 명령어만 WB 스테이지" 설명
- 하단 요약 박스: "RV32I 5단계 파이프라인에서 다루어야 할 해저드 = RAW만"

**색상**: RAW=빨간 강조 (#DC2626), WAR/WAW=회색 처리 (#9CA3AF)

### SVG-2: 포워딩 유닛 블록 다이어그램
**파일명**: `figures/ch10_sec02_forwarding_unit.svg`
**위치**: 10.2절

**구성 요소**:
- 5단계 파이프라인 전체 데이터패스 (ch09_sec03_five_stages.svg 기반 확장)
- `forwarding_unit` 모듈을 별도 블록으로 표시 (파란 테두리 박스)
- 포워딩 유닛 입력: `id_ex_rs1_addr`, `id_ex_rs2_addr`, `ex_mem_rd_addr`, `ex_mem_reg_write`, `mem_wb_rd_addr`, `mem_wb_reg_write`
- 포워딩 유닛 출력: `forward_a[1:0]`, `forward_b[1:0]`
- EX-EX 포워딩 경로: EX/MEM에서 EX 스테이지 ALU 입력으로 굵은 녹색 화살표
- MEM-EX 포워딩 경로: MEM/WB에서 EX 스테이지 ALU 입력으로 굵은 오렌지 화살표
- 포워딩 MUX 2개 (forward_a용, forward_b용) 명시

### SVG-3: 포워딩 MUX 상세 연결도
**파일명**: `figures/ch10_sec02_forwarding_mux.svg`
**위치**: 10.2절

**구성 요소**:
- EX 스테이지 내부 상세도
- forward_a MUX (3입력: rs1_data / EX/MEM.alu_result / MEM/WB.wb_data)
- forward_b MUX (3입력: rs2_data / EX/MEM.alu_result / MEM/WB.wb_data)
- alu_src_a MUX, alu_src_b MUX와의 연결 관계 표시
- MUX 선택 신호 (forward_a/b 2비트 → 3입력 MUX 선택) 설명
- Store 명령어용 rs2 포워딩 경로 별도 표시 (EX/MEM.rs2_data로 전달되는 경로)

### SVG-4: Load-Use 해저드 타이밍 다이어그램
**파일명**: `figures/ch10_sec03_load_use_stall.svg`
**위치**: 10.3절

**구성 요소**:
- **위쪽 패널 (스톨 없이 실행 — 오류)**:
  - 가로=사이클(C1~C7), 세로=명령어(LW/ADD/후속)
  - C4: LW가 MEM 스테이지, ADD가 EX 스테이지 — x1이 없는 상태에서 실행됨
  - 빨간 X 표시: "x1 값 없음! 잘못된 ALU 연산"
- **아래쪽 패널 (1사이클 스톨 + MEM-EX 포워딩)**:
  - C3: LW(EX), ADD(ID) — 해저드 감지 발생
  - C4: LW(MEM), Bubble(EX), ADD(ID-재실행) — 스톨 버블 삽입
  - C5: LW(WB), Bubble(MEM), ADD(EX) — MEM-EX 포워딩으로 x1 전달
  - 포워딩 화살표: LW의 MEM/WB 출력 → ADD의 ALU 입력
  - 수직 강조선: "해저드 감지" (C3 → C4 경계), "스톨 해제" (C4 → C5 경계)

**색상**: 버블 셀 = 연회색 (#F3F4F6), 포워딩 화살표 = 오렌지 (#F59E0B)

### SVG-5: 스톨 제어 신호 타이밍 파형
**파일명**: `figures/ch10_sec04_stall_control.svg`
**위치**: 10.4절

**구성 요소**:
- 가로축: 클럭 사이클 (C1~C8)
- 파형 신호 목록 (위에서 아래로):
  - `clk` 클럭 파형
  - `pc` — C4에서 값 유지 (스톨)
  - `if_id_instr` — C4에서 ADD 명령어 값 유지 (홀드)
  - `pc_en` — C4에서 0 (나머지 1)
  - `if_id_en` — C4에서 0 (나머지 1)
  - `id_ex_flush` — C4에서 1 (나머지 0)
  - `id_ex_mem_read` — C3에서만 1 (LW가 ID/EX에 있을 때), C4(버블)에서 0
  - `forward_b` — C5에서 2'b10 (MEM-EX 포워딩)
- 스톨 구간 강조 박스 (C3~C4)
- 포워딩 구간 강조 (C5)

---

## 7. SystemVerilog 모듈 목록

### 7.1 forwarding_unit.sv

```systemverilog
module forwarding_unit (
   // ID/EX 레지스터 — 현재 EX 스테이지의 소스 레지스터 번호
   input  logic [4:0] id_ex_rs1_addr,
   input  logic [4:0] id_ex_rs2_addr,
   // EX/MEM 레지스터 — 바로 앞 명령어의 목적지 (EX-EX 포워딩 소스)
   input  logic [4:0] ex_mem_rd_addr,
   input  logic       ex_mem_reg_write,
   // MEM/WB 레지스터 — 2단계 앞 명령어의 목적지 (MEM-EX 포워딩 소스)
   input  logic [4:0] mem_wb_rd_addr,
   input  logic       mem_wb_reg_write,
   // 포워딩 MUX 선택 출력
   output logic [1:0] forward_a,    // ALU 입력 A 선택
   output logic [1:0] forward_b     // ALU 입력 B 선택
);
   // EX-EX / MEM-EX 포워딩 조건 (우선순위: EX-EX > MEM-EX > 레지스터 파일)
   always_comb begin
      // forward_a: ALU 입력 A (rs1)
      if (ex_mem_reg_write && (ex_mem_rd_addr != 5'b0) &&
          (ex_mem_rd_addr == id_ex_rs1_addr))
         forward_a = 2'b01;
      else if (mem_wb_reg_write && (mem_wb_rd_addr != 5'b0) &&
               (mem_wb_rd_addr == id_ex_rs1_addr))
         forward_a = 2'b10;
      else
         forward_a = 2'b00;

      // forward_b: ALU 입력 B (rs2)
      if (ex_mem_reg_write && (ex_mem_rd_addr != 5'b0) &&
          (ex_mem_rd_addr == id_ex_rs2_addr))
         forward_b = 2'b01;
      else if (mem_wb_reg_write && (mem_wb_rd_addr != 5'b0) &&
               (mem_wb_rd_addr == id_ex_rs2_addr))
         forward_b = 2'b10;
      else
         forward_b = 2'b00;
   end
endmodule
```

**설계 주의사항**:
- 순수 조합 논리 (`always_comb`) — 등록 소자 없음, 면적 최소
- `always_comb`는 감도 목록 자동 추론 (IEEE 1800-2017 §9.2.2.2)
- x0 조건 (`!= 5'b0`)이 반드시 포함되어야 함

### 7.2 hazard_detection_unit.sv

```systemverilog
module hazard_detection_unit (
   // ID/EX 레지스터 — 현재 EX 스테이지의 Load 명령어 정보
   input  logic [4:0] id_ex_rd_addr,
   input  logic       id_ex_mem_read,    // Load 계열 여부
   // IF/ID 레지스터 — 다음 명령어의 소스 레지스터 번호
   input  logic [4:0] if_id_rs1_addr,   // if_id_instr[19:15]
   input  logic [4:0] if_id_rs2_addr,   // if_id_instr[24:20]
   // 스톨 제어 출력
   output logic       stall,             // 내부 해저드 감지 신호
   output logic       pc_en,             // PC 홀드 (0=홀드)
   output logic       if_id_en,          // IF/ID 홀드 (0=홀드)
   output logic       id_ex_flush        // ID/EX 버블 삽입 (1=플러시)
);
   // Load-Use 해저드 감지
   assign stall = id_ex_mem_read &&
                  (id_ex_rd_addr != 5'b0) &&
                  ((id_ex_rd_addr == if_id_rs1_addr) ||
                   (id_ex_rd_addr == if_id_rs2_addr));

   // 스톨 시 제어 신호
   assign pc_en      = ~stall;  // 스톨 시 PC 홀드
   assign if_id_en   = ~stall;  // 스톨 시 IF/ID 홀드
   assign id_ex_flush = stall;  // 스톨 시 ID/EX 버블 삽입
endmodule
```

**설계 주의사항**:
- 조합 논리만 사용, 클럭 없음
- `pc_en`과 `if_id_en`은 동시에 0이어야 함 (둘 중 하나만 0이면 설계 오류)
- Ch11에서 분기 플러시(`if_id_flush`)를 추가할 때 이 모듈을 확장하거나 별도 분기 감지 유닛을 추가

### 7.3 rv32i_pipeline_top.sv (포워딩/스톨 통합)

Ch09의 `rv32i_pipeline_top.sv` 수정 범위:

```systemverilog
module rv32i_pipeline_top (
   input  logic        clk,
   input  logic        rst,
   output logic [31:0] imem_addr,
   input  logic [31:0] imem_rdata,
   output logic [31:0] dmem_addr,
   output logic [31:0] dmem_wdata,
   output logic        dmem_wen,
   input  logic [31:0] dmem_rdata
);
   // ── 기존 신호 선언 (Ch09 그대로 유지) ──
   // ... (파이프라인 레지스터 간 신호)

   // ── Ch10 신호 선언 ──
   logic [1:0] forward_a, forward_b;      // 포워딩 MUX 선택
   logic       pc_en, if_id_en;           // 스톨 제어 (Ch09: 1'b1 고정 → Ch10: 연결)
   logic       id_ex_flush_stall;         // Load-Use 스톨용 flush
   logic       id_ex_flush;               // 최종 flush (스톨 + 분기, Ch11에서 OR 추가)
   logic [31:0] wb_data;                  // WB 스테이지 최종 출력 (포워딩 소스)
   logic [31:0] forward_a_out, forward_b_out; // 포워딩 MUX 출력

   // ── WB 데이터 계산 ──
   always_comb begin
      case (mem_wb_ctrl.mem_to_reg)
         2'b01:   wb_data = mem_wb_read_data;
         2'b10:   wb_data = mem_wb_pc_plus4;
         default: wb_data = mem_wb_alu_result;
      endcase
   end

   // ── 포워딩 MUX ──
   assign forward_a_out = (forward_a == 2'b01) ? ex_mem_alu_result :
                           (forward_a == 2'b10) ? wb_data           :
                                                   id_ex_rs1_data;
   assign forward_b_out = (forward_b == 2'b01) ? ex_mem_alu_result :
                           (forward_b == 2'b10) ? wb_data           :
                                                   id_ex_rs2_data;

   // ── 포워딩 유닛 인스턴스 ──
   forwarding_unit u_forwarding (
      .id_ex_rs1_addr   (id_ex_rs1_addr),
      .id_ex_rs2_addr   (id_ex_rs2_addr),
      .ex_mem_rd_addr   (ex_mem_rd_addr),
      .ex_mem_reg_write (ex_mem_ctrl.reg_write),
      .mem_wb_rd_addr   (mem_wb_rd_addr),
      .mem_wb_reg_write (mem_wb_ctrl.reg_write),
      .forward_a        (forward_a),
      .forward_b        (forward_b)
   );

   // ── 해저드 감지 유닛 인스턴스 ──
   hazard_detection_unit u_hazard (
      .id_ex_rd_addr    (id_ex_rd_addr),
      .id_ex_mem_read   (id_ex_ctrl.mem_read),
      .if_id_rs1_addr   (if_id_instr[19:15]),
      .if_id_rs2_addr   (if_id_instr[24:20]),
      .stall            (),                      // 내부 신호, 연결 생략 가능
      .pc_en            (pc_en),
      .if_id_en         (if_id_en),
      .id_ex_flush      (id_ex_flush_stall)
   );

   // ── flush 최종 결합 (Ch11에서 분기 flush 추가 예정) ──
   assign id_ex_flush = id_ex_flush_stall; // TODO Ch11: | branch_flush
   // assign if_id_flush = 1'b0;           // TODO Ch11: branch_flush

   // ── 파이프라인 레지스터 en/flush 연결 (Ch09: 1'b1/1'b0 → Ch10: 실제 신호) ──
   // PC, IF/ID: pc_en, if_id_en 연결
   // ID/EX: id_ex_flush 연결
endmodule
```

---

## 8. Critical 기술 주의사항

### 8.1 [C1] x0 레지스터 포워딩 방지 조건 — 포워딩 유닛

**문제**: x0 레지스터(RISC-V 하드와이어드 0)에 대한 포워딩을 방지하지 않으면, ADDI x0, x0, 0 (NOP 버블)의 rd_addr=x0가 포워딩 소스로 잘못 감지될 수 있다.

**구체적 오류 시나리오**:
```asm
NOP (버블)         # rd_addr=x0, reg_write=0 (버블이므로 문제없음)
                   # 하지만 reg_write=1인 실제 명령어가 rd=x0이면?
ADD x0, x1, x2    # 합법적이지만 x0는 항상 0 (write-ignored)
ADD x3, x0, x4    # rs1=x0 → 포워딩 유닛이 ADD x0,x1,x2의 결과를 포워딩?
                   # 포워딩 조건: ex_mem_rd_addr==0 AND id_ex_rs1_addr==0 → TRUE!
                   # 실제로는 x0=0이어야 하므로 EX/MEM.alu_result(≠0)를 포워딩하면 오류
```

**해결책**: 포워딩 유닛의 모든 포워딩 조건에 `rd_addr != 5'b00000` 조건을 필수로 포함. 레지스터 파일에서 x0 읽기가 항상 0을 반환해도, 포워딩이 x0의 "결과"를 덮어쓰면 틀린 값이 사용된다.

**구현**: `forwarding_unit.sv`의 조건에 `(ex_mem_rd_addr != 5'b0)` 필수 포함 (위 코드에 반영됨).

### 8.2 [C2] Load-Use 홀드 방향 오류 가능성

**문제**: 초보자가 스톨 시 "무언가를 홀드"해야 한다는 것을 이해하지만, 어느 방향의 홀드인지 혼동할 수 있다.

**흔한 오류**:
1. `id_ex_en=0` (ID/EX를 홀드) → 올바르지 않음. ID/EX에는 버블을 삽입해야 함.
2. `ex_mem_en=0` (EX/MEM을 홀드) → 완전히 틀림. EX/MEM은 정상 진행해야 함.
3. `if_id_en=1` 유지하면서 `pc_en=0`만 변경 → IF/ID가 다음 사이클에 새 명령어로 덮임 (홀드 실패).

**올바른 방향**: PC와 IF/ID 레지스터가 **홀드**되어야 하고, ID/EX에는 **버블이 삽입**되어야 한다. "이미 처리 중인 명령어들(EX/MEM, MEM/WB)은 그대로 진행"시켜야 한다.

**교재 설명 권장**: 세탁소 비유 확장 — "세탁기(IF)와 세탁물 대기통(IF/ID)은 잠깐 멈추고, 건조기(EX)에는 빈 슬롯을 넣는다. 다림질(MEM)과 포장(WB)은 계속 진행."

### 8.3 [C3] flush/en 동시 인가 우선순위 설계 오류

**문제**: Ch09에서 확정된 코딩 패턴 `if (rst || flush) ... else if (en) ...`을 Ch10에서도 그대로 유지해야 한다. 만약 일부 파이프라인 레지스터에서 `en`과 `flush`의 우선순위가 다르게 구현되면 일관성 오류가 발생한다.

**위험 시나리오** (Ch11까지 고려):
```
Load-Use 스톨 발생 동시에 분기 taken 결정:
  id_ex_flush_stall = 1  (Load-Use)
  id_ex_flush_branch = 1 (분기 플러시, Ch11)
  → id_ex_flush = 1 (OR 결합 — 올바름)

  if_id_en = 0 (Load-Use 스톨)
  pc_en = 0    (Load-Use 스톨)
  branch_taken = 1 (분기 taken → PC = 분기 목표 주소로 변경해야 함)
  → 충돌: PC를 홀드해야 하나 분기 주소로 변경해야 하나?
  → 해결: 분기 taken이 Load-Use보다 우선 (분기 플러시가 스톨보다 우선)
         이 우선순위 결정은 Ch11에서 확정하지만 Ch10 설계 시 "TODO"로 명시 필요
```

**Ch10 집필 시 대응**: 10.4절에 `<aside class="tip">` 박스로 "Ch11에서 분기 flush와 스톨이 동시 발생하는 경우의 우선순위를 다룬다"는 예고를 추가하여 미래 설계 결정을 위한 자리 마련.

### 8.4 [C4] Store 명령어에서 rs2 포워딩 누락

**문제**: Store 명령어 (SW, SH, SB)에서 rs2가 메모리에 쓸 데이터이다. 포워딩 유닛이 `forward_b`를 정확히 계산하더라도, EX/MEM 레지스터에 저장되는 `rs2_data`가 포워딩된 값이 아닌 원래 레지스터 파일 값이면 틀린 데이터가 메모리에 쓰인다.

**오류 시나리오**:
```asm
ADD x5, x1, x2   # C1: x5 = x1 + x2
SW  x5, 0(x3)    # C2: mem[x3] = x5 — C1의 x5 값이 필요
                  # forward_b = 2'b01 (EX-EX 포워딩)
                  # ALU는 x3 + 0 = 주소 계산 (alu_src_b=1, imm=0)
                  # 하지만 rs2_data(메모리 쓰기 데이터)는 어디서?
```

**올바른 구현**: EX/MEM 레지스터에 저장하는 Store 데이터는 `id_ex_rs2_data`가 아닌 포워딩 MUX B의 출력(`forward_b_out`)이어야 한다:

```systemverilog
// EX/MEM 레지스터 - rs2_data 필드를 포워딩 이후 값으로 저장
ex_mem_rs2_data <= forward_b_out;  // NOT id_ex_rs2_data
```

### 8.5 [C5] 포워딩 우선순위 누락으로 인한 "오래된 값" 포워딩

**문제**: EX-EX 포워딩 조건과 MEM-EX 포워딩 조건이 동시에 성립할 때, MEM-EX 포워딩이 실행되면 1사이클 이전의 오래된 값이 사용된다.

**시나리오** (2.4절에서 설명):
```asm
ADD x1, x2, x3   # C1 → C3 WB (EX/MEM에서 rd=x1)
ADD x1, x4, x5   # C2 → C4 WB (WB/MEM 상에서 rd=x1, 이후 EX/MEM에서 rd=x1)
ADD x6, x1, x7   # C3 EX — rs1=x1에 두 포워딩 조건 동시 성립
                  # EX-EX: EX/MEM.rd=x1 (C2의 결과 = 최신)
                  # MEM-EX: MEM/WB.rd=x1 (C1의 결과 = 오래됨)
```

**해결책**: `if-else if` 구조 사용 (EX-EX 먼저 검사). `case` 문 또는 `if-if` (독립 if) 구조는 절대 사용 금지.

---

## 9. 절별 기술 요구사항 요약

### 10.1절 — 데이터 해저드의 3가지 유형

**핵심 기술 메시지**: "RV32I 5단계 파이프라인에서는 RAW 해저드만 발생한다."

**기술적으로 반드시 설명해야 할 내용**:

1. **RAW (Read After Write)**: 쓰기가 완료되기 전에 읽기가 발생. 5단계 파이프라인에서 ADD-ADD 연속 시 EX 스테이지에서 2~3사이클 차이로 데이터 의존이 발생.

2. **WAR (Write After Read)가 발생하지 않는 이유**: 5단계 파이프라인에서 ID 스테이지(레지스터 읽기)는 항상 EX/MEM/WB(레지스터 쓰기) 이전 스테이지이다. 순차적 명령어 흐름에서 후속 명령어의 쓰기는 항상 선행 명령어의 읽기보다 나중에 발생한다.

3. **WAW (Write After Write)가 발생하지 않는 이유**: 5단계 파이프라인에서 한 번에 한 명령어만 WB 스테이지에 있다. 두 명령어가 동시에 WB를 실행하는 일이 없다.

4. **구조적 해저드(Structural Hazard)는 Harvard 구조로 해결 완료**: Ch09에서 IMEM/DMEM 분리로 이미 해결됨. 10.1절에서 간략히 언급하고 이 챕터는 데이터 해저드에만 집중함을 명시.

5. **제어 해저드(Control Hazard)는 Ch11 주제**: 분기 명령어로 인한 해저드는 이 챕터에서 다루지 않음. 10.1절 끝에 "제어 해저드는 Ch11에서 다룬다"를 명시.

**RAW 해저드 3가지 케이스** (거리에 따른 분류):

| 케이스 | 명령어 거리 | 해결 방법 |
|--------|-----------|----------|
| EX-EX RAW | 바로 다음 명령어 (1칸 차이) | EX-EX 포워딩 |
| MEM-EX RAW | 2칸 차이 | MEM-EX 포워딩 |
| Load-Use RAW | LW 바로 다음 명령어 | 1사이클 스톨 + MEM-EX 포워딩 |
| WB-ID RAW | 3칸 차이 (ALU 명령어) | WB-ID 포워딩 (레지스터 파일 내부, Ch12에서 상세 처리) |

> **Ch10 범위 명시**: 10절에서는 EX-EX 포워딩, MEM-EX 포워딩, Load-Use 스톨을 다룬다. WB-ID 포워딩(레지스터 파일 내부 포워딩)은 Ch12에서 처리하며, 현재 설계에서는 레지스터 파일이 동기 쓰기/비동기 읽기이고 NOP 삽입 정책으로 우선 처리한다.

### 10.2절 — 포워딩 유닛 설계

**구현 포인트**:
- `forwarding_unit` 모듈을 독립 모듈로 설계 (파이프라인 탑에서 인스턴스화)
- 포워딩 MUX는 최상위 모듈 또는 EX 스테이지 모듈 내부에 구현 (포워딩 유닛에 포함시키지 않음)
- 포워딩 유닛은 조합 논리만 사용

**코드 예제 포함 내용**:
1. `forwarding_unit` 모듈 전체
2. EX 스테이지에서 포워딩 MUX 연결 코드
3. `wb_data` 계산 코드 (`mem_to_reg` MUX 결과)

### 10.3절 — Load-Use 해저드와 스톨

**구현 포인트**:
- `hazard_detection_unit` 모듈 독립 설계
- `if_id_instr[19:15]`, `if_id_instr[24:20]`을 직접 모듈 입력으로 받는 방식 권장
- ID/EX 레지스터 `flush` 시 모든 제어 신호 0으로 클리어 (특히 `mem_read=0`)

**코드 예제 포함 내용**:
1. `hazard_detection_unit` 모듈 전체
2. 최상위 모듈에서 `pc_en`, `if_id_en` 연결 변경 부분
3. ID/EX 레지스터의 flush 로직 (이미 Ch09에서 설계됨 — 연결만 변경)

### 10.4절 — 파이프라인 제어: Enable/Flush 신호 설계

**구현 포인트**:
- Enable/Flush 신호 전체 목록 및 현재 Ch10에서의 값
- Ch11에서 추가될 신호 위치 예약 (`TODO` 주석)
- 신호 우선순위 결정 이유 명시

**Ch10 완료 시점에서의 제어 신호 상태표**:

| 신호 | Ch09 | Ch10 | Ch11 |
|------|------|------|------|
| `pc_en` | 1 고정 | 해저드 감지 유닛 연결 | 분기 플러시와 AND 또는 분기 우선 처리 |
| `if_id_en` | 1 고정 | 해저드 감지 유닛 연결 | 분기 플러시와 AND |
| `if_id_flush` | 0 고정 | 0 고정 (TODO) | 분기 플러시 연결 |
| `id_ex_flush` | 0 고정 | 해저드 감지 유닛 연결 | OR 분기 플러시 |
| `ex_mem_en` | 1 고정 | 1 고정 | 1 고정 |
| `ex_mem_flush` | 0 고정 | 0 고정 | 분기 필요 시 연결 (설계 결정) |
| `mem_wb_en` | 1 고정 | 1 고정 | 1 고정 |

### 10.5절 — 데이터 해저드 테스트벤치

**테스트 케이스 망라** (최소 필수):

1. **EX-EX RAW 포워딩 (forward_a/b = 2'b01)**:
   ```asm
   ADD x1, x2, x3    # x1 = x2 + x3
   ADD x4, x1, x5    # x4 = x1 + x5 (EX-EX forward_a)
   ```

2. **MEM-EX RAW 포워딩 (forward_a/b = 2'b10)**:
   ```asm
   ADD x1, x2, x3    # C1
   ADD x5, x6, x7    # C2 (x1 무관 명령어)
   ADD x4, x1, x8    # C3 (MEM-EX forward_a)
   ```

3. **연속 EX-EX 포워딩 (A→B→C 체인)**:
   ```asm
   ADD x1, x2, x3    # x1 = ...
   ADD x4, x1, x5    # x4 = x1 + ... (EX-EX)
   ADD x6, x4, x7    # x6 = x4 + ... (EX-EX, 위 명령어의 결과)
   ```

4. **Load-Use 스톨**:
   ```asm
   LW  x1, 0(x2)     # Load x1
   ADD x3, x1, x4    # Load-Use 해저드 (1사이클 스톨 + MEM-EX 포워딩)
   ```

5. **Load 후 2사이클 후 사용 (포워딩만으로 해결)**:
   ```asm
   LW  x1, 0(x2)     # Load x1
   ADD x5, x6, x7    # x1 무관 — 1사이클 거리
   ADD x3, x1, x4    # MEM-EX 포워딩 (스톨 없음)
   ```

6. **Store 포워딩 검증**:
   ```asm
   ADD x5, x1, x2    # x5 = x1 + x2
   SW  x5, 0(x3)     # mem[x3] = x5 (EX-EX 포워딩 for rs2)
   ```

7. **x0 포워딩 방지**:
   ```asm
   ADD x0, x1, x2    # x0에 쓰기 (무시됨, reg_write=1이지만 x0)
   ADD x3, x0, x4    # x0 읽기 = 항상 0 (포워딩 없어야 함)
   ```

**파형에서 확인할 신호**:
- `forward_a`, `forward_b` (포워딩 케이스별 2'b00/01/10)
- `pc_en`, `if_id_en`, `id_ex_flush` (Load-Use 스톨 시 변화)
- `ex_mem_alu_result` → ALU 입력 포워딩 경로
- 레지스터 파일 최종 값 (`$display`로 비교)

### 10.6절 — 중간 마일스톤: 1~10 합산 프로그램

**합산 프로그램 (어셈블리)**:
```asm
# 1부터 10까지 합산: sum = 1+2+3+...+10 = 55
ADDI x1, x0, 10    # x1 = 10 (루프 카운터 종료값)
ADDI x2, x0, 0     # x2 = 0  (누적 합계)
ADDI x3, x0, 0     # x3 = 0  (루프 카운터, 초기값 0)
ADDI x4, x0, 1     # x4 = 1  (증가값)
# loop:
ADD  x2, x2, x3    # x2 = x2 + x3 (EX-EX 포워딩 — x3가 바로 이전 ADD 결과인 경우)
ADD  x3, x3, x4    # x3 = x3 + 1  (EX-EX 포워딩 — x2 결과와 x4)
BLT  x3, x1, loop  # if x3 < 10 goto loop (Ch11에서 처리, Ch10에서는 NOP으로 우회)
ADDI x5, x0, 55    # x5 = 55 (기대값)
BEQ  x2, x5, pass  # if x2 == 55 goto pass
# fail:
ADDI x6, x0, 0     # 실패 표시
# pass:
ADDI x6, x0, 1     # 성공 표시
```

> **Ch10 구현 주의**: 분기 명령어(BLT, BEQ)가 포함되어 있어 Ch11 없이는 루프 구조를 실행할 수 없다. Ch10 마일스톤에서는 **루프 없이 언롤된 버전** 또는 **NOP 4개 + 분기 성립 조건으로 우회**하는 방식을 사용한다.

**언롤된 합산 프로그램** (분기 없이 10회 반복, Ch10에서 사용):
```asm
ADDI x1, x0, 0    # 누적합 = 0
ADDI x2, x0, 1    # x2 = 1
ADD  x1, x1, x2   # x1 = 0 + 1 = 1
ADDI x2, x0, 2    # x2 = 2 (EX-EX 포워딩 없음: x2는 새로 쓰여짐)
ADD  x1, x1, x2   # x1 = 1 + 2 = 3 (MEM-EX 포워딩: x1)
ADDI x2, x0, 3    # x2 = 3
ADD  x1, x1, x2   # x1 = 3 + 3 = 6
... (반복)
ADDI x2, x0, 10
ADD  x1, x1, x2   # 최종 x1 = 55
```

**검증 방법**: `$finish` 전 `$display("sum = %0d, expected = 55", regfile[1])`로 확인.

---

## 10. Major 기술 주의사항

### [M1] WB-ID 포워딩 (레지스터 파일 동시 읽기/쓰기) 범위 명시

3사이클 차이의 RAW 해저드(ALU 명령어)는 레지스터 파일 동기 쓰기/비동기 읽기 구조에서 자연히 해결된다. WB에서 클럭 상승 에지에 쓰고, ID에서 같은 사이클에 비동기 읽기를 하면 값이 올바르게 읽힌다.

그러나 레지스터 파일 구현에 따라 동시 쓰기/읽기 충돌 처리 방식이 다를 수 있다. 10.1절에서 이를 언급하고 "우리의 레지스터 파일은 동기 쓰기/비동기 읽기를 사용하므로 3칸 RAW는 자동 해결"임을 명시해야 한다.

Load 명령어의 경우: LW→(skip)→(skip)→USE의 3칸 차이는 포워딩 없이 해결된다. LW→(skip)→USE의 2칸 차이는 MEM-EX 포워딩으로 해결. LW→USE의 1칸 차이(Load-Use)만 스톨이 필요하다.

### [M2] `ctrl_t` 구조체 flush 시 NOP 초기화

Ch09에서 `ctrl_t` 구조체를 사용하는 경우, ID/EX 레지스터 flush 시 구조체 전체를 0으로 클리어하는 코드를 명시적으로 작성해야 한다:

```systemverilog
// ID/EX 레지스터 flush 시 (NOP 버블)
if (rst || id_ex_flush) begin
   id_ex_ctrl <= '0;  // ctrl_t 구조체 전체 0으로 초기화
   id_ex_rd_addr   <= 5'b0;
   id_ex_rs1_addr  <= 5'b0;
   id_ex_rs2_addr  <= 5'b0;
   // ...
end
```

`'0` (apostrophe-zero)은 IEEE 1800-2017에서 타입에 맞게 모든 비트를 0으로 초기화하는 구조체 초기화 표기법이다.

### [M3] 포워딩 유닛 입력 신호 타이밍 — 조합 루프 가능성

`forwarding_unit`의 출력(`forward_a`, `forward_b`)이 MUX를 거쳐 EX 스테이지 내부를 통과한 후 다시 EX/MEM 레지스터에 저장된다. 이 경로가 동일 클럭 사이클 내에서 완결되므로 조합 루프(combinational loop)가 없다.

그러나 만약 포워딩 유닛 입력에 같은 사이클의 EX 스테이지 출력이 포함된다면 루프가 발생할 수 있다. 포워딩 유닛의 입력은 반드시 **레지스터 출력** (if/id_ex_*, ex/mem_*, mem/wb_*)이어야 한다.

### [M4] 테스트벤치에서 포워딩 검증 시 `#1` 지연 후 신호 샘플링

시뮬레이션에서 포워딩 MUX 출력을 검증할 때 클럭 상승 에지 직후 조합 논리 안정화까지 지연이 필요할 수 있다:

```systemverilog
// 권장 패턴
@(posedge clk);
#1;  // 조합 논리 안정화 후 샘플링
assert (dut.forward_a == 2'b01) else $error("EX-EX forwarding failed");
```

---

## 11. SVG 다이어그램 기술 검토 기준

Ch10의 SVG는 다음 기준을 만족해야 한다:

| 기준 | 세부사항 |
|------|----------|
| 포워딩 경로 명시 | EX-EX와 MEM-EX 포워딩 경로가 색상으로 구분 (녹색/오렌지) |
| 신호 이름 일치 | SVG 내 신호 이름이 SystemVerilog 코드와 일치 |
| 타이밍 다이어그램 | Load-Use 스톨 SVG에 사이클 번호와 버블 셀 명시 |
| 포워딩 MUX 표기 | 3입력 MUX, 2비트 선택 신호 명시 |
| 스톨 파형 | `pc_en`, `if_id_en`, `id_ex_flush` 파형 명시 |

---

## 12. Basys 3 FPGA 리소스 추정

Ch10에서 추가되는 로직의 Basys 3 (Artix-7) 리소스 영향:

| 추가 모듈 | LUT 추정 | FF 추정 | 비고 |
|----------|----------|---------|------|
| `forwarding_unit` | ~10 LUT | 0 (조합) | 비교기 + MUX 선택 신호 생성 |
| `hazard_detection_unit` | ~8 LUT | 0 (조합) | 비교기 + AND/OR |
| 포워딩 MUX (forward_a) | ~6 LUT | 0 | 3입력 32비트 MUX |
| 포워딩 MUX (forward_b) | ~6 LUT | 0 | 3입력 32비트 MUX |
| wb_data MUX | ~4 LUT | 0 | mem_to_reg 3입력 32비트 MUX |
| **합계 추가** | ~34 LUT | 0 | Ch09 대비 추가 |

> Ch09 총 리소스 기준으로 34 LUT 증가는 전체의 ~0.2% (Basys 3 LUT 20,800개 기준). 타이밍에 미치는 영향 미미. EX 스테이지 임계 경로에 3입력 MUX가 추가되므로 Fmax가 약간 감소할 수 있으나 50MHz 목표 달성에 지장 없음.

---

## 13. 집필 진행 체크리스트

기술 저자가 집필 전 반드시 확인해야 할 항목:

- [ ] Ch09 `rv32i_pipeline_top.sv` 전체 소스에서 `en=1'b1`, `flush=1'b0` 고정 위치 파악 → Ch10에서 연결 변경
- [ ] Ch09 `ctrl_t` 구조체 (`pipeline_pkg`) 내 `mem_read`, `reg_write` 필드 위치 확인 — 해저드 감지 유닛 입력으로 사용
- [ ] EX/MEM 레지스터의 `rs2_data` 필드가 Ch10에서 포워딩 이후 값으로 변경됨 명시 (Store 명령어)
- [ ] 포워딩 MUX 2개와 WB MUX(wb_data)의 최상위 연결 위치 결정 (EX 스테이지 내부 vs 최상위 모듈)
- [ ] `hazard_detection_unit`에 `if_id_instr[19:15]`와 `[24:20]`을 직접 연결하는 방식 결정
- [ ] Load-Use 스톨 테스트에서 버블 삽입 후 `id_ex_mem_read=0` 이 되는지 파형으로 검증
- [ ] 10.6절 마일스톤 프로그램을 NOP 삽입 + 언롤 방식으로 분기 없이 구성
- [ ] 전체 소스 코드 절에 `forwarding_unit.sv`, `hazard_detection_unit.sv`, 수정된 `rv32i_pipeline_top.sv` 포함

---

*작성: 기술 리뷰어 (Technical Reviewer)*
*검토 기반: chapter09_final_approval.md, chapter09_plan_tech.md, RISC-V Unprivileged ISA Spec v20191213, IEEE 1800-2017 SystemVerilog Standard, Xilinx Artix-7 FPGA Datasheet*
*다음 단계: 교육 설계자, 교육심리전문가 병렬 기획 리뷰 → chapter10_meeting.md 종합 회의*
