# Appendix A~D 기술 리뷰 체크리스트

> **작성자**: 기술 리뷰어
> **작성일**: 2026-03-16
> **대상**: Appendix A (RV32I 명령어), B (SystemVerilog 합성), C (AMBA), D (Basys 3)
> **검증 기준**: RISC-V Unprivileged ISA Spec v20191213, IEEE 1800-2017, AMBA 3 AHB-Lite / AMBA 2 APB Spec, Xilinx DS180/UG480

---

## Appendix A: RV32I 명령어 레퍼런스

### Critical Issues (🔴 기술 오류 = 불합격)

| # | 검증 항목 | 검증 방법 | 검증 소스 |
|---|----------|----------|----------|
| A-C1 | 전체 37개 RV32I 명령어 빠짐없이 수록 | 명령어 목록 대조 | RISC-V Unprivileged ISA Spec v20191213 Table 24.2 |
| A-C2 | 각 명령어 opcode(6:0) 정확성 | 7비트 opcode 직접 대조 | riscv-opcodes 공식 레포 |
| A-C3 | funct3(14:12) 정확성 — 특히 BEQ/BNE/BLT/BGE/BLTU/BGEU 구분 | 3비트 값 대조 | Spec Table 24.2 |
| A-C4 | funct7(31:25) 정확성 — SUB(0100000)/SRA(0100000) vs ADD(0000000)/SRL(0000000) | funct7[5] 비트 확인 | Spec Ch. 2.4 |
| A-C5 | SLLI/SRLI/SRAI의 shamt[4:0] + funct7 인코딩 구분 | SRAI funct7=0100000, SRLI funct7=0000000 | Spec Ch. 2.4.1 |
| A-C6 | B-Type 비트 재배열 정확성 | `[12\|10:5\|rs2\|rs1\|funct3\|4:1\|11\|opcode]` 직접 검증 | Spec Ch. 2.3 |
| A-C7 | J-Type (JAL) 비트 재배열 정확성 | `[20\|10:1\|11\|19:12\|rd\|opcode]` 직접 검증 | Spec Ch. 2.5 |
| A-C8 | S-Type 즉치수 분할 정확성 | imm[11:5]=inst[31:25], imm[4:0]=inst[11:7] | Spec Ch. 2.6 |
| A-C9 | U-Type (LUI/AUIPC) 즉치수 상위 20비트 배치 | imm[31:12]=inst[31:12] | Spec Ch. 2.4 |
| A-C10 | ABI 레지스터 이름 32개 정확성 | x0=zero, x1=ra, x2=sp, x3=gp, x4=tp, x5~x7=t0~t2, x8=s0/fp, x9=s1, x10~x17=a0~a7, x18~x27=s2~s11, x28~x31=t3~t6 | RISC-V ELF psABI Spec |
| A-C11 | Caller-saved / Callee-saved 분류 정확성 | a0~a7, t0~t6 = caller-saved; s0~s11, sp = callee-saved | psABI Spec |
| A-C12 | ECALL/EBREAK opcode 정확성 | ECALL=0x00000073, EBREAK=0x00100073 | Spec Ch. 2.8 |

**검증용 디코딩 테스트 케이스**:
- BEQ x5, x6, +8 → `0x00628463` → 비트 분해하여 B-Type 재배열 확인
- JAL x1, +0x100 → `0x100000EF` → J-Type 재배열 확인
- SRAI x10, x11, 3 → `0x4035D513` → funct7=0100000 확인

### Major Issues (🟡 비효율/표준 미준수)

| # | 검증 항목 |
|---|----------|
| A-M1 | 6가지 명령어 타입(R/I/S/B/U/J) 분류 일관성 — 모든 명령어가 정확한 타입에 배치 |
| A-M2 | 의사 명령어(pseudo-instruction) 목록: NOP, LI, LA, MV, NOT, NEG, J, JR, RET, CALL 등 주요 항목 포함 |
| A-M3 | 즉치수 부호 확장 규칙 명시 — I-Type 12비트, S-Type 12비트, B-Type 13비트(×2), J-Type 21비트(×2) |
| A-M4 | FENCE 명령어 설명 — 본문 Ch14 FENCE.I와 일관성 확인 |

### Minor Issues (🟢 스타일)

| # | 검증 항목 |
|---|----------|
| A-m1 | 표에서 hex/binary 값은 monospace 폰트 사용 |
| A-m2 | opcode 필드 색상 코딩: 각 타입별 구분 명확 (본문 SVG 색상 팔레트 #2563EB 계열 준수) |
| A-m3 | 비트 위치 번호(31:0) 일관성 — MSB 왼쪽 |

---

## Appendix B: SystemVerilog 합성 가능 구문 레퍼런스

### Critical Issues (🔴)

| # | 검증 항목 | 검증 방법 | 검증 소스 |
|---|----------|----------|----------|
| B-C1 | 합성 가능/불가 구문 분류 정확성 | Vivado 2024.x Synthesis 기준 | Xilinx UG901 (Vivado Synthesis) |
| B-C2 | `always_ff` / `always_comb` / `always_latch` 사용 규칙 정확성 | IEEE 1800-2017 Ch. 9.2.2 대조 | IEEE 1800-2017 |
| B-C3 | BRAM 추론 규칙 — Simple Dual Port 패턴 정확성 | `(* ram_style = "block" *)` 속성, 동기 읽기 필수 | UG901 Ch. 4 |
| B-C4 | BRAM True Dual Port 추론 패턴 정확성 | 두 포트 독립 클록/주소/데이터 | UG901 Ch. 4 |
| B-C5 | LUTRAM 추론 규칙 — `(* ram_style = "distributed" *)` 비동기 읽기 지원 | 조합 읽기 가능 확인 | UG901 Ch. 4 |
| B-C6 | DSP48E1 추론 규칙 — 곱셈/MAC 패턴 정확성 | `(* use_dsp = "yes" *)` 속성 | UG901 Ch. 5 |
| B-C7 | XDC 타이밍 제약 문법 정확성 | `create_clock`, `set_input_delay`, `set_output_delay` 문법 | Xilinx UG903 (Constraints Guide) |
| B-C8 | 합성 불가 구문 목록 정확성: initial (시뮬레이션 전용), $display, $monitor, #delay, fork-join | Vivado 에러 메시지 확인 | UG901 |
| B-C9 | `logic` vs `reg` vs `wire` 사용 가이드 정확성 | SystemVerilog에서 `logic` 통합 사용 권장 | IEEE 1800-2017 |

### Major Issues (🟡)

| # | 검증 항목 |
|---|----------|
| B-M1 | 코드 예제 모두 Vivado에서 합성 가능한지 검증 (경고 없이 합성 통과) |
| B-M2 | Basys 3 XC7A35T 리소스 예산 내 현실적 가이드 — LUT 20,800개 한계 명시 |
| B-M3 | `generate` 구문 사용법 및 합성 결과 정확성 |
| B-M4 | 파라미터(parameter) vs localparam 구분 및 합성 영향 |
| B-M5 | `enum`, `struct`, `typedef` 합성 지원 여부 정확성 (Vivado는 지원) |
| B-M6 | Clock gating 합성 주의사항 — Xilinx는 BUFGCE 사용 권장 |

### Minor Issues (🟢)

| # | 검증 항목 |
|---|----------|
| B-m1 | 코드 들여쓰기 3칸 (프로젝트 규칙) 일관성 |
| B-m2 | snake_case 명명규칙 일관성 |
| B-m3 | 한국어 주석 일관성 |
| B-m4 | 합성 가능/불가 표에 컬러 코딩 (가능=초록, 불가=빨강) |

---

## Appendix C: AMBA 프로토콜 퀵 레퍼런스

### Critical Issues (🔴)

| # | 검증 항목 | 검증 방법 | 검증 소스 |
|---|----------|----------|----------|
| C-C1 | AHB-Lite 신호 목록 완전성 및 방향 정확성 | HCLK, HRESETn, HADDR[31:0], HTRANS[1:0], HWRITE, HSIZE[2:0], HBURST[2:0], HWDATA[31:0], HRDATA[31:0], HREADY, HRESP | ARM AMBA 3 AHB-Lite Protocol Spec (IHI 0033A) |
| C-C2 | HTRANS 인코딩 정확성 | IDLE=2'b00, BUSY=2'b01, NONSEQ=2'b10, SEQ=2'b11 | IHI 0033A Ch. 3.3 |
| C-C3 | HBURST 인코딩 정확성 | SINGLE=3'b000, INCR=3'b001, WRAP4=3'b010, INCR4=3'b011... | IHI 0033A Ch. 3.4 |
| C-C4 | HSIZE 인코딩 정확성 | Byte=3'b000, Halfword=3'b001, Word=3'b010 | IHI 0033A Ch. 3.5 |
| C-C5 | AHB 타이밍: Address Phase → Data Phase 파이프라인 동작 정확성 | 타이밍 다이어그램에서 HADDR가 1사이클 앞서야 함 | IHI 0033A Ch. 4 |
| C-C6 | HREADY가 0일 때 Wait State 삽입 동작 정확성 | 마스터는 HREADY=1까지 대기 | IHI 0033A Ch. 3.1 |
| C-C7 | APB 신호 목록: PCLK, PRESETn, PSEL, PENABLE, PWRITE, PADDR, PWDATA, PRDATA, PREADY | ARM AMBA APB Protocol Spec (IHI 0024B) |
| C-C8 | APB 상태 전이: IDLE → SETUP → ACCESS (→IDLE or SETUP) | PSELx=1 in SETUP, PENABLE=1 in ACCESS | IHI 0024B Ch. 2.1 |
| C-C9 | APB PREADY 동작: 슬레이브가 0 유지 시 ACCESS 상태 연장 | 타이밍 다이어그램 검증 | IHI 0024B Ch. 2.1 |
| C-C10 | AHB-to-APB 브리지 FSM: 본문 Ch16~17과 일관성 | 상태 이름/전이 조건 대조 | 본문 코드 cross-ref |

### Major Issues (🟡)

| # | 검증 항목 |
|---|----------|
| C-M1 | 신호 활성 수준 명확 표기: HRESETn(active-low), PRESETn(active-low) |
| C-M2 | AHB-Lite 전용 (Full AHB 아님) 명시 — Basys 3에서 구현 범위 |
| C-M3 | APB에서 PSLVERR(Error Response) 신호 포함 여부 — APB3 이상에서 추가 |
| C-M4 | 타이밍 다이어그램 SVG에서 클록 엣지 표시 정확성 (상승 엣지 기준) |
| C-M5 | 본문 Ch16 AHB 신호, Ch17 APB 신호와 이름/비트폭 완전 일치 |

### Minor Issues (🟢)

| # | 검증 항목 |
|---|----------|
| C-m1 | 다이어그램 색상 코딩: Address Phase / Data Phase 구분 색상 |
| C-m2 | 신호 방향 화살표 일관성 (Master→Slave, Slave→Master) |
| C-m3 | AMBA 버전 표기 일관성 (AMBA 3 AHB-Lite, AMBA 2 APB or AMBA 3 APB) |

---

## Appendix D: Basys 3 FPGA 리소스 및 핀 배치

### Critical Issues (🔴)

| # | 검증 항목 | 검증 방법 | 검증 소스 |
|---|----------|----------|----------|
| D-C1 | XC7A35T-1CPG236C 리소스 정확성 | 공식 스펙 대조 | Xilinx DS180 (Artix-7 Data Sheet) |
| D-C2 | LUT 수: 20,800개 (3,250 Slices × 4 LUTs + 기타) | DS180 Table 1 | DS180 |
| D-C3 | FF 수: 41,600개 | DS180 Table 1 | DS180 |
| D-C4 | BRAM: 50개 × 36Kb = 1,800Kb (225KB) | DS180 Table 1 | DS180 |
| D-C5 | DSP48E1: 90개 | DS180 Table 1 | DS180 |
| D-C6 | 시스템 클록: 100MHz 온보드 오실레이터 (W5 핀) | Basys 3 Reference Manual | Digilent Basys 3 RM |
| D-C7 | LED 핀 배치 (LD0~LD15): U16, E19, U19, V19, W18, U15, U14, V14, V13, V3, W3, U3, P3, N3, P1, L1 | XDC 파일 대조 | Basys 3 Master XDC |
| D-C8 | 스위치 핀 배치 (SW0~SW15): V17, V16, W16, W17, W15, V15, W14, W13, V2, T3, T2, R3, W2, U1, T1, R2 | XDC 파일 대조 | Basys 3 Master XDC |
| D-C9 | UART 핀: TX=A2 (USB-UART), RX=B1 (USB-UART) — 본문 Ch16과 일치 확인 | XDC + Ch16 코드 대조 | Basys 3 RM |
| D-C10 | 리셋 버튼: 센터 버튼(BTNC)=U18 | XDC 파일 대조 | Basys 3 Master XDC |
| D-C11 | 7-세그먼트 세그먼트 핀(CA~CG, DP) 및 AN0~AN3 정확성 | XDC 파일 대조 | Basys 3 Master XDC |

### Major Issues (🟡)

| # | 검증 항목 |
|---|----------|
| D-M1 | I/O 전압 표기: LVCMOS33 (3.3V), Bank 14/15/34/35 구분 |
| D-M2 | 디지털 I/O와 아날로그 핀(XADC) 구분 명확 |
| D-M3 | 클록 입력에 IBUF → BUFG 경로 명시 (Vivado 자동 삽입 설명) |
| D-M4 | 리셋 회로: 동기 리셋 vs 비동기 리셋 권장 사항 — 본문 설계와 일관성 |
| D-M5 | Basys 3 전원 제약: USB 전원(500mA 한계) 시 I/O 동시 구동 주의 |
| D-M6 | JTAG 프로그래밍 핀 충돌 방지 주의사항 |

### Minor Issues (🟢)

| # | 검증 항목 |
|---|----------|
| D-m1 | SVG 보드 레이아웃/핀맵 가독성 |
| D-m2 | 핀 번호와 Pmod 커넥터 배치도 일관성 |
| D-m3 | XDC 템플릿 예제 코드 형식 (주석 포함) |

---

## 검증 우선순위 (전체)

| 순위 | 대상 | 이유 |
|------|------|------|
| 1 | ISA Spec 정확성 (Appendix A) | 명령어 인코딩 오류 = 전체 프로세서 동작 불가 |
| 2 | AMBA 신호/타이밍 (Appendix C) | 버스 프로토콜 오류 = SoC 통신 불가 |
| 3 | Basys 3 핀/리소스 (Appendix D) | FPGA 구현 실패 직결 |
| 4 | 합성 구문 (Appendix B) | Vivado 합성 실패 직결 |

## 본문 일관성 크로스 체크

| 부록 항목 | 대조 대상 본문 | 확인 사항 |
|----------|-------------|----------|
| App A: opcode 표 | Ch02~03 명령어 디코딩 | 동일 opcode/funct3 값 |
| App A: ABI 레지스터 | Ch04 레지스터 파일 | ABI 이름 일치 |
| App B: BRAM 추론 | Ch13 I-Cache Data Array | `(* ram_style = "block" *)` 패턴 일치 |
| App B: LUTRAM 추론 | Ch14 D-Cache Data Array | `(* ram_style = "distributed" *)` 패턴 일치 |
| App C: AHB 신호 | Ch16 UART + AHB | 신호 이름/비트폭 일치 |
| App C: APB 신호 | Ch17 APB 주변장치 | 신호 이름/비트폭 일치 |
| App C: 브리지 FSM | Ch17 AHB-to-APB 브리지 | FSM 상태 이름 일치 |
| App D: 핀 배치 | Ch01 LED 점멸, Ch20~22 SoC | XDC 핀 번호 일치 |
| App D: 리소스 | Ch20~22 합성 보고서 | LUT/FF/BRAM 사용량 범위 일치 |

---

## 리뷰 실행 계획

1. **Phase 3 리뷰 시**: 위 체크리스트 항목을 하나씩 검증하며 Pass/Fail 표기
2. **검증 실패 항목**: 정확한 수정 값과 출처를 함께 제시
3. **리뷰 결과 파일**: `review_logs/appendix_X_tech_review.md` (A/B/C/D 각각)
4. **최종 보고**: Critical 0건 / Major 0건 달성 시 "✅ App A~D 기술 리뷰 완료"
