# Chapter 12 기술 리뷰 보고서

**리뷰어**: 기술 리뷰어 (Technical Reviewer) 에이전트
**검토 일자**: 2026-03-12
**대상 챕터**: Chapter 12 — 구조적 해저드와 파이프라인 완성
**리뷰 결과 요약**: Critical 4건, Major 3건, Minor 3건

---

## 검토 파일 목록

| 파일 | 검토 결과 |
|------|-----------|
| manuscripts/part4/chapter12.html | Critical 2건, Major 1건, Minor 2건 |
| code_examples/ch12_register_file_with_forwarding.sv | 이상 없음 |
| code_examples/ch12_rv32i_pipeline_complete.sv | Critical 2건, Major 2건 |
| code_examples/ch12_bubble_sort.sv | Critical 1건, Minor 1건 |
| code_examples/ch12_pipeline_complete_tb.sv | Critical 2건 |
| code_examples/ch11_pipeline_with_branch.sv | 참조용 (이상 없음) |
| code_examples/ch10_forwarding_unit.sv | 참조용 (이상 없음) |

---

## Critical 이슈

### [C1] BGE 기계어 인코딩 오류 — 버블정렬이 실행 불가

**심각도**: Critical (ISA 스펙 위반, 시뮬레이션 실패 유발)

**위치**: `ch12_pipeline_complete_tb.sv` line 177, 181 / `ch12_bubble_sort.sv` 주석

**이슈 설명**:

테스트벤치의 버블정렬 IMEM 초기화 코드에 BGE(Branch if Greater or Equal) 명령어 기계어 인코딩 오류가 2건 존재한다. BGE의 funct3 필드는 `101`(3'b101=5)이어야 하나, 잘못 인코딩된 값들이 사용되었다.

**오류 1** — BGE x11, x16, +60 (done 분기):

```
// ch12_pipeline_complete_tb.sv line 177:
dut.u_imem.mem[4] = 32'h03C58663;  // 코드 주석: BGE x11, x16, +60 (done)

// 역디코딩 결과:
//   funct3 = 000 = BEQ (BGE가 아님!)
//   rs2    = x28 (x16이 아님!)
//   imm    = +44 (+60이 아님!)
// 올바른 BGE x11, x16, +60 인코딩:
//   0x0305DE63
```

**오류 2** — BGE x12, x17, +40 (outer_next 분기):

```
// ch12_pipeline_complete_tb.sv line 181:
dut.u_imem.mem[7] = 32'h03164463;  // 코드 주석: BGE x12, x17, +40 (outer_next)

// 역디코딩 결과:
//   funct3 = 100 = BLT (BGE가 아님! 부호 있는 Less Than 비교)
//   rs1=x12, rs2=x17, imm=40 (rs와 imm은 우연히 일치)
// 올바른 BGE x12, x17, +40 인코딩:
//   0x03165463  (funct3 비트 1개 차이)
```

**ch12_bubble_sort.sv 주석 추가 오류**:
```
// 0x010 BGE 주석에서 오프셋 '+88=0x58' → '0x068' 표기: 틀림
// 실제 done 주소 = 0x04C, outer_loop = 0x010, offset = 0x3C = 60
// 0x05058663도 BEQ로 디코딩됨 (funct3=0)
```

**영향**: 외부 루프 종료 조건(done)과 내부 루프 종료 조건(outer_next)이 완전히 다른 명령어(BEQ, BLT)로 실행되어 버블정렬이 시뮬레이션에서 올바른 결과를 낼 수 없다.

**수정 제안**:

```systemverilog
// ch12_pipeline_complete_tb.sv line 177 수정:
dut.u_imem.mem[4] = 32'h0305DE63;  // BGE x11, x16, +60 (done)
//   검증: funct3=101(BGE), rs1=x11, rs2=x16, imm=60

// ch12_pipeline_complete_tb.sv line 181 수정:
dut.u_imem.mem[7] = 32'h03165463;  // BGE x12, x17, +40 (outer_next)
//   검증: funct3=101(BGE), rs1=x12, rs2=x17, imm=40
```

BGE B-type 인코딩 공식 (funct3=5=`101`, opcode=`1100011`):
```
inst[31]    = imm[12]
inst[30:25] = imm[10:5]
inst[24:20] = rs2
inst[19:15] = rs1
inst[14:12] = 101  (BGE funct3)
inst[11:8]  = imm[4:1]
inst[7]     = imm[11]
inst[6:0]   = 1100011
```

---

### [C2] ADD 기계어 인코딩 오류 — 배열 주소 x19가 x18로 저장됨

**심각도**: Critical (ISA 스펙 위반, 시뮬레이션 실패 유발)

**위치**: `ch12_pipeline_complete_tb.sv` line 183

**이슈 설명**:

버블정렬에서 `ADD x19, x10, x18` (배열 기저 주소 + 오프셋 = &a[j]) 명령어의 기계어가 잘못 인코딩되어 있다.

```
// 현재 코드:
dut.u_imem.mem[9] = 32'h01250933;  // 주석: ADD x19, x10, x18 (&a[j])

// 역디코딩:
//   rd  = x18  (10010 = 18, x19가 아님!)
//   rs1 = x10  (정상)
//   rs2 = x18  (정상)
// 실제 디코딩: ADD x18, x10, x18 (x18 자신에게 덮어쓰기)

// 올바른 ADD x19, x10, x18 인코딩:
//   rd=x19=10011, rs1=x10=01010, rs2=x18=10010
//   = 0x012509B3
```

**영향**: `x19`에 &a[j] 주소가 저장되지 않으므로, 이후의 `LW x14, 0(x19)`와 `LW x15, 4(x19)` 및 `SW` 명령어들이 잘못된 주소를 참조한다. 버블정렬 전체가 쓰레기 값을 처리하게 된다.

**수정 제안**:

```systemverilog
// ch12_pipeline_complete_tb.sv line 183 수정:
dut.u_imem.mem[9] = 32'h012509B3;  // ADD x19, x10, x18 (&a[j])
//   검증: rd=x19(10011), rs1=x10(01010), rs2=x18(10010), funct7=0, funct3=0
```

---

### [C3] imm_gen 포트 불일치 — 컴파일 실패

**심각도**: Critical (합성 불가 / 컴파일 실패)

**위치**: `ch12_rv32i_pipeline_complete.sv` line 240-243

**이슈 설명**:

`ch12_rv32i_pipeline_complete.sv`에서 `imm_gen`을 다음과 같이 인스턴스화한다:

```systemverilog
imm_gen u_imm_gen (
   .instr (if_id_instr),
   .imm   (imm)
);
```

그러나 `ch04_imm_gen.sv`의 실제 포트 시그니처는:

```systemverilog
module imm_gen (
   input  logic [31:0] inst,       // 포트명: instr이 아닌 inst
   input  logic [2:0]  imm_sel,    // 누락된 필수 입력 포트
   output logic [31:0] imm_out     // 포트명: imm이 아닌 imm_out
);
```

불일치 사항:
1. `instr` vs `inst` (포트명 불일치)
2. `imm_sel[2:0]` 포트가 연결되지 않음 (즉치수 타입 선택 신호 누락)
3. `imm` vs `imm_out` (포트명 불일치)

`imm_sel` 없이는 즉치수 타입(I/S/B/U/J/R)을 선택할 수 없으므로, Ch04 `imm_gen`을 그대로 사용하면 컴파일조차 되지 않는다.

**수정 제안**:

두 가지 해결 방안 중 하나를 선택해야 한다:

**방안 A**: 파이프라인 전용 `imm_gen`을 별도 제공한다 (opcode로 자동 타입 감지):
```systemverilog
// 파이프라인용 imm_gen (opcode 기반 자동 타입 감지)
module imm_gen (
   input  logic [31:0] instr,
   output logic [31:0] imm
);
   // opcode 기반 즉치수 자동 디코딩 (Ch09부터 사용하던 방식)
```

**방안 B**: 기존 Ch04 `imm_gen` 포트명을 사용하고, `imm_sel`을 `control_unit`에서 연결한다:
```systemverilog
imm_gen u_imm_gen (
   .inst    (if_id_instr),
   .imm_sel (imm_sel_from_ctrl),  // control_unit에서 제공
   .imm_out (imm)
);
```

본문 12.3절 설명("Ch04에서 설계"로 기재)에 맞춰 실제 사용하는 `imm_gen`의 버전을 명확히 명시해야 한다.

---

### [C4] control_unit 포트 불일치 — 컴파일 실패

**심각도**: Critical (합성 불가 / 컴파일 실패)

**위치**: `ch12_rv32i_pipeline_complete.sv` line 246-258

**이슈 설명**:

`ch12_rv32i_pipeline_complete.sv`에서 `control_unit`을 다음과 같이 인스턴스화한다:

```systemverilog
control_unit u_ctrl (
   .opcode    (if_id_instr[6:0]),
   .funct3    (funct3_id),
   .funct7    (if_id_instr[31:25]),
   .reg_w_en  (reg_w_en),
   .mem_read  (mem_read),
   .mem_write (mem_write),
   .branch    (branch_id),
   .a_sel     (a_sel),
   .b_sel     (b_sel),
   .alu_sel   (alu_sel),
   .wb_sel    (wb_sel)
);
```

그러나 `ch06_control_unit.sv`의 실제 포트 시그니처는:

```systemverilog
module control_unit (
   input  logic [31:0] instr,        // opcode/funct3/funct7 분리가 아닌 전체 instr
   input  logic [31:0] rs1_data,     // 분기 비교용 (파이프라인에서는 불필요)
   input  logic [31:0] rs2_data,     // 분기 비교용
   output alu_op_t     alu_sel,      // typedef 타입 (plain logic 아님)
   output imm_sel_t    imm_sel,      // 누락된 출력 (Ch04 imm_gen에 필요)
   output logic        reg_w_en,
   output mem_rw_t     mem_rw,       // mem_read/mem_write 분리 아님
   output pc_sel_t     pc_sel,       // pc_sel 출력 (파이프라인에서 사용 안 함)
   output wb_sel_t     wb_sel,       // typedef 타입
   ...
);
```

불일치 사항:
1. Ch06 `control_unit`은 `instr[31:0]` 전체를 받으나, Ch12는 `opcode/funct3/funct7`을 분리 입력
2. Ch06는 `rs1_data`, `rs2_data` 입력이 필요하나 Ch12에는 없음
3. `mem_rw_t` (typedef) vs 별도 `mem_read`/`mem_write` (plain logic) 불일치
4. `alu_op_t`, `imm_sel_t`, `pc_sel_t`, `wb_sel_t` 등 Ch06의 typedef 타입들이 Ch12 `logic` 선언과 호환 불가
5. `branch` 출력 포트가 Ch06에는 없음

**수정 제안**:

파이프라인에 맞는 새로운 `control_unit`을 제공해야 한다. Ch09부터 파이프라인에서 사용한 제어 유닛이 이미 이 인터페이스로 설계되어 있을 것이므로, 해당 버전의 참조를 명확히 해야 한다:

```systemverilog
// 파이프라인용 control_unit 인터페이스
module control_unit (
   input  logic [6:0] opcode,
   input  logic [2:0] funct3,
   input  logic [6:0] funct7,
   output logic       reg_w_en,
   output logic       mem_read,
   output logic       mem_write,
   output logic       branch,
   output logic       a_sel,
   output logic       b_sel,
   output logic [3:0] alu_sel,
   output logic [1:0] wb_sel
);
```

본문 12.3절의 "Ch06에서 설계" 표현을 수정하거나, 파이프라인 전용 버전임을 명시해야 한다.

---

## Major 이슈

### [M1] 성능 표(12.5절) 수치 내부 불일치

**심각도**: Major (학습 오류 유발 가능)

**위치**: `manuscripts/part4/chapter12.html` 12.5절, 그림 12.6 캡션

**이슈 설명**:

12.5절 성능 비교 표와 설명 텍스트 간에 수치 불일치가 있다.

**표의 수치**:
| 구현 | Fmax (MHz) | CPI | 실행시간 상대값 |
|------|-----------|-----|----------------|
| 단일 사이클 | ~25 | 1.0 | 1.0 |
| 멀티사이클 | ~50 | ~4.1 | ~0.82 |
| 파이프라인 | ~65 | ~1.2 | ~0.22 |

**계산 검증**:
```
실행 시간 = IC × CPI / Fmax  (IC로 정규화 후 상대값 비교)

단일 사이클: IC × 1.0 / 25MHz = IC × 40.0 ns/명령어
멀티사이클:  IC × 4.1 / 50MHz = IC × 82.0 ns/명령어
파이프라인:  IC × 1.2 / 65MHz = IC × 18.5 ns/명령어

상대값 (단일 사이클 = 1.0 기준):
  멀티사이클:  82.0 / 40.0 = 2.05  (표는 0.82 — 틀림)
  파이프라인:  18.5 / 40.0 = 0.46  (표는 0.22 — 틀림)
```

표의 0.82와 0.22는 단일 사이클 Fmax를 약 10~12MHz로 가정해야 나오는 값이다 (Fmax=25MHz와 불일치).

**추가 불일치**:
- 그림 12.6 캡션: "파이프라인이 단일 사이클 대비 약 **4.6배** 빠릅니다"
- 본문 텍스트: "파이프라인이 단일 사이클보다 약 **2.2배** 빠르고" (이 값이 올바름)
- 4.6배는 파이프라인 대 멀티사이클 비율(40.0/18.5×2 ≈ 4.4배)에 가까움

**수정 제안**:

상대값 열을 올바르게 계산하거나, 단일 사이클 Fmax 가정치를 명시해야 한다.

올바른 상대값(Fmax_single=25MHz 기준):
```
멀티사이클  상대값 = 82.0 / 40.0 = 2.05  (멀티사이클이 더 느림 — 올바른 결과)
파이프라인  상대값 = 18.5 / 40.0 ≈ 0.46
```

또는 그림 12.6 캡션을 수정:
```
"파이프라인이 실행 시간 기준으로 단일 사이클 대비 약 2.2배, 멀티사이클 대비 약 4.4배 빠릅니다."
```

---

### [M2] alu_src_b 선언 후 미사용 (합성 경고)

**심각도**: Major (합성 경고 발생, 교육 자료 품질 저하)

**위치**: `ch12_rv32i_pipeline_complete.sv` line 71

**이슈 설명**:

```systemverilog
// line 71:
logic [31:0] alu_src_b;   // ALU B 최종 입력
```

이 신호는 선언되었으나 어디서도 구동(drive)되지 않는다. 실제 ALU B 입력은 `alu_b`라는 이름으로 별도 계산된다 (line 333).

```systemverilog
// line 332-333:
logic [31:0] alu_a, alu_b;
assign alu_a = id_ex_a_sel ? id_ex_pc   : alu_src_a;
assign alu_b = id_ex_b_sel ? id_ex_imm  : fwd_b_data;
```

`alu_src_b`는 댕글링 신호(dangling signal)로 남아 있어 Vivado/VCS에서 합성 경고 `W: Net alu_src_b has no driver`가 발생한다.

**수정 제안**:

```systemverilog
// 수정: alu_src_b 선언 제거 또는 삭제
// 내부 신호 선언부 (line 71)에서 삭제:
// logic [31:0] alu_src_b;  // 삭제
```

---

### [M3] ALU 포트명 Ch04 원본과 불일치 — 주석 오류

**심각도**: Major (학습자 혼란, 교육 자료 신뢰성)

**위치**: `ch12_rv32i_pipeline_complete.sv` line 337 주석, 12.3절 본문

**이슈 설명**:

Ch04 `alu` 모듈의 실제 포트:
```systemverilog
module alu (
   input  logic [31:0] operand_a,   // 첫 번째 피연산자
   input  logic [31:0] operand_b,   // 두 번째 피연산자
   input  logic [3:0]  alu_ctrl,    // ALU 제어 신호
   output logic [31:0] alu_result,  // 연산 결과
   output logic        alu_zero     // 결과가 0일 때 1
);
```

Ch12(및 Ch09~Ch11 공통) 사용 포트:
```systemverilog
alu u_alu (
   .a      (alu_a),
   .b      (alu_b),
   .alu_sel(id_ex_alu_sel),
   .result (alu_result)
);
// alu_zero 연결 없음
```

포트명이 다른 버전을 사용하고 있음에도 코드 주석은 "Ch04에서 설계"라고만 명시한다. 학습자가 Ch04 ALU를 그대로 가져오면 포트 불일치로 컴파일 오류가 발생한다.

`alu_zero`도 연결되지 않아 Vivado에서 경고가 발생한다 (파이프라인에서는 `branch_unit`이 분기 판정을 담당하므로 의미적으로는 올바름).

**수정 제안**:

코드 주석을 수정하여 파이프라인 전용 버전임을 명시:
```systemverilog
// ALU 인스턴스 (Ch09 파이프라인용 — Ch04 원본에서 포트명 변경)
// Ch04: operand_a/operand_b/alu_ctrl → Ch09+: a/b/alu_sel
// alu_zero 포트: 분기 판정은 branch_unit에서 처리하므로 미연결
alu u_alu (
   .a      (alu_a),
   .b      (alu_b),
   .alu_sel(id_ex_alu_sel),
   .result (alu_result)
);
```

또는 Ch04 ALU의 포트를 파이프라인 버전으로 업데이트하고, 그 변경 이력을 교재에서 명시해야 한다.

---

## Minor 이슈

### [N1] ch12_bubble_sort.sv 주석의 BGE 오프셋 표기 오류

**심각도**: Minor (주석 오류, 실제 동작에는 영향 없음)

**위치**: `ch12_bubble_sort.sv` line 63

```
// 현재 주석:
// 0x010   05058663    BGE  x11, x16, done (offset=+88=0x58 → PC=0x068)
//
// 올바른 값:
// done 주소 = 0x04C
// offset = 0x04C - 0x010 = 0x3C = 60 (88이 아님)
// PC = 0x04C (0x068이 아님)
```

**수정 제안**: `offset=+60=0x3C → PC=0x04C`로 수정

---

### [N2] ch12_bubble_sort.sv 주석의 outer_next 오프셋 오류

**심각도**: Minor (주석 오류)

**위치**: `ch12_bubble_sort.sv` line 67

```
// 현재 주석:
// 0x01C   05164663    BGE  x12, x17, outer_next (offset=+96 → PC=0x07C)
//
// 올바른 값:
// outer_next 주소 = 0x044
// offset = 0x044 - 0x01C = 0x28 = 40 (96이 아님)
// PC = 0x044 (0x07C이 아님)
```

**수정 제안**: `offset=+40=0x28 → PC=0x044`로 수정

---

### [N3] BGE x15, x14, +12 (no_swap) 확인 — 정상

**심각도**: 이상 없음 (확인용 기재)

**위치**: `ch12_pipeline_complete_tb.sv` line 186

```systemverilog
dut.u_imem.mem[12] = 32'h00E7D663;  // BGE x15, x14, +12 (no_swap)
```

역디코딩 결과: `funct3=5(BGE)`, `rs1=x15`, `rs2=x14`, `imm=+12` — 정상.

이 명령어는 `BLE x14, x15, no_swap`의 어셈블러 변환인 `BGE x15, x14, no_swap`으로 올바르게 인코딩되었다.

---

## 종합 평가

### 긍정적 측면

1. **WB-ID 포워딩 구현 정확성**: `ch12_register_file_with_forwarding.sv`의 포워딩 로직이 정확하다.
   - `reg_w_en && (rd_addr != 5'b0) && (rd_addr == rs1_addr)` 조건이 RISC-V ISA 스펙에 부합
   - x0 포워딩 방지 조건 포함
   - `assign` 문으로 조합 논리 구현 (합성 가능)

2. **파이프라인 제어 신호 우선순위**: Flush > Stall 우선순위 (`pc_en = if_id_flush ? 1'b1 : hdu_pc_en`)가 Ch11 패턴을 정확히 계승

3. **EX-EX > MEM-EX 포워딩 우선순위**: `forwarding_unit`(Ch10) 그대로 사용, 포워딩 MUX 로직 정확

4. **JALR 하위 비트 처리**: `jalr_target = (alu_src_a + id_ex_imm) & ~32'h1` — ISA 스펙 준수

5. **버블정렬 알고리즘 로직**: BLE가 실제로는 BGE(rs1/rs2 교환)로 처리된다는 설명이 정확하며, 교육적으로 유용

6. **시나리오 1 기계어**: `ADDI`, `ADD`, `SW`, `LW` 명령어들의 기계어 인코딩이 모두 정확

### 수정 필요 우선순위

1. **즉시 수정 필요** (C1, C2): 버블정렬 기계어 오류 수정 — 수정 없이는 시뮬레이션 검증 불가
2. **집필 전 설계 결정 필요** (C3, C4): imm_gen과 control_unit의 파이프라인 버전 정의 및 제공
3. **수치 수정** (M1): 성능 표 상대값 또는 캡션 수정
4. **코드 정리** (M2): `alu_src_b` 미사용 선언 제거
5. **주석 수정** (N1, N2, M3): BGE 오프셋 및 ALU 출처 주석 수정

---

## 기계어 인코딩 검증 요약표

| 명령어 | 현재 코드 | 역디코딩 결과 | 올바른 값 | 판정 |
|--------|-----------|-------------|-----------|------|
| BGE x11,x16,+60 | 0x03C58663 | BEQ x11,x28,+44 | 0x0305DE63 | **오류** |
| BGE x12,x17,+40 | 0x03164463 | BLT x12,x17,+40 | 0x03165463 | **오류** |
| BGE x15,x14,+12 | 0x00E7D663 | BGE x15,x14,+12 | — | 정상 |
| ADD x19,x10,x18 | 0x01250933 | ADD x18,x10,x18 | 0x012509B3 | **오류** |
| JAL x0,-40 | 0xFD9FF06F | JAL x0,-40 | — | 정상 |
| JAL x0,-60 | 0xFC5FF06F | JAL x0,-60 | — | 정상 |
| SUB x17,x16,x11 | 0x40B808B3 | SUB x17,x16,x11 | — | 정상 |
| SLLI x18,x12,2 | 0x00261913 | SLLI x18,x12,2 | — | 정상 |
| LW x14,0(x19) | 0x0009A703 | LW x14,0(x19) | — | 정상 |
| LW x15,4(x19) | 0x0049A783 | LW x15,4(x19) | — | 정상 |
| SW x15,0(x19) | 0x00F9A023 | SW x15,0(x19) | — | 정상 |
| SW x14,4(x19) | 0x00E9A223 | SW x14,4(x19) | — | 정상 |
| ADDI x13,x0,8 | 0x00800693 | ADDI x13,x0,8 | — | 정상 |
| ADDI x16,x13,-1 | 0xFFF68813 | ADDI x16,x13,-1 | — | 정상 |
