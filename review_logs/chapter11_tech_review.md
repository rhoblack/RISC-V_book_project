# Chapter 11 기술 리뷰

## 총평

전반적으로 설계 구조(branch_unit, flush 로직, JAL/JALR 처리)는 기술적으로 올바르게 설계되었으며,
RISC-V ISA 스펙을 충실히 반영합니다. 그러나 **테스트벤치와 HTML 원고의 머신코드 인코딩에
2개의 Critical 오류**가 발견되었습니다. 이 오류로 인해 루프 마일스톤 시뮬레이션이 정상
동작하지 않습니다(무한 루프 또는 잘못된 점프). 또한 BHT 성능 테이블에 Major 오류와
테스트벤치 커버리지 부족 문제가 확인되었습니다.

Critical/Major 수정 후 재승인이 필요합니다.

---

## Critical 이슈 (🔴)

### 🔴 C1 — `add x2, x2, x1` 머신코드 오류 (테스트벤치 + HTML 원고)

**위치**: `code_examples/ch11_control_hazard_tb.sv` line 62, `manuscripts/part4/chapter11.html` line 721

**현상**:
```
dut.u_imem.mem[3] = 32'h001101B3; // add  x2, x2, x1   (loop:)
```

**실제 디코딩**:
- `0x001101B3`을 디코딩하면 `add x3, x2, x1` (rd=x3, rs1=x2, rs2=x1)
- `rd` 필드 비트[11:7] = `00110` = 6 → x3, 주석과 달리 rd가 x2가 아님

**올바른 인코딩**:
- `add x2, x2, x1`: funct7=0000000, rs2=x1(00001), rs1=x2(00010), funct3=000, rd=x2(00010), opcode=0110011
- = `0x00110133`

**영향**:
- 루프 실행 시 `x2(sum)`가 갱신되지 않고 `x3(limit=11)`이 매 반복마다 덮어씌워짐
- `x3 = x2(=0) + x1 = x1_prev`, `x1 = x1_prev + 1` → x1 항상 x3+1 → BNE 조건 항상 성립
- **무한 루프 발생**, 검증 조건 `x2=55` 절대 통과 불가
- 동일 오류가 HTML 원고 11.7절 테스트벤치 코드 스니펫에도 동일하게 존재함

**수정 방법**: `32'h001101B3` → `32'h00110133`

---

### 🔴 C2 — `bne x1, x3, -12` 머신코드 오류 (테스트벤치 + HTML 원고)

**위치**: `code_examples/ch11_control_hazard_tb.sv` line 65–70, `manuscripts/part4/chapter11.html` line 724

**현상**:
```
dut.u_imem.mem[5] = 32'hFE3090E3; // bne  x1, x3, -12 (offset=-12 -> 0x0C)
```

**실제 디코딩**:
- `0xFE3090E3`을 B-type 디코딩: imm[12]=1, imm[11]=0, imm[10:5]=111111, imm[4:1]=0000
- imm_B = 0b1_0_111111_0000_0 = -32 (부호 있는 13비트)
- `bne x1, x3, -32`로 디코딩됨

**오프셋 계산 오류**:
- BNE 위치: PC = 0x14 (mem[5] = 5×4 = 0x14)
- 루프 레이블 위치: PC = 0x0C (mem[3] = 3×4 = 0x0C)
- 필요한 오프셋: 0x0C - 0x14 = **-8** (주석의 -12는 잘못됨)

**올바른 인코딩**:
- `bne x1, x3, -8`: imm_B = -8 = 0b1_1_111111_1000 (13비트)
  - imm12=1, imm11=1, imm10_5=111111, imm4_1=1000
  - = `0xFE309CE3`

**영향**:
- 오프셋 -32: PC = 0x14 + (-32) = -12 → **음수 PC 주소로 점프** (완전히 무효한 타겟)
- 루프가 올바른 위치(0x0C)로 돌아오지 않음, 시뮬레이션 결과 검증 불가

**수정 방법**: `32'hFE3090E3` → `32'hFE309CE3`, 주석도 `-12` → `-8`로 수정

---

## Major 이슈 (🟡)

### 🟡 M1 — BHT 성능 테이블 페널티 사이클 수 오류

**위치**: `manuscripts/part4/chapter11.html` 11.5절 성능 비교 표

**현상**:
| 전략 | 루프 10회 | 페널티 총합 |
|------|-----------|-------------|
| BHT 2-bit | 첫 반복 1회 오예측 | 2사이클 (초기화 후 ~0) |

**실제 계산** (초기 상태: 01 = 약한 미분기):
- BNE 실행 10회: 9회 taken + 1회 not-taken (루프 종료)
- Exec 1: predict=NT(01), actual=T → **MISS**, 상태 01→10
- Exec 2~9: predict=T(10→11), actual=T → HIT (8회)
- Exec 10: predict=T(11), actual=NT → **MISS**, 상태 11→10

실제 오예측 횟수: **2회** = **4사이클 페널티**

**잘못된 이유**: 루프의 마지막 반복(루프 탈출) 시 BNE not-taken이 되어 발생하는
두 번째 오예측을 누락함.

**수정 방법**: 표의 BHT 행을 아래와 같이 수정
- "첫 반복 1회 오예측" → "첫 반복 + 루프 탈출 시 2회 오예측"
- "2사이클" → "4사이클"

같은 절 본문 설명 "첫 반복에서만 오예측이 일어나므로" 문장도 "첫 반복과 루프 탈출 시 2회 오예측이 일어나므로"로 수정 필요.

---

### 🟡 M2 — 테스트벤치 커버리지: 선언된 시나리오 미구현

**위치**: `code_examples/ch11_control_hazard_tb.sv` lines 7–10

**현상**: 파일 헤더 주석에 4가지 테스트 시나리오가 선언되어 있으나:
```
// 테스트 시나리오:
//   1. BEQ taken   -- flush 동작, wrong-path 제거 검증
//   2. BNE not-taken -- 정상 실행, 플러시 없음 검증
//   3. Load-JALR hazard -- 스톨 후 JALR 정상 실행
//   4. 루프 마일스톤 -- 1~10 합산 (x2 = 55) 검증
```
실제 구현은 **시나리오 4(루프 마일스톤)만 존재**. 시나리오 1, 2, 3은 명령어 메모리 초기화
코드도 없고 검증 assertion도 없음.

**영향**:
- 시나리오 1(BEQ taken flush) 미검증: wrong-path 명령어가 레지스터 파일을 오염시키는
  가장 중요한 버그가 숨겨질 수 있음
- 시나리오 3(Load-JALR) 미검증: JALR의 rs1 의존성 + HDU 스톨 + EX 포워딩 경로를
  통합 검증하는 테스트 케이스 부재

**수정 방법**: 헤더 주석에 맞게 3개 시나리오를 별도 `initial` 블록 또는 태스크로 추가,
또는 헤더 주석을 "루프 마일스톤 단독 검증" 으로 축소 수정.

---

## Minor 이슈 (🟢)

### 🟢 m1 — 연습문제 3번 예상 답에 BHT 페널티 반영 필요

**위치**: `manuscripts/part4/chapter11.html` 연습문제 3번

"루프 100회를 PNT와 BHT(2-bit) 전략으로 각각 실행할 때, 전체 페널티 사이클을 계산하십시오.
단, BHT 초기 상태는 '약한 미분기(01)'"

이 문제의 정답은 M1 수정 후 다음과 같아야 함:
- PNT: 99회 taken × 2 = 198사이클
- BHT 2-bit: 2회 오예측 × 2 = 4사이클

교재 해설 작성 시 이 값을 사용해야 함. 현재 원고에는 정답이 명시되지 않아 독자가 11.5절의
잘못된 테이블을 참고할 경우 오답을 도출할 수 있음.

---

## 확인 사항 (이상 없음)

다음 항목들은 기술적으로 올바르게 구현되었음을 확인하였습니다.

**branch_unit.sv**
- BEQ(000), BNE(001), BLT(100), BGE(101), BLTU(110), BGEU(111) — funct3 코드 모두 RISC-V 스펙 일치
- BLT/BGE: `$signed()` 사용 (부호 있는 비교) 올바름
- BLTU/BGEU: 부호 없는 비교 올바름
- `assign branch_taken = branch && cond` — branch 신호 게이팅 올바름
- 합성 가능한 `always_comb` + `case` 구조

**flush 로직**
- `if_id_flush = branch_taken_ex | jal_id | jalr_taken_ex` — 올바름
- `id_ex_flush = load_use_stall | branch_taken_ex | jalr_taken_ex` — 올바름
- IF/ID 레지스터: `!rst_n || if_id_flush` 조건에서 NOP 삽입 — flush > en 우선순위 올바름
- ID/EX 레지스터: `!rst_n || id_ex_flush` 조건에서 NOP 삽입 — 올바름

**JAL 처리**
- ID 단계 감지 (`if_id_instr[6:0] == 7'b1101111`)
- J-type imm: `{{12{instr[31]}}, instr[19:12], instr[20], instr[30:21], 1'b0}` — RISC-V 스펙 일치
- `if_id_flush`만 활성화, `id_ex_flush` 미활성화 → 1사이클 버블 올바름
- JAL 자신은 파이프라인을 계속 진행, WB에서 `wb_sel=2'b10` → `wb_data=pc_plus4` 저장 올바름

**JALR 처리**
- EX 단계 처리, `jalr_taken_ex = id_ex_jalr` 조건으로 항상 taken
- `jalr_target = (alu_src_a + id_ex_imm) & ~32'h1` — 하위 1비트 클리어 RISC-V 스펙 일치
- `if_id_flush + id_ex_flush` 동시 활성화 → 2사이클 버블 올바름

**pc_next 4-way MUX**
- `priority if` 순서: branch_taken_ex > jalr_taken_ex > jal_id > pc_plus4
- `branch_taken_ex`와 `jalr_taken_ex`는 동일 명령어에서 동시 성립 불가 (opcode 상이)
- `branch_taken_ex`와 `jal_id`가 동시 활성화될 경우 branch 우선 → 올바름 (branch flush 시 IF/ID의 JAL도 플러시되므로 jal_id는 무효화됨)

**Load-JALR 해저드**
- HDU가 `if_id_rs1 = rs1_addr = if_id_instr[19:15]` 체크 → JALR rs1 의존성 감지 올바름
- 1사이클 스톨 후 MEM-EX 포워딩으로 정확한 rs1 값 공급

**BHT 2-bit 포화 카운터 (11.5절 코드)**
- 상태 전이: taken 시 +1(상한 11), not-taken 시 -1(하한 00) — 포화 카운터 올바름
- `pred_taken = counter[pred_idx][1]` — MSB가 1이면 taken 예측 올바름
- `for (int i = 0; i < 256; i++) counter[i] <= 2'b01` — `always_ff` 리셋 블록 내 사용, 합성 가능

**기타 코드 품질**
- SystemVerilog IEEE 1800-2017 `always_comb`, `always_ff`, `logic` 타입 사용
- 들여쓰기 3칸, snake_case 명명 규칙 준수
- B-type imm 비트 재배열: `{instr[31],instr[7],instr[30:25],instr[11:8],1'b0}` — 스펙 일치

---

## 승인 여부

- [x] **조건부 승인** — Critical/Major 수정 후 재검토 요청
- [ ] 승인

### 수정 우선순위

| 우선순위 | 이슈 | 수정 위치 | 변경 내용 |
|----------|------|-----------|-----------|
| 1 (즉시) | C1 — add 인코딩 오류 | tb.sv line 62 + HTML line 721 | `0x001101B3` → `0x00110133` |
| 2 (즉시) | C2 — BNE 인코딩 오류 | tb.sv line 70 + HTML line 724 | `0xFE3090E3` → `0xFE309CE3`, 주석 `-12` → `-8` |
| 3 | M1 — BHT 테이블 페널티 | HTML 11.5절 표 + 본문 | "1회 2사이클" → "2회 4사이클" |
| 4 | M2 — TB 커버리지 | tb.sv | 시나리오 1~3 구현 또는 헤더 수정 |
| 5 | m1 — 연습문제 3 해설 | HTML 연습문제 | BHT 정답 수정 (M1 수정과 연동) |
