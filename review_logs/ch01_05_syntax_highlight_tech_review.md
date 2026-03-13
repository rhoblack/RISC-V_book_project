# 기술 리뷰 보고서: Ch01~Ch05 Syntax Highlighting & 전체 소스 코드 섹션

- **검토자**: 기술 리뷰어 (Technical Reviewer) 에이전트
- **검토 일시**: 2026-03-11
- **검토 대상**: manuscripts/part0/chapter01.html, manuscripts/part2/chapter04.html, manuscripts/part2/chapter05.html
- **변경 범위**: (1) Highlight.js CDN 기반 syntax highlighting 추가, (2) "전체 소스 코드" 섹션 추가

---

## 1. Highlight.js 설정 검토

### 1.1 CDN URL 및 버전

| 항목 | 값 | 상태 |
|------|-----|------|
| CSS (테마) | `https://cdnjs.cloudflare.com/ajax/libs/highlight.js/11.9.0/styles/atom-one-dark.min.css` | ✅ 정상 |
| 핵심 스크립트 | `https://cdnjs.cloudflare.com/ajax/libs/highlight.js/11.9.0/highlight.min.js` | ✅ 정상 |
| 추가 언어 스크립트 | `https://cdnjs.cloudflare.com/ajax/libs/highlight.js/11.9.0/languages/verilog.min.js` | ✅ 정상 |

- 세 챕터(Ch01, Ch04, Ch05) 모두 동일한 버전(11.9.0)을 사용하여 일관성 유지: **정상**
- CDN URL 형식이 cdnjs.cloudflare.com 표준 경로를 따름: **정상**

### 1.2 초기화 스크립트

```javascript
document.querySelectorAll('pre code').forEach(el => {
  if (el.className.includes('language-systemverilog')) {
    el.className = el.className.replace('language-systemverilog', 'language-verilog');
  }
});
hljs.highlightAll();
```

- `language-systemverilog` → `language-verilog` 변환 로직: **정상** (Highlight.js는 `verilog` 문법을 SystemVerilog에 적용하는 표준 방식)
- `hljs.highlightAll()` 호출 위치: `</body>` 직전 → DOM 완성 후 실행되어 **정상**
- 스크립트가 `</body>` 태그 바로 앞에 위치하여 DOMContentLoaded 없이도 안전: **정상**

### 1.3 CSS 오버라이드 스타일

```css
.hljs { background: transparent !important; padding: 0 !important; }
```

- book_style.css의 `pre` 스타일을 유지하기 위한 투명 배경 처리: **정상**
- `!important` 사용은 Highlight.js의 인라인 스타일 덮어쓰기를 위해 불가피함

---

## 2. 언어 클래스 적합성 검토

### 2.1 언어 클래스 사용 현황

| 챕터 | 클래스명 | 적용 블록 수 | 판정 |
|------|---------|------------|------|
| Ch01 | `language-systemverilog` | 12개 | ✅ 변환 스크립트로 처리됨 |
| Ch01 | `language-verilog` | 2개 (전체 소스 섹션) | ✅ 직접 지정 |
| Ch01 | `language-tcl` | 2개 (XDC 파일, 전체 소스 XDC) | ⚠️ **주의** |
| Ch01 | `language-bash` | 1개 (VCS 명령어) | ⚠️ **주의** |
| Ch04 | `language-systemverilog` | 6개 | ✅ 변환 스크립트로 처리됨 |
| Ch04 | `language-verilog` | 5개 (전체 소스 섹션) | ✅ 직접 지정 |
| Ch04 | `language-systemverilog` | 1개 (VCS 명령어 주석) | 🔴 **오류** |
| Ch05 | `language-systemverilog` | 6개 | ✅ 변환 스크립트로 처리됨 |
| Ch05 | `language-verilog` | 3개 (전체 소스 섹션) | ✅ 직접 지정 |
| Ch05 | `language-bash` | 1개 (VCS 명령어) | ⚠️ **주의** |

### 2.2 언어 스크립트 로딩 문제

**현재 명시적으로 로드된 언어 스크립트**: `verilog.min.js` 만 로드됨

`highlight.min.js` (코어 번들)에는 언어가 포함되어 있지 않다. `language-tcl`과 `language-bash` 클래스를 사용하는 블록이 존재하지만, 해당 언어 스크립트는 로드되지 않는다. Highlight.js는 알 수 없는 언어에 대해 자동 감지(auto-detection)를 시도하거나 하이라이팅을 건너뛰는데, 이 경우 렌더링 결과가 불확실하다.

---

## 3. HTML 특수문자 이스케이프 정확성 검토

### 3.1 검토 방법

모든 `<pre><code>` 블록 내부에서 이스케이프되지 않은 `<`, `>`, `&` 문자를 파이썬 정규식으로 탐지하였다.

### 3.2 전체 소스 코드 섹션 (신규 추가) — 결과

| 챕터 | 섹션 | 판정 |
|------|------|------|
| Ch01 | 전체 소스 (ch01_led_blinker.sv, ch01_led_blinker_tb.sv, ch01_basys3.xdc) | ✅ 모두 올바르게 이스케이프됨 |
| Ch04 | 전체 소스 (ch04_alu.sv, ch04_register_file.sv, ch04_imm_gen.sv, ch04_alu_tb.sv, ch04_register_file_tb.sv) | ✅ 모두 올바르게 이스케이프됨 |
| Ch05 | 전체 소스 (ch05_instruction_memory.sv, ch05_data_memory.sv, ch05_memory_tb.sv) | ✅ 모두 올바르게 이스케이프됨 |

신규 추가된 "전체 소스 코드" 섹션의 HTML 이스케이프 처리는 전반적으로 정상이다.

### 3.3 기존 본문 코드 블록 — 이스케이프 누락 발견

기존 본문 섹션의 코드 블록에서 다수의 미이스케이프 특수문자가 발견되었다. 이는 이번 PR에서 수정된 영역(전체 소스 섹션)은 아니지만, Highlight.js 적용 시 HTML 렌더링 오류를 유발하므로 기록한다.

#### Ch01 (chapter01.html) — 기존 본문 블록

| 라인 | 블록 내용 | 미이스케이프 문자 |
|------|-----------|----------------|
| 358 | `result = a & b;` | `&` → `&amp;` 필요 |
| 388, 390 | `q <= 32'h0;`, `q <= d;` | `<` → `&lt;` 필요 |
| 442 | `temp = a & b;` | `&` × 2 → `&amp;` 필요 |
| 448~450 | `q1 <= d;`, `q2 <= q1;`, `q3 <= q2;` | `<` × 3 → `&lt;` 필요 |
| 478, 480 | `curr_state <= IDLE;`, `curr_state <= next_state;` | `<` × 2 → `&lt;` 필요 |
| 578~595 | 카운터 로직 `<=` 할당 여러 곳 | `<` × 5 → `&lt;` 필요 |
| 792 | `sum === exp_sum && cout === exp_cout` | `&` × 2 → `&amp;` 필요 |
| 886 | `-ssf simple_adder_tb.fsdb &` | `&` → `&amp;` 필요 |
| 971~984 | 파라미터화 LED 점멸기 `<=` 할당 | `<` × 5 → `&lt;` 필요 |

#### Ch04 (chapter04.html) — 기존 본문 블록

| 라인 | 블록 내용 | 미이스케이프 문자 |
|------|-----------|----------------|
| 234 | `result = a & b;` | `&` → `&amp;` 필요 |
| 237 | `result = a << b[4:0];` | `<` × 2 → `&lt;` 필요 |
| 238 | `result = a >> b[4:0];` | `>` × 2 → `&gt;` 필요 |
| 239 | `result = $signed(a) >>> b[4:0];` | `>` × 3 → `&gt;` 필요 |
| 240 | `$signed(a) < $signed(b)` | `<` → `&lt;` 필요 |
| 241 | `a < b` | `<` → `&lt;` 필요 |
| 463 | `if (we3 && (wa3 != 5'b0))` | `&` × 2 → `&amp;` 필요 |
| 464 | `rf[wa3] <= wd3;` | `<` → `&lt;` 필요 |
| 783 | `// AND: 0xFF00 & 0x0FF0 = 0x0F00` | `&` → `&amp;` 필요 |
| 796 | `// SLL: 1 << 3 = 8` | `<` × 2 → `&lt;` 필요 |
| 800 | `// SRL: 0x80000000 >> 1` | `>` × 2 → `&gt;` 필요 |
| 804 | `// SRA: 0x80000000 >>> 1` | `>` × 3 → `&gt;` 필요 |
| 809 | `// SLT: -1 < 0` | `<` → `&lt;` 필요 |
| 813 | `// SLTU: 0xFFFFFFFF > 0` | `>` → `&gt;` 필요 |

#### Ch05 (chapter05.html) — 기존 본문 블록

| 라인 | 블록 내용 | 미이스케이프 문자 |
|------|-----------|----------------|
| 502~508 | `mem[addr+N] <= wdata[...];` (4곳) | `<` × 4 → `&lt;` 필요 |
| 760 | `.we (we & dmem_sel),` | `&` → `&amp;` 필요 |

---

## 4. SystemVerilog 코드 기술 정확성 검토

### 4.1 Ch01 — led_blinker.sv / led_blinker_tb.sv

| 항목 | 내용 | 판정 |
|------|------|------|
| 클럭 분주 로직 | `counter == MAX_COUNT[25:0]` 비교 후 리셋 | ✅ 정상 |
| 비동기 리셋 | `always_ff @(posedge clk or negedge rst_n)` | ✅ IEEE 1800-2017 표준 |
| LED 순환 시프트 | `{led_pattern[2:0], led_pattern[3]}` | ✅ 좌측 순환 시프트 정확 |
| 카운터 비트 폭 | 26비트 (최대 67,108,863 > 49,999,999) | ✅ 적정 |
| 테스트벤치 리셋 검증 | `assert (led == 4'b0001)` | ✅ 비동기 리셋 초기값 일치 |
| Basys 3 핀 배정 (XDC) | clk=W5, rst_n=U18, led[0..3]=U16/E19/U19/V19 | ✅ Basys 3 공식 XDC와 일치 |

**발견된 기술 이슈**: 없음

### 4.2 Ch04 — alu.sv

| 항목 | 내용 | 판정 |
|------|------|------|
| 시프트 어마운트 | `shamt = operand_b[4:0]` (5비트) | ✅ RV32I 스펙 준수 |
| 산술 우측 시프트 | `$signed(operand_a) >>> shamt` | ✅ 필수 캐스팅 적용 |
| SLT | `$signed(operand_a) < $signed(operand_b)` | ✅ 필수 캐스팅 적용 |
| SLTU | `operand_a < operand_b` (unsigned 비교) | ✅ 정상 |
| Zero 플래그 | `alu_zero = (alu_result == 32'b0)` | ✅ BEQ/BNE에서 활용 |
| Default 처리 | `default: alu_result = 32'b0` | ✅ 래치 방지 |
| ALU 제어 코드 10개 | ADD/SUB/AND/OR/XOR/SLL/SRL/SRA/SLT/SLTU | ✅ RV32I 전체 커버 |

**발견된 기술 이슈**: 없음

### 4.3 Ch04 — register_file.sv

| 항목 | 내용 | 판정 |
|------|------|------|
| 배열 선언 | `logic [31:0] registers [0:31]` | ✅ 32개 레지스터 |
| 동기 쓰기 | `always_ff @(posedge clk or negedge rst_n)` | ✅ 정상 |
| x0 쓰기 방지 | `reg_wr_en && (rd_addr != 5'b0)` | ✅ 하드와이어드 0 보장 |
| 비동기 읽기 | `assign rs1_data = ...` | ✅ 조합 논리로 LUTRAM 추론 유도 |
| 리셋 시 전체 초기화 | `for (int i=0; i<32; i++) registers[i] <= 32'b0` | ✅ Vivado 합성 가능 |

**발견된 기술 이슈**: 없음

### 4.4 Ch04 — imm_gen.sv

RISC-V RV32I 명령어 형식별 즉치수 추출 로직을 검증하였다.

| 형식 | 코드 | 비트 합계 | RV32I 스펙 일치 | 판정 |
|------|------|----------|----------------|------|
| I-type | `{{20{inst[31]}}, inst[31:20]}` | 20+12=32 | ✅ | ✅ |
| S-type | `{{20{inst[31]}}, inst[31:25], inst[11:7]}` | 20+7+5=32 | ✅ | ✅ |
| B-type | `{{19{inst[31]}}, inst[31], inst[7], inst[30:25], inst[11:8], 1'b0}` | 19+1+1+6+4+1=32 | ✅ | ✅ |
| U-type | `{inst[31:12], 12'b0}` | 20+12=32 | ✅ | ✅ |
| J-type | `{{11{inst[31]}}, inst[31], inst[19:12], inst[20], inst[30:21], 1'b0}` | 11+1+8+1+10+1=32 | ✅ | ✅ |

B-type의 imm[11]=inst[7], imm[10:5]=inst[30:25], imm[4:1]=inst[11:8] 매핑이 스펙과 정확히 일치한다.
J-type의 imm[20]=inst[31], imm[19:12]=inst[19:12], imm[11]=inst[20], imm[10:1]=inst[30:21] 매핑이 스펙과 정확히 일치한다.

**발견된 기술 이슈**: 없음

### 4.5 Ch05 — instruction_memory.sv

| 항목 | 내용 | 판정 |
|------|------|------|
| 비동기 읽기 | `assign instr_o = mem[pc_i[ADDR_WIDTH+1:2]]` | ✅ 조합 논리, 단일 사이클 호환 |
| 주소 변환 | `pc_i[13:2]` (ADDR_WIDTH=12) → 12비트 워드 주소 → 4096 워드 | ✅ 정확 |
| $readmemh 초기화 | `initial` 블록에서 NOP 선채우기 후 hex 로드 | ✅ Vivado/VCS 호환 |
| NOP 선택 | `32'h0000_0013` (ADDI x0, x0, 0) | ✅ 올바른 RV32I NOP |
| BRAM 추론 고려사항 | 비동기 읽기로 Vivado가 분산 RAM으로 추론 가능 | ✅ 본문에서 설명됨 |

**발견된 기술 이슈**: 없음

### 4.6 Ch05 — data_memory.sv

| 항목 | 내용 | 판정 |
|------|------|------|
| 바이트 뱅크 분리 | `mem_bank0/1/2/3 [0:MEM_DEPTH-1]` | ✅ 바이트 인에이블 BRAM 추론 |
| SB 바이트 인에이블 | byte_offset에 따라 4'b0001/0010/0100/1000 선택 | ✅ 정상 |
| SH 하프워드 인에이블 | byte_offset[1]에 따라 4'b0011/1100 선택 | ✅ 정상 |
| SW 전체 인에이블 | 4'b1111 고정 | ✅ 정상 |
| SB 쓰기 데이터 | 모든 바이트 위치에 `wdata_i[7:0]` 기록 | ✅ RISC-V 스펙 준수 |
| LB 부호 확장 | `{{24{mem_word[N]}}, mem_word[N:M]}` | ✅ 정상 |
| LH 부호 확장 | `{{16{mem_word[15/31]}}, mem_word[15:0/31:16]}` | ✅ 정상 |
| LBU/LHU 제로 확장 | `{24'b0, ...}` / `{16'b0, ...}` | ✅ 정상 |
| 리틀 엔디언 | `{bank3, bank2, bank1, bank0}` 조합 | ✅ RV32I 스펙 준수 |
| 동기 쓰기 / 비동기 읽기 | `always_ff` 쓰기, `assign` 읽기 | ✅ 단일 사이클 호환 |
| funct3 상수 | FUNCT3_LB=3'b000, LH=001, LW=010, LBU=100, LHU=101 | ✅ RV32I 스펙 정확 |

**발견된 기술 이슈**: 없음

---

## 5. 발견된 이슈 목록

### 🔴 Critical (즉시 수정 필요)

없음 (전체 소스 코드 섹션 자체에는 Critical 이슈 없음)

### 🟡 Major (HTML 렌더링 오류 유발)

#### ISSUE-M01: 기존 본문 코드 블록 내 다수의 HTML 특수문자 미이스케이프
- **대상**: Ch01 8개 블록, Ch04 3개 블록, Ch05 2개 블록
- **영향**: Highlight.js가 `<code>` 블록 내 `<`를 HTML 태그로 해석하여 렌더링 오류 발생. `<=` 연산자가 HTML 속성 시작으로 파싱될 수 있음. `&`는 HTML 엔티티 파서 오류를 유발.
- **조치**: 아래 문자를 일괄 치환해야 함:
  - `<` → `&lt;`
  - `>` → `&gt;`
  - `&` → `&amp;`
- **주요 발생 위치**:
  - Ch01: 라인 358, 388-390, 442, 448-450, 478-480, 578-595, 792, 886, 971-984
  - Ch04: 라인 234, 237-241, 463-464, 783, 796, 800, 804, 809, 813
  - Ch05: 라인 502-508, 760

#### ISSUE-M02: `language-tcl` 및 `language-bash` 언어 스크립트 미로드
- **대상**: Ch01 (`language-tcl` 2개, `language-bash` 1개), Ch05 (`language-bash` 1개)
- **영향**: Highlight.js 코어(`highlight.min.js`)는 기본 언어 번들을 포함하지 않는다. `verilog.min.js`만 추가 로드되었으므로, `tcl`과 `bash` 클래스는 하이라이팅이 적용되지 않거나 자동 감지를 시도한다. 오류 로그 없이 조용히 실패함.
- **조치**: `</body>` 직전에 다음 스크립트를 추가해야 함:
  ```html
  <script src="https://cdnjs.cloudflare.com/ajax/libs/highlight.js/11.9.0/languages/tcl.min.js"></script>
  <script src="https://cdnjs.cloudflare.com/ajax/libs/highlight.js/11.9.0/languages/bash.min.js"></script>
  ```

#### ISSUE-M03: Ch04 라인 928 — VCS 명령어 블록에 잘못된 언어 클래스 사용
- **대상**: `manuscripts/part2/chapter04.html`, 라인 928
- **내용**: VCS 컴파일 명령어를 `language-systemverilog`로 지정하였으나, 해당 블록의 내용은 bash 주석 형태의 쉘 명령어이다.
- **조치**: `language-systemverilog` → `language-bash`로 변경하고, `languages/bash.min.js`를 로드해야 함

### 🟢 Minor (스타일 및 가독성 개선)

#### ISSUE-N01: `data_memory.sv`에서 `always_ff` 리셋 신호 미사용
- **대상**: `manuscripts/part2/chapter05.html`, data_memory.sv 전체 소스, 라인 1298
- **내용**: `always_ff @(posedge clk_i)` — `rst_ni` 신호가 포트에 선언되었으나 동기 쓰기 `always_ff` 블록의 감도 목록에 없다. 리셋 시 메모리 내용이 초기화되지 않는다.
- **기술적 평가**: SRAM/BRAM은 통상 리셋으로 내용을 지우지 않으므로, 이는 의도적 설계 선택으로 볼 수 있다. 단, 독자에게 "메모리 리셋은 `initial` 블록으로만 처리됨"을 명시적으로 설명하는 주석이 필요하다.

#### ISSUE-N02: `full-source-section` 내 파일명 배지 스타일
- **대상**: 모든 챕터 전체 소스 섹션
- **내용**: `.file-badge` CSS 클래스가 인라인 `<style>` 블록에 정의되어 있다. 향후 `book_style.css`로 이동을 권고함.

#### ISSUE-N03: Ch04 ALU TB에서 `zero` 플래그 `alu_zero` 검증 미흡
- **대상**: `manuscripts/part2/chapter04.html`, 전체 소스 ch04_alu_tb.sv
- **내용**: `check()` 태스크가 `exp_z` 파라미터로 `alu_zero`를 검증하도록 설계되어 있으나, 일부 테스트 케이스(예: SRA, SLT=1)에서 zero 플래그 기대값이 정확한지 세심한 확인이 필요하다. SRA 결과 `32'hF800_0000`은 비제로이므로 `exp_z=0` 맞음. SLT 결과 `32'd1`은 비제로이므로 `exp_z=0` 맞음. — 현재 코드는 정확하다.

---

## 6. 수정 권고사항

### 우선순위 1 (즉시 수정)

1. **ISSUE-M01 해결**: Ch01, Ch04, Ch05 기존 본문 코드 블록에서 `<`, `>`, `&` 문자를 `&lt;`, `&gt;`, `&amp;`로 일괄 치환. Highlight.js 적용 후 브라우저에서 레이아웃 깨짐 방지를 위해 필수.

2. **ISSUE-M02 해결**: Ch01, Ch05 `</body>` 직전 스크립트 블록에 `languages/tcl.min.js`와 `languages/bash.min.js` CDN 스크립트 태그 추가.

3. **ISSUE-M03 해결**: Ch04 라인 928의 `language-systemverilog` 클래스를 `language-bash`로 수정.

### 우선순위 2 (다음 리뷰 사이클)

4. **ISSUE-N01 해결**: `data_memory.sv` 동기 쓰기 블록에 "메모리는 리셋으로 내용이 소거되지 않음" 주석 추가.

5. `full-source-section` CSS를 `book_style.css`로 이동하여 스타일 일관성 확보.

---

## 7. 종합 평가

| 검토 항목 | 결과 |
|----------|------|
| Highlight.js CDN 설정 | ✅ 정상 (버전, URL, 초기화 스크립트) |
| 전체 소스 코드 섹션 이스케이프 | ✅ 정상 (신규 추가 블록 전체) |
| 기존 본문 코드 블록 이스케이프 | 🟡 다수 누락 — 수정 필요 |
| 언어 클래스 지정 | 🟡 tcl/bash 스크립트 미로드 |
| SystemVerilog 코드 기술 정확성 (전체 소스) | ✅ 정상 (ALU/RF/ImmGen/IMEM/DMEM 모두) |
| RV32I ISA 스펙 준수 | ✅ 정상 (즉치수 인코딩, funct3, ALU 연산 코드) |
| Basys 3 FPGA 적합성 | ✅ 정상 (XDC 핀 배정, BRAM/LUTRAM 추론) |
| Vivado/VCS 시뮬레이션 호환성 | ✅ 정상 ($readmemh, $dumpvars, task 등) |

**전체 소스 코드 섹션의 새 코드는 기술적으로 정확하고 RV32I 스펙을 준수한다.** 주요 수정 과제는 기존 본문 코드 블록의 HTML 특수문자 이스케이프 처리와 TCL/Bash 언어 스크립트 추가이다.
