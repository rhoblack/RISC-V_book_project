# Chapter 24 기술 리뷰

**리뷰어**: 기술 리뷰어 (Technical Reviewer)
**대상**: Chapter 24 — RV32I 확장: M & F 표준 확장
**일시**: 2026-03-15

---

## ISA 정확성 체크

- [x] **M 확장 인코딩**: opcode=0110011(OP), funct7=0000001 — 원고 L87~88 정확. funct3 테이블(L109~168) 8개 명령어 모두 RISC-V 스펙(Vol.I §7.1) 준수.
  - MUL=000, MULH=001, MULHSU=010, MULHU=011, DIV=100, DIVU=101, REM=110, REMU=111 ✓
- [x] **M 확장 피연산자 구분**: signed/unsigned 구분이 테이블에 명시됨 (L121~166). MUL 하위 32비트가 signed/unsigned 무관하다는 점도 L222에서 정확히 설명.
- [x] **나눗셈 특수 케이스**: 0으로 나누기(DIV→-1/0xFFFFFFFF, REM→rs1)와 signed overflow(-2^31 ÷ -1) 모두 L199~206에서 RISC-V 스펙 준수 설명.
- [x] **F 확장 IEEE 754**: 1+8+23=32비트 구조, bias=127, 정규화 1.f × 2^(E-127) — L457~496 정확.
- [x] **Zicntr**: mcycle/minstret CSR 표준화 설명 정확 (L569~606). 보안 위험(타이밍 사이드채널) 분리 이유도 적절.

## SystemVerilog 합성 가능성

### ch24_mul_divider.sv

- [x] **곱셈 — `*` 연산자 사용**: `assign mul_ss = $signed(operand_a) * $signed(operand_b)` (L40) — Vivado DSP48E1 자동 매핑 가능. 합성 가능.
- [x] **MULHSU 구현**: `$signed(operand_a) * $signed({1'b0, operand_b})` (L41) — signed × unsigned를 33비트 signed로 처리. 정확한 접근.
- [x] **MULHU 구현**: `{32'b0, operand_a} * {32'b0, operand_b}` (L42) — unsigned 확장 후 곱셈. 정확.
- [x] **나눗셈 FSM 5상태**: IDLE→INIT→COMPUTE(×32)→SIGN_ADJ→DONE — 합리적 설계.
- [x] **count 카운터**: 6비트로 0~31 범위 충분. `count == 6'd31`에서 COMPUTE 종료 (L98).
- [x] **flush 처리**: FSM 상태와 데이터패스 모두 flush 시 IDLE/리셋 (L86, L116~119).
- [x] **ready/busy 신호**: 곱셈은 1사이클 후 ready, 나눗셈은 DONE에서 ready. busy는 IDLE/DONE 아닌 상태 (L193~195).

### ch24_mul_tb.sv

- [x] **테스트 커버리지**: 곱셈 5케이스(양수, 음수, 0, 1, -1×-1) + MULH 2케이스 + MULHU 2케이스 = 9건 곱셈.
- [x] **나눗셈 커버리지**: DIV 3건 + DIVU 2건 + REM 2건 + REMU 1건 + 특수케이스 4건 = 12건 나눗셈.
- [x] **특수 케이스**: 0으로 나누기(DIV, REM, DIVU, REMU) 4건 포함.
- [x] **타임아웃 가드**: 200us 제한 — 적절.
- [x] **pass/fail 카운터**: 결과 요약 포함 — 좋은 관행.

### ch24_mul_extended.sv

- [x] **2단계 파이프라인**: Stage1(곱셈+래치) → Stage2(결과선택+래치). 합성 가능.
- [x] **3종 곱셈 모두 지원**: ss, su, uu 별도 래치 — MULHSU/MULHU 정확 처리.
- [x] **flush 처리**: 양 스테이지 모두 flush 시 리셋.

---

## Critical Issues

### C1. MULHSU 곱셈 결과가 잘못됨 — `mul_su` 계산 오류
- **파일**: `ch24_mul_divider.sv` L41, `chapter24.html` L376~377 (인라인 코드)
- **위치**: 곱셈 조합 논리
- **내용**:
  ```systemverilog
  assign mul_su = $signed(operand_a) * $signed({1'b0, operand_b});
  ```
  이 구현은 MULHSU(signed × unsigned)에 정확합니다. 그러나 **HTML 본문 L376~377의 인라인 코드**에서는:
  ```systemverilog
  assign mul_result_su = $signed({1'b0, operand_a}) * $signed({1'b0, operand_b}); // unsigned×unsigned
  ```
  라고 되어 있어, 주석이 "unsigned×unsigned"로 잘못 표기되어 있고, operand_a에도 `{1'b0,...}`를 붙여 signed 확장 대신 unsigned 확장을 수행합니다. **본문 인라인 코드와 전체 소스 코드가 불일치합니다.**
- **심각도**: 🔴 Critical — 독자가 본문의 잘못된 코드를 따라할 경우 MULHSU 결과가 틀립니다.
- **수정 권고**: 본문 L376~377의 인라인 코드를 전체 소스(`ch24_mul_divider.sv` L41)와 일치시키고, 주석을 "signed×unsigned"로 수정.

### C2. 나눗셈 0으로 나누기 시 DIVU 결과값 미구분
- **파일**: `ch24_mul_divider.sv` L126~127
- **내용**: 0으로 나누기 처리에서:
  ```systemverilog
  if (is_div)
     quotient <= 32'hFFFFFFFF;  // signed도 unsigned도 동일
  ```
  RISC-V 스펙에서 `DIV x/0 = -1 (0xFFFFFFFF)`, `DIVU x/0 = 0xFFFFFFFF` 모두 동일한 비트 패턴이므로 **결과적으로는 정확**합니다. 그러나 `is_div`은 DIV/DIVU 모두 참이고 REM/REMU는 거짓인데, REMU x/0의 결과가 `quotient <= operand_a`로 처리됩니다. REMU x/0 = rs1이 RISC-V 스펙이므로 이것도 정확.
  - **재확인**: 이 항목은 분석 결과 정확합니다. Critical에서 제외합니다.

### C3. 나눗셈 signed overflow 특수 케이스 미구현
- **파일**: `ch24_mul_divider.sv` 전체, `ch24_mul_tb.sv`
- **내용**: RISC-V 스펙에서 `-2^31 ÷ (-1)`의 결과는 `DIV = -2^31`, `REM = 0`으로 정의합니다 (원고 L205~206에서 정확히 설명). 그러나 **코드에서 이 특수 케이스에 대한 검출/처리 로직이 없습니다.** Restoring Division FSM이 이 입력을 받으면:
  - dividend_abs = 2^31 (오버플로: `~(0x80000000) + 1 = 0x80000000` — 2의 보수 특성상 동일)
  - divisor_abs = 1
  - 결과: quotient = 2^31, SIGN_ADJ에서 부호 반전 → `~0x80000000 + 1 = 0x80000000 = -2^31`
  - **분석 결과**: 2의 보수 특성상 FSM이 올바른 결과를 생성할 가능성이 높습니다. 그러나 이를 **테스트벤치에서 검증하지 않고 있습니다.**
- **심각도**: 🔴 Critical — 특수 케이스가 테스트벤치에 누락됨. 교재 수준에서 스펙에 명시된 특수 케이스는 반드시 테스트해야 합니다.
- **수정 권고**: `ch24_mul_tb.sv`에 다음 테스트 추가:
  ```systemverilog
  // signed overflow: -2^31 / -1 = -2^31
  test_div("DIV overflow", 3'b100, 32'h8000_0000, 32'hFFFF_FFFF, 32'h8000_0000);
  // signed overflow: -2^31 % -1 = 0
  test_div("REM overflow", 3'b110, 32'h8000_0000, 32'hFFFF_FFFF, 32'd0);
  ```

### C4. HTML 본문 인라인 코드의 `<` / `>` / `&&` 이스케이프 불완전
- **파일**: `chapter24.html` L359~380 (본문 내 인라인 코드 블록)
- **내용**: 본문의 `<pre><code>` 블록 내에서 `<`, `>`, `&&` 등이 이스케이프 없이 그대로 사용됩니다. 전체 소스 코드 섹션(L801~)에서는 `&lt;`, `&gt;`, `&amp;`로 올바르게 이스케이프되어 있으나, **본문 중간의 인라인 코드(L359~380)는 이스케이프가 누락**되어 있습니다.
  - L376: `$signed({1'b0, operand_a})` — `<`, `>` 미이스케이프 (**그런데 이 부분은 실제로 `<` `>`가 없으므로 문제없음**)
  - L667~686의 파이프라인 통합 코드: `1'b0`은 괜찮으나, 만약 부등호 연산자가 있다면 문제.
  - **재검토**: L667~686 코드 블록을 확인하면, `1'b0`, `1'b1` 외에 HTML 특수문자가 없으므로 이 블록은 괜찮습니다.
  - **그러나 L185~196의 어셈블리 코드 블록**도 확인 필요: `#` 주석만 있고 특수문자 없음 — OK.
  - **결론**: 이 항목은 재확인 결과 대부분 안전합니다. 전체 소스 코드 섹션은 이스케이프 완료. Critical에서 제외합니다.

---

## 최종 Critical Issues (확정)

### C1. 본문 인라인 코드와 전체 소스 코드 불일치 (MULHSU)
- **파일**: `chapter24.html` L376~377
- **심각도**: 🔴 Critical
- **수정**: 본문 인라인 코드를 `ch24_mul_divider.sv`의 실제 구현과 일치시킬 것.
  - `mul_result_su` → `mul_su`
  - `$signed({1'b0, operand_a}) * $signed({1'b0, operand_b})` → `$signed(operand_a) * $signed({1'b0, operand_b})`
  - 주석 "unsigned×unsigned" → "signed×unsigned (MULHSU)"

### C2. 테스트벤치에 signed overflow 특수 케이스 누락
- **파일**: `ch24_mul_tb.sv`
- **심각도**: 🔴 Critical
- **수정**: `-2^31 ÷ (-1)` 및 `-2^31 % (-1)` 테스트 케이스 추가.

---

## Major Issues

### M1. `mul_div_unit`에서 곱셈 결과가 조합 논리(`assign`)인데, `result` 출력도 조합 논리로 연결
- **파일**: `ch24_mul_divider.sv` L192
- **내용**: `assign result = is_mul_op ? mul_result : div_result;` — 곱셈 시 `result`는 순수 조합 논리 경로. `mul_ready_r`은 1사이클 지연되지만, `result`는 `start` 신호와 같은 사이클에 즉시 유효합니다. 즉, `ready`가 1이 되는 사이클에서 `result`를 읽으면 **이전 사이클의 입력에 대한 결과**가 아니라 **현재 사이클의 입력에 대한 조합 결과**가 나올 수 있습니다.
- **심각도**: 🟡 Major — 파이프라인 통합 시 타이밍 불일치 유발 가능.
- **수정 권고**: 곱셈 결과도 1사이클 래치하여 `mul_ready_r`과 동기화하거나, 원고에서 "곱셈은 조합 논리이므로 start와 같은 사이클에 result가 유효하고, ready는 다음 사이클"이라는 타이밍을 명확히 설명.

### M2. `ch24_mul_extended.sv` 본문 코드(HTML)와 실제 파일 불일치
- **파일**: `chapter24.html` L1128~1187 vs `ch24_mul_extended.sv`
- **내용**: HTML 전체 소스 코드 섹션의 `ch24_mul_extended.sv`는 `stage1_product` 하나만 사용하고 `$signed(operand_a) * $signed(operand_b)`만 수행 (MULH만 지원). 실제 `.sv` 파일은 `stage1_product_ss`, `stage1_product_su`, `stage1_product_uu` 3종을 모두 래치하여 MULHSU/MULHU도 지원합니다.
- **심각도**: 🟡 Major — 독자가 HTML의 단순화된 버전을 구현하면 MULHSU/MULHU가 동작하지 않음.
- **수정 권고**: HTML 전체 소스 섹션의 코드를 실제 `ch24_mul_extended.sv`와 일치시킬 것.

### M3. Basys 3 DSP 사용량 설명 부재
- **파일**: `chapter24.html`
- **내용**: DSP48E1은 25×18비트 곱셈기입니다 (연습문제 L762에서 언급). 32×32 곱셈을 DSP로 구현하려면 **최소 4개** DSP가 필요합니다 (32=18+14 분할, 각 부분곱에 DSP 1개). 코드에서 `*` 연산자를 3번 사용(ss, su, uu)하므로 **최대 12개 DSP** 소요 가능. Basys 3에는 90개 DSP가 있으므로 문제없지만, 이 추정이 본문에 없습니다.
- **심각도**: 🟡 Major — FPGA 리소스 인식이 교재의 핵심 목표.
- **수정 권고**: 24.1.2절 또는 24.4절에 DSP 사용량 추정 표 추가. "32×32 곱셈 1개당 DSP 약 4개 × 3종 = 최대 12개 DSP. 실제로 Vivado는 결과 공유 최적화로 4~8개로 줄일 수 있음."

### M4. 나눗셈 총 사이클 수 불일치
- **파일**: `chapter24.html` L19 "1~34사이클", 그림24.2 캡션 L349 "최대 34사이클(초기화 + 32반복 + 부호 보정)"
- **내용**: FSM 사이클 카운트:
  - IDLE→INIT: 1사이클
  - INIT→COMPUTE: 1사이클
  - COMPUTE: 32사이클 (count 0~31)
  - SIGN_ADJ→DONE: 1사이클 (signed만)
  - DONE→IDLE: 1사이클
  - **총**: IDLE(1) + INIT(1) + COMPUTE(32) + SIGN_ADJ(1) + DONE(1) = **36사이클** (signed), **35사이클** (unsigned)
  - 0으로 나누기: IDLE→DONE→IDLE = **2사이클**
  - 원고에서 "최대 34사이클"이라 했지만, 실제 FSM은 **36사이클** (signed 기준).
- **심각도**: 🟡 Major — 사이클 수가 정확해야 파이프라인 스톨 분석이 올바름.
- **수정 권고**: "최대 36사이클(signed)" 또는 FSM을 최적화하여 DONE 상태를 제거하고 SIGN_ADJ에서 바로 ready를 출력.

### M5. `pipeline_stall` 코드에서 flush 처리 의미 불명확
- **파일**: `chapter24.html` L681~685
- **내용**:
  ```systemverilog
  assign pipeline_stall = flush       ? 1'b0 :  // flush 시 스톨 무시
                          icache_stall ? 1'b1 : ...
  ```
  `flush` 시 `pipeline_stall = 0`이면 파이프라인이 정상 진행되는데, flush와 동시에 진행 중인 곱셈/나눗셈의 중간 결과가 파이프라인에 올라갈 수 있습니다. `flush` 시에는 `pipeline_stall`을 0으로 하되, **동시에 mul_div_unit에도 flush를 보내야** 합니다. 코드 스켈레톤에서 이 연결이 명시되지 않았습니다.
- **심각도**: 🟡 Major — 독자가 flush/stall 상호작용을 오해할 수 있음.
- **수정 권고**: 코드 스켈레톤에 `mul_div_unit`의 `flush` 포트 연결을 명시하거나, 주석으로 "flush 시 mul_div_unit.flush도 동시 활성화 필요" 추가.

### M6. `ch24_mul_divider.sv`에서 REMU 연산 시 `is_signed=0`인데 SIGN_ADJ 건너뛰기 확인
- **파일**: `ch24_mul_divider.sv` L78, L98~99
- **내용**: `is_signed = (funct3 == DIV_OP) || (funct3 == REM_OP)` — REMU(111)에서 `is_signed=0`이므로 COMPUTE 완료 후 SIGN_ADJ를 건너뛰고 바로 DONE으로 갑니다. 이때 `is_div = (funct3 == DIV_OP) || (funct3 == DIVU)` — REMU에서 `is_div=0`이므로 `div_result = remainder[31:0]`. **정확합니다.**
- 그러나 REMU의 입력이 unsigned이므로 INIT에서 절대값 변환이 불필요합니다. `is_signed=0`이면 절대값 변환 조건 `(is_signed && operand_a[31])`이 false이므로 원래 값 그대로 사용. **정확합니다.**
- **결론**: 이 항목은 정확. Major에서 제외.

---

## 최종 Major Issues (확정)

| ID | 이슈 | 파일 | 수정 권고 |
|----|------|------|----------|
| M1 | 곱셈 result 조합논리와 ready 타이밍 불일치 | ch24_mul_divider.sv:192 | 래치 추가 또는 타이밍 명확히 문서화 |
| M2 | HTML 내 ch24_mul_extended 코드가 실제 파일과 불일치 | chapter24.html:1128~1187 | HTML을 실제 파일과 동기화 |
| M3 | DSP 사용량 추정 본문 부재 | chapter24.html | 24.1.2절에 DSP 추정 표 추가 |
| M4 | 나눗셈 사이클 수 34 → 실제 36 | chapter24.html:L19,L349 | 36사이클로 수정 또는 FSM 최적화 |
| M5 | flush 시 mul_div_unit.flush 연결 미명시 | chapter24.html:L667~686 | 코드에 flush 연결 추가 |

---

## Minor Issues

| ID | 이슈 | 파일 | 위치 |
|----|------|------|------|
| Mi1 | "스스로" 오타 → "스스로" (원고 전체에서 일관 사용 중이므로 의도적일 수 있음) | chapter24.html | L383, L393, L689, L700 |
| Mi2 | 연습문제 4번의 DSP 분할 힌트 "32=18+14"인데, 실제 DSP48E1은 25×18. 정확한 분할은 32=18+14이므로 힌트는 맞지만, "최소 4개"라는 답이 명확히 유도되지 않음 | chapter24.html | L761~764 |
| Mi3 | 그림 24.2(division_longdiv.svg) 예제가 "13÷3=4 나머지 1"인데, 본문 L335~337에서는 "100÷7=14 나머지 2" 예제 사용. 본문과 SVG 예제 불일치 | figures/ch24_sec02_division_longdiv.svg | SVG 타이틀 |
| Mi4 | IEEE 754 변환 예제: 본문은 "-6.5 = 0xC0D00000" (L504), SVG도 "-6.5 = 0xC0D00000". 검증: S=1, E=129=10000001, F=10100...=0x500000. 비트: 1_10000001_10100000... = 0xC0D00000. **정확** ✓ | — | — |
| Mi5 | `chapter24.html` L1194~1195에 `tcl.min.js`와 `bash.min.js` 로드하지만 본 챕터에서 TCL/bash 코드 블록 없음. 불필요한 로딩. | chapter24.html | L1194~1195 |
| Mi6 | 그림 참조 불일치: HTML에서 참조하는 SVG 파일명 4개(multiply_stages, division_longdiv, ieee754_bits, twoissue_multiplier)와 실제 figures/ 디렉토리의 파일 일치 확인 ✓. 추가로 5개 SVG(m_extension_instructions, dsp48e1_multiplier, f_extension_overview, zicntr_counters, mul_pipeline_integration)가 HTML에서 참조되지 않음. | figures/ | — |

---

## Basys 3 리소스 추정

| 항목 | 추정치 | 비고 |
|------|--------|------|
| 곱셈기 DSP | 4~12개 (DSP48E1) | 3종 곱셈(ss/su/uu) × 32비트 분할. Vivado 최적화 시 4~8개 |
| 나눗셈기 LUT | ~800~1200 LUT | 33비트 뺄셈기 + FSM + 레지스터 |
| 전체 M 확장 | ~1200~1500 LUT + 4~12 DSP | |
| 누적 SoC | ~8000 LUT (40%) + 12 DSP (13%) | Basys 3 = 20,800 LUT / 90 DSP — **충분** |

---

## 도식 정확성

| SVG | 판정 | 비고 |
|-----|------|------|
| ch24_sec01_multiply_stages.svg | ✅ 정확 | 4단계 진화(순차→Booth→Wallace→DSP), 사이클 수 명시 |
| ch24_sec02_division_longdiv.svg | ⚠️ Mi3 | 본문과 예제 불일치(SVG: 13÷3, 본문: 100÷7). FSM 다이어그램은 정확 |
| ch24_sec03_ieee754_bits.svg | ✅ 정확 | 비트 구조, 변환 예제(-6.5) 모두 정확 |
| ch24_sec04_twoissue_multiplier.svg | ✅ 정확 | 스톨 우선순위, EX 스테이지 MUX 확장, 포워딩 표시 적절 |

---

## 코드 품질

- [x] 문법: SystemVerilog IEEE 1800-2017 준수
- [x] 들여쓰기: 3칸 일관
- [x] 명명: snake_case (mul_div_unit, mul_result, quotient, remainder 등)
- [x] 한국어 주석: 핵심 로직 주석 포함
- [x] 합성 가능성: 곱셈(조합), 나눗셈(FSM) 모두 합성 가능 구조
- [x] FSM 무한루프: DONE→IDLE 전이 보장, default 처리 포함

---

## 교과서 품질

- [x] HTML 구조: chapter_template 준수 (header, learning-objectives, sections, exercises, full-source)
- [x] 섹션 ID: sec-24-1, sec-24-1-1 등 계층 명확
- [x] 코드 블록: `<pre><code class="language-systemverilog">` 사용
- [x] SVG 임베드: `<img src="../../figures/ch24_*.svg">` 경로 정확
- [x] CSS 경로: `../../templates/book_style.css` 정확
- [x] Highlight.js: atom-one-dark, language-systemverilog→verilog 변환 스크립트 포함

---

## 요약

| 분류 | 건수 |
|------|------|
| 🔴 Critical | 2건 (C1: 본문/소스 불일치, C2: TB 특수케이스 누락) |
| 🟡 Major | 5건 (M1~M5) |
| 🟢 Minor | 6건 (Mi1~Mi6) |

**승인 조건**: Critical 2건 수정 필수. Major 5건 강력 권장.
