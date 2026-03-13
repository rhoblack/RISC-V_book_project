# Chapter 08 기획 — 기술 리뷰어 의견

**챕터**: Chapter 08 — FSM 기반 제어 유닛
**리뷰어**: 기술 리뷰어 (Technical Reviewer)
**작성일**: 2026-03-11
**검토 기반**: Ch07 확정 데이터패스 (`ch07_multicycle_datapath.sv`), Ch07 기술 리뷰 로그, RISC-V Unprivileged ISA Spec v20191213

---

## 개요

Chapter 08은 Ch07에서 완성한 멀티사이클 데이터패스에 FSM 제어 유닛을 붙여 CPU를 완성하는 챕터다. 기술 리뷰어 관점에서 가장 중요한 세 가지 설계 결정은 다음과 같다:

1. **FSM 상태 정의**: 각 상태에서 어떤 제어 신호를 assert할 것인가
2. **PCSrc 수정**: Ch07 [C1] 이슈(MIPS 방식 2'b10)를 Ch08 FSM에서 올바르게 해결
3. **명령어 타입별 상태 분기**: RV32I 전체 명령어 집합을 커버하는 상태 경로 설계

---

## 1. FSM 상태별 제어 신호 설계

### 전제: Ch07 확정 제어 신호 목록

| 신호명 | 비트폭 | 설명 |
|--------|--------|------|
| `pc_write` | 1 | PC 무조건 쓰기 인에이블 |
| `pc_write_cond` | 1 | 조건부 PC 쓰기 (Branch 시 alu_zero 조건과 AND) |
| `i_or_d` | 1 | 메모리 주소 선택: 0=PC, 1=ALUOut |
| `mem_read` | 1 | 메모리 읽기 인에이블 |
| `mem_write` | 1 | 메모리 쓰기 인에이블 |
| `ir_write` | 1 | IR 쓰기 인에이블 |
| `reg_write` | 1 | 레지스터 파일 쓰기 인에이블 |
| `mem_to_reg` | 2 | WB 데이터 선택: 00=ALUOut, 01=MDR, 10=PC |
| `alu_src_a` | 1 | ALU A 입력: 0=PC, 1=A 레지스터 |
| `alu_src_b` | 2 | ALU B 입력: 00=B 레지스터, 01=상수 4, 10=imm_ext |
| `alu_op` | 4 | ALU 연산 코드 |
| `pc_src` | 2 | PC 소스 선택: 00=ALU 직접, 01=ALUOut, 10=(미사용 재정의 예정) |

> **주의**: `reg_dst` 신호는 Ch07 기술 리뷰 [M1]에서 "RV32I에 불필요"로 판정됨. Ch08 FSM에서는 이 신호를 생성하지 않을 것.

---

### S0: IF (Instruction Fetch) — 모든 명령어 공통

**목적**: PC 주소로 통합 메모리에서 명령어를 읽어 IR에 저장하고, 동시에 PC+4를 계산하여 PC를 갱신한다.

| 제어 신호 | 값 | 이유 |
|-----------|-----|------|
| `mem_read` | 1 | 통합 메모리에서 명령어 인출 |
| `mem_write` | 0 | 쓰기 없음 |
| `i_or_d` | 0 | 메모리 주소 = PC (명령어 주소) |
| `ir_write` | 1 | 인출한 명령어를 IR에 래치 |
| `alu_src_a` | 0 | ALU A = PC |
| `alu_src_b` | 2'b01 | ALU B = 상수 4 |
| `alu_op` | 4'b0000 | ADD (PC + 4 계산) |
| `pc_src` | 2'b00 | PC 소스 = ALU 직접 출력 (PC+4) |
| `pc_write` | 1 | PC에 PC+4를 저장 |
| `pc_write_cond` | 0 | 조건부 갱신 없음 |
| `reg_write` | 0 | 레지스터 파일 쓰기 없음 |
| `mem_to_reg` | 2'b00 | 무관 (reg_write=0이므로) |

> **설계 근거**: IF 단계에서 PC+4 계산과 PC 갱신을 동시에 수행하는 것은 Hennessy-Patterson 멀티사이클 설계의 표준 패턴이다. 단, 이 시점의 PC는 "현재 명령어의 PC"이므로, ALUOut(이전 단계의 ALU 결과)와 구별하기 위해 `pc_src=2'b00`(ALU 직접)을 사용한다.

---

### S1: ID (Instruction Decode / Register Read) — 모든 명령어 공통

**목적**: IR에서 명령어를 디코딩하고, 레지스터 파일에서 rs1, rs2를 읽어 A, B 레지스터에 저장한다. 동시에 분기 주소(PC + imm_B)를 ALU로 미리 계산하여 ALUOut에 저장해 두는 구현도 가능하나, 교재에서는 EX 단계로 분리하는 것이 설명의 명확성을 위해 권장된다.

| 제어 신호 | 값 | 이유 |
|-----------|-----|------|
| `mem_read` | 0 | 메모리 접근 없음 |
| `mem_write` | 0 | 메모리 쓰기 없음 |
| `ir_write` | 0 | IR은 이미 래치됨 — 유지 |
| `alu_src_a` | 0 | ALU A = PC (다음 단계 분기 주소 미리 계산 용도) |
| `alu_src_b` | 2'b10 | ALU B = imm_ext (분기 오프셋) |
| `alu_op` | 4'b0000 | ADD (PC + imm 미리 계산, 필요 시 ALUOut에 저장) |
| `pc_write` | 0 | PC 갱신 없음 |
| `pc_write_cond` | 0 | 조건부 갱신 없음 |
| `reg_write` | 0 | 레지스터 파일 쓰기 없음 |

> **설계 주의**: ID 단계에서 ALU를 활용하여 분기 주소를 미리 계산하는 방식(분기 주소 = PC + imm_B)은 Hennessy-Patterson 교재의 원래 설계다. 그러나 이를 교재에서 채택하면 Branch의 EX 상태가 사라지고 ID에서 직접 PC를 갱신해야 하므로 상태 수가 줄어드는 대신 ID 상태 복잡도가 증가한다. **Ch08 기본 설계에서는 ID를 단순하게 유지하고(미리 계산 없음), 분기 주소를 EX 상태에서 계산하는 방식을 선택한다.** ID 단계 ALU 사용 여부는 절 내에서 두 방식을 비교로 제시하는 것이 교육적으로 유익하다.

---

### S2: EX_R (Execution — R-type)

**목적**: R-type 명령어의 ALU 연산 수행. A 레지스터(rs1)와 B 레지스터(rs2)를 ALU에 입력.

| 제어 신호 | 값 | 이유 |
|-----------|-----|------|
| `alu_src_a` | 1 | ALU A = A 레지스터 (rs1) |
| `alu_src_b` | 2'b00 | ALU B = B 레지스터 (rs2) |
| `alu_op` | 명령어 의존 | funct3/funct7에 따라 ADD/SUB/AND/OR/XOR/SLT/SLTU/SLL/SRL/SRA |
| `pc_write` | 0 | PC 갱신 없음 |
| `reg_write` | 0 | WB는 다음 상태에서 수행 |
| `mem_read` | 0 | — |
| `mem_write` | 0 | — |

> **ALUOp 디코딩 설계**: FSM 제어 유닛은 `alu_op` 4비트를 직접 생성하거나, 2비트 ALUControl 신호를 출력하고 별도 ALU 제어 유닛이 funct3/funct7과 조합하여 4비트를 생성하는 2단계 방식을 선택할 수 있다. 2단계 방식이 FSM 상태 수를 줄이고 구현을 단순화하므로 **교재에서는 2단계 방식을 권장한다**.

---

### S3: EX_I (Execution — I-type 연산: ADDI, ANDI, ORI 등)

**목적**: 즉치수 연산. A 레지스터(rs1)와 imm_ext를 ALU에 입력.

| 제어 신호 | 값 | 이유 |
|-----------|-----|------|
| `alu_src_a` | 1 | ALU A = A 레지스터 (rs1) |
| `alu_src_b` | 2'b10 | ALU B = imm_ext (I-type 즉치수) |
| `alu_op` | funct3/funct7 의존 | ADDI=ADD, ANDI=AND, ORI=OR, XORI=XOR, SLTI=SLT, SLTIU=SLTU, SLLI=SLL, SRLI=SRL, SRAI=SRA |
| `pc_write` | 0 | — |
| `reg_write` | 0 | WB는 다음 상태에서 수행 |

---

### S4: EX_LOAD (Execution — Load Address Calc)

**목적**: LW/LH/LB/LHU/LBU. 주소 계산: A(rs1) + imm_I.

| 제어 신호 | 값 | 이유 |
|-----------|-----|------|
| `alu_src_a` | 1 | ALU A = A 레지스터 (rs1) |
| `alu_src_b` | 2'b10 | ALU B = imm_ext (I-type 즉치수) |
| `alu_op` | 4'b0000 | ADD (주소 계산) |
| `pc_write` | 0 | — |
| `reg_write` | 0 | — |

---

### S5: MEM_LOAD (Memory Read — Load)

**목적**: ALUOut 주소로 메모리에서 데이터를 읽어 MDR에 저장.

| 제어 신호 | 값 | 이유 |
|-----------|-----|------|
| `mem_read` | 1 | 데이터 메모리 읽기 |
| `mem_write` | 0 | — |
| `i_or_d` | 1 | 메모리 주소 = ALUOut (데이터 주소) |
| `pc_write` | 0 | — |
| `reg_write` | 0 | MDR에 래치 후 WB 상태에서 쓰기 |

> **MDR 갱신 타이밍**: Ch07 기술 리뷰 [C2] 이슈에서 확인했듯이, `mem_data_out`이 동기 메모리 출력이므로 MEM_LOAD 상태의 클럭 에지에서 MDR가 갱신된다. WB_LOAD 상태에서 MDR를 읽는 시점에는 올바른 로드 데이터가 보장된다.

---

### S6: WB_LOAD (Write-Back — Load)

**목적**: MDR 데이터를 레지스터 파일의 rd에 저장.

| 제어 신호 | 값 | 이유 |
|-----------|-----|------|
| `reg_write` | 1 | 레지스터 파일 쓰기 |
| `mem_to_reg` | 2'b01 | WB 데이터 = MDR |
| `mem_read` | 0 | — |
| `mem_write` | 0 | — |
| `pc_write` | 0 | — |

---

### S7: EX_STORE (Execution — Store Address Calc)

**목적**: SW/SH/SB. 주소 계산: A(rs1) + imm_S.

| 제어 신호 | 값 | 이유 |
|-----------|-----|------|
| `alu_src_a` | 1 | ALU A = A 레지스터 (rs1) |
| `alu_src_b` | 2'b10 | ALU B = imm_ext (S-type 즉치수) |
| `alu_op` | 4'b0000 | ADD (주소 계산) |
| `pc_write` | 0 | — |
| `reg_write` | 0 | — |

---

### S8: MEM_STORE (Memory Write — Store)

**목적**: ALUOut 주소에 B 레지스터(rs2) 데이터를 메모리에 저장.

| 제어 신호 | 값 | 이유 |
|-----------|-----|------|
| `mem_read` | 0 | — |
| `mem_write` | 1 | 데이터 메모리 쓰기 |
| `i_or_d` | 1 | 메모리 주소 = ALUOut (데이터 주소) |
| `pc_write` | 0 | — |
| `reg_write` | 0 | Store는 레지스터 파일 수정 없음 |

> **Store 완료**: Store는 이 상태에서 종료된다 (WB 없음). 다음 상태는 S0(IF)로 복귀.

---

### S9: EX_BRANCH (Execution — Branch)

**목적**: BEQ/BNE/BLT/BGE/BLTU/BGEU. A-B 비교(ALU 연산)와 분기 주소(ALUOut)를 동시에 처리한다.

**설계 선택**: Branch의 EX 상태에서 두 가지 작업이 필요하다:
1. A(rs1)와 B(rs2)를 비교하여 분기 조건 판단 (alu_zero 또는 별도 비교 결과)
2. 분기 목표 주소 계산: PC + imm_B

이 두 작업을 하나의 ALU로 한 상태에서 처리하는 것은 불가능하다(ALU는 한 번에 하나의 연산). 해결 방법:

**방법 A (권장): 2상태 Branch 처리**
- S9a: 비교 연산 (A SUB B → alu_zero 생성)
- S9b: 분기 주소 계산 (PC + imm_B → ALUOut) 및 조건부 PC 갱신

**방법 B: 1상태 Branch (ID 단계 미리 계산 활용)**
- ID 단계에서 이미 PC+imm_B를 ALUOut에 저장 → EX 상태에서 비교만 수행
- EX에서 비교 결과(alu_zero)와 이미 계산된 ALUOut을 조합하여 PC 갱신

**교재 권장**: 방법 B(ID 단계 미리 계산)가 Branch를 1사이클 짧게 만들지만, ID 상태의 복잡도를 높인다. 교재에서는 **방법 A(2상태)를 기본으로 하고 방법 B를 최적화 예시로 제시**하는 것이 교육적으로 명확하다.

**S9a: EX_BRANCH_CMP (비교)**

| 제어 신호 | 값 | 이유 |
|-----------|-----|------|
| `alu_src_a` | 1 | ALU A = A 레지스터 (rs1) |
| `alu_src_b` | 2'b00 | ALU B = B 레지스터 (rs2) |
| `alu_op` | funct3 의존 | BEQ=SUB(zero), BNE=SUB(!zero), BLT=SLT, BGE=SLT(반전 처리 필요), BLTU=SLTU, BGEU=SLTU(반전 처리 필요) |
| `pc_write` | 0 | 아직 갱신 없음 |
| `pc_write_cond` | 0 | 비교만 수행 |

**S9b: EX_BRANCH_ADDR (주소 계산 + PC 갱신)**

| 제어 신호 | 값 | 이유 |
|-----------|-----|------|
| `alu_src_a` | 0 | ALU A = PC |
| `alu_src_b` | 2'b10 | ALU B = imm_ext (B-type 즉치수) |
| `alu_op` | 4'b0000 | ADD (PC + imm_B) |
| `pc_write` | 0 | 무조건 갱신 없음 |
| `pc_write_cond` | 1 | alu_zero 조건에 따라 PC 갱신 |
| `pc_src` | 2'b01 | PC 소스 = ALUOut (분기 목표 주소) |

> **BGE/BGEU 처리 주의**: BLT는 `SLT`(A < B이면 alu_result=1 → 별도 zero 조건 반전 필요)이고, BGE는 `!(A < B)` 즉 `SLT` 결과를 반전해야 한다. 이를 `pc_write_cond`와 어떻게 연결할지가 설계 복잡도의 핵심이다. 단순 구현에서는 `alu_zero` 신호 외에 `alu_negative`(또는 `alu_lt`)를 추가하거나, 분기 조건별로 별도 상태를 두거나, funct3를 제어 유닛이 직접 참조하여 조건 판단을 내부에서 처리한다. **교재에서는 BEQ/BNE(zero 플래그만 사용)를 먼저 구현하고 BLT/BGE는 심화로 다루는 방식을 권장**한다.

---

### S10: EX_LUI (Execution — LUI)

**목적**: LUI는 rs1 사용 없이 imm_U를 rd에 직접 저장.

| 제어 신호 | 값 | 이유 |
|-----------|-----|------|
| `alu_src_a` | 0 | ALU A = PC (실제로는 무관; imm_U를 단독 사용) |
| `alu_src_b` | 2'b10 | ALU B = imm_ext (U-type: {imm[31:12], 12'b0}) |
| `alu_op` | 4'b0000 | ADD (0 + imm_U = imm_U) |

> **LUI 정확 구현**: LUI의 결과는 단순히 `imm_U`다. ALU A를 0으로 만들어 ADD를 수행하는 것이 가장 단순한 구현이다. `alu_src_a=0`(PC)이 아닌 0 상수를 ALU A에 넣는 방법이 더 정확하지만, 데이터패스에 "ALU A = 0" 입력이 없으므로 대안이 필요하다. **권장**: x0 레지스터(항상 0)를 `rs1_addr=5'd0`으로 읽어 A 레지스터에 저장한 뒤 `alu_src_a=1`(A 레지스터 = 0)로 사용한다. 이를 위해 ID 단계에서 opcode=LUI일 때 레지스터 파일이 x0을 읽도록 처리하거나, 즉치수 생성기가 U-type에서 상위 20비트를 이미 처리하므로 단순히 A=0 OR A=PC 중 하나를 선택한다. **가장 단순한 교육 구현**: `alu_src_a=0`(PC 사용)은 LUI의 결과에 PC를 더하는 오류를 낸다. 따라서 **LUI EX 상태에서 반드시 ALU A = 0을 보장하는 방법을 명시해야 한다**.

---

### S11: EX_AUIPC (Execution — AUIPC)

**목적**: AUIPC = PC + imm_U.

| 제어 신호 | 값 | 이유 |
|-----------|-----|------|
| `alu_src_a` | 0 | ALU A = PC |
| `alu_src_b` | 2'b10 | ALU B = imm_ext (U-type) |
| `alu_op` | 4'b0000 | ADD |

> AUIPC는 LUI와 달리 PC + imm_U이므로 `alu_src_a=0`(PC)이 올바르다.

---

### S12: WB_R_I (Write-Back — R/I-type 및 LUI/AUIPC/JALR 공통)

**목적**: ALUOut을 레지스터 파일의 rd에 저장.

| 제어 신호 | 값 | 이유 |
|-----------|-----|------|
| `reg_write` | 1 | 레지스터 파일 쓰기 |
| `mem_to_reg` | 2'b00 | WB 데이터 = ALUOut |
| `mem_read` | 0 | — |
| `mem_write` | 0 | — |
| `pc_write` | 0 | — |

---

### S13: EX_JAL (Execution — JAL)

**목적**: JAL = PC + imm_J. 복귀 주소 저장과 PC 점프를 수행.

**Ch07 [C1] 이슈 해결**: JAL 점프 목표 주소는 `PC + imm_J`(PC-relative)이다. EX 상태에서 ALU로 이 계산을 수행하고 ALUOut에 저장한다.

| 제어 신호 | 값 | 이유 |
|-----------|-----|------|
| `alu_src_a` | 0 | ALU A = PC (현재 명령어의 PC) |
| `alu_src_b` | 2'b10 | ALU B = imm_ext (J-type 즉치수) |
| `alu_op` | 4'b0000 | ADD (PC + imm_J) |
| `pc_write` | 0 | PC 갱신은 WB_JAL 상태에서 |
| `reg_write` | 0 | WB는 별도 상태에서 |

---

### S14: WB_JAL (Write-Back — JAL)

**목적**: rd에 복귀 주소(PC+4) 저장, PC를 ALUOut(점프 목표)으로 갱신.

| 제어 신호 | 값 | 이유 |
|-----------|-----|------|
| `reg_write` | 1 | rd에 복귀 주소 저장 |
| `mem_to_reg` | 2'b10 | WB 데이터 = PC (현재 명령어 PC+4가 이미 IF 단계에서 PC에 저장됨) |
| `pc_write` | 1 | PC = ALUOut (점프 목표) |
| `pc_src` | 2'b01 | PC 소스 = ALUOut |
| `mem_read` | 0 | — |
| `mem_write` | 0 | — |

> **복귀 주소 = PC+4**: IF 단계에서 이미 `PC ← PC+4`가 수행되었으므로, WB_JAL 상태에서 `mem_to_reg=2'b10`(PC 레지스터)을 선택하면 이미 PC+4가 된 PC 값이 rd에 저장된다. 이 설계는 IF와 WB_JAL 사이에 다른 명령어가 없는(현재 JAL 명령어만 있는) 조건에서 성립한다.

> **중요 주의사항**: IF 단계에서 `pc_write=1`로 PC가 이미 PC+4로 갱신되므로, WB_JAL 단계에서 PC 레지스터의 값은 "현재 JAL 명령어 PC + 4"다. 이는 JAL의 복귀 주소 스펙(`rd = PC+4`)과 일치한다. **단, 이 의존 관계를 교재에서 명확히 설명해야 한다. 독자가 "WB_JAL에서 PC가 이미 점프 전 주소+4인가?"라고 질문할 것이다.**

---

### S15: EX_JALR (Execution — JALR)

**목적**: JALR = (A + imm_I) & ~1. I-type이지만 PC를 레지스터+즉치수로 갱신.

| 제어 신호 | 값 | 이유 |
|-----------|-----|------|
| `alu_src_a` | 1 | ALU A = A 레지스터 (rs1) |
| `alu_src_b` | 2'b10 | ALU B = imm_ext (I-type 즉치수) |
| `alu_op` | 4'b0000 | ADD (rs1 + imm_I) |
| `pc_write` | 0 | PC 갱신은 WB_JALR 상태에서 |
| `reg_write` | 0 | — |

> **JALR 하위 1비트 클리어**: RV32I 스펙 §2.5에 의하면 JALR의 목표 주소는 `(rs1 + imm_I) & ~1`(하위 1비트를 0으로 클리어)해야 한다. 현재 Ch07 데이터패스에는 이 비트 마스킹 하드웨어가 없다. **해결 방법**: WB_JALR 상태에서 `pc_next` 계산 시 `alu_out_reg & 32'hFFFFFFFE`를 적용하는 별도 하드웨어를 데이터패스에 추가하거나, 교재 범위에서 "최하위 비트는 항상 0이라고 가정(4-byte 정렬 가정)"으로 단순화할 수 있다. **교재 권장**: JALR 목표 주소 마스킹이 필요하다는 사실을 명시하고, 교육 범위에서는 정렬된 주소만 테스트하는 단순화를 사용. 실용 구현에서는 반드시 마스킹 추가.

---

### S16: WB_JALR (Write-Back — JALR)

**목적**: rd에 복귀 주소(PC+4) 저장, PC를 ALUOut(rs1+imm_I)으로 갱신.

| 제어 신호 | 값 | 이유 |
|-----------|-----|------|
| `reg_write` | 1 | rd에 복귀 주소 저장 |
| `mem_to_reg` | 2'b10 | WB 데이터 = PC (PC+4, JAL과 동일 이유) |
| `pc_write` | 1 | PC = ALUOut (rs1+imm_I) |
| `pc_src` | 2'b01 | PC 소스 = ALUOut |
| `mem_read` | 0 | — |
| `mem_write` | 0 | — |

---

## 2. 명령어 타입별 FSM 상태 경로

| 명령어 타입 | 대표 명령어 | 상태 경로 | 총 사이클 |
|------------|------------|----------|----------|
| R-type | ADD, SUB, AND, OR, XOR, SLT, SLTU, SLL, SRL, SRA | S0(IF) → S1(ID) → S2(EX_R) → S12(WB_R_I) | **4** |
| I-type 연산 | ADDI, ANDI, ORI, XORI, SLTI, SLTIU, SLLI, SRLI, SRAI | S0(IF) → S1(ID) → S3(EX_I) → S12(WB_R_I) | **4** |
| Load | LW, LH, LB, LHU, LBU | S0(IF) → S1(ID) → S4(EX_LOAD) → S5(MEM_LOAD) → S6(WB_LOAD) | **5** |
| Store | SW, SH, SB | S0(IF) → S1(ID) → S7(EX_STORE) → S8(MEM_STORE) | **4** |
| Branch (BEQ/BNE) | BEQ, BNE | S0(IF) → S1(ID) → S9a(EX_BRANCH_CMP) → S9b(EX_BRANCH_ADDR) | **4** |
| Branch (BLT/BGE/BLTU/BGEU) | BLT, BGE, BLTU, BGEU | S0(IF) → S1(ID) → S9a(EX_BRANCH_CMP) → S9b(EX_BRANCH_ADDR) | **4** |
| LUI | LUI | S0(IF) → S1(ID) → S10(EX_LUI) → S12(WB_R_I) | **4** |
| AUIPC | AUIPC | S0(IF) → S1(ID) → S11(EX_AUIPC) → S12(WB_R_I) | **4** |
| JAL | JAL | S0(IF) → S1(ID) → S13(EX_JAL) → S14(WB_JAL) | **4** |
| JALR | JALR | S0(IF) → S1(ID) → S15(EX_JALR) → S16(WB_JALR) | **4** |

> **CPI 분석 요약**:
> - R/I-type 연산, LUI, AUIPC, JAL, JALR: 4사이클
> - Load: 5사이클
> - Store: 4사이클
> - Branch: 4사이클
>
> 표준 명령어 믹스(R:I:L:S:B = 40:20:20:10:10 가정) 기준 가중 평균 CPI:
> `CPI_avg = 4×0.40 + 4×0.20 + 5×0.20 + 4×0.10 + 4×0.10 = 4.2`
>
> 이 값이 Ch08.5 성능 비교의 기준이 된다.

---

## 3. PCSrc 제어 신호 설계 (중요 — Ch07 [C1] 이슈 해결)

### 현행 PCSrc 인코딩 (Ch07 데이터패스)

| `pc_src` | Ch07 정의 | 문제 |
|----------|-----------|------|
| 2'b00 | ALU 직접 출력 (PC+4, IF 단계) | 정확 |
| 2'b01 | ALUOut (EX 단계 결과, 분기 주소 등) | 정확 |
| 2'b10 | `{alu_out_reg[31:28], ir_reg[25:0], 2'b00}` MIPS 방식 | **🔴 오류: RV32I에 해당 없음** |

### Ch08 PCSrc 재정의 (권장)

| `pc_src` | Ch08 재정의 | 사용 상태 |
|----------|------------|----------|
| 2'b00 | ALU 직접 출력 | S0(IF): PC+4 |
| 2'b01 | ALUOut | S9b(BRANCH), S14(WB_JAL), S16(WB_JALR) |
| 2'b10 | (미사용 — 제거 또는 예비 용도) | — |

### 명령어별 PC 업데이트 메커니즘

| 명령어 | PC 업데이트 상태 | `pc_src` | `pc_write`/`pc_write_cond` | 최종 PC 값 |
|--------|----------------|----------|---------------------------|-----------|
| 순차 실행 (R/I/S 등) | S0(IF) | 2'b00 | `pc_write=1` | PC + 4 |
| BEQ (taken) | S9b | 2'b01 | `pc_write_cond=1`, alu_zero=1 | PC + imm_B |
| BEQ (not taken) | S9b | 2'b01 | `pc_write_cond=1`, alu_zero=0 | 갱신 없음 (IF에서 PC+4 유지) |
| JAL | S14(WB_JAL) | 2'b01 | `pc_write=1` | PC + imm_J |
| JALR | S16(WB_JALR) | 2'b01 | `pc_write=1` | rs1 + imm_I (& ~1) |

> **Branch not-taken 처리**: IF 단계에서 이미 `pc_write=1`로 PC가 PC+4로 갱신되어 있다. Branch EX 단계에서 조건이 불성립이면 `pc_write_cond=1`이더라도 `alu_zero=0`이므로 `pc_en = pc_write | (pc_write_cond & alu_zero) = 0 | (1 & 0) = 0`이 되어 PC가 갱신되지 않는다. 따라서 IF에서 갱신된 PC+4가 그대로 유지된다. 이는 설계 의도에 부합한다.

> **BNE/BLT/BGE 처리**: `pc_write_cond`는 `alu_zero`와 AND되는 단일 신호이므로, BNE(not taken: alu_zero=1)이나 BLT(SLT 결과 = 1이면 taken)를 처리하기 위해 FSM 내부에서 조건 신호를 별도로 생성하거나 `pc_write_cond` 신호 외에 `branch_taken` 신호를 추가해야 한다. **교재에서는 `branch_taken` 단일 신호로 통합 처리하는 방식을 권장한다**:
> ```
> branch_taken = (funct3==BEQ && alu_zero) || (funct3==BNE && !alu_zero) ||
>                (funct3==BLT && alu_lt)   || (funct3==BGE && !alu_lt) ||
>                (funct3==BLTU && alu_ltu) || (funct3==BGEU && !alu_ltu)
> ```
> 이 로직은 FSM의 출력 또는 별도 Branch 판정 모듈로 분리할 수 있다.

---

## 4. SystemVerilog 구현 주의사항

### 4.1 FSM 코딩 패턴: `always_ff` + `always_comb` 이중 블록

```systemverilog
// 권장 패턴: 3-process FSM (상태 레지스터 / 다음 상태 / 출력)
// Process 1: 상태 레지스터 (순차 논리)
always_ff @(posedge clk or negedge rst_n) begin
   if (!rst_n)
      current_state <= S_IF;
   else
      current_state <= next_state;
end

// Process 2: 다음 상태 결정 (조합 논리)
always_comb begin
   next_state = S_IF; // 기본값 설정 필수 (latch 방지)
   case (current_state)
      S_IF:  next_state = S_ID;
      S_ID:  begin
         // opcode에 따라 다음 상태 결정
         case (opcode)
            7'b0110011: next_state = S_EX_R;     // R-type
            7'b0010011: next_state = S_EX_I;     // I-type 연산
            7'b0000011: next_state = S_EX_LOAD;  // Load
            // ...
         endcase
      end
      // ...
   endcase
end

// Process 3: 출력 (Moore FSM — 조합 논리)
always_comb begin
   // 모든 출력의 기본값 설정 (latch 방지 — 합성 Critical)
   pc_write      = 1'b0;
   pc_write_cond = 1'b0;
   ir_write      = 1'b0;
   mem_read      = 1'b0;
   mem_write     = 1'b0;
   i_or_d        = 1'b0;
   reg_write     = 1'b0;
   mem_to_reg    = 2'b00;
   alu_src_a     = 1'b0;
   alu_src_b     = 2'b00;
   alu_control   = 2'b00; // 2단계 ALU 제어
   pc_src        = 2'b00;

   case (current_state)
      S_IF: begin
         mem_read  = 1'b1;
         ir_write  = 1'b1;
         alu_src_a = 1'b0; // PC
         alu_src_b = 2'b01; // 상수 4
         pc_write  = 1'b1;
         pc_src    = 2'b00; // ALU 직접
      end
      // ...
   endcase
end
```

### 4.2 피해야 할 기술적 함정

**함정 1: 출력 기본값 미설정 → Latch 추론**
- `always_comb` 내 출력 신호에 반드시 기본값을 할당한 후 `case` 문을 시작해야 한다.
- 기본값 없이 `case`만 사용하면 Vivado가 해당 신호를 latch로 추론하고 합성 경고/오류 발생.
- 교재에서 "모든 `always_comb` 신호 기본값 설정"을 코딩 규칙으로 명시해야 한다.

**함정 2: 상태 인코딩 — binary vs one-hot**
- Basys 3(Artix-7)에서 FSM 상태 수가 16개 이하면 Vivado가 자동으로 one-hot 인코딩을 선택하는 경우가 있다.
- 교재에서 `(* fsm_encoding = "binary" *)` 또는 `(* fsm_encoding = "one-hot" *)` 속성으로 인코딩을 명시적으로 제어하는 방법을 설명할 것.
- 상태 수에 따른 인코딩 선택 기준 (`log2(N)` 비트 binary vs N비트 one-hot)도 면접 빈출 주제다.

**함정 3: 다음 상태 결정 로직에서 `opcode`/`funct3` 직접 참조**
- `next_state` 결정 시 `opcode`, `funct3`는 `ir_reg`에서 추출된 조합 신호다.
- `ir_reg`가 IR에 안정적으로 래치된 이후(`ir_write=1`이 있었던 S0 이후)에만 이 신호들이 유효하다.
- S0(IF) 상태에서는 `ir_reg`가 이전 명령어의 값이므로, S0→S1 전이에서 `opcode`를 참조하면 안 된다.
- 교재에서 "S1(ID) → S2(EX) 전이에서만 opcode에 따라 분기"한다는 규칙을 명시해야 한다.

**함정 4: `mem_read`와 `mem_write` 동시 assert 금지**
- 통합 메모리(Princeton 구조)에서 같은 사이클에 읽기+쓰기를 동시에 하면 BRAM 동작이 구현 의존적이다.
- FSM 상태 설계에서 `mem_read=1`과 `mem_write=1`이 동시에 발생하는 상태를 절대 만들지 않아야 한다.
- Ch08 FSM 구현 후 시뮬레이션에서 이 조건을 검증하는 assertion 추가 권장:
  ```systemverilog
  // SVA assertion: mem_read와 mem_write 동시 assert 금지
  assert_no_mem_conflict: assert property (
     @(posedge clk) !(mem_read && mem_write)
  ) else $error("mem_read and mem_write asserted simultaneously!");
  ```

**함정 5: JAL/JALR 복귀 주소 — PC 타이밍 의존성**
- JAL WB 상태에서 `mem_to_reg=2'b10`(PC 레지스터)을 사용해 복귀 주소를 읽는 방식은, IF 단계에서 `pc_write=1`로 PC가 이미 PC+4로 갱신된 것에 의존한다.
- IF와 WB_JAL 사이에 PCWrite가 추가로 발생하면 이 의존성이 깨진다.
- 더 안전한 대안: 복귀 주소를 저장하는 별도 레지스터(`return_addr_reg`)를 EX 또는 ID 단계에서 래치하는 방법. 교재에서 두 방법의 장단점을 비교할 것.

**함정 6: JALR 하위 1비트 클리어 미처리**
- 현재 Ch07 데이터패스에는 JALR 목표 주소의 하위 1비트 클리어 하드웨어가 없다.
- FSM 구현 시 JALR 상태에서 이를 처리하는 하드웨어(예: PC 소스에 `alu_out_reg & ~32'h1` 추가)가 필요하다.
- 교재 범위에서는 "4바이트 정렬된 주소만 사용"으로 단순화할 수 있지만, 이 제한을 명시해야 한다.

**함정 7: 분기 조건 판단 — `alu_zero` 단일 신호의 한계**
- `alu_zero` 하나로는 BEQ(zero=1이면 taken)와 BNE(zero=0이면 taken)도 혼동 없이 처리하기 어렵다.
- 별도 `branch_taken` 신호(funct3과 alu_result를 조합하는 조합 논리)를 데이터패스 또는 제어 유닛에서 생성해야 한다.
- 교재에서 `branch_taken` 신호 설계를 별도 소절로 다루는 것이 명확하다.

**함정 8: LUI에서 ALU A = 0 보장**
- LUI 결과 = 0 + imm_U = imm_U이어야 하므로, ALU A가 정확히 0이어야 한다.
- 현재 데이터패스에서 ALU A 소스는 PC 또는 A 레지스터만 선택 가능하다.
- A 레지스터에 0이 저장되도록 하려면 ID 단계에서 `rs1_addr = 5'd0`(x0 = 항상 0)을 강제하는 방법을 사용한다.
- 또는 데이터패스에 ALU A 소스로 "0 상수" 옵션을 추가하는 하드웨어 변경이 필요하다.
- **이 이슈는 Ch08 데이터패스 소규모 수정 사항으로 공개해야 한다.**

---

## 5. 기술적 이슈 사전 식별

### 🔴 Critical

**[C1] LUI의 ALU A = 0 보장 하드웨어 없음**
- **문제**: Ch07 데이터패스의 ALU A 소스는 PC(0) 또는 A 레지스터(1)만 선택 가능하다. LUI는 ALU A = 0이 필요하지만, `alu_src_a=0`(PC)은 PC 값을 사용하므로 오류다. `alu_src_a=1`(A 레지스터)에 0을 넣으려면 ID 단계에서 x0을 rs1로 읽어야 한다. LUI 명령어에서 rs1 필드는 정의되어 있지 않으며, 어셈블러가 `rs1=x0`을 넣는 관례(RISC-V ABI)를 따른다는 것을 설명해야 한다.
- **수정 방안**: LUI EX 상태에서 `alu_src_a=1`(A 레지스터), ID 단계에서 opcode=LUI일 때 레지스터 파일이 x0(5'b00000)을 rs1로 읽도록 보장. 실제 LUI 인코딩에서 `ir[19:15]=5'b00000`이므로 x0이 자동으로 읽힌다. 이를 교재에서 명시적으로 설명해야 한다.
- **심각도 근거**: 잘못 구현하면 LUI가 `PC + imm_U`(AUIPC와 동일한 동작)를 수행하는 기능 오류 발생.

**[C2] JALR 하위 1비트 클리어 하드웨어 부재**
- **문제**: RV32I 스펙 §2.5 — "The target address is obtained by adding the sign-extended 12-bit I-immediate to the register rs1, then setting the least-significant bit of the result to zero." 현재 Ch07 데이터패스에는 이 마스킹 하드웨어가 없다.
- **수정 방안**: `pc_next` 계산 시 `alu_out_reg & 32'hFFFFFFFE`를 적용. 데이터패스에 JALR 전용 PC 소스 추가 또는 FSM 출력에서 별도 마스킹 신호를 사용. **교재에서는 반드시 이 제약을 명시하고, 교육 구현에서의 단순화 여부를 결정해야 한다.**

**[C3] Branch 분기 조건 판단 로직 미확정**
- **문제**: `pc_write_cond`는 `alu_zero`와 AND되는 단일 조건이므로 BEQ(zero=1이면 taken)만 정확히 처리할 수 있다. BNE(zero=0이면 taken)는 현재 신호 체계로 처리 불가.
- **수정 방안**: FSM 출력에 `branch_taken` 신호를 추가하고, PC Enable 로직을 `pc_en = pc_write | branch_taken`으로 변경. 데이터패스도 이에 맞게 수정.

---

### 🟡 Major

**[M1] 상태 수 최적화 vs 교육적 명확성 트레이드오프**
- 현재 설계는 최대 17개 상태를 사용한다. Vivado에서 3비트(8개) 이상의 FSM을 one-hot 인코딩으로 처리하면 LUT 사용량이 증가한다.
- Basys 3 LUT 20K 기준에서 FSM 자체는 소량이지만, 교재에서 상태 인코딩 선택과 Vivado의 자동 최적화 동작을 설명할 것.
- EX_R과 EX_I를 통합하거나, WB_R_I를 여러 타입이 공유하는 방식으로 상태 수를 줄이는 최적화를 "심화 구현"으로 제시할 것.

**[M2] funct3 기반 ALU 제어 신호 생성 로직**
- FSM은 EX 상태에서 `alu_control` 신호를 생성해야 한다. R-type과 I-type의 경우 funct3/funct7[5]에 따라 10가지 연산 중 하나를 선택해야 한다.
- 이 디코딩 로직은 FSM 내부에 포함하면 next_state 결정 로직과 출력 결정 로직이 복잡해진다.
- **권장**: 별도 ALU 제어 모듈(`alu_controller.sv`)로 분리. FSM은 2비트 `alu_control` 신호만 출력(00=ADD, 01=SUB, 10=funct3 기반, 11=설정 가능)하고, ALU 제어 모듈이 funct3/funct7을 받아 4비트 `alu_op`를 생성.

**[M3] 통합 메모리 바이트 인에이블 확장 — LB/SB/LH/SH**
- Ch07 기술 리뷰 [M2]에서 지적했듯이, 현재 통합 메모리는 LW/SW(32비트 워드)만 지원한다.
- Ch08에서 `funct3`을 메모리 접근 크기/부호 확장 결정에 사용하는 완전한 바이트 인에이블 로직을 추가해야 RV32I 완전 구현이 된다.
- 교재에서 Ch08.4 통합 시뮬레이션 전에 이 부분을 구현하거나, 명시적으로 LW/SW 전용 구현임을 테스트 프로그램에서 제한할 것.

**[M4] ECALL/EBREAK 처리**
- RV32I에 ECALL, EBREAK가 포함되며, 이에 대한 FSM 상태 처리가 필요하다.
- 최소 구현: illegal instruction 상태(S_TRAP)로 전이하고 FSM을 정지시키는 방법.
- 교재 Ch08에서 ECALL/EBREAK FSM 처리 방안을 명시할 것(Ch18 CSR/예외 챕터와의 의존성 명시).

**[M5] 멀티사이클 통합 테스트벤치의 RV32I 완전성 검증**
- Ch08.4 시뮬레이션에서 R/I/S/B/U/J 타입 전체를 테스트하는 어셈블리 프로그램이 필요하다.
- 특히 JAL/JALR의 복귀 주소와 점프 주소, Branch taken/not-taken 양방향, LUI/AUIPC 상수 생성을 테스트 케이스에 포함해야 한다.
- 현재 code_examples에 `ch08_multicycle_tb.sv`가 없으므로 신규 작성 필요.

---

### 🟢 Minor

**[N1] 상태 이름 명명 규칙 통일**
- FSM 상태 열거형(enum)의 이름은 SystemVerilog 코드, SVG 다이어그램, HTML 설명에서 일관되게 사용해야 한다.
- 권장 패턴: `typedef enum logic [4:0] {S_IF, S_ID, S_EX_R, S_EX_I, S_EX_LOAD, S_MEM_LOAD, S_WB_LOAD, ...} state_t;`

**[N2] FSM 상태 전이도 SVG 가독성**
- Ch08.2절의 FSM 상태 전이도 SVG는 17개 이상의 상태를 표시해야 한다. 상태가 많으면 SVG가 복잡해져 가독성이 저하된다.
- **권장**: 전체 FSM을 한 SVG에 표시하는 것 외에, 명령어 타입별로 경로를 하이라이트하는 별도 SVG(예: Load 경로만 강조한 SVG, Branch 경로만 강조한 SVG)를 추가로 제공.

**[N3] CPI 테이블 표기 기준 명시**
- Ch08.5 성능 비교에서 CPI 수치(R:4, Load:5, Store:4, Branch:4)가 사용된다. Table_of_Contents에는 "Branch:3"으로 표기되어 있으나, 이 설계에서는 Branch가 4사이클이다.
- **검토 필요**: TABLE_OF_CONTENTS.md의 Branch CPI=3은 ID 단계에서 분기 주소를 미리 계산하는 방식(방법 B) 기준인 것으로 보인다. 교재 채택 방식에 따라 CPI 표를 일관되게 업데이트해야 한다.

---

## 6. Ch08 FSM 설계를 위한 데이터패스 수정 사항

Ch07에서 완성된 `ch07_multicycle_datapath.sv`를 Ch08에서 사용하기 전에 다음 수정이 필요하다:

| 수정 항목 | 현황 | 수정 방향 | 우선도 |
|-----------|------|----------|--------|
| PCSrc 2'b10 케이스 재정의 | MIPS 방식 | 제거 또는 예비 용도로 재정의 | 🔴 Critical |
| JALR 하위 1비트 클리어 | 없음 | PC 소스에 마스킹 로직 추가 | 🔴 Critical |
| `branch_taken` 신호 | `pc_write_cond & alu_zero`만 존재 | `branch_taken` 조합 신호 추가 | 🔴 Critical |
| `reg_dst` 포트 | 선언만 있고 미사용 | 제거 | 🟡 Major |
| 바이트 인에이블 메모리 | LW/SW만 지원 | `funct3` 기반 바이트/하프워드 처리 추가 | 🟡 Major |
| ALU 비교 신호 | `alu_zero`만 존재 | `alu_lt`(signed 비교), `alu_ltu`(unsigned 비교) 추가 | 🟡 Major |
| MDR 인에이블 조건부 갱신 | 무조건 갱신 | `mem_read && i_or_d` 조건 추가 권장 | 🟢 Minor |

---

## 7. 검증 계획 — 상태별 단위 테스트

Ch08.4 시뮬레이션에서 검증할 핵심 시나리오:

| 테스트 케이스 | 검증 항목 | 예상 결과 |
|-------------|----------|----------|
| ADD x1, x2, x3 | S0→S1→S2(EX_R)→S12(WB) 전이, 4사이클 | rd 갱신, 다음 명령어 PC+4 |
| ADDI x1, x2, 100 | I-type 즉치수 처리, ALUOut 정확성 | rd = rs1 + 100 |
| LW x1, 4(x2) | 5사이클 전체, MDR 데이터 정확성 | rd = mem[rs1+4] |
| SW x1, 4(x2) | 4사이클, 메모리 쓰기 검증 | mem[rs1+4] = rs1_data |
| BEQ x1, x2, label (taken) | branch_taken=1, PC = PC_label | 점프 성공 |
| BEQ x1, x2, label (not taken) | branch_taken=0, PC = PC+4 | 순차 실행 |
| BNE x1, x2, label | BNE 조건 반전 처리 | 정확한 분기 판단 |
| JAL x1, label | 복귀 주소 = PC+4, PC = PC+imm_J | rd=PC+4, 점프 성공 |
| JALR x1, x2, 0 | rs1+imm_I 목표, 하위 1비트 클리어 | 정렬 주소로 점프 |
| LUI x1, 0x12345 | ALU A=0, 결과 = 0x12345000 | rd = 0x12345000 |
| AUIPC x1, 0x12345 | 결과 = PC + 0x12345000 | rd = PC+imm_U |
| 피보나치 수열 (fibonacci.asm) | 전체 연산 정합성, 다수 명령어 혼합 | 결과 레지스터 값 검증 |

---

## 8. 면접 연결 포인트

| 면접 질문 | 관련 절 | 핵심 답변 요소 |
|----------|---------|--------------|
| 멀티사이클 FSM의 각 상태에서 어떤 제어 신호가 활성화되는가? | Ch08.2 | IF의 IRWrite+PCWrite, EX의 ALUSrcA/B, WB의 RegWrite 조합 |
| 하드와이어드 제어 vs 마이크로프로그래밍의 차이점 | Ch08.6 | 속도/유연성 트레이드오프, 마이크로코드 ROM 구조 |
| Moore FSM과 Mealy FSM의 차이, 어느 것을 CPU 제어에 사용하는가 | Ch08.1 | Moore=출력이 상태에만 의존(안정적), Mealy=입력에도 의존(빠름) |
| FSM 상태 인코딩 방법과 선택 기준 | Ch08.3 | binary, one-hot, gray code 비교, LUT/FF 트레이드오프 |

---

*작성: 기술 리뷰어 (Technical Reviewer)*
*검토 기반: RISC-V Unprivileged ISA Spec v20191213, IEEE 1800-2017, Ch07 확정 데이터패스*
*다음 단계: 교육 설계자, 교육심리전문가, 교육전문강사 병렬 검토 후 chapter08_meeting.md 종합 회의*
