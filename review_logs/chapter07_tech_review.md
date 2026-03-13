# Chapter 07 기술 리뷰 — 멀티사이클 데이터패스

**챕터**: Chapter 07 — 멀티사이클 데이터패스
**리뷰어**: 기술 리뷰어 (Technical Reviewer)
**리뷰 일자**: 2026-03-11
**검토 파일**:
- `manuscripts/part3/chapter07.html`
- `code_examples/ch07_multicycle_datapath.sv`
- `code_examples/ch07_sec02_unified_memory.sv`
- `code_examples/ch07_sec03_intermediate_regs.sv`

---

## 전체 기술 정확도 점수: **7.5 / 10**

> 구조적으로 정확하고 교육적으로 유용한 구현이나, 특별 검토 포인트에서 지적된 이슈 중 일부가 실제로 오류로 확인되었으며 몇 가지 추가 이슈도 발견되었다. Critical 2건, Major 5건, Minor 3건.

---

## Critical 이슈

---

### 🔴 [C1] PCSrc 2'b10 — MIPS 방식 점프 주소: RV32I JAL과 완전히 불일치

**파일**: `ch07_multicycle_datapath.sv`, 줄 104 / HTML 줄 1128
**현재 코드**:
```systemverilog
2'b10: pc_next = {alu_out_reg[31:28], ir_reg[25:0], 2'b00}; // 점프 주소
```

**문제 분석**:
이 수식은 MIPS-32 J-type 명령어(`jr`, `j`)의 점프 주소 조합 방식이다. MIPS는 `{PC[31:28], instr[25:0], 2'b00}` 형태로 26비트 필드에서 28비트를 만들고 상위 4비트를 PC에서 가져온다.

RV32I JAL은 **PC-relative 주소 방식**이다. RV32I ISA 스펙(§2.5)에 따르면:
```
JAL: PC_next = PC + sign_extend(imm_J)
```
여기서 `imm_J`는 J-type 즉치수(±1MB 범위). `alu_out_reg[31:28]`을 상위 4비트로 사용하는 구조는 RV32I에 존재하지 않는다. 또한 `ir_reg[25:0]`은 JAL의 J-type 인코딩 필드(`imm[20|10:1|11|19:12]`)와 직접 대응하지 않는다.

**실제 RISC-V JAL 동작**:
EX 단계에서 FSM이 `alu_src_a=0`(PC), `alu_src_b=2'b10`(imm_ext, J-type 즉치수)를 설정하여 ALU가 `PC + imm_J`를 계산하고 결과가 ALUOut에 저장된다. 따라서 WB/PC 갱신 단계에서 `pc_src=2'b01`(ALUOut)을 사용하면 충분하다. `pc_src=2'b10`은 불필요하거나, JALR 등을 위한 별도 케이스로 재정의가 필요하다.

**수정 방안**:
1. 단기(Ch07 범위): `2'b10` 케이스를 `alu_out_reg`로 교체하거나, HTML 주석처럼 "Ch08 FSM 검토 예정"을 더 명확히 하여 독자가 이 코드를 실제 동작 코드로 오해하지 않도록 경고문 추가.
2. 장기(Ch08에서): JAL은 `pc_src=2'b01`(ALUOut = PC+imm_J)을 사용하도록 FSM 상태표 설계. JALR은 `A + imm_I`를 ALU로 계산 후 하위 1비트 클리어 처리(RV32I 스펙 §2.5 요구 사항).
3. **즉시 필요**: HTML 7.3.1절 PCSrc 설명(줄 511)에서 `2'b10`을 "점프 주소 조합 (JAL/JALR용)"이라 설명하는 내용은 **오해를 유발**한다. 현재 코드가 RV32I와 맞지 않는다는 경고 없이 해당 설명을 두는 것은 독자에게 잘못된 이해를 심는다.

**심각도 근거**: ISA 스펙 위반. 이 코드를 그대로 Ch08 FSM과 연결하면 JAL이 잘못된 주소로 점프하는 버그가 발생한다.

---

### 🔴 [C2] MDR 무조건 갱신 — IF 단계 데이터 오염 가능성 (기능 버그)

**파일**: `ch07_multicycle_datapath.sv`, 줄 148–150 / `ch07_sec03_intermediate_regs.sv`, 줄 58–60
**현재 코드**:
```systemverilog
always_ff @(posedge clk) begin
   mdr_reg <= mem_data_out; // 매 사이클 갱신 (인에이블 불필요)
end
```

**문제 분석**:
통합 메모리 읽기가 동기 방식이므로 `mem_data_out`은 `mem_read`가 1일 때 다음 클럭 에지에 유효해진다.

1. **IF 단계**: `mem_read=1`, `i_or_d=0`(PC 주소). 메모리에서 명령어를 읽어 `mem_data_out`에 출력. 이 사이클 클럭 에지 후 `mdr_reg`가 `mem_data_out`(= 명령어 코드)으로 갱신된다.
2. **ID 단계**: `mem_read=0`. 메모리는 읽기를 수행하지 않으나, 현재 구현에서 `mem_data_out`은 이전 사이클 읽기 결과(명령어 코드)를 보유하고 있다. `mdr_reg`는 또 갱신된다(동일 값이므로 무해).
3. **EX 단계**: `mem_read=0`. 동일.
4. **MEM 단계(LW)**: `mem_read=1`, `i_or_d=1`(ALUOut 주소). 데이터 메모리 읽기. 클럭 에지 후 `mdr_reg`가 로드 데이터로 갱신된다 (올바름).
5. **WB 단계**: `mem_read=0`. `mdr_reg`는 MEM 단계 클럭 에지에서 저장된 로드 데이터를 유지 (올바름).

현재 구현의 `mem_data_out`은 `mem_read=0`일 때 값을 "보유"한다(레지스터가 아닌 조합 신호라면 X가 될 수 있음). 그러나 `mem_data_out`이 `always_ff` 출력이므로, `mem_read=0`일 때 마지막 읽기 값을 유지한다. 따라서 MDR가 IF 단계의 명령어 코드를 저장하는 것은 맞지만, **WB 단계에서 MDR를 참조하는 시점에 올바른 로드 데이터(MEM 단계 결과)가 들어있으면 기능적으로는 동작한다**.

그러나 이는 **설계 의도가 불명확**하고, 교재 설명("인에이블 불필요, MEM 단계가 아닌 사이클에서도 무해하다")이 부정확하다. 특히 `mem_data_out` 신호의 동작 특성(동기 레지스터 출력 vs 조합 신호)이 명시되지 않으면 독자가 올바른 분석을 할 수 없다.

**더 중요한 실제 기능 리스크**: `ch07_multicycle_datapath.sv`에서 `mem_data_out`은 내부 logic 선언(`logic [31:0] mem_data_out`)이고 `always_ff`로 구동된다. 이 경우 `mem_read=0`이면 `mem_data_out`은 이전 값을 유지한다(레지스터). 그러므로 IF 단계 이후 MDR에는 명령어 코드가 들어있게 된다. LW의 WB 단계에서 MDR가 MEM 단계 결과를 담고 있으려면, MEM 단계(사이클 4)의 클럭 에지에서 MDR가 갱신되어야 하고 WB 단계(사이클 5)에서는 갱신되지 않아야 한다. 현재 코드는 WB 단계에서도 MDR를 갱신한다. WB 단계에서 `mem_read=0`이므로 `mem_data_out`은 MEM 단계의 읽기 결과를 유지하고, MDR는 같은 값으로 갱신된다. **결국 기능적으로는 동작하나, 설계가 암묵적 의존성에 의존한다.**

**수정 방안**:
```systemverilog
// 권장: MDR는 LW MEM 단계에서만 갱신
always_ff @(posedge clk) begin
   if (mem_read && i_or_d)  // 데이터 메모리 읽기일 때만
      mdr_reg <= mem_data_out;
end
```
또는 최소한 HTML 설명에서 "IF 단계에서 MDR가 명령어 코드로 갱신되지만, LW WB 단계에서는 MEM 단계의 읽기 결과가 이미 저장되어 있으므로 기능적으로 무해하다"는 정확한 동작 설명 추가 필요.

**교재 수정 필수**: "MEM 단계가 아닌 다른 사이클에서는 MDR 값을 WB MUX가 선택하지 않으므로 무해합니다"라는 설명(HTML 줄 549)은 부분적으로 옳지만, 설계 의존성을 감추는 설명이다. 정확한 동작 원리를 명시해야 한다.

---

## Major 이슈

---

### 🟡 [M1] reg_dst 포트가 데이터패스에서 실제로 사용되지 않음

**파일**: `ch07_multicycle_datapath.sv`, 줄 26–27 / HTML 줄 1052
**현재 코드**:
```systemverilog
input  logic [1:0]  reg_dst,  // 쓰기 레지스터 선택 (rd)
```

**문제**: `reg_dst` 신호가 포트로 선언되어 있으나, 모듈 내부에서 어디에도 사용되지 않는다. 레지스터 파일 쓰기 주소는 항상 `rd_addr = ir_reg[11:7]`로 고정되어 있다 (줄 84). RV32I에서 쓰기 대상 레지스터는 항상 `rd`(ir[11:7])이므로, `reg_dst`로 다른 레지스터를 선택해야 할 경우가 없다. 이 신호는 MIPS 구조에서 R-type rd와 I-type rt를 구분하기 위한 제어 신호인데, RV32I에는 해당하지 않는다.

Vivado에서 합성 시 "unused port" 경고 또는 `reg_dst`를 구동하는 FSM에서 불필요한 출력이 추가된다.

**수정 방안**: `reg_dst` 포트 제거. 또는 사용 목적이 있다면(예: WB 주소를 JAL의 rd로 고정) 해당 MUX 로직 추가 및 설명.

---

### 🟡 [M2] 통합 메모리의 바이트/하프워드 접근 미지원 — 교재 범위 경계 불명확

**파일**: `ch07_multicycle_datapath.sv`, 줄 130–133 / `ch07_sec02_unified_memory.sv`
**현재 코드**:
```systemverilog
// ch07_multicycle_datapath.sv — 워드 단위 쓰기만 지원
always_ff @(posedge clk) begin
   if (mem_write)
      memory[mem_addr[13:2]] <= b_reg;
end
```

**문제**: `ch07_multicycle_datapath.sv`의 메모리는 SB, SH(바이트/하프워드 쓰기) 및 LB, LH, LBU, LHU(바이트/하프워드 읽기)를 전혀 지원하지 않는다. `ch07_sec02_unified_memory.sv`는 바이트 인에이블(`byte_enable[3:0]`)을 지원하나, 메인 데이터패스 모듈(`ch07_multicycle_datapath.sv`)은 `byte_enable` 신호 자체가 없다.

두 파일 간 불일치가 있으며, 독자는 `ch07_multicycle_datapath.sv`가 완전한 RV32I 구현이라 오해할 수 있다. 7.3절에서 LW/SW 이외의 메모리 명령어 지원 여부를 명시적으로 제한하지 않으면 혼란이 발생한다. Ch07 원고(HTML)에는 이 제한 사항에 대한 설명이 없다.

**수정 방안**:
- HTML 7.3절에 명시적 제한 표기: "이 챕터의 구현은 LW/SW(워드 단위)만 지원합니다. LB/SB/LH/SH 지원은 Ch08 구현 시 funct3 기반 바이트 인에이블 로직을 추가합니다."
- `ch07_multicycle_datapath.sv`에도 동일한 제한 주석 추가.
- `ch07_sec02_unified_memory.sv`의 바이트 인에이블 설계는 유지하되, "확장 구현 예시"임을 명확히.

---

### 🟡 [M3] A/B 레지스터 무조건 갱신 — 설계 의도 미명시

**파일**: `ch07_multicycle_datapath.sv`, 줄 180–183 / `ch07_sec03_intermediate_regs.sv`, 줄 69–88

**문제**: A/B 레지스터는 매 사이클 `rs1_data`, `rs2_data`로 무조건 갱신된다. ID 단계 이후(EX, MEM, WB 단계)에도 갱신이 발생한다.

이 동작이 안전한 이유:
1. `ir_reg`는 `ir_write=0` (ID 이후 사이클)이면 값을 유지한다.
2. `rs1_addr = ir_reg[19:15]`, `rs2_addr = ir_reg[24:20]`이므로 IR이 유지되는 한 레지스터 파일 읽기 주소가 안정적이다.
3. 따라서 레지스터 파일에서 읽히는 값도 변하지 않는다 (레지스터 파일 쓰기는 WB 단계에서만 발생하며, 그것도 현재 명령어의 `rd_addr`에 대해서만 발생하므로 EX 단계 이후 A/B가 다시 읽혀도 같은 값).

그러나 교재 설명은 이 의존 관계를 설명하지 않는다. 독자가 "A/B는 왜 인에이블이 없나?"라고 질문할 때, 현재 설명("ID 단계 이후 값이 EX에서 필요", HTML 줄 67 `intermediate_regs.sv`)은 정확하지 않다. 실제로는 ID 단계에서만 갱신해도 충분하며, 매 사이클 갱신은 불필요한 전력 소모다.

**수정 방안**:
- HTML 7.3.1절에 설명 추가: "A/B 레지스터가 매 사이클 갱신되어도 안전한 이유는 IR이 IF 단계 이후 값을 유지하기 때문이다. IR의 rs1/rs2 필드가 변하지 않으면 레지스터 파일 읽기 결과도 변하지 않는다."
- 선택적 개선: ID 상태 인에이블을 명시적으로 추가하는 "엄격한 설계" 예시와 "암묵적 의존 설계" 예시를 나란히 제시하여 설계 의도 비교.

---

### 🟡 [M4] ALU `always_comb` 내 출력 다중 드라이브 경고 가능성

**파일**: `ch07_multicycle_datapath.sv`, 줄 241–257
**현재 코드**:
```systemverilog
always_comb begin
   alu_zero = 1'b0;           // ① 초기화
   case (alu_op)
      4'b0000: alu_result = alu_a + alu_b;
      // ...
   endcase
   alu_zero = (alu_result == 32'd0);  // ② 재할당
end
```

**문제**: `alu_zero`가 같은 `always_comb` 블록 내에서 두 번 할당된다 (줄 242, 256). SystemVerilog 시뮬레이션에서는 마지막 할당이 유효하므로 기능적으로는 올바르다. 그러나 일부 합성 도구(특히 구형 버전)에서 "multiple drivers" 또는 "signal driven from multiple statements" 경고를 발생시킬 수 있다.

또한 `alu_result`가 `case` 문 안에서만 할당되므로, `default` 케이스 없이 `case`를 완료하면 `alu_result`에 대해 latch 추론 경고가 발생할 수 있다(현재 `default: alu_result = alu_a + alu_b;`가 있으므로 이 부분은 안전). Vivado는 현재 코드에서 경고 없이 합성될 것으로 예상되나, 교육 목적에서 학생 코드 스타일로 권장하기에는 혼란을 줄 수 있다.

**수정 방안**:
```systemverilog
always_comb begin
   case (alu_op)
      4'b0000: alu_result = alu_a + alu_b;
      // ...
      default: alu_result = alu_a + alu_b;
   endcase
   alu_zero = (alu_result == 32'd0);  // case 이후 단 한 번만 할당
end
```
초기화(`alu_zero = 1'b0`)를 제거하고 case 이후 한 번만 할당하는 패턴이 더 명확하다.

---

### 🟡 [M5] Basys 3 BRAM 합성 가능성 — 단일 포트 제약 설명 부재

**파일**: `ch07_multicycle_datapath.sv`, 줄 121–133 / HTML 7.2절 Princeton 구조 설명

**문제**: 교재 HTML 7.2절은 "하나의 포트로 명령어 인출과 데이터 읽기를 시분할 처리"라고 설명하나, Vivado가 `logic [31:0] memory [0:4095]`를 추론하는 BRAM 타입과 포트 설정에 따라 동작이 달라진다.

Xilinx Artix-7(Basys 3):
- `mem_read`와 `mem_write`가 같은 always_ff 블록에 있지 않고 별도 블록에 있다.
- Vivado는 두 always_ff 블록을 Simple Dual Port BRAM으로 추론할 가능성이 있다 (읽기 포트 / 쓰기 포트 분리).
- Simple Dual Port BRAM은 같은 사이클에 읽기+쓰기가 가능하다. 멀티사이클 FSM이 `mem_read`와 `mem_write`를 절대 동시에 assert하지 않으면 안전하다.
- 그러나 읽기 포트와 쓰기 포트에 서로 다른 주소를 같은 사이클에 사용할 수 있으므로, IF와 MEM이 같은 사이클에 발생한다면 이는 기능 오류가 된다. 멀티사이클 FSM이 이를 막는다는 보장을 교재에서 명시해야 한다.

**현재 HTML**: "FSM이 한 번에 하나의 상태만 활성화하기 때문"이라는 설명이 7.2절 FAQ(줄 367)에 있으나, "BRAM 포트 구성이 Vivado에서 어떻게 추론되는가"에 대한 설명은 없다.

**수정 방안**: HTML에 아래 내용 추가:
- Vivado에서 이 통합 메모리가 Block RAM으로 추론될 때 포트 구성(Simple Dual Port 가능성) 설명.
- FSM이 `mem_read`와 `mem_write`를 동시에 assert하지 않아야 한다는 제약을 명시 (Ch08 FSM 설계 시 준수 사항).
- `initial begin $readmemh(...) end`이 합성 시 BRAM 초기값으로 처리되는 점 언급 (시뮬레이션에서는 동작, 합성에서는 `.coe` 또는 `$readmemh`를 Vivado가 BRAM 초기화 파일로 인식).

---

## Minor 이슈

---

### 🟢 [N1] `ch07_sec03_intermediate_regs.sv` 모듈 헤더 불일치

**파일**: `ch07_sec03_intermediate_regs.sv`, 줄 1–9

모듈 헤더 주석에 "중간 레지스터 4종"이라고 하지만 실제로는 ALUOut 레지스터를 포함하지 않는다(IR, MDR, A, B만 포함). 챕터 본문(HTML 7.1절 학습목표 줄 27)에서는 "A/B/ALUOut/MDR 레지스터"를 핵심으로 언급하고, 7.5절 요약(줄 951)에서도 "중간 레지스터 5종: IR, A/B, ALUOut, MDR"라 명시한다. 이 모듈 이름/헤더와 교재 본문 간 수량 불일치(4 vs 5)가 독자 혼란을 유발한다.

**수정 방안**: 모듈 헤더 주석을 "중간 레지스터 4종 (ALUOut 제외 — ch07_multicycle_datapath.sv에 포함)"으로 명확화.

---

### 🟢 [N2] B-type 즉치수 비트 위치 검증

**파일**: `ch07_multicycle_datapath.sv`, 줄 200–202
**현재 코드**:
```systemverilog
7'b1100011:  // B-type
   imm_ext = {{19{ir_reg[31]}}, ir_reg[31], ir_reg[7],
               ir_reg[30:25], ir_reg[11:8], 1'b0};
```

RV32I B-type 즉치수(ISA §2.3):
- `imm[12]` = `ir[31]`
- `imm[11]` = `ir[7]`
- `imm[10:5]` = `ir[30:25]`
- `imm[4:1]` = `ir[11:8]`
- `imm[0]` = 0 (1비트 왼쪽 정렬)

따라서 32비트 부호 확장:
```
{sign_ext[19비트], imm[12], imm[11], imm[10:5], imm[4:1], 1'b0}
= {{19{ir[31]}}, ir[31], ir[7], ir[30:25], ir[11:8], 1'b0}
```
총 비트 수: 19+1+1+6+4+1 = 32비트. **현재 코드는 정확하다.**

Ch06 리뷰 로그에서 "B/J 타입 즉치수 비트 재배열 반드시 설명" 지침이 있었으므로 확인 완료로 표기한다.

---

### 🟢 [N3] J-type 즉치수 비트 위치 검증

**파일**: `ch07_multicycle_datapath.sv`, 줄 209–211
**현재 코드**:
```systemverilog
7'b1101111:  // J-type (JAL)
   imm_ext = {{11{ir_reg[31]}}, ir_reg[31], ir_reg[19:12],
               ir_reg[20], ir_reg[30:21], 1'b0};
```

RV32I J-type 즉치수(ISA §2.3):
- `imm[20]` = `ir[31]`
- `imm[19:12]` = `ir[19:12]`
- `imm[11]` = `ir[20]`
- `imm[10:1]` = `ir[30:21]`
- `imm[0]` = 0

따라서 32비트 부호 확장:
```
{{11{ir[31]}}, ir[31], ir[19:12], ir[20], ir[30:21], 1'b0}
```
총 비트 수: 11+1+8+1+10+1 = 32비트. **현재 코드는 정확하다.**

---

## 특별 검토 포인트 종합 판정

| 기획 단계 이슈 | 판정 | 상세 |
|---------------|------|------|
| **[P1] PCSrc 2'b10 MIPS 방식 여부** | 🔴 확인: RV32I와 불일치 | MIPS J-type 방식. RV32I JAL에는 부적합. [C1] 참조. |
| **[P2] MDR 무조건 갱신 오염 가능성** | 🔴 확인: 암묵적 의존성 존재 | 기능적으로는 동작하나 설계 근거 불명확. 교재 설명 수정 필요. [C2] 참조. |
| **[P3] A/B 레지스터 인에이블 없음** | 🟡 조건부 안전 | IR 유지에 의존하는 암묵적 안전성. 명시적 설명 필요. [M3] 참조. |
| **[P4] 통합 메모리 바이트 인에이블** | 🟡 교재 범위 제한 미명시 | 메인 모듈이 LW/SW만 지원하나 제한 명시 없음. [M2] 참조. |
| **[P5] Basys 3 BRAM 단일 포트 제약** | 🟡 설명 보완 필요 | BRAM 추론 방식 미설명. FSM 제약 명시 필요. [M5] 참조. |

---

## ISA 스펙 준수 검토

| 항목 | 판정 | 근거 |
|------|------|------|
| R-type opcode (0110011) | ✅ | ALU 연산 opcode 정확 |
| I-type 즉치수 부호 확장 | ✅ | `{{20{ir[31]}}, ir[31:20]}` |
| S-type 즉치수 | ✅ | `{ir[31:25], ir[11:7]}` 정확 |
| B-type 즉치수 재조합 | ✅ | [N2] 검증 완료 |
| U-type 즉치수 | ✅ | `{ir[31:12], 12'd0}` |
| J-type 즉치수 재조합 | ✅ | [N3] 검증 완료 |
| JAL PC-relative 주소 계산 | 🔴 | PCSrc 2'b10 MIPS 방식. [C1] 참조 |
| x0 레지스터 쓰기 방지 | ✅ | `rd_addr != 5'd0` 조건 |
| SLT signed 비교 | ✅ | `$signed(alu_a) < $signed(alu_b)` |
| SRA 산술 우시프트 | ✅ | `$signed(alu_a) >>> alu_b[4:0]` |

---

## SystemVerilog 문법 및 합성 가능성 검토

| 항목 | 판정 | 근거 |
|------|------|------|
| `always_ff` 비동기 리셋 패턴 | ✅ | IEEE 1800-2017 표준 준수 |
| `always_comb` 조합 논리 | ✅ | 적절한 사용 |
| `logic` 타입 사용 | ✅ | SystemVerilog 권장 타입 |
| Latch 추론 방지 | ✅ | `default` 케이스 포함 |
| 합성 불가능 구조 | ✅ | 없음 |
| `$signed()` 캐스트 | ✅ | 합성 가능 |
| 다중 드라이브 경고 가능성 | 🟡 | ALU `alu_zero` 이중 할당. [M4] 참조 |
| 네이밍 규칙 (snake_case) | ✅ | 일관적 적용 |
| 들여쓰기 3칸 | ✅ | 준수 |
| `$readmemh` 합성 처리 | 🟡 | Vivado BRAM 초기화 파일 처리 방식 미설명. [M5] 참조 |

---

## 즉시 수정 필요 Action Items

### Critical — 집필 전 반드시 처리

1. **[C1] HTML 7.3.1절 PCSrc 2'b10 설명 수정**
   - 위치: `chapter07.html` 줄 511 ("2'b10: 점프 주소 조합 (JAL/JALR용…)")
   - 조치: "현재 코드의 2'b10 케이스는 RV32I JAL과 일치하지 않는다. JAL은 EX 단계에서 PC+imm_J를 ALU로 계산하여 ALUOut에 저장하고, pc_src=2'b01을 사용한다. 이 케이스는 Ch08 FSM 설계와 함께 올바르게 재정의된다."를 명시.
   - `ch07_multicycle_datapath.sv` 줄 104에도 경고 주석 강화.

2. **[C2] HTML MDR 설명 정확화**
   - 위치: `chapter07.html` 줄 546–551 ("MDR는 ir_write처럼 인에이블 신호가 없습니다… 기능적으로 무해합니다")
   - 조치: IF 단계에서도 MDR가 갱신되나 LW WB 단계에서 참조 시점에 올바른 값이 보장되는 메커니즘(mem_data_out이 동기 레지스터이므로 MEM 단계 결과를 유지)을 명확히 설명.

### Major — Ch08 FSM 연동 전 처리 권장

3. **[M1] reg_dst 포트 사용 여부 명확화**
   - 사용하지 않는다면 포트에서 제거하거나, 사용 목적 추가.

4. **[M2] LW/SW 전용 제한 명시**
   - HTML 7.3절에 "이 구현은 LW/SW(32비트 워드)만 지원, LB/SB 지원은 Ch08에서 확장" 명시.

5. **[M4] ALU alu_zero 이중 할당 리팩터링**
   - `alu_zero = 1'b0;` 초기화 제거, case 이후 단 한 번만 할당.

6. **[M5] BRAM 합성 관련 설명 추가**
   - HTML 7.2절 Princeton 구조 설명에 Vivado BRAM 추론 방식 및 FSM 제약 추가.

### Minor — 최종 원고 교정 시 처리

7. **[N1] `ch07_sec03_intermediate_regs.sv` 헤더 주석 수정**
   - "4종 (ALUOut 제외 — ch07_multicycle_datapath.sv에 포함)" 명시.

---

## 긍정적 평가 사항

- **즉치수 생성기 정확성**: B-type, J-type을 포함한 모든 즉치수 비트 재조합이 RV32I 스펙과 일치한다 (Ch06 리뷰 주의사항 반영 확인).
- **x0 쓰기 방지**: 레지스터 파일에서 `rd_addr != 5'd0` 조건으로 x0 덮어쓰기를 방지했다.
- **비동기 리셋 패턴**: `always_ff @(posedge clk or negedge rst_n)` 패턴이 IR, PC에 일관되게 적용되었다.
- **IorD MUX 설계**: `assign mem_addr = i_or_d ? alu_out_reg : pc_reg` — 정확하고 간결하다.
- **Write-Back MUX 3선택**: JAL/JALR 복귀 주소를 위한 `mem_to_reg=2'b10 → pc_reg` 케이스가 포함되어 있어 RISC-V의 link register 동작을 지원하는 구조다.
- **SLT/SLTU 구분**: signed/unsigned 비교를 `$signed()` 캐스트로 올바르게 구분했다.
- **MDR를 독립 모듈로 분리한 `ch07_sec03_intermediate_regs.sv`**: 교육 목적에서 핵심 레지스터만 분리하여 설명하는 접근이 적절하다.
- **HTML 코드 블록 HTML 이스케이프**: `<`, `>`, `&` 이스케이프 처리가 일관되게 적용되었다.

---

*작성: 기술 리뷰어*
*다음 단계: 초보자 독자 리뷰, 교육 설계자 리뷰, 교육심리전문가 리뷰 병렬 진행 후 chapter07_meeting.md 종합 회의*
