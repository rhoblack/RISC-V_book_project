# Chapter 18 기술 기획 리뷰
날짜: 2026-03-13
검토자: 기술 리뷰어

---

## 구현할 CSR 목록 및 비트 정의

교육용 최소 집합 7개를 구현한다. RISC-V Privileged Architecture v1.12 기준.

### 1. mstatus (Machine Status Register)
- **주소**: 0x300
- **구현 비트**:
  - [3] MIE (Machine Interrupt Enable): 전역 인터럽트 활성화. 0이면 모든 인터럽트 차단
  - [7] MPIE (Machine Previous Interrupt Enable): 트랩 진입 직전 MIE 값 저장
  - [12:11] MPP (Machine Previous Privilege): 트랩 진입 직전 특권 수준 (M-mode only 구현 시 항상 2'b11)
- **나머지 비트**: WPRI(예약, 0 고정) 또는 WLRL(무시)
- **주의**: mret 실행 시 MIE←MPIE, MPIE←1, MPP←U(2'b00) 처리 필요 (Ch19에서 완성)

### 2. mtvec (Machine Trap-Vector Base-Address Register)
- **주소**: 0x305
- **구현 비트**:
  - [31:2] BASE: 트랩 핸들러 기본 주소 (4바이트 정렬 보장)
  - [1:0] MODE: 0=Direct(단일 핸들러), 1=Vectored(원인별 핸들러)
- **Vectored 모드 계산**: 핸들러 주소 = BASE + 4×cause_code
- **주의**: MODE=2,3은 구현 미지원(WARL — 0 또는 1만 허용)

### 3. mepc (Machine Exception Program Counter)
- **주소**: 0x341
- **구현 비트**:
  - [31:2] 또는 [31:1]: 예외/인터럽트 발생 시점의 PC 값 저장
  - [1:0]: RV32I에서 명령어는 4바이트 정렬 → 하위 2비트 항상 0 (WARL)
- **주의**: mret 실행 시 PC←mepc 처리 (Ch19에서 완성)

### 4. mcause (Machine Cause Register)
- **주소**: 0x342
- **구현 비트**:
  - [31] Interrupt: 1=인터럽트, 0=동기 예외
  - [30:0] Exception Code: 원인 코드
- **주요 코드 목록 (교육용 필수)**:
  - 인터럽트: 3=Machine SW Interrupt, 7=Machine Timer Interrupt, 11=Machine External Interrupt
  - 예외: 0=Instruction Address Misaligned, 2=Illegal Instruction, 4=Load Address Misaligned, 6=Store Address Misaligned, 8=Environment Call from U-mode, 11=Environment Call from M-mode

### 5. mie (Machine Interrupt Enable Register)
- **주소**: 0x304
- **구현 비트**:
  - [3] MSIE (Machine Software Interrupt Enable)
  - [7] MTIE (Machine Timer Interrupt Enable)
  - [11] MEIE (Machine External Interrupt Enable)
- **나머지 비트**: 0 고정 (WPRI)
- **주의**: 실제 인터럽트 활성 조건 = mstatus.MIE AND mie.MxIE AND mip.MxIP

### 6. mip (Machine Interrupt Pending Register)
- **주소**: 0x344
- **구현 비트**:
  - [3] MSIP: 소프트웨어가 쓰기 가능 (교육용 단순화)
  - [7] MTIP: 타이머 하드웨어에 의해 설정, 소프트웨어 직접 쓰기 불가 (RORL)
  - [11] MEIP: 외부 인터럽트 컨트롤러에 의해 설정, 소프트웨어 직접 쓰기 불가 (RORL)
- **교육용 단순화**: Ch18에서는 외부 입력 포트로 처리 (timer_irq, ext_irq 입력 신호)

### 7. mscratch (Machine Scratch Register)
- **주소**: 0x340
- **구현 비트**: [31:0] 전체 — 용도 제한 없는 범용 임시 저장소
- **용도**: 트랩 핸들러 진입 시 일반 레지스터 값 보존용 (관례)

---

## 코드 파일 설계

### ch18_csr_unit.sv 포트 목록

```
module csr_unit #(
    parameter DATA_WIDTH = 32
) (
    // 클록/리셋
    input  logic                  clk,
    input  logic                  rst_n,

    // CSR 명령어 인터페이스 (디코더로부터)
    input  logic [11:0]           csr_addr,      // CSR 주소 (명령어[31:20])
    input  logic [2:0]            csr_funct3,    // CSRRW=001, CSRRS=010, CSRRC=011,
                                                 // CSRRWI=101, CSRRSI=110, CSRRCI=111
    input  logic [DATA_WIDTH-1:0] rs1_data,      // rs1 레지스터 값 (CSRRW/CSRRS/CSRRC)
    input  logic [4:0]            uimm,          // 즉시값 (CSRRWI/CSRRSI/CSRRCI, 명령어[19:15])
    input  logic [4:0]            rd_addr,       // rd 주소 (x0 여부 판단용)
    input  logic [4:0]            rs1_addr,      // rs1 주소 (x0 여부 판단용, CSRRS/CSRRC)
    input  logic                  csr_wen,       // CSR 쓰기 활성화 (명령어 유효 시)

    // CSR 읽기 출력
    output logic [DATA_WIDTH-1:0] csr_rdata,     // CSR 읽기 데이터 → rd에 기록

    // 트랩/예외 인터페이스 (Ch19 연결용, 현재는 0 고정)
    input  logic                  trap_en,       // 트랩 발생 (예외/인터럽트)
    input  logic [DATA_WIDTH-1:0] trap_pc,       // 트랩 발생 시 PC
    input  logic [DATA_WIDTH-1:0] trap_cause,    // mcause 값 (interrupt[31] + code[30:0])
    input  logic                  mret_en,       // mret 명령어 실행

    // 트랩 핸들러 주소 출력 (Ch19 연결용)
    output logic [DATA_WIDTH-1:0] mtvec_out,     // 트랩 벡터 주소
    output logic [DATA_WIDTH-1:0] mepc_out,      // 복귀 주소

    // 인터럽트 외부 입력
    input  logic                  timer_irq,     // 타이머 인터럽트 요청 (→ mip.MTIP)
    input  logic                  ext_irq,       // 외부 인터럽트 요청 (→ mip.MEIP)
    input  logic                  sw_irq,        // 소프트웨어 인터럽트 요청 (→ mip.MSIP)

    // 인터럽트 활성 출력 (Ch19 연결용)
    output logic                  irq_pending    // 처리 가능한 인터럽트 존재
);
```

**내부 구조**:
1. CSR 레지스터 7개: always_ff (clk, rst_n)
2. 읽기 MUX: always_comb (csr_addr 기반 csr_rdata 선택)
3. 쓰기 데이터 계산: always_comb (funct3 기반 write_data 계산)
4. 쓰기 활성화 조건:
   - CSRRW: 항상 쓰기 (rd=x0이어도 쓰기 발생)
   - CSRRS/CSRRC: rs1≠x0일 때만 쓰기
   - CSRRWI: 항상 쓰기
   - CSRRSI/CSRRCI: uimm≠0일 때만 쓰기
5. mip: timer_irq/ext_irq 입력은 MTIP/MEIP에 직접 반영 (소프트웨어 쓰기 무시)
6. irq_pending: mstatus.MIE & |(mie & mip) 조합 논리

**쓰기 데이터 계산 규칙**:
- CSRRW/CSRRWI: write_data = (funct3[2] ? {27'b0, uimm} : rs1_data)
- CSRRS/CSRRSI: write_data = csr_rdata | (funct3[2] ? {27'b0, uimm} : rs1_data)
- CSRRC/CSRRCI: write_data = csr_rdata & ~(funct3[2] ? {27'b0, uimm} : rs1_data)

### ch18_csr_tb.sv 테스트 시나리오

**시나리오 1: 기본 CSR 읽기/쓰기**
- CSRRW mscratch, x0, t0: mscratch에 t0 값 쓰기, 이전 값 x0에 폐기
- CSRRS t1, mscratch, x0: mscratch 읽기만 (rs1=x0이므로 쓰기 없음)
- 검증: csr_rdata == 기록한 값

**시나리오 2: CSRRS/CSRRC 비트 조작**
- mscratch = 32'h0000_000F 초기화
- CSRRS: mscratch |= 32'hF0 → 결과 0x0000_00FF
- CSRRC: mscratch &= ~32'h0F → 결과 0x0000_00F0
- 검증: 각 단계별 csr_rdata 확인

**시나리오 3: 즉시값 명령어 (CSRRWI/CSRRSI/CSRRCI)**
- CSRRWI mscratch, 5'b10101: mscratch = 32'h15
- CSRRSI mscratch, 5'b01010: mscratch = 32'h1F (OR)
- CSRRCI mscratch, 5'b10101: mscratch = 32'h0A (AND NOT)
- 검증: 각 단계별 값 확인

**시나리오 4: mstatus MIE 비트 조작**
- CSRRS mstatus, x0, t0 (t0=32'h8): mstatus.MIE = 1 세트
- 검증: irq_pending = 0 (mie 초기값=0이므로)
- CSRRSI mie, 5'b01000: mie.MTIE = 1 세트 (bit[7])
  - 주의: uimm=5'b01000은 bit3만 세트 → MTIE는 bit7이므로 실제로는 직접 쓰기 테스트
- timer_irq = 1 입력 → irq_pending = 1 검증

**시나리오 5: mtvec Direct/Vectored 모드**
- mtvec = 32'h0000_1000 (BASE=0x400, MODE=Direct)
- mtvec_out 검증: Direct 모드 → BASE 그대로 출력
- mtvec = 32'h0000_1001 (BASE=0x400, MODE=Vectored)
- 검증: Vectored 모드 설정 확인 (실제 주소 계산은 Ch19 트랩 핸들러에서)

**시나리오 6: trap_en 인터페이스 (Ch19 예비 검증)**
- trap_en=1, trap_pc=32'h0000_2000, trap_cause=32'h8000_0007 (타이머 인터럽트)
- 검증: mepc_out == 32'h0000_2000, mcause == 32'h8000_0007
- mret_en=1 → mepc_out이 복귀 주소로 사용 가능함 확인

---

## SVG 다이어그램 설계

### ch18_sec01_privilege_levels.svg
**제목**: RISC-V 특권 수준 계층 구조

**포함 내용**:
- 동심원 또는 계층 다이어그램: U-mode(최외곽/낮음) → S-mode(중간, 회색 처리/미구현) → M-mode(최내곽/높음, 파란색 강조)
- 각 수준 레이블: U(User), S(Supervisor, 이 챕터 미구현), M(Machine)
- M-mode 특징 박스: "하드웨어 직접 접근", "트랩 처리 권한", "CSR 전체 접근"
- 화살표: 하위→상위 트랩 진입, 상위→하위 mret 복귀
- 교육용 강조: "이 챕터는 M-mode만 구현" 주석
- 색상: M-mode=#2563EB, S-mode=#9CA3AF(회색), U-mode=#DBEAFE

### ch18_sec02_csr_map.svg
**제목**: 핵심 CSR 레지스터 맵 및 비트 필드

**포함 내용**:
- 7개 CSR 테이블: 주소(12비트 헥스), 이름, 주요 비트 필드
- 각 CSR별 비트 필드 시각화 (32비트 막대, 주요 비트 색상 구분):
  - mstatus[31:0]: MPP[12:11]=초록, MPIE[7]=노랑, MIE[3]=빨강, 나머지=회색
  - mtvec[31:0]: BASE[31:2]=파랑, MODE[1:0]=주황
  - mepc[31:0]: PC값[31:2]=파랑, 하위2비트=회색(0고정)
  - mcause[31:0]: Interrupt[31]=빨강, Code[30:0]=파랑
  - mie[31:0]: MEIE[11]=파랑, MTIE[7]=초록, MSIE[3]=주황, 나머지=회색
  - mip[31:0]: MEIP[11]=파랑, MTIP[7]=초록, MSIP[3]=주황
  - mscratch[31:0]: 전체=하늘색(범용)
- CSR 주소 공간 설명: 12비트[11:10]=R/W권한, [9:8]=최소권한수준

### ch18_sec03_csr_instruction.svg
**제목**: CSR 명령어 인코딩 및 원자적 읽기-수정-쓰기 동작

**포함 내용**:
- 상단: CSRRW 명령어 비트 필드 인코딩 (32비트 다이어그램)
  - [31:20]=csr(12비트), [19:15]=rs1(5비트), [14:12]=funct3(3비트), [11:7]=rd(5비트), [6:0]=opcode(1110011)
- 중단: 6개 CSR 명령어 동작 요약 테이블
  - 명령어 / funct3 / 읽기 동작 / 쓰기 조건 / 쓰기 데이터
- 하단: CSRRW 원자적 동작 흐름도
  - old_val = CSR[addr] → rd = old_val → CSR[addr] = rs1 (동일 사이클)
  - "원자성: 읽기와 쓰기가 분리되지 않음" 강조 박스
- rs1=x0/rd=x0 특례 별도 주석 박스

---

## 기술적 주의 사항 (집필 시 필수 반영)

### 1. mip 레지스터 쓰기 제한
**위험**: MTIP(bit7), MEIP(bit11)은 소프트웨어가 직접 클리어 불가. 타이머/외부 인터럽트 클리어는 해당 주변 장치(mtimecmp 업데이트, PLIC)를 통해야 함.
**교육용 처리**: Ch18 코드에서 timer_irq/ext_irq 입력 포트를 mip.MTIP/MEIP에 직접 연결. 쓰기 시도는 무시(RORL).
**집필 주의**: "소프트웨어로 mip.MTIP를 직접 클리어할 수 없다" 명시 필수.

### 2. CSRRS/CSRRC에서 rs1=x0 의미
**위험**: CSRRS rd, csr, x0은 "읽기만 수행, 쓰기 없음"을 의미. CSR에 부수효과(side effect)가 있는 경우 이를 구분해야 함.
**집필 주의**: rd=x0(CSRRW)과 rs1=x0(CSRRS/CSRRC)의 의미가 다름을 반드시 설명.
- rd=x0 + CSRRW: 읽기 부수효과 없음 + 쓰기는 발생
- rs1=x0 + CSRRS: 읽기 발생 + 쓰기 없음

### 3. mstatus WPRI 비트 처리
**위험**: 스펙상 WPRI 비트에 쓸 때 무시해야 하며, 읽을 때 0을 반환해야 함. 마스크 없이 전체 비트를 저장하면 스펙 위반.
**구현 방법**: mstatus 쓰기 시 마스크 적용: `mstatus_q <= (write_data & 32'h0001_1888)` (MIE[3]+MPIE[7]+MPP[12:11] 비트만 허용)
**집필 주의**: 실제 하드웨어는 WPRI 비트를 무시하는 마스크가 필수임을 코드 주석에 명시.

### 4. mtvec Vectored 모드 주소 계산 위치
**위험**: mtvec_out을 단순히 {BASE, 2'b00}으로 출력하면 Vectored 모드에서 핸들러 주소 계산이 누락됨.
**올바른 처리**: Vectored 모드 주소 계산(BASE + 4×cause_code)은 Ch19 트랩 처리 로직에서 수행. Ch18 csr_unit은 mtvec 레지스터 값만 출력.
**집필 주의**: "주소 계산은 Ch19에서 다룬다"는 연결 안내 문구 삽입.

### 5. CSR 명령어 원자성(Atomicity)
**위험**: "원자적"이라는 표현을 "인터럽트에 의해 분리되지 않음"으로만 설명하면 오해 소지. 파이프라인 구현에서는 CSR 읽기(ID)와 쓰기(WB) 사이 스톨 또는 포워딩 필요.
**집필 주의**: Ch18은 독립 모듈 테스트이므로 단일 사이클 내 처리. 파이프라인 통합 시 해저드는 Ch19에서 다룸을 명시.

### 6. mcause 인터럽트/예외 코드 중복 주의
**위험**: 인터럽트 코드와 예외 코드는 번호 공간이 겹침 (예: 코드 3은 인터럽트=Machine SW Interrupt, 예외=Breakpoint). Interrupt[31] 비트로 구분.
**집필 주의**: 표 제시 시 인터럽트 표와 예외 표를 반드시 분리.

### 7. CSR 주소 권한 비트 교육 범위
**위험**: CSR 주소[11:10]=11이면 Read-Only CSR (cycle, time, instret 등). 이 비트에 쓰기 시도는 Illegal Instruction 예외 발생.
**Ch18 범위**: 7개 CSR은 모두 M-mode R/W (주소[11:10]=11 아님). 읽기 전용 CSR 침범 시 예외 처리는 Ch19에서.

---

## Ch19 인터페이스 예약

Ch19(예외와 인터럽트 처리)에서 csr_unit을 파이프라인에 통합할 때 사용할 포트 목록.

### Ch19에서 구동하는 입력 포트 (현재 Ch18 TB에서 0 고정)

| 신호 | 방향 | 비트 | 설명 |
|------|------|------|------|
| trap_en | input | 1 | 트랩 발생 (동기 예외 또는 인터럽트 처리 진입) |
| trap_pc | input | 32 | mepc에 저장할 PC 값 (예외 발생 명령어 PC) |
| trap_cause | input | 32 | mcause에 저장할 값 {interrupt, code} |
| mret_en | input | 1 | mret 명령어 감지 시 1 (mstatus 복원 트리거) |

### Ch19에서 소비하는 출력 포트

| 신호 | 방향 | 비트 | 설명 |
|------|------|------|------|
| mtvec_out | output | 32 | 트랩 벡터 기본 주소 (MODE 비트 포함) |
| mepc_out | output | 32 | mret 복귀 주소 |
| irq_pending | output | 1 | 처리 가능한 인터럽트 존재 여부 (파이프라인 플러시 트리거) |

### Ch19에서 추가 필요한 신호 (현재 csr_unit 외부)

| 신호 | 출처 | 설명 |
|------|------|------|
| exception_en | 파이프라인 WB 스테이지 | 동기 예외 감지 (Illegal Inst, Misalign 등) |
| exception_cause | 파이프라인 디코더/EX | 예외 코드 (mcause[30:0]) |
| current_pc | 파이프라인 IF/ID | trap_pc용 PC 값 |
| csr_hazard_stall | csr_unit → 파이프라인 | CSR 해저드 시 스톨 신호 (Ch19 추가 예정) |

### mstatus 트랩 진입/복귀 동작 (Ch19에서 완성)

**트랩 진입 시** (trap_en=1):
```
MPIE <= MIE
MIE  <= 0
MPP  <= 현재 특권 수준 (M-mode only → 2'b11 고정)
```

**mret 실행 시** (mret_en=1):
```
MIE  <= MPIE
MPIE <= 1
MPP  <= 2'b00 (U-mode로 설정, 스펙 요구사항)
PC   <= mepc
```

### Ch19 파이프라인 통합 시 CSR 해저드 처리 방안 (예비 설계)
- CSR 명령어 감지: ID 스테이지에서 opcode=SYSTEM, funct3≠000 판단
- CSR 읽기: ID 스테이지에서 csr_rdata → rd 포워딩
- CSR 쓰기: WB 스테이지에서 csr_wen 활성화
- 해저드 조건: CSR 명령어 후속 2사이클 내 동일 CSR 접근 시 스톨 (단순화 정책)
- 대안: CSR 명령어 시 전체 파이프라인 드레인 (fence 방식, 성능 희생 대신 단순성)
