# Appendix B 기획: SystemVerilog 합성 가능 구문 레퍼런스

## 목표
RTL 설계 시 "이 구문이 합성 가능한가?"라는 질문에 즉시 답할 수 있는 참조 문서. Vivado의 BRAM/LUTRAM/DSP 추론 규칙과 XDC 타이밍 제약 템플릿을 제공하여, 독자가 Ch04~Ch22 실습 중 합성 문제를 자체적으로 해결할 수 있도록 지원.

## 섹션 구분

1. **B.1 합성 가능/불가 구문 분류표** — SystemVerilog IEEE 1800-2017 구문의 합성 가능 여부 분류
2. **B.2 Vivado 하드웨어 추론 규칙** — BRAM, LUTRAM, DSP48E1, Shift Register 등 추론 패턴
3. **B.3 합성 관련 pragma 및 속성** — `(* ram_style *)`, `(* use_dsp *)` 등 Vivado 합성 지시어
4. **B.4 XDC 타이밍 제약 템플릿** — 본 교재 프로젝트에 바로 적용 가능한 XDC 파일 템플릿
5. **B.5 흔한 합성 경고/오류와 해결법** — Vivado에서 자주 만나는 합성 메시지 Top 10

## 콘텐츠 항목 상세

### B.1 합성 가능/불가 구문 분류표
- **표 1개** (대형): 약 40개 구문 × (구문, 합성 가능 여부, 비고)
  - 예상 행: 45행
  - 분류:
    - ✅ 합성 가능: `always_ff`, `always_comb`, `assign`, `logic`, `wire`, `parameter`, `localparam`, `generate`, `case`/`casez`/`casex`, `if-else`, 산술/논리 연산자, `packed struct`, `enum`
    - ⚠️ 조건부 합성: `initial` (BRAM 초기화만), `$clog2` (파라미터 전용), `for` (정적 언롤만), `function` (조합 논리만)
    - ❌ 합성 불가: `$display`, `$monitor`, `$readmemh`, `#delay`, `@(posedge clk)` 외 이벤트, `fork-join`, `class`, `program`, `interface.modport` (일부 도구), `real`, `string`
- **코드 조각**: 각 구문별 1~3줄 사용 예시 (합성 가능/불가 대비)

### B.2 Vivado 하드웨어 추론 규칙
- **표 4개** (중형):
  1. **BRAM 추론 조건** (~10행): 동기 읽기/쓰기 패턴, 최소/최대 크기, 포트 설정
  2. **LUTRAM (분산 RAM) 추론 조건** (~8행): 비동기 읽기 + 동기 쓰기 패턴
  3. **DSP48E1 추론 조건** (~8행): 곱셈, MAC, 패턴 매칭
  4. **SRL (Shift Register LUT) 추론 조건** (~6행)
- **코드 예제 4개** (각 10~15줄): 각 리소스 추론을 유도하는 정확한 코딩 패턴
  - `ch_appb_bram_pattern.sv` (BRAM 추론 패턴)
  - `ch_appb_lutram_pattern.sv` (LUTRAM 추론 패턴)
  - `ch_appb_dsp_pattern.sv` (DSP 추론 패턴)
  - `ch_appb_srl_pattern.sv` (SRL 추론 패턴)
- **SVG 1개**: Vivado 합성 흐름도 — RTL → 합성 → 리소스 매핑 → 배치배선 (`app_b_synth_flow.svg`)

### B.3 합성 관련 pragma 및 속성
- **표 1개** (~15행): 속성명, 적용 대상, 효과, 사용 예시
  - `(* ram_style = "block" / "distributed" *)` — 메모리 추론 제어
  - `(* use_dsp = "yes" / "no" *)` — DSP 사용 제어
  - `(* keep = "true" *)` — 최적화 방지
  - `(* dont_touch = "true" *)` — 제거 방지
  - `(* max_fanout = N *)` — 팬아웃 제한
  - `(* async_reg = "true" *)` — CDC 레지스터 표시
- **코드 예제**: 본 교재 코드에서의 실제 사용 사례 3개 (Ch13 I-Cache BRAM, Ch14 D-Cache LUTRAM, Ch24 DSP 곱셈기)

### B.4 XDC 타이밍 제약 템플릿
- **코드 1개** (30~40줄): Basys 3 프로젝트용 완전한 XDC 템플릿
  ```
  # 클록 제약 (100MHz → 50MHz 사용)
  create_clock -period 10.000 -name sys_clk [get_ports clk]
  # I/O 타이밍
  set_input_delay / set_output_delay
  # 거짓 경로
  set_false_path -from [get_ports rst_n]
  # 클록 그룹
  ```
- **표 1개** (~8행): 주요 XDC 명령어 요약 (create_clock, set_input_delay, set_output_delay, set_false_path, set_multicycle_path, set_max_delay)

### B.5 흔한 합성 경고/오류
- **표 1개** (~12행): 경고/오류 메시지, 원인, 해결법
  - "Inferring latch for..." — 불완전 case문
  - "Multi-driven net..." — 다중 드라이버
  - "Timing constraint not met (WNS < 0)" — 타이밍 위반
  - "Signal is read but never assigned" — 미연결 신호
  - "ROM will be implemented using Block RAM" — 의도하지 않은 BRAM 사용

## 사용성

- **주 사용 시점**: Ch01(SystemVerilog 복습) 이후 전 챕터에서 참조, 특히 Ch20(합성 최적화)에서 집중 활용
- **선호 사용법**:
  1. 특정 구문의 합성 가능 여부 빠른 확인 (B.1)
  2. 의도한 하드웨어 리소스가 추론되지 않을 때 코딩 패턴 확인 (B.2)
  3. XDC 파일 작성 시 템플릿 복사-수정 (B.4)
  4. 합성 경고 메시지 해석 (B.5)
- **인쇄 친화성**: A4 3~4페이지

## 예상 초안 생성 시간

- 합성 가능/불가 분류표: 1시간 (IEEE 1800-2017 + Vivado UG901 대조)
- 추론 규칙 표 + 코드 예제: 1시간
- XDC 템플릿 + pragma 표: 0.5시간
- 경고/오류 표 + HTML 포맷팅: 0.5시간
- **총 3시간**

## 리뷰 포인트 (기술 리뷰어 주력)

- 🔴 **Critical**:
  - 합성 가능/불가 분류 정확성 (Vivado 2024.x 기준)
  - BRAM/LUTRAM 추론 패턴의 정확성 (실제 합성 시 추론 성공 여부)
  - XDC 템플릿이 Basys 3 (XC7A35T, 100MHz 오실레이터) 환경에 정확히 맞는지
- 🟡 **Major**:
  - DSP48E1 추론 조건이 Artix-7 패밀리에 맞는지
  - `(* ram_style *)` 등 pragma 동작이 Vivado 2024.x에서 검증됐는지
  - 합성 경고 메시지가 최신 Vivado 버전과 일치하는지
- 🟢 **Minor**:
  - 코드 예제의 스타일 일관성 (3칸 들여쓰기, snake_case)
  - 합성 불가 구문 중 시뮬레이션 전용 용도 설명

## 생성 파일

- `manuscripts/appendices/appendix_b.html` (400줄 예상)
- `figures/app_b_synth_flow.svg` (1개)
- `code_examples/ch_appb_bram_pattern.sv`
- `code_examples/ch_appb_lutram_pattern.sv`
- `code_examples/ch_appb_dsp_pattern.sv`
- `code_examples/ch_appb_srl_pattern.sv`
- 총 SVG 1개, 코드 4개
