# Chapter 08 — 편집장 종합 회의록

**일시**: 2026-03-11
**참여**: 편집장, 기술 리뷰어, 초보자 독자, 교육 설계자, 교육심리전문가
**대상 파일**: manuscripts/part3/chapter08.html

---

## 회의 개요

4개 리뷰(기술, 초보자, 교육 설계, 교육심리)를 종합하여 Critical 3건, Major 다수 이슈에 대한 최종 결정을 내린다.
원고 수정은 편집장이 직접 수행한다. 기술 정확성 > 심리적 안전 > 이해도 > 분량 우선순위를 준수한다.

---

## A. Critical 이슈 결정

### C-1: branch_taken 이중 구동 (합성 오류)

**문제**: 전체 소스 코드 섹션 완전 버전 fsm_controller에서 두 번째 always_comb 블록(출력 로직)에
`branch_taken = 1'b0;` 이 포함되어 있어 첫 번째 always_comb (funct3 디코딩 블록)과
multiple driver 오류가 발생한다. Vivado 합성 거부.

**결정**: 두 번째 always_comb 블록(출력 로직)에서 `branch_taken = 1'b0;` 행을 삭제한다.
branch_taken은 첫 번째 always_comb에서만 구동한다.

**수정 공수**: 낮음 (1행 삭제)

---

### C-2: EX_BR 분기 주소 계산 방식 불일치

**문제**: 8.2.4절 본문에서 branch_adder 별도 덧셈기를 언급하나, 제어 신호 표와 코드에서
`pc_src=2'b01 (ALUOut)`로 설정되어 있다. EX_BR에서 ALUOut에는 A-B(SUB 결과)가 저장되지
PC+imm_B가 저장되지 않는다. 구조적 모순.

**편집장 결정**: **Option A 채택** — pc_src 인코딩에 2'b10을 추가하여 branch_adder 출력을
PC MUX에 연결. branch_adder는 데이터패스에 소형 추가 덧셈기로 IF단계에서 저장한
old_pc_reg + imm_B를 계산한다.

이유: 3사이클 Branch가 교육적으로 더 명확하고 CPI 계산의 다양성을 보여준다.
branch_adder는 데이터패스에 작은 추가이며, 8.2절 EX_BR 설명에서 별도 덧셈기를 명시적으로
설명함으로써 교육 효과를 높인다.

**구현**:
- pc_src 인코딩 표 수정: `2'b10 = branch_adder 출력 (old_pc_reg + imm_B)`
- EX_BR 상태에서 pc_src = 2'b10으로 수정 (본문 표 및 코드)
- 8.2절 EX_BR 설명에 branch_adder 명시적 기술 추가

---

### C-3: JAL/AUIPC에서 PC 기준점 문제 (old_pc_reg 추가)

**문제**: IF 단계에서 PC가 PC+4로 갱신되므로, EX_JAL/EX_AUIPC에서 ALU A=PC는
original_PC+4를 참조하여 4바이트 오차 발생.

**편집장 결정**: **Option A 채택** — Ch07 데이터패스에 `old_pc_reg` 소급 추가.
PC 갱신 직전 원본 PC를 별도 레지스터에 저장.

이유: Ch07에 대한 최소한의 수정으로 C-3과 M-2(AUIPC) 모두 해결.
Ch08 도입부에서 "데이터패스 한 가지 보완" 박스로 자연스럽게 처리.

**alu_src_a 2비트 확장 결정**:
현재 1비트 alu_src_a(0=PC, 1=A레지스터)를 2비트로 확장하여
세 가지 소스를 구분한다:
- `2'b00` = PC 레지스터 (현재 PC, IF 단계 PC+4 계산용)
- `2'b01` = old_pc_reg (IF 단계 직전 원본 PC, JAL/AUIPC용)
- `2'b10` = A 레지스터 (rs1, EX 단계)

**상태별 alu_src_a 업데이트**:
| 상태 | alu_src_a | 이유 |
|------|-----------|------|
| S_IF | 2'b00 | PC (현재) |
| S_ID | 2'b00 | don't care (사용 안 함) |
| S_EX_R, S_EX_I, S_EX_LOAD, S_EX_ST, S_EX_BR, S_EX_JALR | 2'b10 | A 레지스터 (rs1) |
| S_EX_JAL, S_EX_AUIPC | 2'b01 | old_pc_reg |
| S_EX_LUI | 2'b10 | A 레지스터 (= x0 = 0, ID에서 강제) |

**old_pc_reg 구현**:
```systemverilog
always_ff @(posedge clk or negedge rst_n) begin
   if (!rst_n)
      old_pc_reg <= 32'd0;
   else if (ir_write)  // IF 단계에서만 갱신
      old_pc_reg <= pc_reg;  // PC 갱신 직전 값 캡처
end
```

---

## B. Major 이슈 결정

### M-1: BLTU/BGEU 무부호 비교

**결정**: ALU에서 alu_ltu(무부호 less-than) 신호를 추가 출력한다.
branch_ctrl 로직에서 funct3[1]=0이면 부호(alu_lt), funct3[1]=1이면 무부호(alu_ltu) 사용.
fsm_controller 포트에 `input logic alu_ltu` 추가. branch_taken 디코딩 로직 수정.
aside에 "BLTU/BGEU는 무부호 비교" 기술적 설명 추가.

### M-3: ID 단계 ALU 연산 모호성

**결정**: 본문 표의 "실제 사용 안 함" 설명을 유지하되, 추가 설명 추가:
"ID 단계의 ALU 설정(alu_src_a=PC, alu_src_b=imm_ext)은 branch_adder 없이 분기 주소를
미리 계산하는 최적화 방향을 염두에 둔 것입니다. 현재 구현에서는 branch_adder를 사용하므로
이 결과는 사용되지 않으나, 기본값과 다른 값을 출력하더라도 회로 동작에 영향을 주지 않습니다."

### M-4: 전체 소스 코드 중첩 case 문법 주의

**결정**: S_ID: case(opcode) 부분을 단순 설명 코드임을 명시하는 주석 추가.
"아래 코드는 다음 상태 로직의 압축 표현입니다. 실제 합성 시에는 각 case 항목을 별도 행으로
분리해야 합니다."라는 주석을 해당 블록 앞에 추가한다.

### 교육/심리 Major 이슈

| 이슈 | 결정 |
|------|------|
| 8.4절 마일스톤 축하 문장 | 추가 — "두 챕터에 걸쳐 설계한 데이터패스와 FSM이 지금 하나의 CPU로 합쳐집니다." |
| 8.7절 파이프라인 준비 완료 문구 | 추가 — "이제 여러분은 파이프라인을 배울 준비가 충분히 되어 있습니다." |
| 8.3절 긴 코드 전 안심 문구 | 추가 — "코드가 길어 보이지만 패턴이 17번 반복될 뿐입니다." |
| 래치 경고 실패 정상화 | 추가 — "처음 FSM을 작성하는 거의 모든 엔지니어가 만나는 통과의례입니다." |
| 8.3절 interview 박스 중복 | 8.3절 박스를 간략 언급으로 축소 + 8.6절 forward reference |
| 8.2절 소결 추가 | 추가 — 17개 상태 설계 완료 후 핵심 3가지 요약 |
| 8.3절 소결 추가 | 추가 — FSM 코드 구조 요약 |
| Fmax 첫 등장 병기 | 수정 — "최대 클럭 주파수(Fmax, Maximum Clock Frequency)" |
| MIPS 단위 첫 등장 병기 | 수정 — "백만 명령어/초(MIPS, Million Instructions Per Second)" |

---

## C. Minor 이슈 결정

| 이슈 | 결정 |
|------|------|
| m-1: interview 박스 번호 중복 (#11) | 8.3절 박스에서 번호 제거 (간략 언급으로 변경) |
| m-2: MIPS 용어 혼란 | 위 Major 결정과 동일 |

---

## 수정 우선순위 및 담당

편집장이 직접 수행. 순서:
1. C-1: branch_taken 이중 구동 1행 삭제
2. C-2: EX_BR pc_src=2'b10, branch_adder 설명 추가
3. C-3: old_pc_reg 박스 추가, alu_src_a 2비트 확장 (본문 표 + 코드)
4. M-1: alu_ltu 추가 (포트 + 로직)
5. 교육/심리 Major: 안심 문구, 마일스톤, 소결, 용어 병기
6. Minor: interview 박스 정리

---

## 피드백 충돌 해결

**기술 리뷰어 vs 교육 설계자**: M-3(ID 단계 ALU 연산 모호성)에 대해 기술 리뷰어는
"사용하지 않으면 기본값으로 두라"고, 교육 설계자는 "목적을 명확히 설명하라"고 요청.
→ **결정**: 기존 설정값 유지 + 설명 보강. 정확성 > 이해도 원칙에 따라 기술적 배경
(최적화 방향 염두)을 명시하여 두 요구를 모두 충족.

---

*회의 완료: 2026-03-11*
*다음 단계: 편집장 직접 원고 수정 → 최종 승인 문서 작성*
