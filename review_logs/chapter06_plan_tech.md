# Chapter 06 기술 기획 검토 보고서

**챕터**: Chapter 06 — 제어 유닛과 단일 사이클 통합
**검토자**: 기술 리뷰어 (Technical Reviewer)
**검토일**: 2026-03-11
**관련 선행 코드**:
- `code_examples/ch04_alu.sv`, `ch04_register_file.sv`, `ch04_imm_gen.sv`
- `code_examples/ch05_instruction_memory.sv`, `ch05_data_memory.sv`
- `code_examples/ch06_decoder.sv`, `ch06_control_unit.sv`, `ch06_single_cycle_top.sv`, `ch06_single_cycle_tb.sv`, `ch06_fibonacci.hex`

---

## 1. RV32I 디코더 설계 요구사항

### 1.1 37개 명령어 완전 목록

RV32I 기본 명령어셋은 총 47개의 니모닉을 정의하지만, FENCE/FENCE.I와 CSR 계열(CSRRW 등 6개)을 제외하고 ECALL/EBREAK를 NOP 처리로 단순화하면 6개 타입에 걸쳐 아래 37개를 구현해야 한다.

#### R 타입 (opcode = 7'b011_0011) — 10개

| 명령어 | funct7[6:0] | funct3[2:0] | 동작 |
|--------|-------------|-------------|------|
| ADD    | 0000000     | 000         | rd = rs1 + rs2 |
| SUB    | 0100000     | 000         | rd = rs1 - rs2 |
| SLL    | 0000000     | 001         | rd = rs1 << rs2[4:0] |
| SLT    | 0000000     | 010         | rd = (signed(rs1) < signed(rs2)) ? 1 : 0 |
| SLTU   | 0000000     | 011         | rd = (rs1 < rs2) ? 1 : 0 (무부호) |
| XOR    | 0000000     | 100         | rd = rs1 ^ rs2 |
| SRL    | 0000000     | 101         | rd = rs1 >> rs2[4:0] |
| SRA    | 0100000     | 101         | rd = $signed(rs1) >>> rs2[4:0] |
| OR     | 0000000     | 110         | rd = rs1 \| rs2 |
| AND    | 0000000     | 111         | rd = rs1 & rs2 |

#### I 타입 — ALU (opcode = 7'b001_0011) — 9개

| 명령어 | funct7 구분 | funct3[2:0] | 동작 |
|--------|-------------|-------------|------|
| ADDI   | —           | 000         | rd = rs1 + imm_I |
| SLLI   | [31:25]=0000000 | 001    | rd = rs1 << imm[4:0] |
| SLTI   | —           | 010         | rd = (signed(rs1) < signed(imm_I)) ? 1 : 0 |
| SLTIU  | —           | 011         | rd = (rs1 < unsigned(imm_I)) ? 1 : 0 |
| XORI   | —           | 100         | rd = rs1 ^ imm_I |
| SRLI   | [31:25]=0000000 | 101    | rd = rs1 >> imm[4:0] |
| SRAI   | [31:25]=0100000 | 101    | rd = $signed(rs1) >>> imm[4:0] |
| ORI    | —           | 110         | rd = rs1 \| imm_I |
| ANDI   | —           | 111         | rd = rs1 & imm_I |

#### I 타입 — Load (opcode = 7'b000_0011) — 5개

| 명령어 | funct3[2:0] | 동작 |
|--------|-------------|------|
| LB     | 000         | rd = sign_ext(mem[rs1+imm][7:0]) |
| LH     | 001         | rd = sign_ext(mem[rs1+imm][15:0]) |
| LW     | 010         | rd = mem[rs1+imm][31:0] |
| LBU    | 100         | rd = zero_ext(mem[rs1+imm][7:0]) |
| LHU    | 101         | rd = zero_ext(mem[rs1+imm][15:0]) |

#### S 타입 (opcode = 7'b010_0011) — 3개

| 명령어 | funct3[2:0] | 동작 |
|--------|-------------|------|
| SB     | 000         | mem[rs1+imm][7:0] = rs2[7:0] |
| SH     | 001         | mem[rs1+imm][15:0] = rs2[15:0] |
| SW     | 010         | mem[rs1+imm][31:0] = rs2 |

#### B 타입 (opcode = 7'b110_0011) — 6개

| 명령어 | funct3[2:0] | 분기 조건 |
|--------|-------------|-----------|
| BEQ    | 000         | rs1 == rs2 |
| BNE    | 001         | rs1 != rs2 |
| BLT    | 100         | signed(rs1) < signed(rs2) |
| BGE    | 101         | signed(rs1) >= signed(rs2) |
| BLTU   | 110         | rs1 < rs2 (무부호) |
| BGEU   | 111         | rs1 >= rs2 (무부호) |

#### U 타입 — 2개

| 명령어 | opcode        | 동작 |
|--------|---------------|------|
| LUI    | 7'b011_0111   | rd = {imm[31:12], 12'b0} |
| AUIPC  | 7'b001_0111   | rd = PC + {imm[31:12], 12'b0} |

#### J 타입 — 1개

| 명령어 | opcode        | 동작 |
|--------|---------------|------|
| JAL    | 7'b110_1111   | rd = PC+4; PC = PC + imm_J |

#### I 타입 — JALR — 1개

| 명령어 | opcode        | funct3 | 동작 |
|--------|---------------|--------|------|
| JALR   | 7'b110_0111   | 000    | rd = PC+4; PC = (rs1+imm_I) & ~1 |

**합계**: R(10) + I-ALU(9) + Load(5) + S(3) + B(6) + U(2) + JAL(1) + JALR(1) = **37개**

---

### 1.2 특수 케이스: SLLI / SRLI / SRAI의 funct7[5] 구분

I 타입 시프트 명령어(SLLI, SRLI, SRAI)는 opcode=`7'b001_0011`이고 funct3이 각각 `3'b001`, `3'b101`로 구분된다. 여기서 인코딩 상 즉치수 필드의 상위 7비트(instr[31:25])가 `funct7`처럼 기능한다.

```
SLLI: instr[31:25] = 0000000, funct3 = 001
SRLI: instr[31:25] = 0000000, funct3 = 101
SRAI: instr[31:25] = 0100000, funct3 = 101
```

**구분 방법**: funct7[5] (즉 instr[30])의 값으로 SRLI/SRAI를 분리한다.
- `funct7[5] == 0` → SRLI (논리 시프트)
- `funct7[5] == 1` → SRAI (산술 시프트)

**시프트 양**: I 타입 시프트에서 실제 시프트 양은 imm_I[4:0] = instr[24:20]의 하위 5비트만 유효하다. instr[31:25]는 타입 구분에만 사용되며, 즉치수 생성기에는 I-type 그대로 전달하되 ALU에서 `b[4:0]`을 참조하여 사용하면 된다.

**현재 ch06_decoder.sv 코드의 처리 방식**:
```systemverilog
3'b101: alu_sel = (funct7[5]) ? ALU_SRA : ALU_SRL; // SRAI / SRLI
```
이 방식은 올바르다. R 타입 ADD/SUB 구분도 동일한 `funct7[5]` 패턴이 적용된다.

---

### 1.3 FENCE, ECALL, EBREAK 처리 방침

#### FENCE (opcode = 7'b000_1111)
- RV32I 스펙상 메모리 순서(Memory Ordering) 보장 명령어.
- 단일 사이클 프로세서에서는 메모리 접근이 항상 순서대로 완료되므로 **NOP으로 처리**해도 기능적으로 정확하다.
- 처리 방침: `default` 분기 또는 별도 case에서 `reg_w_en=0`, `mem_rw=MEM_NONE`, `pc_sel=PC_PLUS4`로 안전하게 처리.
- 🟡 **Major**: 현재 `ch06_decoder.sv`에 FENCE opcode(`7'b000_1111`) case가 없다. `default`로 `illegal_instr=1`이 세트되므로, 명시적 FENCE NOP 처리를 추가해야 한다.

#### ECALL (opcode = 7'b111_0011, funct12 = 000)
- 운영체제 서비스 요청. 단일 사이클 최소 구현에서는 **NOP 처리** 후 Ch18(CSR/Trap)에서 완성.
- 현재 `ch06_decoder.sv`의 `OP_SYSTEM` case에서 `reg_w_en=0`으로 처리 — 기능적으로 NOP과 동등하여 올바름.
- 교육적으로 "Ch18에서 mcause 레지스터에 환경 호출 코드(11=M-mode)가 기록됨"을 주석으로 명시 권장.

#### EBREAK (opcode = 7'b111_0011, funct12 = 001)
- 디버거 브레이크포인트. ECALL과 opcode 동일, funct12 필드(instr[31:20])로 구분.
- 단일 사이클 최소 구현에서는 **NOP 처리** 후 Ch18에서 완성.
- 현재 `OP_SYSTEM` 처리와 동일하게 묶어도 기능적으로 문제없음.
- 🟢 **Minor**: ECALL과 EBREAK를 단일 `OP_SYSTEM` case로 묶되, `funct12` 구분 로직을 주석으로 남겨 독자가 향후 확장 위치를 인식하도록 안내 권장.

---

## 2. 제어 신호 설계 (진리표)

### 2.1 제어 신호 목록 및 비트 폭

| 신호명 | 비트 폭 | 설명 |
|--------|---------|------|
| `alu_sel` | 4비트 (`alu_op_t`) | ALU 연산 선택 (enum) |
| `imm_sel` | 3비트 (`imm_sel_t`) | 즉치수 타입 선택 (enum) |
| `reg_w_en` | 1비트 | 레지스터 파일 쓰기 인에이블 |
| `mem_rw` | 2비트 (`mem_rw_t`) | 메모리 None/Read/Write |
| `pc_sel` | 2비트 (`pc_sel_t`) | 다음 PC 선택 |
| `wb_sel` | 2비트 (`wb_sel_t`) | Write-Back 소스 선택 |
| `a_sel` | 1비트 | ALU A 입력: 0=rs1, 1=PC |
| `b_sel` | 1비트 | ALU B 입력: 0=rs2, 1=imm |
| `br_un` | 1비트 | 분기 무부호 비교 여부 |

### 2.2 ALUSel 인코딩 (4비트)

`ch06_decoder.sv`의 `alu_op_t` typedef enum 기준:

| 값 | 연산 | 해당 명령어 (예시) |
|----|------|--------------------|
| 4'b0000 (`ALU_ADD`)  | 덧셈 | ADD, ADDI, LW, SW, JAL, JALR, AUIPC |
| 4'b0001 (`ALU_SUB`)  | 뺄셈 | SUB |
| 4'b0010 (`ALU_AND`)  | 비트 AND | AND, ANDI |
| 4'b0011 (`ALU_OR`)   | 비트 OR | OR, ORI |
| 4'b0100 (`ALU_XOR`)  | 비트 XOR | XOR, XORI |
| 4'b0101 (`ALU_SLL`)  | 논리 좌측 시프트 | SLL, SLLI |
| 4'b0110 (`ALU_SRL`)  | 논리 우측 시프트 | SRL, SRLI |
| 4'b0111 (`ALU_SRA`)  | 산술 우측 시프트 | SRA, SRAI |
| 4'b1000 (`ALU_SLT`)  | 부호 있는 비교 | SLT, SLTI |
| 4'b1001 (`ALU_SLTU`) | 부호 없는 비교 | SLTU, SLTIU, BLTU, BGEU |

**주의**: Branch 명령어의 ALU는 항상 ADD(`ALU_ADD`)를 사용하여 분기 목표 주소(PC + imm_B)를 계산한다. 분기 조건 판정은 별도의 `branch_comparator` 모듈에서 처리한다.

### 2.3 ImmSel 인코딩 (3비트)

`ch04_imm_gen.sv`(Ch04 원본)와 `ch06_decoder.sv`의 `imm_sel_t`를 비교하면 **불일치**가 발견된다.

| 값 | ch04_imm_gen.sv | ch06_decoder.sv (imm_sel_t) |
|----|-----------------|------------------------------|
| 3'b000 | I 타입 (`IMM_I`) | `IMM_I = 3'b000` |
| 3'b001 | S 타입 (`IMM_S`) | `IMM_S = 3'b001` |
| 3'b010 | B 타입 (`IMM_B`) | `IMM_B = 3'b010` |
| 3'b011 | U 타입 (`IMM_U`) | `IMM_U = 3'b011` |
| 3'b100 | J 타입 (`IMM_J`) | `IMM_J = 3'b100` |
| 3'b101 | R 타입 (즉치수 없음) | (없음 — R 타입은 b_sel=0이므로 미사용) |

**확인**: `ch04_imm_gen.sv`의 `imm_sel` 코드와 `ch06_decoder.sv`의 `imm_sel_t` enum 값이 일치한다. 단, `ch04_imm_gen.sv`의 포트명이 `inst`/`imm_sel`/`imm_out`이고 `ch06_single_cycle_top.sv`의 `immediate_generator` 모듈 포트명은 `instr`/`imm_sel`/`imm`이다.

🔴 **Critical**: `ch06_single_cycle_top.sv`에는 `immediate_generator`가 인라인 재정의되어 있다. Ch04의 `imm_gen` 모듈과 포트 이름/시그니처가 다르다(`inst` vs `instr`, `imm_out` vs `imm`). 6.3절에서 Top-Level 연결 시 **Ch04 모듈을 재사용하는 경우** 포트명 매핑을 명시해야 한다. 챕터에서 Ch04 코드를 그대로 재사용하는지, 아니면 Ch06 내에 새로 정의하는지 방침을 명확히 해야 한다.

### 2.4 명령어 타입별 제어 신호 진리표

| 명령어 타입 | 예시 | RegWEn | MemRW | WBSel | ASel | BSel | ImmSel | PCSel (기본) | ALUSel |
|-------------|------|--------|-------|-------|------|------|--------|--------------|--------|
| R 타입      | ADD  | 1      | NONE  | ALU   | rs1  | rs2  | — (미사용) | PC+4 | funct3/funct7 결정 |
| I-ALU       | ADDI | 1      | NONE  | ALU   | rs1  | imm  | I      | PC+4 | funct3/funct7 결정 |
| Load        | LW   | 1      | READ  | MEM   | rs1  | imm  | I      | PC+4 | ADD |
| Store       | SW   | 0      | WRITE | —     | rs1  | imm  | S      | PC+4 | ADD |
| Branch      | BEQ  | 0      | NONE  | —     | PC   | imm  | B      | 조건부 BRANCH/PC+4 | ADD |
| JAL         | JAL  | 1      | NONE  | PC+4  | PC   | imm  | J      | BRANCH (항상) | ADD |
| JALR        | JALR | 1      | NONE  | PC+4  | rs1  | imm  | I      | JALR | ADD |
| LUI         | LUI  | 1      | NONE  | ALU   | (x0) | imm | U      | PC+4 | ADD |
| AUIPC       | AUIPC| 1      | NONE  | ALU   | PC   | imm  | U      | PC+4 | ADD |
| ECALL/EBREAK| —    | 0      | NONE  | —     | —    | —    | —      | PC+4 | — |

🟡 **Major**: LUI의 ASel이 `rs1=0`로 처리되는데, 현재 `ch06_decoder.sv`에서 `a_sel=1'b0`(rs1 선택)으로 설정하고 "ALU A 입력을 0으로 설정하여 imm을 그대로 전달"이라고 주석에 언급하고 있다. 그러나 레지스터 파일에서 x0(rs1_addr=5'b0)은 항상 0을 반환하므로, LUI의 rs1_addr 필드가 실제 x0이 아닌 경우(`instr[19:15] != 5'b0`)에는 rs1_data가 0이 아닐 수 있다. **6.3절에서 명시적으로 `a_sel=1'b0`이고 명령어의 rs1 필드가 x0임을 RISC-V 스펙에서 요구함을 설명해야 한다.** 스펙 Vol. I, Section 2.4: LUI의 rs1은 명령어 인코딩에서 상관없는 필드(don't-care)이므로 assembler가 x0으로 채운다. 교재에서 이 점을 명시해야 혼란을 방지할 수 있다.

---

## 3. 단일 사이클 Top-Level 모듈 포트 연결 계획

### 3.1 모듈 계층 구조

```
rv32i_single_cycle_top
├── instruction_memory (ch05)  ← pc → instr
├── control_unit (ch06)
│   ├── instruction_decoder (ch06)
│   └── branch_comparator (ch06)
├── register_file (ch04)       ← rs1/rs2 비동기 읽기, rd 동기 쓰기
├── immediate_generator (ch04/ch06)
├── alu (ch04)
├── data_memory (ch05)         ← 동기 쓰기, 비동기 읽기
└── MUX들 (assign 문으로 구현)
    ├── ALU-A MUX: rs1_data / pc
    ├── ALU-B MUX: rs2_data / imm
    └── WB MUX: alu_result / dmem_rdata_ext / pc_plus4
```

### 3.2 신호 연결 매핑 (Ch04/Ch05 모듈 포트 기준)

#### Ch04 모듈 원본 포트 vs Ch06 top-level 신호

| Ch04 모듈 | Ch04 포트명 | Ch06 top-level 신호 | 방향 |
|-----------|------------|---------------------|------|
| `register_file` | `clk` | `clk` | in |
| `register_file` | `rst_n` | `rst_n` | in |
| `register_file` | `rs1_addr` | `rs1_addr` (from control_unit) | in |
| `register_file` | `rs2_addr` | `rs2_addr` (from control_unit) | in |
| `register_file` | `rd_addr` | `rd_addr` (from control_unit) | in |
| `register_file` | `rd_data` | `rd_data` (from WB MUX) | in |
| `register_file` | `reg_wr_en` | `reg_w_en` (from control_unit) | in |
| `register_file` | `rs1_data` | `rs1_data` | out |
| `register_file` | `rs2_data` | `rs2_data` | out |
| `alu` | `operand_a` | `alu_a` (from A MUX) | in |
| `alu` | `operand_b` | `alu_b` (from B MUX) | in |
| `alu` | `alu_ctrl` | `alu_sel` (from control_unit, 4비트) | in |
| `alu` | `alu_result` | `alu_result` | out |
| `alu` | `alu_zero` | (미사용 — 분기 조건은 branch_comparator가 처리) | out |
| `imm_gen` | `inst` | `instr` | in |
| `imm_gen` | `imm_sel` | `imm_sel` (from control_unit, 3비트) | in |
| `imm_gen` | `imm_out` | `imm` | out |

#### Ch05 모듈 원본 포트 vs Ch06 top-level 신호

| Ch05 모듈 | Ch05 포트명 | Ch06 top-level 신호 | 방향 |
|-----------|------------|---------------------|------|
| `instruction_memory` | `pc_i` | `pc` | in |
| `instruction_memory` | `instr_o` | `instr` | out |
| `data_memory` | `clk_i` | `clk` | in |
| `data_memory` | `rst_ni` | `rst_n` | in |
| `data_memory` | `addr_i` | `alu_result` | in |
| `data_memory` | `wdata_i` | `rs2_data` | in |
| `data_memory` | `mem_write_i` | `mem_rw == MEM_WRITE` | in |
| `data_memory` | `funct3_i` | `funct3` | in |
| `data_memory` | `rdata_o` | `dmem_rdata` | out |

🔴 **Critical**: Ch05의 `data_memory`는 `mem_write_i` (1비트 논리 신호)를 사용하는 반면, `ch06_single_cycle_top.sv`의 인라인 재정의 `data_memory`는 `mem_rw` (`mem_rw_t` enum 2비트)를 사용한다. 교재에서 Ch04/Ch05 원본 모듈을 그대로 재사용하는 것을 원칙으로 한다면, **Ch05 DMEM의 인터페이스(`mem_write_i` 1비트)에 맞게** top-level에서 `assign mem_write = (mem_rw == MEM_WRITE);`와 같은 변환이 필요하다. 6.3절에서 이 인터페이스 불일치를 명확히 설명하고 해결 방법을 코드로 제시해야 한다.

🔴 **Critical**: Ch05의 `data_memory`는 이미 내부적으로 로드 데이터의 부호/무부호 확장(`rdata_o`)을 완료하여 출력한다. 반면 `ch06_single_cycle_top.sv`의 인라인 재정의 버전은 raw `rdata`를 출력하고 top-level에서 다시 확장 로직을 갖는다. Ch05 원본을 재사용하면 top-level의 `dmem_rdata_ext` 로직이 중복된다. 6.3절 설계에서 어느 방식을 채택할지 명확히 정의해야 한다. **권장**: Ch05 원본 `data_memory` 재사용 + top-level 확장 로직 제거 (단, 이 경우 `funct3`이 비-Load 명령어에서도 `data_memory`로 전달되므로 동작 무결성 확인 필요).

🟡 **Major**: Ch04 `alu.sv`의 포트명은 `operand_a`, `operand_b`, `alu_ctrl`, `alu_result`이고 `ch06_single_cycle_top.sv`의 인라인 재정의 `alu`는 `a`, `b`, `alu_op`, `result`를 사용한다. 6.3절에서 Ch04 원본을 연결할 때 포트명 매핑을 명시해야 한다.

### 3.3 MUX 위치 및 선택 신호

| MUX 이름 | 위치 | 선택 신호 | 입력 0 | 입력 1 | 출력 |
|----------|------|-----------|--------|--------|------|
| ALU-A MUX | 레지스터 파일 → ALU 사이 | `a_sel` | `rs1_data` | `pc` | `alu_a` |
| ALU-B MUX | 레지스터 파일/ImmGen → ALU 사이 | `b_sel` | `rs2_data` | `imm` | `alu_b` |
| PC MUX | PC 레지스터 입력 | `pc_sel` (2비트) | `pc_plus4` (00) | `alu_result` (01, BRANCH) | `pc_next`; JALR(10) = `alu_result & ~1` |
| WB MUX | ALU/DMEM/PC+4 → RF 쓰기 | `wb_sel` (2비트) | `alu_result` (00) | `dmem_rdata_ext` (01) | `rd_data`; PC+4 (10) |

**JALR LSB 클리어**: JALR 목표 주소의 최하위 비트는 스펙에 따라 반드시 0으로 설정해야 한다 (`pc_next = alu_result & 32'hFFFF_FFFE`). 현재 `ch06_single_cycle_top.sv`에 올바르게 구현되어 있다.

### 3.4 데이터패스 임계 경로(Critical Path) 분석

단일 사이클 프로세서에서 가장 긴 조합 논리 경로가 최대 동작 주파수를 결정한다.

#### Load 명령어 임계 경로 (가장 긴 경로)

```
PC_reg → IMEM(비동기) → 디코더(조합) → RF(비동기 읽기) → [ALU-A MUX] → ALU(ADD) → DMEM(비동기 읽기) → [WB MUX] → RF_write_data → RF_reg (클록 에지)
```

구성 요소별 Artix-7 예상 지연:

| 단계 | 구성 요소 | 예상 지연 |
|------|-----------|-----------|
| IMEM 읽기 | 분산 RAM 비동기 읽기 | ~2.0 ns |
| 디코더 | always_comb case 문 | ~1.5 ns |
| RF 읽기 | 분산 RAM 비동기 읽기 | ~2.0 ns |
| ALU-A MUX | assign 조합 | ~0.3 ns |
| ALU (ADD) | 32비트 가산기 (LUT 체인) | ~4.0 ns |
| DMEM 읽기 | 분산 RAM 비동기 읽기 | ~2.0 ns |
| WB MUX | assign 조합 | ~0.3 ns |
| RF 셋업 타임 | FF 셋업 | ~0.1 ns |
| **합계** | | **~12.2 ns** |

예상 최대 주파수: 1 / 12.2 ns ≈ **82 MHz** (이상적 경우)
실제 Vivado P&R 후: 라우팅 지연 포함 약 **25~35 MHz** 예상 (Basys 3 Artix-7 XC7A35T 기준).

#### R 타입/I-ALU 임계 경로

```
PC_reg → IMEM → 디코더 → RF(읽기) → ALU → [WB MUX] → RF_reg
```
Load 경로보다 DMEM 읽기 단계가 없어 약 2~3 ns 더 짧다.

#### Branch 임계 경로

```
PC_reg → IMEM → 디코더 → RF(읽기) → branch_comparator → pc_sel → [PC MUX] → PC_reg
AND:
PC_reg → IMEM → 디코더 → [ALU-A MUX(PC)] → ALU(ADD) → [PC MUX] → PC_reg
```
두 경로가 병렬로 존재하며, 두 경로 중 긴 쪽이 실제 임계 경로가 된다.

---

## 4. Basys 3 합성 예상

### 4.1 예상 최대 주파수

**예상 범위: 25~35 MHz**

근거:
1. Artix-7 XC7A35T의 LUT 지연은 약 0.5~1.0 ns/LUT, 라우팅 지연 포함 시 32비트 ALU의 조합 경로는 약 8~12 ns.
2. 분산 RAM(LUTRAM) 비동기 읽기는 약 2~4 ns.
3. IMEM → 디코더 → RF → ALU → DMEM → WB MUX → RF_setup 전체 경로가 약 28~40 ns.
4. Vivado 합성+P&R 후 WNS(Worst Negative Slack)가 기준 클록 40 ns(25 MHz)에서 약 0~-5 ns 예상.
5. 30 MHz(33 ns) 기준 클록으로 합성 시 대부분의 경우 타이밍 만족 가능.

**파트 2 마일스톤(피보나치 실행) 권장 클록**: **25 MHz** (안전 마진 확보). Basys 3 온보드 100 MHz 클록을 MMCM으로 4분주하여 사용.

### 4.2 임계 경로 구성 요소

Load 명령어(LW)의 데이터패스가 가장 긴 임계 경로를 형성한다:

```
IMEM 분산 RAM → 명령어 디코더(case 문) → RF 분산 RAM →
ALU 32비트 가산기 → DMEM 분산 RAM → WB MUX → RF 셋업
```

Vivado Timing Report에서 확인할 수 있는 주요 항목:
- `Worst Negative Slack (WNS)`: 음수이면 타이밍 위반
- `Total Negative Slack (TNS)`: 모든 타이밍 위반 경로의 합
- `Worst Hold Slack (WHS)`: 홀드 타임 위반 (단일 사이클에서는 일반적으로 문제없음)

### 4.3 LUT / BRAM / LUTRAM 예상 사용량

| 리소스 | 예상 사용량 | 비율 (XC7A35T 기준) | 근거 |
|--------|------------|---------------------|------|
| LUT (Logic) | 1,200 ~ 2,000 | 6~10% | ALU 32비트: ~300 LUT, 디코더: ~150 LUT, MUX: ~200 LUT |
| LUT (RAM / LUTRAM) | 1,024 ~ 2,048 | 5~10% | RF 32×32b: ~512 LUTRAM, IMEM 1K×32b: ~1024 LUTRAM |
| BRAM | 0 ~ 2 | 0~5% | DMEM가 LUTRAM이면 0, BRAM 추론 시 1~2개 (36Kb) |
| FF (Flip-Flop) | 64 ~ 96 | 0.1% | PC(32) + RF 쓰기 FF(32) = ~64개 |
| DSP48E1 | 0 | 0% | 32비트 ALU는 LUT로 합성 (단순 가산기/감산기) |
| I/O | 2 | 2% | clk, rst_n |

**Basys 3 자원 제약 이내**: XC7A35T는 LUT 20,800개, BRAM 50×36Kb, FF 41,600개로 본 설계는 여유 있게 수용 가능.

🟢 **Minor**: IMEM을 분산 RAM으로 구성하면 1K×32b = 32,768비트 = ~512 LUTRAM이 필요하다. Artix-7의 분산 RAM 총 용량은 LUT의 절반(약 10,400 LUT-RAM)으로 수용 가능하나, 교재에서 IMEM 크기를 4K 이상으로 늘릴 경우 BRAM 사용을 권장함을 명시해야 한다.

---

## 5. 검증 프로그램 설계

### 5.1 명령어 타입 전체 커버리지 테스트 시퀀스

6.4절 통합 시뮬레이션에서는 다음 순서로 모든 명령어 타입을 커버하는 프로그램을 실행한다.

#### 단계 1: 기본 검증 프로그램 (단위 명령어 테스트)

```asm
# --- R 타입 검증 ---
ADDI  x1, x0, 10      # x1 = 10
ADDI  x2, x0, 3       # x2 = 3
ADD   x3, x1, x2      # x3 = 13     [ADD 검증]
SUB   x4, x1, x2      # x4 = 7      [SUB 검증]
AND   x5, x1, x2      # x5 = 2      [AND 검증: 10&3=2]
OR    x6, x1, x2      # x6 = 11     [OR 검증: 10|3=11]
XOR   x7, x1, x2      # x7 = 9      [XOR 검증: 10^3=9]
SLL   x8, x1, x2      # x8 = 80     [SLL 검증: 10<<3=80]
SRL   x9, x1, x2      # x9 = 1      [SRL 검증: 10>>3=1]
ADDI  x10, x0, -1     # x10 = 0xFFFFFFFF
SRA   x11, x10, x2    # x11 = 0xFFFFFFFF [SRA 검증: 부호 확장]
SLT   x12, x2, x1     # x12 = 1     [SLT: 3 < 10 = true]
SLTU  x13, x2, x1     # x13 = 1     [SLTU: 3 < 10 = true]

# --- I 타입 ALU 검증 ---
ADDI  x14, x0, 100    # x14 = 100   [ADDI 검증]
ANDI  x15, x14, 0xFF  # x15 = 100   [ANDI 검증]
ORI   x16, x0, 0x5A5  # x16 = 0x5A5 [ORI 검증]
XORI  x17, x16, -1    # x17 = ~0x5A5 [XORI 검증]
SLLI  x18, x1, 4      # x18 = 160   [SLLI 검증]
SRLI  x19, x14, 2     # x19 = 25    [SRLI 검증]
SRAI  x20, x10, 4     # x20 = 0xFFFFFFF [SRAI 검증]

# --- U 타입 검증 ---
LUI   x21, 0x12345    # x21 = 0x12345000 [LUI 검증]
AUIPC x22, 0x00001    # x22 = PC + 0x1000 [AUIPC 검증]

# --- S/L 타입 검증 ---
LUI   x23, 0x10       # x23 = 0x10000 (데이터 메모리 기저 주소)
SW    x1, 0(x23)      # mem[0x10000] = 10  [SW 검증]
SH    x1, 4(x23)      # mem[0x10004] = 0x000A [SH 검증]
SB    x1, 8(x23)      # mem[0x10008] = 0x0A [SB 검증]
LW    x24, 0(x23)     # x24 = 10    [LW 검증]
LH    x25, 4(x23)     # x25 = 10    [LH 검증]
LB    x26, 8(x23)     # x26 = 10    [LB 검증]
LHU   x27, 4(x23)     # x27 = 10    [LHU 검증 — 무부호]
LBU   x28, 8(x23)     # x28 = 10    [LBU 검증 — 무부호]

# --- B 타입 검증 ---
ADDI  x1, x0, 5
ADDI  x2, x0, 5
BEQ   x1, x2, pass1   # 같으면 분기 [BEQ taken 검증]
ADDI  x0, x0, 0       # 이 명령어는 실행되면 안 됨 (테스트 실패)
pass1:
BNE   x1, x2, fail1   # 다르지 않으면 분기 안 함 [BNE not-taken 검증]
# ... (BLT, BGE, BLTU, BGEU 유사 검증)

# --- J 타입 검증 ---
JAL   x29, jal_target  # rd = PC+4, PC = 목표 [JAL 검증]
# 실행되면 안 됨
jal_target:
JALR  x30, x29, 0      # PC = x29 (복귀 주소) [JALR 검증]
```

#### 단계 2: 피보나치 수열 프로그램 (Part 2 마일스톤)

**목표**: F(0)=0, F(1)=1, ..., F(10)=55, F(11)=89를 계산하여 DMEM 0x1000 번지부터 연속 저장.

**사용 명령어 타입**: ADDI(I), LUI(U), ADD(R), SW(S), BLT(B), JAL(J)

현재 `ch06_fibonacci.hex`의 구조적 검증:

| 주소 | 명령어 코드 | 니모닉 | 검증 결과 |
|------|------------|--------|-----------|
| 0x000 | 00000513 | ADDI x10, x0, 0 | ✅ 올바름 |
| 0x004 | 00100593 | ADDI x11, x0, 1 | ✅ 올바름 |
| 0x008 | 00000693 | ADDI x13, x0, 0 | ✅ 올바름 |
| 0x00C | 00A00713 | ADDI x14, x0, 10 | ✅ 올바름 |
| 0x010 | 000017B7 | LUI x15, 0x1 | ✅ 올바름 (x15 = 0x1000) |
| 0x014 | 00A7A023 | SW x10, 0(x15) | ✅ 올바름 |
| 0x018 | 00478793 | ADDI x15, x15, 4 | ✅ 올바름 |
| 0x01C | 00B7A023 | SW x11, 0(x15) | ✅ 올바름 |
| 0x020 | 00478793 | ADDI x15, x15, 4 | ✅ 올바름 |
| 0x024 | 00B50633 | ADD x12, x10, x11 | ✅ 올바름 |
| 0x028 | 00C7A023 | SW x12, 0(x15) | ✅ 올바름 |
| 0x02C | 00478793 | ADDI x15, x15, 4 | ✅ 올바름 |
| 0x030 | 000585B3 | ADD x11, x11, x0 | ✅ (주석에 "ADDI"라 오기되었으나 실제 코드는 올바른 ADDI) |
| 0x030 (수정) | 00058513 | ADDI x10, x11, 0 | ✅ 올바름 (a0 = a1) |
| 0x034 | 00060593 | ADDI x11, x12, 0 | ✅ 올바름 (a1 = a2) |
| 0x038 | 00168693 | ADDI x13, x13, 1 | ✅ 올바름 |
| 0x03C | FEE6C4E3 | BLT x13, x14, -24 | ✅ 올바름 (루프 시작 0x024로 분기) |
| 0x040 | 00000013 | NOP | ✅ |
| 0x044 | FFDFF06F | JAL x0, -4 | ✅ 무한 루프 |

🔴 **Critical**: `ch06_fibonacci.hex` 파일 내에 주소 0x030에 **두 개의 명령어 코드가 중복 기재**되어 있다:
- 줄 11: `000585B3` (실제 코드)
- 줄 12: `00058513` (주석에서 "수정"이라 표기)

16진수 파일로서 한 줄이 하나의 명령어임을 가정하면, `$readmemh`는 두 값을 모두 별개 워드로 읽어 0x030=`000585B3`, 0x034=`00058513`으로 로드한다. 이는 루프 내 명령어 수와 BLT 분기 오프셋 계산에 영향을 준다. **실제 메모리 내용과 주석의 의도가 일치하는지 재검증하고 불필요한 중복 인코딩을 제거해야 한다.**

상세 BLT 오프셋 검증:
- BLT 위치: 0x03C (12번째 명령어 이후, 중복 줄 포함 시 0x040에 위치할 수 있음)
- 루프 시작: 0x024
- 오프셋: 0x024 - 0x03C = -0x18 = -24 → `FEE6C4E3` 인코딩 검증 필요.
- 만약 중복 줄 때문에 BLT가 0x044에 있다면 오프셋이 달라짐.

🟡 **Major**: `ch06_fibonacci_mem.hex` 파일도 별도로 존재하는데, `ch06_fibonacci.hex`와의 차이가 명확하지 않다. 테스트벤치에서 `IMEM_INIT = "ch06_fibonacci_mem.hex"`를 사용하므로, 두 파일 중 어느 것이 실제 실행 파일인지 교재에서 명확히 구분해야 한다.

### 5.2 검증 커버리지 목표

| 명령어 타입 | 커버 여부 | 검증 방법 |
|-------------|-----------|-----------|
| R 타입 (ADD/SUB 등) | ✅ 피보나치 루프에서 ADD 사용 | 레지스터 결과 확인 |
| I-ALU (ADDI 등) | ✅ 초기화 및 루프 카운터 | 레지스터 결과 확인 |
| Load (LW) | ❌ 피보나치 프로그램에 미포함 | 별도 로드 검증 필요 |
| Store (SW) | ✅ 피보나치 결과 저장 | DMEM 내용 확인 |
| Branch (BLT) | ✅ 루프 종료 조건 | 루프 카운터 확인 |
| JAL | ✅ 무한 루프 | PC 고정 확인 |
| JALR | ❌ 피보나치 프로그램에 미포함 | 별도 서브루틴 테스트 필요 |
| LUI | ✅ 메모리 주소 초기화 | 레지스터 상위 비트 확인 |
| AUIPC | ❌ 미포함 | 단위 명령어 테스트 필요 |
| SH/SB | ❌ 미포함 | 단위 명령어 테스트 필요 |
| LH/LB/LHU/LBU | ❌ 미포함 | 단위 명령어 테스트 필요 |
| BEQ/BNE/BGE/BLTU/BGEU | ❌ 미포함 | 별도 분기 테스트 필요 |
| SLT/SLTU | ❌ 미포함 | 단위 명령어 테스트 필요 |

🟡 **Major**: 6.4절 검증 프로그램이 피보나치만으로는 RV32I 전체 명령어 커버리지를 달성하지 못한다. 6.4절에는 두 단계 검증을 권장한다:
1. **단계 1**: 전체 명령어 타입 단위 테스트 프로그램 (위 5.1절 기술)
2. **단계 2**: 피보나치 통합 테스트 (Part 2 마일스톤)

---

## 6. 기술적 위험 사항

### 🔴 Critical

#### [CRITICAL-1] 포트 인터페이스 불일치 — Ch04/Ch05 원본 모듈 재사용 시

**문제**: `ch06_single_cycle_top.sv`에는 모든 서브모듈이 인라인 재정의되어 있다. 교재의 설계 원칙이 "Ch04/Ch05에서 만든 모듈을 그대로 재사용"이라면 다음 불일치를 해결해야 한다:
- `register_file`: `reg_wr_en` (Ch04) vs `reg_w_en` (Ch06)
- `alu`: `operand_a/b`, `alu_ctrl`, `alu_result`, `alu_zero` (Ch04) vs `a`, `b`, `alu_op`, `result` (Ch06)
- `imm_gen`: `inst`, `imm_out` (Ch04) vs `instr`, `imm` (Ch06)
- `data_memory`: `mem_write_i` 1비트 (Ch05) vs `mem_rw` 2비트 enum (Ch06)
- `instruction_memory`: `pc_i`, `instr_o`, `ADDR_WIDTH` 파라미터 (Ch05) vs `addr`, `instr`, `DEPTH` 파라미터 (Ch06)

**권장 해결책**: 6.3절에서 Ch04/Ch05 원본 모듈을 그대로 사용하는 wrapper 또는 연결 코드를 명시하거나, Ch06용 인터페이스 표준을 정의하고 "Ch04/Ch05 코드는 이 챕터의 구현과 인터페이스가 일부 다를 수 있으며, 본 챕터 코드가 통합 설계의 최종 기준"임을 명확히 해야 한다.

#### [CRITICAL-2] ch06_fibonacci.hex 중복 명령어 코드

**문제**: `ch06_fibonacci.hex`의 주소 0x030 부근에 `000585B3`과 `00058513` 두 줄이 연속으로 존재한다. `$readmemh` 동작상 두 값이 각각 별개 메모리 워드로 로드되어 루프 오프셋 계산이 틀어질 수 있다.
**조치**: hex 파일을 RISC-V 어셈블러(riscv-gnu-toolchain)로 재생성하여 검증하거나, 수동으로 각 명령어 인코딩을 재확인하여 단일 버전으로 통일해야 한다.

#### [CRITICAL-3] LUI의 A 입력 처리 — rs1 don't care 명세

**문제**: 현재 디코더에서 LUI에 대해 `a_sel=1'b0`(rs1 선택)으로 설정하고 ALU에서 `a + imm`를 계산한다. RISC-V 스펙에서 LUI의 rs1 필드는 don't-care이므로 assembler가 x0으로 채우지만, 임의의 바이너리 코드에서 rs1 필드가 x0이 아닐 경우 잘못된 결과가 나온다. 교육적으로 "LUI의 rs1은 항상 x0이어야 하며 assembler가 보장한다"고 명시하거나, 하드웨어에서 `alu_a = 32'h0`을 강제하는 별도 MUX를 추가해야 한다.

### 🟡 Major

#### [MAJOR-1] FENCE opcode 미처리 → illegal_instr 세트

**문제**: `ch06_decoder.sv`에서 FENCE opcode(`7'b000_1111`)가 명시적 case로 처리되지 않아 `default` 분기에서 `illegal_instr=1`이 된다. 단순 프로그램에서는 FENCE를 사용하지 않으므로 기능적 문제는 없지만, 교재에서 `illegal_instr` 신호의 의미를 설명할 때 혼란을 줄 수 있다.
**조치**: FENCE opcode를 명시적 case로 추가하여 NOP 처리.

#### [MAJOR-2] 검증 프로그램 명령어 커버리지 불완전

**문제**: 피보나치 프로그램만으로는 Load 명령어, JALR, AUIPC, B 타입 전체(BEQ/BNE/BGE/BLTU/BGEU), 시프트 명령어 등이 검증되지 않는다.
**조치**: 6.4절에 단위 명령어 테스트 섹션을 추가하거나, 테스트벤치의 `verify_instructions()` task를 확장하여 전체 명령어 타입을 커버해야 한다.

#### [MAJOR-3] br_un 신호의 조합 루프(Combinational Loop) 가능성

**문제**: `control_unit`에서 `branch_comparator`에 `br_un`을 입력하고, `instruction_decoder`에서도 `br_un`을 출력한다. 현재 코드에서 `br_un`은 디코더의 출력이면서 동시에 비교기의 입력인데, 비교기의 출력(`br_eq`, `br_lt`)이 디코더의 입력(`branch_taken` 결정)에 사용된다. 이 경로가 `always_comb` 내에서 순환 의존성을 형성하지는 않는지 시뮬레이터에서 검증 필요. 현재 코드 분석상 순환 루프는 없지만(디코더 내 `br_un`은 funct3에서 직접 계산), Vivado 합성 시 경고 여부를 확인해야 한다.

#### [MAJOR-4] DMEM 비정렬 접근(Misaligned Access) 미처리

**문제**: 현재 `data_memory` 구현은 비정렬 접근(예: 홀수 주소에 LW 접근)에 대한 예외를 처리하지 않는다. 단일 사이클 교육 목적에서는 허용 가능하지만, 교재에서 "비정렬 접근은 미정의 동작(Undefined Behavior)이며 Ch18에서 Address Misaligned 예외로 처리됨"을 명시해야 한다.

### 🟢 Minor

#### [MINOR-1] ch06_fibonacci.hex 주석 형식

**문제**: `.hex` 파일 내에 `//` 주석이 포함되어 있다. `$readmemh`는 `//` 주석을 지원하므로 기능적으로는 문제없다. 단, 실제 FPGA COE 파일 변환 시 주석 처리 방식이 다를 수 있으므로 6.5절 합성 단계에서 주석 없는 순수 hex 파일 사용을 권장.

#### [MINOR-2] alu_zero 신호 미활용

**문제**: Ch04 `alu.sv`는 `alu_zero` 신호를 출력하지만, `ch06_single_cycle_top.sv`에서 사용되지 않는다. 분기 조건 판정을 `branch_comparator`가 담당하므로 `alu_zero`는 불필요하다. 교재에서 "단일 사이클에서는 별도의 분기 비교기를 사용하므로 `alu_zero`는 미사용"임을 명시하고, Ch07 이후 파이프라인 설계와의 비교 관점으로 언급 가능.

#### [MINOR-3] 테스트벤치 사이클 수 하드코딩

**문제**: `rv32i_single_cycle_tb.sv`에서 `repeat (120) @(posedge clk)`로 실행 사이클을 하드코딩했다. 프로그램 수정 시 사이클 수도 함께 수정해야 하는 유지보수 부담이 있다.
**개선 방향**: 프로그램 종료를 감지하는 조건(예: PC가 특정 주소에 머무는 경우)을 테스트벤치에서 감지하여 자동 종료하는 방식 권장.

#### [MINOR-4] typedef enum의 패키지 분리 권장

**문제**: `alu_op_t`, `imm_sel_t`, `wb_sel_t`, `pc_sel_t`, `mem_rw_t` 등의 typedef enum이 `ch06_decoder.sv` 파일 최상단에 정의되어 있다. 여러 모듈에서 공유하려면 SystemVerilog package로 분리하는 것이 표준적이다.
**교육적 처리**: 파이프라인 챕터(Ch09 이상)에서 패키지 분리를 소개하는 것으로 미루고, 현재는 단일 파일 내 typedef를 유지하면서 "이후 패키지 분리로 확장 예정"을 주석으로 명시.

---

## 7. 요약 및 집필 지침

### 7.1 집필 시 필수 반영 사항 (Critical → Major 순)

1. **[CRITICAL-1] 포트 인터페이스 방침 결정**: Ch04/Ch05 원본 재사용 vs Ch06 인라인 재정의 중 하나를 명확히 선택하고, 두 방식의 차이를 독자에게 설명.
2. **[CRITICAL-2] fibonacci.hex 파일 재검증**: 중복 명령어 코드 제거 및 전체 인코딩 재확인.
3. **[CRITICAL-3] LUI A 입력 처리**: 스펙 기반 설명 추가 또는 하드웨어 수정.
4. **[MAJOR-1] FENCE NOP 처리 추가**: 디코더에 명시적 case 추가.
5. **[MAJOR-2] 검증 프로그램 확장**: 전체 명령어 타입 커버리지 달성.

### 7.2 6.5절 Vivado 타이밍 분석을 위한 사전 안내

독자가 Vivado 타이밍 리포트를 처음 접할 때 혼란을 방지하기 위해 다음 개념을 6.1절 또는 6.5절 도입부에서 설명해야 한다:

- **슬랙(Slack)**: "타이밍 여유 시간". `슬랙 = 요구 도착 시간 - 실제 도착 시간`. 양수이면 타이밍 만족, 음수이면 타이밍 위반.
- **WNS (Worst Negative Slack)**: 모든 경로 중 가장 나쁜(가장 음수인) 슬랙. 0 이상이면 설계가 요구 주파수를 만족.
- **TNS (Total Negative Slack)**: 타이밍 위반이 있는 모든 경로의 슬랙 합. 0이면 위반 없음.
- **임계 경로(Critical Path)**: WNS를 결정하는 가장 느린 조합 논리 경로. 이 경로를 최적화하면 최대 주파수를 높일 수 있다.
- **최대 주파수(Fmax)**: `Fmax = 1 / (클록 주기 - WNS)` (현재 클록 주기로 실패한 경우).

### 7.3 Part 2 마일스톤 성취감 설계

6.4절 시뮬레이션 후 "피보나치 수열이 데이터 메모리에 올바르게 저장되었습니다"라는 `[PASS]` 메시지가 출력되는 순간이 독자에게 **Part 2 최대 성취감 지점**이다. 테스트벤치 출력 형식을 명확히 하고, 교재 본문에서 이 성취감을 충분히 강조해야 한다.

---

*검토 완료. 편집장 최종 승인 후 기술 저자 집필 착수 권장.*
