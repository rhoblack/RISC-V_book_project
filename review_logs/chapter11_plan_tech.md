# Ch11 기획 단계 기술 계획서 — 기술 리뷰어

**챕터**: Chapter 11 — 제어 해저드와 분기 처리
**리뷰어**: 기술 리뷰어 (Technical Reviewer)
**작성일**: 2026-03-11
**검토 기반**: Ch10 확정 설계 (chapter10_final_approval.md), Ch09 원고 (manuscripts/part4/chapter09.html), Ch10 원고 (manuscripts/part4/chapter10.html), RISC-V Unprivileged ISA Spec v20191213, IEEE 1800-2017, Xilinx Basys 3 Reference Manual, Patterson & Hennessy "Computer Organization and Design" 5th Ed.

---

## 개요

Chapter 11은 Ch09~Ch10에서 구축한 파이프라인 위에 **제어 해저드(Control Hazard)** 처리를 추가하는 챕터다. 이 챕터의 집필 품질은 세 가지 설계 결정의 정확성에 달려 있다:

1. **분기 판정 위치 결정**: EX 스테이지에서 `branch_taken` 확정 → 2사이클 버블 발생 (Ch09 MEM 판정 방식에서 EX 판정으로의 이동 명확히 설명 필요)
2. **Flush 대상 및 타이밍**: `if_id_flush`와 `id_ex_flush`의 동시/독립 인가 조건 완전 정의
3. **JAL/JALR 처리 위치**: JAL은 ID 단계, JALR은 EX 단계 — 각각 1사이클, 2사이클 버블 발생

---

## 1. 설계 연속성 — Ch09/Ch10 확정 사항과의 충돌 분석

### 1.1 [Critical 선결 사항] Ch09 MEM 판정 vs Ch11 EX 판정 불일치

**문제**: Ch09 원고 (`chapter09.html`, 833행)에는 다음 코드가 존재한다:

```systemverilog
assign pc_next = (branch_taken_mem) ? alu_result_mem : pc_plus4_if;
```

Ch09는 MEM 스테이지에서 `branch_taken_mem`을 판정하여 PC를 변경하는 방식으로 설계되었다. 이 설계에서는 BEQ/BNE 실행 시 3사이클 버블이 발생한다 (IF/ID/EX 레지스터를 모두 플러시해야 함).

그러나 Ch10 원고 (`chapter10.html`, 1042/1217행)에는 다음 코드가 존재한다:

```systemverilog
logic        zero_ex, branch_taken_ex;
assign branch_taken_ex = ctrl_ex.branch && zero_ex;
```

그리고 `pc_next`는 다음과 같이 변경되었다:

```systemverilog
assign pc_next  = pc_plus4;  // Ch11에서 분기 MUX 추가 예정
```

**Ch11 기획안은 EX 스테이지 판정(2사이클 버블)을 명시하고 있다.** 이는 Ch09의 MEM 판정 방식과 다르며, Ch10에서 `branch_taken_ex`만 준비하고 `branch_taken_mem` 경로를 제거한 것으로 보인다. 이 전환이 Ch11 집필에서 **명시적으로 설명**되어야 한다.

**기술 저자 필수 조치**:
- 11.2절에서 "Ch09에서는 MEM 스테이지 판정(3사이클 버블)으로 초안 구현, Ch11에서 EX 스테이지 판정(2사이클 버블)으로 전환" 경위를 명시적으로 서술
- EX 판정의 장점: 버블 1개 감소 (3→2)
- EX 판정의 전제: `zero` 신호가 EX 스테이지에서 즉시 확정됨 (ALU 비교 결과, 동일 사이클)
- Ch09 `pc_next` 코드(`branch_taken_mem` 사용)가 Ch11에서 `branch_taken_ex` 기반으로 교체됨을 명시

### 1.2 Ch10 확정 설계 활용 가능 인터페이스

| 파이프라인 레지스터 | Ch11 활용 필드 | 용도 |
|------------------|--------------|------|
| IF/ID | `flush` 포트 (예약, Ch09에서 `1'b0` 고정) | 분기 플러시 → **활성화** |
| ID/EX | `flush` 포트 (Ch10에서 `stall`로 연결) | 분기 플러시 OR Load-Use stall |
| ID/EX | `ctrl_ex.branch`, `ctrl_ex.jump` | 분기/점프 명령어 여부 |
| EX/MEM | `alu_result_mem` (Ch09에서 PC 변경 소스) | 분기 타겟 주소 (EX/MEM.alu_result) |
| 포워딩 유닛 | `forward_a`, `forward_b` | JALR rs1 포워딩 지원 |
| `branch_taken_ex` | Ch10 이미 정의 | 분기 판정 신호 → Ch11에서 PC MUX 연결 |

### 1.3 Ch10 `pc_next` 변경 범위

Ch10의 `pc_next` 코드가 `pc_plus4`만 반환하므로 Ch11에서 다음으로 교체한다:

```systemverilog
// Ch11 수정 — 분기/점프 PC MUX
always_comb begin
   if (branch_taken_ex)      pc_next = pc_branch_ex;  // B-type: EX 스테이지 분기 타겟
   else if (jal_taken_id)    pc_next = pc_jal_id;     // JAL: ID 스테이지에서 계산
   else if (jalr_taken_ex)   pc_next = jalr_target_ex; // JALR: EX 스테이지에서 계산
   else                      pc_next = pc_plus4;
end
```

이 변경이 Ch11의 핵심 수정 지점이다.

---

## 2. 핵심 기술 결정사항 (집필 전 확정)

### 2.1 분기 판정 위치: EX 스테이지

**결정**: B-type 분기(BEQ, BNE, BLT, BGE, BLTU, BGEU)는 **EX 스테이지**에서 판정한다.

**근거**:
- ALU가 두 피연산자의 차(또는 비교)를 계산하고 `zero`/`lt` 신호를 생성 → 동일 EX 사이클에서 즉시 확정 가능
- MEM 판정(Ch09 초안) 대비 1사이클 버블 감소 (3사이클 → 2사이클)
- Patterson & Hennessy 교재의 표준 EX 판정 방식과 일치
- Ch10에서 `branch_taken_ex = ctrl_ex.branch && zero_ex`로 이미 정의 완료

**2사이클 버블 발생 근거**:
```
사이클:  C1    C2    C3    C4    C5
BEQ:    IF    ID    EX    MEM   WB
I+1:    IF    ID   [bubble] EX   MEM   (IF/ID 플러시 → ID/EX에 NOP)
I+2:         IF   [bubble]  ID   EX    (ID/EX 플러시)
I+3 (분기 타겟):              IF   ID   EX
```
BEQ가 EX(C3)에서 `branch_taken=1` → C4 시작 시 PC=분기 타겟으로 변경.
C3까지 인출된 I+1(ID 단계)과 I+2(IF 단계)는 무효 → **IF/ID, ID/EX 레지스터를 NOP으로 플러시**.

**BLT/BGE/BLTU/BGEU 처리**:
- `zero_ex` 신호만으로는 부족 — ALU에서 `lt` (less-than), `ltu` (less-than unsigned) 신호도 필요
- Ch10 ALU 모듈이 `zero`만 출력한다면 Ch11에서 `negative`/`overflow` 또는 `lt_signed`/`lt_unsigned` 신호 추가 필요
- **집필 결정**: BEQ/BNE만 메인으로 설명, BLT/BGE/BLTU/BGEU는 동일 메커니즘의 연장으로 aside 처리 (Basys 3 검증은 BEQ/BNE)
- ALU 수정 사항: `branch_taken = ctrl_ex.branch && (funct3 기반 조건 신호)` — `funct3`을 EX 스테이지에 전달하거나, 조건 비교 로직을 ALU 외부에 추가

### 2.2 분기 타겟 주소 계산 위치

**결정**: 분기 타겟 = `ID/EX.pc + ID/EX.imm_ext` (EX 스테이지 가산기)

```systemverilog
assign pc_branch_ex = pc_ex + imm_ext_ex;  // EX 스테이지 가산기
```

- `pc_ex`: ID/EX 파이프라인 레지스터에 저장된 PC 값 (Ch09에서 이미 포함)
- `imm_ext_ex`: ID/EX에 저장된 B-type 즉치수 (부호 확장, {imm[12,10:5], imm[4:1,11], 0})
- B-type 즉치수 비트 재배열은 Ch06에서 디코더 설계 시 확정된 사항 — 그대로 활용

**주의**: 포워딩 MUX를 통과한 `rs1_fwd_ex`, `rs2_fwd_ex` 값이 ALU 입력으로 들어가므로 분기 비교 연산도 포워딩 후 값을 사용한다. 별도 포워딩 처리 불필요.

### 2.3 BNE 처리 — branch_taken 조건 확장

BEQ: `branch_taken = branch && zero`
BNE: `branch_taken = branch && ~zero`

`funct3[2:0]` 값에 따라 조건 분기:

```systemverilog
// branch_unit 또는 최상위에서 계산
always_comb begin
   case (funct3_ex)
      3'b000:  branch_taken_ex = ctrl_ex.branch && zero_ex;          // BEQ
      3'b001:  branch_taken_ex = ctrl_ex.branch && ~zero_ex;         // BNE
      3'b100:  branch_taken_ex = ctrl_ex.branch && lt_signed_ex;     // BLT
      3'b101:  branch_taken_ex = ctrl_ex.branch && ~lt_signed_ex;    // BGE
      3'b110:  branch_taken_ex = ctrl_ex.branch && lt_unsigned_ex;   // BLTU
      3'b111:  branch_taken_ex = ctrl_ex.branch && ~lt_unsigned_ex;  // BGEU
      default: branch_taken_ex = 1'b0;
   endcase
end
```

**전제**: `funct3_ex`가 ID/EX 파이프라인 레지스터에 포함되어야 함. Ch09에서 `ctrl_t` 구조체에 `funct3`이 없다면 추가 필요. 또는 `ctrl_ex.alu_control` 4비트에서 역추산하는 방식도 가능하나 권장하지 않음.

**집필 결정**: 초안에서는 BEQ/BNE만 다루고 `funct3_ex` 필드를 ID/EX에 추가하는 방식 채택.

### 2.4 Flush 메커니즘 완전 정의

#### 플러시 대상 및 사이클

| 명령어 | 판정 위치 | 플러시 대상 | 버블 수 | 조건 |
|--------|---------|------------|--------|------|
| BEQ/BNE (taken) | EX 스테이지 | IF/ID + ID/EX | 2 | `branch_taken_ex == 1` |
| BEQ/BNE (not taken) | EX 스테이지 | 없음 | 0 | `branch_taken_ex == 0` |
| JAL | ID 스테이지 | IF/ID | 1 | `ctrl_id.jump && ~ctrl_id.jalr` |
| JALR | EX 스테이지 | IF/ID + ID/EX | 2 | `ctrl_ex.jalr` (또는 `jump && jalr`) |

#### Flush 신호 연결 (Ch11 확정)

```
if_id_flush  = branch_taken_ex | jal_id_flush | jalr_ex_flush
id_ex_flush  = branch_taken_ex | jalr_ex_flush | stall(Ch10 Load-Use)
```

**Ch10 코드 수정 지점**:
```systemverilog
// Ch10: id_ex_flush = stall_load_use (단일 소스)
// Ch11: id_ex_flush = stall_load_use | branch_taken_ex | jalr_taken_ex

// Ch10: if_id_flush = 1'b0 (고정)
// Ch11: if_id_flush = branch_taken_ex | jal_taken_id | jalr_taken_ex
```

#### Flush vs Stall 동시 발생 우선순위 (Ch10 확정 패턴 유지)

파이프라인 레지스터 우선순위: `flush > en` (Ch09/Ch10 확정 패턴 그대로 유지)

```systemverilog
always_ff @(posedge clk) begin
   if (rst || flush) begin  // flush 우선
      // NOP 버블
   end else if (en) begin   // en 활성 시 정상 진행
      // 정상 캡처
   end
   // else: en=0, flush=0 → 홀드
end
```

**Load-Use 스톨 + 분기 Taken 동시 발생 처리**:

이 경우는 실제 파이프라인에서 발생 가능하다:
- Load-Use 스톨: `pc_en=0`, `if_id_en=0`, `id_ex_flush=1` (Load-Use 버블)
- 분기 Taken: `if_id_flush=1`, `id_ex_flush=1`, `pc_next=branch_target`

동시 발생 시 **분기 flush가 Load-Use stall보다 우선**:
- `pc_next = branch_target` (분기 타겟으로 이동 — stall의 PC 홀드 해제)
- `if_id_flush = 1` (분기 flush 적용)
- `id_ex_flush = 1` (OR — Load-Use 버블과 분기 flush 모두 적용)

```systemverilog
// PC 제어 (Ch11 최종)
always_ff @(posedge clk or posedge rst) begin
   if (rst)
      pc_reg <= 32'd0;
   else if (branch_taken_ex || jal_taken_id || jalr_taken_ex)
      pc_reg <= pc_next;   // 분기/점프 우선 — stall 무시
   else if (~stall)
      pc_reg <= pc_plus4;  // 정상 진행
   // else: stall=1, 분기 없음 → PC 홀드
end
```

### 2.5 Predict-Not-Taken 정책

**정의**: 분기 명령어를 만나면 항상 "분기 안 함(not taken)"으로 예측하고 PC+4 다음 명령어를 계속 인출한다.

**동작**:
- 예측 성공 (실제 not taken): flush 없음 → 0 사이클 패널티
- 예측 실패 (실제 taken): EX에서 branch_taken=1 확인 → 2사이클 버블 flush

**성능 식**:
```
CPI_branch = 1 + (taken_rate × 2)
예시: taken_rate=50% → CPI_branch = 2.0
예시: taken_rate=25% → CPI_branch = 1.5
```

**구현**: 별도 예측 로직 불필요. EX 스테이지 판정 후 `branch_taken_ex=1`이면 플러시, `0`이면 진행 — 이것이 Predict-Not-Taken의 자연스러운 구현이다.

### 2.6 JAL 처리 — ID 스테이지 (1사이클 버블)

**설계 결정**: JAL은 ID 스테이지에서 타겟 주소를 계산하고 PC를 변경한다.

**근거**:
- JAL 타겟 = PC + imm_J (rs1 읽기 불필요 — 즉시 PC와 즉치수만으로 계산 가능)
- PC와 imm_J는 IF/ID 레지스터 출력에 즉시 존재 → ID 사이클 내 조합 논리로 계산 가능
- EX까지 기다리면 2사이클 버블 필요 → ID 처리로 1사이클 버블로 단축

**구현**:
```systemverilog
// ID 스테이지에서 JAL 타겟 계산 (조합 논리)
logic [31:0] pc_jal_id;
logic        jal_taken_id;

assign pc_jal_id   = pc_id + imm_j_id;  // imm_j: J-type 즉치수 (IF/ID에서 디코딩)
assign jal_taken_id = (opcode_id == 7'b1101111);  // JAL opcode = 7'h6F
```

**1사이클 버블**:
```
사이클:  C1    C2    C3    C4    C5
JAL:    IF    ID    EX    MEM   WB
I+1:    IF   [bubble→NOP] EX   MEM  (IF/ID 플러시)
PC:           PC=JAL target 로드됨
I_target:          IF    ID    EX
```
JAL이 ID(C2)에서 처리 → C3 시작 시 PC=JAL 타겟.
C2까지 인출된 I+1(IF 단계)만 무효 → **IF/ID만 플러시**.

**rd 저장 (pc+4)**:
- JAL의 rd에 PC+4 저장은 WB에서 처리 (`mem_to_reg = 2'b10`, Ch09/Ch10 확정)
- ID/EX에 `pc_plus4_id`가 전달되어 EX/MEM/WB를 거쳐 WB에서 레지스터에 저장

**주의**: JAL의 J-type 즉치수 비트 재배열 — `{imm[31], imm[19:12], imm[20], imm[30:21], 1'b0}`. 이는 Ch06 디코더 설계에서 확정된 사항. `imm_j_id`는 IF/ID 레지스터의 `instr` 필드에서 직접 즉치수 재조합하거나, 디코더가 ID 스테이지에서 계산한 `imm_ext_id` 필드를 활용한다.

### 2.7 JALR 처리 — EX 스테이지 (2사이클 버블)

**설계 결정**: JALR은 EX 스테이지에서 타겟 주소를 계산한다.

**근거**:
- JALR 타겟 = (rs1 + imm_I) & ~1 — rs1 레지스터 값이 필요
- rs1은 ID 스테이지에서 읽히지만, 포워딩 가능성 때문에 최종 값은 EX에서 확정
- 따라서 EX 스테이지에서 포워딩 MUX 이후의 `rs1_fwd_ex` + `imm_ext_ex`로 계산

**구현**:
```systemverilog
logic [31:0] jalr_target_ex;
logic        jalr_taken_ex;

assign jalr_target_ex = (rs1_fwd_ex + imm_ext_ex) & 32'hFFFF_FFFE;  // &~1: 하위 1비트 클리어
assign jalr_taken_ex  = ctrl_ex.jump && ctrl_ex.jalr;  // JALR 판정
```

**2사이클 버블**: BEQ taken과 동일 메커니즘. IF/ID와 ID/EX 동시 플러시.

**JALR 하위 1비트 &~1 처리**:
- RISC-V 스펙: JALR 타겟의 하위 1비트를 0으로 강제 (2바이트 정렬, 16비트 압축 명령어 호환)
- 교재 범위에서는 "모든 명령어가 4바이트 정렬"을 가정하므로 실제 동작에 영향 없음
- 단, 스펙 준수를 위해 `& ~1` 처리를 코드에 포함하고 aside로 "교육 환경에서는 정렬 가정, 실무에서는 필수" 명시

**`ctrl_t` 구조체 확장 필요**:
- `jalr` 신호 추가: JALR과 JAL을 구분하기 위해 `ctrl_t`에 `jalr` 1비트 추가
  - `jump=1, jalr=0`: JAL
  - `jump=1, jalr=1`: JALR
- 또는 `mem_to_reg=2'b10` + `jalr=1`로 JALR 구분 가능 (설계 결정 필요)

**집필 권장 방식**: `ctrl_t`에 `jalr` 필드를 추가하여 명시적 구분.

---

## 3. 코드 설계 계획 상세

### 3.1 branch_unit 모듈

```systemverilog
module branch_unit (
   // EX 스테이지 입력
   input  logic [2:0] funct3,          // 분기 조건 종류 (BEQ=000, BNE=001, ...)
   input  logic       branch,          // ctrl_ex.branch
   input  logic       zero,            // ALU zero 출력
   input  logic       negative,        // ALU 부호 비트 (또는 lt 신호)
   input  logic       overflow,        // ALU overflow (signed 비교용)
   input  logic       carry,           // ALU carry out (unsigned 비교용)
   // 출력
   output logic       branch_taken     // 분기 성립 여부
);
   always_comb begin
      if (branch) begin
         case (funct3)
            3'b000:  branch_taken = zero;                   // BEQ
            3'b001:  branch_taken = ~zero;                  // BNE
            3'b100:  branch_taken = negative ^ overflow;    // BLT  (signed)
            3'b101:  branch_taken = ~(negative ^ overflow); // BGE  (signed)
            3'b110:  branch_taken = ~carry & ~zero;         // BLTU (unsigned: carry=0 && not zero)
            3'b111:  branch_taken = carry | zero;           // BGEU (unsigned)
            default: branch_taken = 1'b0;
         endcase
      end else begin
         branch_taken = 1'b0;
      end
   end
endmodule
```

> **주의**: BLTU/BGEU의 `carry` 기반 조건은 ALU 구현에 따라 다를 수 있다. ALU에서 SUB 연산의 차 결과(`A - B`)에서 borrow(= ~carry)를 사용하는 경우 조건식이 달라진다. Ch06 ALU 구현을 확인하여 일관성 유지 필요.

**집필 방향**: BEQ/BNE를 메인으로 상세 설명. BLT/BGE/BLTU/BGEU는 "동일 메커니즘, 조건만 다름"으로 요약하고 표로 제시.

### 3.2 pc_src 신호 — 4가지 PC 선택

| pc_src | 값 | PC 소스 | 명령어 | 판정 스테이지 |
|--------|-----|---------|--------|------------|
| PC+4 선택 | default | `pc_plus4` | 일반 명령어 | — |
| 분기 타겟 | `branch_taken_ex` | `pc_branch_ex = pc_ex + imm_ext_ex` | BEQ/BNE (taken) | EX |
| JAL 타겟 | `jal_taken_id` | `pc_jal_id = pc_id + imm_j_id` | JAL | ID |
| JALR 타겟 | `jalr_taken_ex` | `jalr_target_ex = (rs1_fwd_ex + imm_ext_ex) & ~1` | JALR | EX |

**우선순위**: `branch_taken_ex` 및 `jalr_taken_ex`는 동시 성립 불가 (분기 명령어와 JALR은 같은 명령어가 아님). `jal_taken_id`는 다른 두 신호와 동시 성립 가능성 있음 — JAL이 ID에 있고 이전 명령어가 EX에서 분기를 결정하는 경우. 이때 **EX 판정 우선** (branch_taken_ex > jal_taken_id).

```systemverilog
// PC 다음 값 결정 (우선순위: EX 분기/JALR > ID JAL > PC+4)
always_comb begin
   if (branch_taken_ex || jalr_taken_ex)
      pc_next = branch_taken_ex ? pc_branch_ex : jalr_target_ex;
   else if (jal_taken_id)
      pc_next = pc_jal_id;
   else
      pc_next = pc_plus4;
end
```

### 3.3 if_id_flush 및 id_ex_flush 연결 (Ch11 최종)

```systemverilog
// Flush 신호 합산
logic if_id_flush_ctrl;
logic id_ex_flush_ctrl;

assign if_id_flush_ctrl = branch_taken_ex | jal_taken_id | jalr_taken_ex;
assign id_ex_flush_ctrl = branch_taken_ex | jalr_taken_ex | stall_load_use;
//  id_ex_flush_ctrl 해설:
//    - branch_taken_ex: BEQ/BNE taken → IF/ID + ID/EX 클리어
//    - jalr_taken_ex:   JALR → IF/ID + ID/EX 클리어
//    - stall_load_use:  Load-Use 스톨 → ID/EX에 NOP 버블 (Ch10 기존)
//    - jal_taken_id:    JAL → IF/ID만 클리어 (ID/EX는 정상 진행)
```

> **중요**: JAL은 IF/ID만 플러시하고 ID/EX는 플러시하지 않는다. JAL 명령어 자체는 EX/MEM/WB를 거쳐 rd에 PC+4를 저장해야 하므로 ID/EX를 클리어하면 안 된다.

### 3.4 동적 분기 예측 BHT (선택 구현, 11.5절)

**BHT (Branch History Table) 2-bit 포화 카운터**:

```systemverilog
module bht #(
   parameter ENTRIES = 256,             // 256 엔트리 = 8비트 인덱스
   parameter CNT_BITS = 2               // 2비트 포화 카운터
) (
   input  logic        clk, rst,
   input  logic [7:0]  pc_index,        // PC[9:2] — 4바이트 정렬이므로 하위 2비트 제외
   input  logic        update_en,       // 분기 결과 업데이트 활성화
   input  logic        actual_taken,    // 실제 분기 결과 (EX 스테이지)
   output logic        predict_taken    // 예측 결과 (IF/ID 스테이지)
);
   logic [CNT_BITS-1:0] table [0:ENTRIES-1];

   // 예측 출력 (조합 논리)
   assign predict_taken = table[pc_index][CNT_BITS-1];  // MSB = 예측

   // 업데이트 (동기 쓰기)
   always_ff @(posedge clk or posedge rst) begin
      if (rst) begin
         // 모든 엔트리를 "Weakly Not Taken (2'b01)"으로 초기화
         for (int i = 0; i < ENTRIES; i++)
            table[i] <= 2'b01;
      end else if (update_en) begin
         if (actual_taken && table[pc_index] != 2'b11)
            table[pc_index] <= table[pc_index] + 1;
         else if (!actual_taken && table[pc_index] != 2'b00)
            table[pc_index] <= table[pc_index] - 1;
      end
   end
endmodule
```

**2-bit 포화 카운터 상태 머신**:
```
00 (Strongly Not Taken) ←→ 01 (Weakly Not Taken) ←→ 10 (Weakly Taken) ←→ 11 (Strongly Taken)
  분기 성립 시: 카운터 증가 (포화 11에서 멈춤)
  분기 불성립 시: 카운터 감소 (포화 00에서 멈춤)
  MSB=1: Taken 예측, MSB=0: Not Taken 예측
```

**Basys 3 LUT 예산**:
- 256 × 2비트 = 512비트 = LUTRAM 또는 FF 사용
- Artix-7 (Basys 3) 20,800 LUT 기준 약 8 LUT + 256 FF (0.04%)
- 전체 파이프라인 CPU 대비 리소스 영향 미미 — 구현 권장

**BTB (Branch Target Buffer)**:
- 256 엔트리 × 32비트(타겟 주소) = 8KB → BRAM 사용 필요
- Basys 3 BRAM 18Kbit × 10개 — 1개 BRAM 소모
- 교육적 효과 대비 구현 복잡도가 높음
- **집필 결정**: BTB는 11.5절에서 개념만 소개, 구현은 선택 과제로 제시

---

## 4. 기술적 주의사항 (Critical)

### 4.1 [C1] BNE 처리 누락 가능성

**문제**: Ch10에서 `branch_taken_ex = ctrl_ex.branch && zero_ex`로 정의되어 있다. 이는 BEQ만 올바르게 처리하며, BNE(funct3=001)는 `zero_ex=1`일 때 분기가 성립해야 하지 않는데 오히려 성립하는 반전 오류가 발생한다.

**오류 시나리오**:
```asm
BNE x1, x2, target    # x1 != x2 → taken (zero=0 → 분기 성립해야 함)
                       # 현재 코드: branch && zero = 1 && 0 = 0 (not taken) → 오류!
```

**필수 수정**: Ch11에서 `branch_taken_ex` 계산을 `funct3` 기반으로 확장하거나 `branch_unit` 모듈로 분리. `funct3_ex` 필드를 ID/EX 파이프라인 레지스터에 추가하거나 `ctrl_t` 구조체에 포함.

**구현 옵션**:
- 옵션 A: `ctrl_t`에 `funct3[2:0]` 필드 추가 (구조체 확장, 3비트 추가)
- 옵션 B: `alu_control[3:0]` 값에서 역산 (비권장 — alu_control은 ALU 연산 종류이지 분기 조건이 아님)
- **권장**: 옵션 A 채택

### 4.2 [C2] JAL이 ID/EX 파이프라인 레지스터를 플러시해서는 안 됨

**문제**: JAL은 ID 스테이지에서 타겟 주소를 계산하고 IF/ID만 플러시한다. JAL 명령어 자체는 ID/EX → EX/MEM → MEM/WB를 정상적으로 통과하여 WB에서 rd = PC+4를 레지스터에 저장해야 한다.

만약 `jal_taken_id` 신호를 `id_ex_flush`에도 연결하면 JAL 명령어가 NOP으로 처리되어 링크 주소(PC+4)가 rd에 저장되지 않는다.

**정확한 연결**:
```
if_id_flush  ← jal_taken_id 연결 (O)
id_ex_flush  ← jal_taken_id 연결 (X) — JAL 자체가 id_ex를 통과해야 함
```

### 4.3 [C3] JALR rs1 포워딩 의존성 — Load-JALR 해저드

**문제**: JALR은 rs1을 레지스터에서 읽어 타겟 주소를 계산한다. 바로 직전 명령어가 LW이고 rd가 JALR의 rs1인 경우:

```asm
LW  x1, 0(x2)     # x1 로드
JALR x0, x1, 0   # JALR 타겟 = x1 + 0 → x1이 아직 MEM에서 읽히는 중
```

이는 Load-Use 해저드 + JALR이 결합된 상황이다. Ch10의 `hazard_detection_unit`이 LW-JALR 조합도 스톨로 감지하는지 확인 필요.

**분석**: Ch10 해저드 감지 조건:
```
stall = id_ex_mem_read && (id_ex_rd_addr != 5'b0) &&
        ((id_ex_rd_addr == if_id_rs1_addr) || (id_ex_rd_addr == if_id_rs2_addr))
```

JALR의 경우 `if_id_rs1_addr = instr[19:15]` → rs1 필드 정상적으로 감지. **Load-JALR 해저드는 Ch10 hazard_detection_unit이 이미 커버한다** (if_id_rs1_addr 조건이 성립). 별도 처리 불필요.

**다만**: 포워딩 MUX가 JALR의 rs1에도 적용되는지 확인 필요. EX 스테이지에서 `rs1_fwd_ex`를 JALR 타겟 계산에 사용하므로 포워딩은 자동으로 적용된다.

### 4.4 [C4] 분기 + Load-Use 동시 발생 시 PC 제어

**문제**: 드문 경우지만 EX 스테이지에서 분기가 taken으로 결정되는 동시에 Load-Use 스톨이 발생할 수 있다.

**시나리오**:
```
사이클 C3:
  EX: BEQ → branch_taken=1 (분기 성립)
  ID: LW (다음 명령어 — Load-Use 해저드 감지)
```

이 경우:
- Load-Use 스톨 신호: `pc_en=0`, `if_id_en=0`, `id_ex_flush=1`
- 분기 Taken 신호: `if_id_flush=1`, `id_ex_flush=1`, `pc_next=branch_target`

**충돌**: Load-Use stall이 `pc_en=0`으로 PC를 홀드하려 하지만 분기 taken이 `pc_next=branch_target`으로 PC를 변경하려 한다.

**결정**: 분기 taken이 Load-Use stall보다 우선. 분기 타겟 주소로 PC를 변경하고 버블을 삽입하면 Load-Use 해저드는 자연스럽게 해소된다 (분기 타겟 이후 명령어가 새로 인출됨).

```systemverilog
always_ff @(posedge clk or posedge rst) begin
   if (rst)
      pc_reg <= 32'd0;
   else if (branch_taken_ex || jalr_taken_ex)
      pc_reg <= pc_next;            // 분기/JALR 우선 (stall 무시)
   else if (jal_taken_id)
      pc_reg <= pc_jal_id;          // JAL 우선 (stall 무시)
   else if (pc_en)                  // pc_en = ~stall_load_use
      pc_reg <= pc_plus4;           // 정상 진행
   // else: stall, 분기 없음 → PC 홀드
end
```

---

## 5. Major 기술 주의사항

### [M1] `ctrl_t` 구조체 확장 시 Ch09/Ch10 코드와의 호환성

Ch11에서 `ctrl_t`에 `funct3[2:0]`과 `jalr` 필드를 추가하면 Ch09/Ch10의 모든 파이프라인 레지스터 NOP 초기화 코드(`ctrl <= '0`)는 자동으로 새 필드도 0으로 초기화하므로 호환성 문제 없다.

단, 디코더(`rv32i_decoder.sv` 또는 동등 모듈)에서 JALR 명령어(`opcode=1100111`)를 `jalr=1, jump=1, reg_write=1, mem_to_reg=2'b10`으로 디코딩해야 하며, JAL과의 구분이 명확해야 한다.

### [M2] 분기 타겟 주소 정확성 — B-type 즉치수 비트 재배열

B-type 즉치수: `{instr[31], instr[7], instr[30:25], instr[11:8], 1'b0}`

이 즉치수는 Ch06 디코더에서 이미 정확히 구현되었으며, ID/EX 파이프라인 레지스터의 `imm_ext` 필드로 전달된다. 분기 타겟 계산 시 `imm_ext_ex`를 그대로 사용하면 된다.

단, 컴파일러/어셈블러가 생성한 즉치수 인코딩과 테스트벤치의 기대값이 일치하는지 반드시 시뮬레이션으로 검증한다.

### [M3] Predict-Not-Taken 성능 분석 — 교재 데이터 정확성

교재에서 제시하는 분기 taken 비율 통계:
- SPEC CPU 벤치마크 기준: 약 60~65%의 분기가 taken
- Predict-Not-Taken의 미예측률: ~60-65%
- Predict-Taken의 미예측률: ~35-40%
- 2-bit BHT: 미예측률 ~10-15% (루프 내 분기 등 규칙적 패턴에 효과적)

이 수치는 교재에서 정확히 출처를 명시하거나 "일반적인 정수 프로그램 기준"임을 명기해야 한다.

### [M4] ALU 모듈 신호 — `lt`, `negative`, `overflow`, `carry` 출력 확인

Ch06~Ch09에서 확정된 ALU 모듈이 다음 신호를 출력하는지 확인 필요:
- `zero`: A == B (SUB 결과 = 0) → BEQ/BNE 처리 (Ch09에서 확인됨)
- `negative`: SUB 결과의 MSB (부호 비트) → BLT/BGE 처리
- `overflow`: 부호 있는 오버플로 → BLT/BGE signed 비교 정확성
- `carry_out`: unsigned 비교 → BLTU/BGEU 처리

ALU 모듈에 이 신호들이 없다면 Ch11에서 ALU 인터페이스 확장이 필요하다. 이 경우 Ch06~Ch09 원고에서 ALU 인터페이스가 바뀌는 것이므로 독자에게 "Ch11에서 ALU를 확장한다"는 사전 안내가 필요하다.

**집필 결정**: Ch11 집필 전 Ch06 ALU 구현을 확인하고, 없는 신호는 추가하되 교재 서술에서 "기존 ALU에 출력 신호 추가" 절차를 명시적으로 안내한다.

### [M5] 동적 분기 예측 BHT — Vivado 합성 시 초기화 문제

BHT의 `for` 루프 초기화는 SystemVerilog의 초기 블록이 아닌 `always_ff` 내 `rst` 조건으로 처리해야 Vivado에서 올바르게 합성된다 (위 코드에 반영됨).

`initial` 블록으로 초기화하는 경우 시뮬레이션에서는 동작하지만 Vivado 합성에서 레지스터 초기값으로 처리되지 않을 수 있다.

---

## 6. 절별 기술 요구사항 요약

### 11.1절 — 제어 해저드의 발생 원인

**핵심 기술 메시지**: "분기 명령어는 결과가 확정되기 전에 다음 명령어가 인출되어 버린다."

**반드시 설명할 내용**:
1. 데이터 해저드 vs 제어 해저드 차이 — Ch10과의 연계
2. 분기 명령어 파이프라인 흐름: IF → ID → EX(판정) → 이미 IF/ID에 있는 명령어들 무효
3. 버블 발생 수 계산: EX 판정 기준 2사이클 버블 (MEM 판정 기준 3사이클과 비교)
4. 제어 해저드의 근본 원인: 분기 결과를 사전에 알 수 없음

### 11.2절 — 분기 결과를 EX 스테이지에서 처리

**핵심 기술 내용**:
1. `branch_taken_ex` 신호 생성 (`branch_unit` 모듈)
2. 분기 타겟 주소 계산 (`pc_branch_ex = pc_ex + imm_ext_ex`)
3. EX 판정으로의 전환 근거 (MEM 판정 대비 1사이클 버블 감소)
4. `pc_next` 변경 코드 (Ch10의 `pc_plus4` 고정 → 분기 MUX 추가)

**SVG 필수**: 2사이클 버블 타이밍 다이어그램 (BEQ taken 케이스)

### 11.3절 — Flush 메커니즘 설계

**핵심 기술 내용**:
1. `if_id_flush` 활성화 — Ch09에서 `1'b0` 고정이었던 것 해제
2. `id_ex_flush`에 분기 flush 추가 (기존 Load-Use stall과 OR)
3. flush > en 우선순위 확인 (Ch09 패턴 그대로 적용됨)
4. JAL은 ID/EX flush 불필요 — 상세 설명

**코드 예제**:
- IF/ID 레지스터의 flush 입력 연결 변경
- `id_ex_flush = stall_load_use | branch_taken_ex | jalr_taken_ex`
- `if_id_flush = branch_taken_ex | jal_taken_id | jalr_taken_ex`

### 11.4절 — 정적 분기 예측: Predict-Not-Taken

**핵심 기술 내용**:
1. Predict-Not-Taken 정의 및 구현 (별도 로직 불필요 — 현재 구조가 이미 Predict-Not-Taken)
2. 성능 분석: CPI = 1 + taken_rate × 2
3. 비교: 분기 없음 CPI=1, Predict-Not-Taken, Predict-Taken, 완전 예측

**aside**: 실무에서의 분기 예측기 — 현대 프로세서의 복잡한 예측 구조 간단 소개

### 11.5절 — 동적 분기 예측 (선택 구현)

**핵심 기술 내용**:
1. 2-bit 포화 카운터 상태 머신
2. BHT 구조 (인덱스, 카운터, 예측 출력)
3. 예측 실패 시 flush 메커니즘 수정 (예측 성공 시 flush 없음)
4. 성능 개선 수치: taken 루프에서 ~50% → ~90%+ 예측 정확도

**코드**: `bht.sv` 전체 (위 3.4절 참조)

**Basys 3 검증 방법**: 동일 루프 프로그램에서 flush 횟수를 카운터로 측정, BHT 유/무 비교

### 11.6절 — JAL/JALR 처리

**핵심 기술 내용**:
1. JAL: ID 단계 타겟 계산, 1사이클 버블, rd=PC+4 정상 WB
2. JALR: EX 단계 타겟 계산, 2사이클 버블, rs1 포워딩 의존
3. JALR 하위 1비트 &~1 처리 aside 명시
4. `ctrl_t` 구조체 `jalr` 필드 추가 설명

**코드**: `pc_next` 완전한 MUX 코드, `jalr_target_ex` 계산

### 11.7절 — 제어 해저드 테스트벤치

**테스트 케이스 목록**:

1. **BEQ taken — 2사이클 버블**:
   ```asm
   ADDI x1, x0, 5
   ADDI x2, x0, 5
   BEQ  x1, x2, target    # taken → 2 버블
   ADDI x3, x0, 99        # 버블 (실행되면 안 됨)
   ADDI x4, x0, 99        # 버블 (실행되면 안 됨)
   target: ADDI x5, x0, 1  # 실행됨 (x5=1 확인)
   ```

2. **BEQ not taken — 0사이클 버블**:
   ```asm
   ADDI x1, x0, 3
   ADDI x2, x0, 5
   BEQ  x1, x2, target    # not taken → flush 없음
   ADDI x3, x0, 1         # 정상 실행 (x3=1 확인)
   ```

3. **BNE taken**:
   ```asm
   ADDI x1, x0, 3
   ADDI x2, x0, 5
   BNE  x1, x2, target    # taken (x1 != x2)
   ```

4. **루프 프로그램 — 포워딩 + 분기 통합**:
   ```asm
   ADDI x1, x0, 0     # 누적합
   ADDI x2, x0, 1     # 카운터
   ADDI x3, x0, 11    # 상한값
   # loop:
   ADD  x1, x1, x2    # x1 += x2 (EX-EX 포워딩)
   ADDI x2, x2, 1     # x2++ (EX-EX 포워딩 가능)
   BNE  x2, x3, loop  # x2 != 11이면 반복
   # x1 = 1+2+...+10 = 55 검증
   ```

5. **JAL 검증**:
   ```asm
   JAL  x1, target    # x1 = PC+4(링크 주소), 점프
   ADDI x2, x0, 99    # 버블 (실행 안 됨)
   target: ADDI x3, x0, 1  # 실행됨
   ```

6. **JALR 검증**:
   ```asm
   ADDI x1, x0, 20   # 점프 주소
   JALR x2, x1, 4    # x2=PC+4, PC=x1+4=24
   ```

7. **포워딩 + 분기 복합 — 분기 비교 대상이 포워딩된 값**:
   ```asm
   ADDI x1, x0, 5
   ADD  x2, x1, x0   # x2 = x1 (EX-EX 포워딩)
   BEQ  x2, x1, target  # x2==x1 → taken (포워딩된 x2값으로 비교)
   ```

**파형 검증 신호**:
- `if_id_flush`, `id_ex_flush` — 분기 taken 시 활성화 확인
- `pc_reg` — 분기 타겟으로 변경 확인
- `branch_taken_ex` — EX 스테이지에서 1사이클만 활성화
- 레지스터 파일 최종값 비교

### 11.8절 — 본 챕터 요약 및 다음 단계

**포함 내용**:
- 제어 해저드 해결 방법 전체 요약표 (정적 예측, 동적 예측)
- Ch09~Ch11 파이프라인 발전 과정 전체 요약 (NOP→포워딩→분기)
- Ch12 미리보기: 예외(Exception)와 인터럽트(Interrupt) 처리

---

## 7. SVG 다이어그램 필수 목록

| 번호 | 파일명 | 절 | 내용 |
|------|--------|-----|------|
| SVG-1 | `ch11_sec01_control_hazard_intro.svg` | 11.1 | 분기 명령어 파이프라인 타이밍 — 버블 발생 개요 |
| SVG-2 | `ch11_sec02_branch_ex_timing.svg` | 11.2 | BEQ taken 시 2사이클 버블 상세 타이밍 |
| SVG-3 | `ch11_sec02_branch_datapath.svg` | 11.2 | 분기 처리 데이터패스 (branch_unit, pc_branch_ex MUX) |
| SVG-4 | `ch11_sec03_flush_mechanism.svg` | 11.3 | if_id_flush + id_ex_flush 신호 흐름 |
| SVG-5 | `ch11_sec04_predict_not_taken.svg` | 11.4 | Predict-Not-Taken 동작 (taken/not-taken 두 케이스 비교) |
| SVG-6 | `ch11_sec05_bht_2bit.svg` | 11.5 | 2-bit 포화 카운터 상태 머신 (선택) |
| SVG-7 | `ch11_sec06_jal_jalr_timing.svg` | 11.6 | JAL(1버블) vs JALR(2버블) 타이밍 비교 |
| SVG-8 | `ch11_sec07_loop_waveform.svg` | 11.7 | 루프 프로그램 시뮬레이션 파형 |

---

## 8. Basys 3 FPGA 리소스 추정

Ch11에서 추가되는 로직의 Basys 3 (Artix-7) 리소스 영향:

| 추가 모듈/로직 | LUT 추정 | FF 추정 | 비고 |
|--------------|----------|---------|------|
| `branch_unit` | ~10 LUT | 0 | 조합 논리, funct3 기반 조건 생성 |
| `pc_branch_ex` 계산 | ~32 LUT | 0 | 32비트 가산기 (이미 존재 시 공유 가능) |
| `jalr_target_ex` 계산 | ~33 LUT | 0 | 32비트 가산기 + &~1 (1 LUT) |
| `jal_taken_id` 감지 | ~5 LUT | 0 | opcode 비교 |
| Flush 신호 OR 로직 | ~3 LUT | 0 | if_id_flush, id_ex_flush OR 게이트 |
| PC MUX (4방향) | ~64 LUT | 0 | 32비트 4:1 MUX |
| BHT (256 × 2bit) | ~16 LUT + 256 FF | 256 | 포화 카운터 (선택 구현) |
| **합계 (BHT 제외)** | ~147 LUT | 0 | Ch10 대비 추가 |
| **합계 (BHT 포함)** | ~163 LUT | 256 | — |

> Ch10 총 리소스 대비 약 ~147 LUT 증가. Basys 3 전체 20,800 LUT의 약 0.7%. 타이밍 임계 경로(EX 스테이지)에 분기 타겟 계산 가산기가 추가되므로 Fmax가 약간 감소할 수 있으나 50MHz 목표는 달성 가능.

---

## 9. 집필 진행 체크리스트

기술 저자가 집필 전 반드시 확인해야 할 항목:

- [ ] Ch06 ALU 모듈 출력 신호 목록 확인 — `negative`, `overflow`, `carry` 출력 유무 확인 및 없으면 추가 계획 수립
- [ ] Ch09 원고 `branch_taken_mem` 사용 → Ch11에서 `branch_taken_ex`로 전환하는 경위 설명 문단 초안 준비
- [ ] `ctrl_t` 구조체에 `funct3[2:0]` 필드 추가 결정 (BNE 지원 필수)
- [ ] `ctrl_t` 구조체에 `jalr` 필드 추가 결정 (JAL/JALR 구분 필수)
- [ ] Ch10 `rv32i_pipeline_top.sv`의 `pc_next = pc_plus4` 고정 코드 → Ch11에서 분기/점프 MUX로 교체
- [ ] Ch10 `if_id_flush = 1'b0` 고정 연결 해제 → `if_id_flush_ctrl` 연결
- [ ] Ch10 `id_ex_flush = id_ex_flush_stall` → `id_ex_flush_ctrl` (OR 추가)
- [ ] JAL이 ID/EX를 플러시하지 않음 확인 (rd = PC+4 저장 정상 동작 보장)
- [ ] JALR 하위 1비트 &~1 처리 aside 위치 결정
- [ ] 루프 프로그램 (x1 = 1~10 합산 = 55) 분기 포함 버전 — BNE 루프로 구현, Ch10 언롤 버전과 비교
- [ ] BHT 선택 구현 시 Vivado 합성 검증 (`for` 루프 초기화 → `always_ff`의 `rst` 조건)

---

## 10. 정리 — Ch11 집필 핵심 설계 결정 (확정안)

| 항목 | 결정 |
|------|------|
| 분기 판정 위치 | EX 스테이지 (`branch_taken_ex`) |
| 분기 버블 수 | 2사이클 (IF/ID + ID/EX 플러시) |
| JAL 처리 위치 | ID 스테이지 (1사이클 버블, IF/ID만 플러시) |
| JALR 처리 위치 | EX 스테이지 (2사이클 버블, IF/ID + ID/EX 플러시) |
| JALR 하위 1비트 | &~1 처리 (스펙 준수, aside 명시) |
| BNE 지원 | `funct3_ex` 기반 `branch_unit` 모듈로 확장 |
| 포워딩 의존 | JALR rs1은 포워딩 MUX 이후 값 사용 (자동 적용) |
| 분기 예측 (기본) | Predict-Not-Taken (별도 로직 불필요) |
| 동적 예측 (선택) | 2-bit 포화 카운터 BHT, 256 엔트리 |
| BTB | 개념 소개만, 구현은 선택 과제 |
| flush > en 우선순위 | Ch09 확정 패턴 유지 |
| 분기 > Load-Use 우선순위 | 분기 taken 시 Load-Use stall 무시하고 PC 변경 |

---

*작성: 기술 리뷰어 (Technical Reviewer)*
*검토 기반: chapter10_final_approval.md, manuscripts/part4/chapter09.html, manuscripts/part4/chapter10.html, RISC-V Unprivileged ISA Spec v20191213, IEEE 1800-2017 SystemVerilog Standard, Xilinx Artix-7 FPGA Datasheet*
*다음 단계: 교육 설계자, 교육심리전문가 병렬 기획 리뷰 → chapter11_meeting.md 종합 회의*
