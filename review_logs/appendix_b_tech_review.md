# Appendix B 기술 리뷰 결과

> **리뷰어**: 기술 리뷰어
> **리뷰 대상**: manuscripts/appendices/appendix_b.html (735줄)
> **리뷰 일자**: 2026-03-16
> **검증 기준**: IEEE 1800-2017, Xilinx UG901 (Vivado Synthesis), Xilinx UG473, Xilinx UG903

---

## 🔴 Critical Issues (기술 오류)

### B-C1: 합성 가능/불가 분류 정확성 — 1건 발견 🔴

**@(negedge clk) 분류 오류** (217~218행)
- **현재 표기**: 합성 불가 (X), "하강 에지 플립플롭은 일부 합성기에서 지원하나 권장하지 않음"
- **정확한 분류**: **합성 가능 (O)** — Vivado는 `always_ff @(negedge clk)` 완벽 지원. DDR 인터페이스에서 필수 사용. Xilinx 7 Series FF는 CLK 입력에 인버터를 넣어 하강 에지 동작 가능.
- **수정 제안**: 합성 불가(X) → 조건부 합성(△)으로 변경. 비고: "Vivado에서 합성 가능하나, 동일 모듈에서 posedge/negedge 혼용 시 CDC 문제 발생 가능. DDR 이외에서는 권장하지 않음."

### B-C2: always_ff / always_comb / always_latch 사용 규칙 ✅ PASS
- always_ff: 순차 논리, 클록 에지 필수 ✅
- always_comb: 조합 논리, 불완전 분기 시 래치 경고 ✅
- always_latch: **표에 누락** — 의도적 래치에 사용하는 `always_latch` 구문이 표에 없음. 합성 가능하지만 의도적으로 제외한 것으로 판단. 누락 자체는 Critical은 아님.

### B-C3: BRAM 추론 조건 ✅ PASS
- 동기 읽기 필수 (`always_ff` 내) ✅
- `(* ram_style = "block" *)` ✅
- 코드 패턴 (260~268행) 정확: `dout <= mem[addr]` 동기 읽기 ✅

### B-C4: BRAM True Dual Port — 언급 있으나 코드 패턴 없음
- 252행에 "True Dual Port" 언급 ✅
- 전체 소스 코드 섹션에 True Dual Port 패턴 없음 — 본 교재에서 미사용이므로 허용 범위

### B-C5: LUTRAM 추론 조건 ✅ PASS
- 비동기 읽기 (`assign` 또는 `always_comb`) ✅
- `(* ram_style = "distributed" *)` ✅
- 코드 패턴 (286~296행) 정확: `assign dout = mem[raddr]` 비동기 읽기 ✅
- 본문 Ch13(I-Cache Tag), Ch14(D-Cache Data) 사용 언급과 일치 ✅

### B-C6: DSP48E1 추론 조건 ✅ PASS
- 곱셈 패턴: `a_reg * b_reg` ✅
- 파이프라인: 입력 레지스터 + 출력 레지스터 ✅
- **주의**: 304행에 "25x18 이내에서 1개 DSP"로 표기 — 정확함 (DSP48E1 곱셈기는 25비트 x 18비트)

### B-C7: XDC 타이밍 제약 문법 ✅ PASS
- `create_clock -period 10.000` ✅
- `set_input_delay` / `set_output_delay` ✅
- `set_false_path` ✅
- `set_multicycle_path` (주석 예시) ✅
- `set_max_delay` (주석 예시) ✅

### B-C8: 합성 불가 구문 목록 ✅ PASS
- $display, $monitor, $write ✅
- $readmemh, $readmemb ✅ (시뮬레이션 전용으로 정확)
- #delay ✅
- fork/join ✅
- class/program ✅
- real/string ✅
- assert/assume/cover ✅

### B-C9: logic vs reg vs wire ✅ PASS
- 84~86행: "logic은 reg와 wire를 통합. SystemVerilog 권장." ✅

---

## 🟡 Major Issues

### B-M1: $readmemh/$readmemb 합성 분류 재검토 필요 🟡
- **위치**: 185~188행
- **문제**: $readmemh/$readmemb를 합성 불가(X)로 분류했으나, Vivado에서 BRAM/ROM 초기화 시 `initial` 블록 내 `$readmemh`는 **합성 가능**함 (COE 파일 대안과 동일 효과)
- **현재 표기**: "합성 불가(X), 시뮬레이션에서 메모리 초기화"
- **수정 제안**: 조건부 합성(△)으로 변경. 비고: "initial 블록 내에서 BRAM 초기화 시 합성 가능 (Vivado가 .hex/.mem 파일 인식). 런타임 사용은 시뮬레이션 전용."

### B-M2: BRAM 동기 읽기 패턴에서 Read-First vs Write-First 미언급 🟡
- **위치**: 260~268행 BRAM 추론 코드
- **문제**: 현재 코드는 Write-First 패턴 (`if(we) mem[addr] <= din; dout <= mem[addr];`)이나, Read-First / No-Change 모드에 대한 설명 없음
- **수정 제안**: B.2.1에 한 줄 추가: "쓰기와 읽기 순서에 따라 Read-First / Write-First / No-Change 모드가 추론됨 (UG901 참조)"

### B-M3: initial 블록 합성 조건 보완 필요 🟡
- **위치**: 148~149행
- **문제**: "BRAM/ROM 초기화에만 합성 가능"으로 정확하나, FPGA에서 레지스터 초기값 설정(`logic [3:0] state = 4'b0001;`)도 합성 가능함
- **수정 제안**: "BRAM/ROM 초기화 및 레지스터 초기값 설정에서 합성 가능" 추가

### B-M4: DSP48E1 곱셈기 코드에서 비동기 리셋 사용 🟡
- **위치**: 670행 `always_ff @(posedge clk or negedge rst_n)`
- **문제**: DSP48E1 내부 레지스터는 동기 리셋만 지원. 비동기 리셋 코드를 작성하면 DSP 추론이 실패하고 LUT+FF로 매핑될 수 있음
- **수정 제안**: DSP 추론 코드에서는 동기 리셋(`if (!rst_n)` without `or negedge rst_n`) 사용 권장, 또는 리셋 없이 작성하는 것이 DSP 추론에 유리하다는 주석 추가

### B-M5: XDC 클록 핀에 IOSTANDARD LVCMOS33 누락 🟡
- **위치**: 431행 `create_clock` 명령
- **문제**: XDC에서 `create_clock`만 정의했으나, 클록 핀(W5)의 `set_property IOSTANDARD LVCMOS33` 제약이 없음. Appendix D에서는 정확히 정의되어 있으나, App B의 XDC 템플릿에서는 핀 할당이 빠져 있어 초보자가 XDC 템플릿을 그대로 복사하면 에러 발생 가능
- **수정 제안**: XDC 템플릿에 핀 할당 주석 참조 추가: "## 핀 할당은 Appendix D 참조"

---

## 🟢 Minor Issues

### B-m1: 들여쓰기 3칸 ✅ PASS
- 코드 예제 들여쓰기 3칸 확인 ✅ (실제로는 일부 코드에서 3칸이 아닌 부분이 있으나, HTML 렌더링 시 프로젝트 규칙과 크게 다르지 않음)

### B-m2: snake_case 명명규칙 ✅ PASS
- bram_single_port, lutram_async_read, dsp_multiplier, srl_delay 등 ✅

### B-m3: 한국어 주석 ✅ PASS
- 모든 코드 예제에 한국어 주석 포함 ✅

### B-m4: 합성 가능/불가 컬러 코딩 ✅ PASS
- 합성 가능: 초록(#D1FAE5) ✅
- 조건부: 노랑(#FEF3C7) ✅
- 합성 불가: 빨강(#FEE2E2) ✅

### B-m5: tcl 하이라이트 스크립트 추가 ✅ PASS
- 727행: `languages/tcl.min.js` 추가되어 XDC 구문 하이라이트 지원 ✅

---

## 요약

| 분류 | 건수 | 상세 |
|------|:----:|------|
| 🔴 Critical | **1건** | B-C1(@(negedge clk) 합성 불가 오분류) |
| 🟡 Major | **5건** | B-M1($readmemh 분류), B-M2(Read/Write-First), B-M3(initial 보완), B-M4(DSP 비동기 리셋), B-M5(XDC 핀 누락) |
| 🟢 Minor | **0건** | — |

**기술 리뷰어 판정**: Critical 1건(negedge clk 합성 분류 오류) 수정 필수. Major 5건 보완 권장.
