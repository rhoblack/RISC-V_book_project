# Appendix A 기획: RV32I 명령어 레퍼런스

## 목표
디코더 설계(Ch06), 파이프라인 디버깅(Ch09~12), 테스트벤치 작성 시 독자가 즉시 참조할 수 있는 완전한 RV32I 명령어 인코딩 사전. opcode/funct3/funct7로 명령어를 빠르게 검색하고, 비트 필드 배치를 한눈에 확인할 수 있도록 구성.

## 섹션 구분

1. **A.1 명령어 인코딩 전체 표** — 37개 RV32I 명령어를 타입별로 그룹화한 대형 인코딩 표
2. **A.2 명령어 타입별 비트 필드 다이어그램** — R/I/S/B/U/J 6가지 타입의 32비트 필드 배치 SVG
3. **A.3 즉치수(Immediate) 비트 재배열 상세** — B/J 타입의 비트 재배열 규칙 시각화
4. **A.4 ABI 레지스터 명명규약** — x0~x31 레지스터의 ABI 이름, 용도, 호출 규약(caller/callee-saved)
5. **A.5 의사 명령어(Pseudo-instruction) 매핑** — 자주 쓰는 의사 명령어와 실제 명령어 대응 표

## 콘텐츠 항목 상세

### A.1 명령어 인코딩 전체 표
- **표 1개** (대형): 37개 명령어 × (명령어 이름, 타입, opcode[6:0], funct3[2:0], funct7[6:0]/imm, 동작 설명)
  - 예상 행: 43행 (37개 명령어 + 6개 타입 헤더)
  - 타입별 색상 코딩: R(파란), I(초록), S(주황), B(빨간), U(보라), J(분홍)
  - 특수 케이스 강조: SLLI/SRLI/SRAI (I타입이지만 funct7 사용), ECALL/EBREAK (고정 인코딩)
- **코드 없음** (참조 표 전용)

### A.2 명령어 타입별 비트 필드
- **SVG 6개**: 각 타입(R/I/S/B/U/J)의 32비트 필드 배치 다이어그램
  - 비트 번호 [31:0] 표시
  - 필드별 색상 구분 (opcode, rd, rs1, rs2, funct3, funct7, imm)
  - 각 SVG 크기: 약 700×120px
  - 파일명: `app_a_rtype.svg`, `app_a_itype.svg`, `app_a_stype.svg`, `app_a_btype.svg`, `app_a_utype.svg`, `app_a_jtype.svg`
- **텍스트**: 각 타입 필드 구성 설명 (1~2문장)

### A.3 즉치수 비트 재배열 상세
- **SVG 2개**:
  1. B-타입 즉치수 재배열 다이어그램 (`app_a_btype_imm.svg`): inst[31|7|30:25|11:8] → imm[12|11|10:5|4:1|0=0]
  2. J-타입 즉치수 재배열 다이어그램 (`app_a_jtype_imm.svg`): inst[31|19:12|20|30:21] → imm[20|19:12|11|10:1|0=0]
  - 화살표로 비트 이동 경로 시각화
  - 각 SVG 크기: 약 700×200px
- **텍스트**: 재배열 목적 설명 (부호 확장 용이성, 하드웨어 최적화)

### A.4 ABI 레지스터 명명규약
- **표 1개**: 32개 레지스터 × (레지스터 번호, ABI 이름, 용도, 호출 규약)
  - 예상 행: 34행 (32개 레지스터 + 헤더 + 주석)
  - 특수 레지스터 강조: x0(zero), x1(ra), x2(sp), x8(s0/fp)
  - Caller-saved / Callee-saved 구분 색상

### A.5 의사 명령어 매핑
- **표 1개**: 약 20개 의사 명령어 × (의사 명령어, 실제 명령어, 설명)
  - 예상 행: 22행
  - 포함: nop, li, la, mv, not, neg, j, jr, ret, call, beqz, bnez, bgt, ble 등

## 사용성

- **주 사용 시점**: Ch02~03 학습 후 참조 시작, Ch06(디코더 설계)~Ch12(파이프라인 완성)에서 가장 빈번히 참조
- **선호 사용법**:
  1. opcode[6:0]로 명령어 타입 분류 → funct3/funct7로 세부 명령어 확인 (디코더 설계 시)
  2. 명령어 이름으로 인코딩 확인 (테스트벤치 .hex 파일 작성 시)
  3. 비트 필드 SVG로 즉치수 추출 로직 확인 (즉치수 생성기 설계 시)
  4. ABI 이름으로 레지스터 용도 확인 (C 프로그램 연동 시)
- **인쇄 친화성**: A4 2~3페이지에 수납 가능하도록 폰트/간격 설계

## 예상 초안 생성 시간

- 명령어 인코딩 표 작성: 1.5시간 (37개 명령어 ISA 스펙 대조)
- SVG 다이어그램 8개: 1.5시간 (6타입 + 2재배열)
- ABI/의사 명령어 표: 0.5시간
- 텍스트 설명 및 HTML 포맷팅: 0.5시간
- **총 4시간**

## 리뷰 포인트 (기술 리뷰어 주력)

- 🔴 **Critical**:
  - ISA 스펙(v20191213) 대조: 37개 명령어 누락 없이 포함 여부
  - 각 명령어의 opcode/funct3/funct7 값 정확성
  - B-타입/J-타입 즉치수 비트 재배열 순서 정확성 (가장 흔한 오류 지점)
  - SLLI/SRLI/SRAI의 funct7[5] 구분 정확성
- 🟡 **Major**:
  - 비트 필드 SVG에서 비트 번호 [31:0] 배치 정확성
  - ABI 레지스터의 Caller/Callee-saved 분류 정확성
  - 의사 명령어 → 실제 명령어 변환 정확성
- 🟢 **Minor**:
  - 타입별 색상 코딩 일관성
  - 표 포맷 및 정렬 통일성
  - 인쇄 시 가독성

## 생성 파일

- `manuscripts/appendices/appendix_a.html` (350줄 예상)
- `figures/app_a_rtype.svg`
- `figures/app_a_itype.svg`
- `figures/app_a_stype.svg`
- `figures/app_a_btype.svg`
- `figures/app_a_utype.svg`
- `figures/app_a_jtype.svg`
- `figures/app_a_btype_imm.svg`
- `figures/app_a_jtype_imm.svg`
- 총 SVG 8개
