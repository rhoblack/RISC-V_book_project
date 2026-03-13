# Ch10 기술 리뷰

**리뷰어**: 기술 리뷰어 (Technical Reviewer)
**리뷰 대상**: `manuscripts/part4/chapter10.html`
**리뷰 일시**: 2026-03-11

---

## 🔴 Critical 이슈 (1건)

### C1: SW 어노테이션 — MEM-EX 포워딩 표기 오류 (10.6절 어셈블리 주석)

**위치**: 10.6절 어셈블리 코드 (줄: `SW   x10, 0(x0)   ; mem[0] = 55  <-- MEM-EX 포워딩(x10)`)

**오류 설명**:
`SW x10, 0(x0)`은 `ADD x10, x10, x11` 바로 다음 명령어입니다. SW가 EX 스테이지에 있을 때, ADD는 EX/MEM 레지스터에 있습니다. 따라서 SW의 rs2=x10은 **EX-EX 포워딩(forward_b = 2'b01)**으로 처리됩니다.

- SW는 ADD 직후 (1명령어 간격) → EX/MEM 포워딩 = EX-EX
- MEM-EX(2'b10)는 2명령어 간격일 때 적용됩니다 (예: `ADD x10 → NOP → SW x10`)

**올바른 표기**:
```
SW   x10, 0(x0)        ; mem[0] = 55      <-- EX-EX 포워딩(x10)
```

**영향**: 10.2절에서 정의한 EX-EX/MEM-EX 인코딩 규칙과 직접 모순되며, 학생이 시뮬레이션에서 `forward_b=2'b01`을 확인할 때 교재 설명과 불일치하여 혼란을 초래합니다.

---

## 🟡 Major 이슈 (2건)

### M1: 10.6절 서술 — "EX-EX 포워딩만 발생" 설명이 부정확

**위치**: 10.6절 본문 (`매 ADD x10,x10,x11마다 EX-EX 포워딩이 발생하고`)

**오류 설명**:
`ADD x10, x10, x11`이 EX 스테이지에 있을 때의 실제 포워딩 패턴:

| 소스 레지스터 | 직전 명령어 (EX/MEM) | 2개 전 명령어 (MEM/WB) | 포워딩 종류 |
|---|---|---|---|
| rs1 = x10 | ADDI x11,x11,1 (rd=x11, 불일치) | ADD x10,x10,x11 (rd=x10, 일치) | **MEM-EX (2'b10)** |
| rs2 = x11 | ADDI x11,x11,1 (rd=x11, 일치) | — | **EX-EX (2'b01)** |

즉, 각 ADD에서 rs1=x10은 **MEM-EX 포워딩**, rs2=x11은 **EX-EX 포워딩**이 동시에 발생합니다. "EX-EX 포워딩만 발생"이라는 서술은 부정확합니다.

**수정안**: `매 ADD x10,x10,x11마다 rs2(x11)에는 EX-EX 포워딩이, rs1(x10)에는 MEM-EX 포워딩이 동시에 발생하고`

**영향**: 학생이 시뮬레이션에서 `forward_a=2'b10`을 보고 교재 설명과 불일치하여 설계 오류로 오해할 수 있습니다.

---

### M2: 10.6절 어셈블리 주석 — 포워딩 종류 오표기 (3곳)

**위치**: 10.6절 어셈블리 코드 주석

**오류 목록**:

| 줄 | HTML 표기 | 실제 포워딩 |
|---|---|---|
| `ADD x10,x10,x11 ; sum=1 <-- EX-EX 포워딩(x11)` | EX-EX만 표기 | forward_a=MEM-EX(x10), forward_b=EX-EX(x11) 동시 발생 |
| `ADDI x11,x11,1  ; x11=2 <-- EX-EX 포워딩(x11)` | EX-EX 오표기 | rs1=x11: 2명령어 전(ADD x10)이 x10을 썼고, x11을 마지막으로 쓴 것은 2명령어 전 `ADDI x11,x0,1` → **MEM-EX** |
| `ADD x10,x10,x11 ; sum=3 <-- EX-EX 포워딩(x10, x11)` | x10을 EX-EX로 오표기 | x10=**MEM-EX**, x11=EX-EX |

**수정안 예시**:
```asm
ADD  x10, x10, x11     ; x10 = 0+1 = 1    <-- MEM-EX(x10), EX-EX(x11)
ADDI x11, x11, 1       ; x11 = 2          <-- MEM-EX(x11)
ADD  x10, x10, x11     ; x10 = 1+2 = 3    <-- MEM-EX(x10), EX-EX(x11)
```

---

## 🟢 Minor 이슈 (1건)

### m1: hazard_detection_unit — LOAD 명령어의 instr[24:20] 사용 미설명

**위치**: 10.3절 `hazard_detection_unit.sv` 및 최상위 모듈 연결부

**내용**: `hazard_detection_unit`은 IF/ID 명령어의 rs2 주소로 `instr[24:20]`을 사용합니다. LOAD 명령어(LW 등)에서 `[24:20]`은 실제 rs2가 아니라 즉치수(immediate)의 일부입니다. 이로 인해 `imm[9:5] != 0`인 LW 뒤에 오는 명령어에서 드물게 불필요한 스톨이 발생할 수 있습니다(보수적 동작).

**판단**: Patterson & Hennessy 교과서를 포함한 대부분의 교재가 동일한 단순화를 사용합니다. 기능적으로 정확성을 보장하며(스톨 누락 없음), 교재 범위에서 허용 가능합니다. 다만 관련 aside나 각주로 "LOAD 명령어의 [24:20] 비트가 즉치수이므로 드물게 불필요한 스톨이 발생할 수 있다"고 언급하면 완성도가 높아집니다.

---

## 검증 완료 항목

| 항목 | 결과 |
|---|---|
| `forwarding_unit.sv` EX-EX 조건 (`ex_mem_reg_write && rd!=x0 && rd==rs1`) | ✅ 정확 |
| `forwarding_unit.sv` MEM-EX 조건 (EX-EX 미성립 시만) | ✅ 정확 |
| `forwarding_unit.sv` 우선순위 (EX-EX > MEM-EX, if-else if) | ✅ 정확 |
| `forwarding_unit.sv` x0 방지 조건 | ✅ 정확 |
| `forwarding_unit.sv` `always_comb` 사용 | ✅ 정확 |
| `hazard_detection_unit.sv` 감지 조건 (`id_ex_mem_read && rd!=x0 && (rd==rs1 || rd==rs2)`) | ✅ 정확 |
| 스톨 제어: `pc_en=~stall`, `if_id_en=~stall`, `id_ex_flush=stall` | ✅ 정확 |
| flush > en 우선순위 (`if (rst \|\| flush) ... else if (en)`) | ✅ 정확 |
| NOP 버블 시 `ctrl_out <= '0` → `mem_read=0` 보장 | ✅ 정확 |
| `wb_data` MUX: `mem_to_reg` 2'b00/01/10 인코딩 | ✅ 정확 |
| Store 포워딩: `EX/MEM.rs2_data_in = rs2_fwd_ex` | ✅ 정확 |
| 포워딩 MUX: `case(forward_a/b)` 2'b01=EX-EX, 2'b10=MEM-EX, default=레지스터파일 | ✅ 정확 |
| 1~10 합산 프로그램: 기계어 hex 24개 전부 검증 | ✅ 전부 정확 |
| 최종 결과: x10=55, x12=55, x13=55 | ✅ 정확 |
| 테스트벤치 T1~T7 시나리오 설명 | ✅ 정확 (T7 포워딩 방향 포함) |
| 3칸 들여쓰기, snake_case 명명 | ✅ 준수 |
| `always_comb` 사용 (포워딩/감지 유닛) | ✅ 준수 |
| SystemVerilog IEEE 1800-2017 합성 가능 여부 | ✅ 합성 가능 |

---

## 최종 기술 판정: **조건부 승인**

**근거**:
- Critical 이슈 1건: SW 포워딩 종류 오표기 (EX-EX ↔ MEM-EX 혼동) — 수정 필수
- Major 이슈 2건: 10.6절 서술 및 어셈블리 주석의 포워딩 종류 오표기 — 수정 필수
- 핵심 RTL 로직(forwarding_unit, hazard_detection_unit, 최상위 모듈)은 기술적으로 정확하고 합성 가능
- 기계어 코드, 테스트벤치, 파이프라인 제어 신호 모두 정확

**수정 후 재검토 불필요** — Critical/Major 이슈는 모두 어셈블리 주석 및 서술 레벨 수정이며, RTL 코드 변경은 불필요합니다.
