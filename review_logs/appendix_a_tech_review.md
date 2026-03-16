# Appendix A 기술 리뷰 결과

> **리뷰어**: 기술 리뷰어
> **리뷰 대상**: manuscripts/appendices/appendix_a.html (923줄)
> **리뷰 일자**: 2026-03-16
> **검증 기준**: RISC-V Unprivileged ISA Spec v20191213, RISC-V ELF psABI Spec

---

## 🔴 Critical Issues (기술 오류)

### A-C1: 37개 명령어 완전성 ✅ PASS
- R-Type: ADD, SUB, SLL, SLT, SLTU, XOR, SRL, SRA, OR, AND = **10개** ✅
- I-Type 산술: ADDI, SLTI, SLTIU, XORI, ORI, ANDI, SLLI, SRLI, SRAI = **9개** ✅
- I-Type 로드: LB, LH, LW, LBU, LHU = **5개** ✅
- S-Type: SB, SH, SW = **3개** ✅
- B-Type: BEQ, BNE, BLT, BGE, BLTU, BGEU = **6개** ✅
- U-Type: LUI, AUIPC = **2개** ✅
- J-Type: JAL = **1개** ✅
- I-Type 기타: JALR, ECALL, EBREAK, FENCE = **4개** 개 ✅ (단, 3개는 시스템/기타)
- **합계: 10+9+5+3+6+2+1+4 = 40개**

> ⚠️ **주의**: RV32I 공식 명령어 수는 문서에 따라 37~47개로 변동. 본 부록은 "37개"라고 명시했으나 실제 표에는 40개가 수록되어 있음 (ECALL, EBREAK, FENCE 포함). 이는 계산 방식 차이이며 기술적 오류는 아님. 다만 헤더 문구를 정확히 하려면:
> - ECALL/EBREAK/FENCE를 포함하면 40개
> - 또는 "RV32I 기본 정수 명령어 37개 + ECALL/EBREAK/FENCE 3개 = 40개"로 명시 필요
> - **권장**: 헤더의 "37개"를 "40개"로 수정하거나, ECALL/EBREAK/FENCE를 별도 카테고리로 분리하여 "37+3" 표기

### A-C2: opcode(6:0) 정확성 ✅ PASS
| 타입 | 표기 opcode | 정확한 opcode | 결과 |
|------|-----------|-------------|------|
| R-Type (레지스터 연산) | 0110011 | 0110011 | ✅ |
| I-Type (산술 즉치수) | 0010011 | 0010011 | ✅ |
| I-Type (로드) | 0000011 | 0000011 | ✅ |
| S-Type (스토어) | 0100011 | 0100011 | ✅ |
| B-Type (분기) | 1100011 | 1100011 | ✅ |
| U-Type (LUI) | 0110111 | 0110111 | ✅ |
| U-Type (AUIPC) | 0010111 | 0010111 | ✅ |
| J-Type (JAL) | 1101111 | 1101111 | ✅ |
| I-Type (JALR) | 1100111 | 1100111 | ✅ |
| I-Type (ECALL/EBREAK) | 1110011 | 1110011 | ✅ |
| I-Type (FENCE) | 0001111 | 0001111 | ✅ |

### A-C3: funct3 정확성 ✅ PASS
전체 funct3 값 대조 완료. BEQ=000, BNE=001, BLT=100, BGE=101, BLTU=110, BGEU=111 모두 정확.

### A-C4: funct7 정확성 ✅ PASS
- ADD: 0000000 ✅
- SUB: 0100000 ✅ (funct7[5]=1)
- SRA: 0100000 ✅ (funct7[5]=1)
- SRL: 0000000 ✅ (funct7[5]=0)

### A-C5: SLLI/SRLI/SRAI 인코딩 ✅ PASS
- SLLI: funct7=0000000, funct3=001 ✅
- SRLI: funct7=0000000, funct3=101, funct7[5]=0 ✅
- SRAI: funct7=0100000, funct3=101, funct7[5]=1 ✅
- "I*" 타입 표기로 특수성 명시 ✅

### A-C6: B-Type 비트 재배열 ✅ PASS
- 531행: `imm = {inst[31], inst[7], inst[30:25], inst[11:8], 1'b0}` ✅
- Spec Ch.2.3의 [12|10:5|rs2|rs1|funct3|4:1|11|opcode]과 일치
- imm[12]=inst[31](부호), imm[11]=inst[7], imm[10:5]=inst[30:25], imm[4:1]=inst[11:8], imm[0]=0

### A-C7: J-Type 비트 재배열 ✅ PASS
- 540행: `imm = {inst[31], inst[19:12], inst[20], inst[30:21], 1'b0}` ✅
- Spec Ch.2.5의 [20|10:1|11|19:12|rd|opcode]과 일치

### A-C8: S-Type 즉치수 분할 — 표에서 직접 표기 없음
- 표에서는 "offset[11:0]"으로만 표기
- **비트 분할 설명 누락**: S-Type의 imm[11:5]=inst[31:25], imm[4:0]=inst[11:7] 분할이 A.2 SVG에 위임되어 있으나, 텍스트로 명시적 설명이 없음
- **심각도**: 🟡 Major (A.3절에서 B/J-Type만 상세 설명, S-Type 분할은 누락)

### A-C9: U-Type 즉치수 ✅ PASS
- LUI: "rd = imm << 12" ✅
- AUIPC: "rd = PC + (imm << 12)" ✅

### A-C10: ABI 레지스터 이름 32개 ✅ PASS
모든 32개 레지스터(x0~x31) 정확하게 수록:
- x0=zero, x1=ra, x2=sp, x3=gp, x4=tp ✅
- x5~x7=t0~t2 ✅
- x8=s0/fp, x9=s1 ✅
- x10~x17=a0~a7 ✅
- x18~x27=s2~s11 ✅
- x28~x31=t3~t6 ✅

### A-C11: Caller/Callee-saved 분류 ✅ PASS
- Caller-saved: ra(x1), t0~t2(x5~x7), a0~a7(x10~x17), t3~t6(x28~x31) ✅
- Callee-saved: sp(x2), s0/fp(x8), s1(x9), s2~s11(x18~x27) ✅
- 특수: zero(x0), gp(x3), tp(x4) — 호출 규약 "—" 표기 ✅

### A-C12: ECALL/EBREAK opcode ✅ PASS
- ECALL: opcode=1110011, funct3=000, imm=000000000000 → 0x00000073 ✅
- EBREAK: opcode=1110011, funct3=000, imm=000000000001 → 0x00100073 ✅

---

## 🟡 Major Issues

### A-M1: S-Type 즉치수 분할 텍스트 설명 누락 🟡
- **위치**: A.3절 (즉치수 비트 재배열 상세)
- **문제**: B-Type과 J-Type의 재배열만 상세히 설명하고, S-Type의 imm 분할(`imm[11:5]=inst[31:25], imm[4:0]=inst[11:7]`)은 텍스트 설명 없음
- **수정 제안**: A.3절에 "S-Type 즉치수 분할" 소절을 추가하거나, 최소한 한 문장으로 설명 추가

### A-M2: 명령어 수 표기 불일치 🟡
- **위치**: 71행 헤더 "37개 명령어 완전 참조"
- **문제**: 실제 표에는 ECALL, EBREAK, FENCE 포함 40개 수록
- **수정 제안**: "40개" 또는 "37개 기본 명령어 + 시스템 명령어 3개" 등으로 수정

### A-M3: 의사 명령어 표에 sltz 누락 🟡
- **위치**: A.5절 의사 명령어 표
- **문제**: `seqz`, `snez`, `sgtz`는 있으나 `sltz rd, rs` → `slt rd, rs, x0` 누락
- **수정 제안**: sltz 추가

### A-M4: FENCE 명령어 설명 미흡 🟡
- **위치**: 459행 "fm/pred/succ" 부분
- **문제**: FENCE의 즉치수 필드(fm, pred, succ)가 간략하게만 표기됨. pred/succ 4비트 (IORW) 의미가 없음.
- **수정 제안**: 최소한 pred/succ = {I, O, R, W} 4비트 의미 한 줄 추가. 본문 Ch14의 FENCE.I와 연계 참조 추가.

---

## 🟢 Minor Issues

### A-m1: monospace 폰트 사용 ✅ PASS
- hex/binary 값은 `<code>` 태그 내 monospace 사용 확인

### A-m2: 색상 코딩 ✅ PASS
- 6가지 타입별 색상 구분 명확 (R=파랑, I=초록, S=노랑, B=빨강, U=보라, J=핑크)

### A-m3: 비트 위치 번호 일관성 ✅ PASS
- [6:0], [14:12], [31:25] 등 MSB 왼쪽 일관 표기

### A-m4: 시스템 명령어 헤더 "opcode = 1110011 / 0001111" 🟢
- **위치**: 435행
- **문제**: ECALL/EBREAK(1110011)와 FENCE(0001111)의 opcode가 다르므로, 하나의 헤더로 묶으면 혼동 가능
- **수정 제안**: FENCE를 별도 헤더로 분리하면 더 명확

---

## 요약

| 분류 | 건수 | 상세 |
|------|:----:|------|
| 🔴 Critical | **0건** | 모든 명령어 인코딩 정확 |
| 🟡 Major | **4건** | A-M1(S-Type 설명), A-M2(명령어 수), A-M3(sltz 누락), A-M4(FENCE 설명) |
| 🟢 Minor | **1건** | A-m4(시스템 명령어 헤더) |

**기술 리뷰어 판정**: Critical 0건으로 기술적 정확성은 우수. Major 4건은 보완 권장.
