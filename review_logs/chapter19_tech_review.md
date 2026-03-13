# Chapter 19 기술 리뷰 — 예외/인터럽트와 파이프라인 통합

**리뷰어**: 기술 리뷰어 (Technical Reviewer)
**리뷰 일자**: 2026-03-13
**리뷰 대상**:
- `manuscripts/part8/chapter19.html`
- `code_examples/ch19_exception_unit.sv`
- `code_examples/ch19_trap_controller.sv`
- `code_examples/ch19_exception_tb.sv`

---

## 요약 판정

| 항목 | 판정 |
|------|------|
| SystemVerilog IEEE 1800-2017 문법 준수 | 조건부 통과 (Minor 1건) |
| RISC-V 특권 아키텍처 스펙 준수 | 조건부 통과 (Critical 1건, Major 3건) |
| 합성 가능성 (Synthesizability) | 조건부 통과 (Critical 1건) |
| 예외/인터럽트 처리 로직 정확성 | 조건부 통과 (Major 2건) |
| CSR 해저드 처리 방법의 적절성 | 통과 |
| 파이프라인 플러시 신호 병합 로직 | 통과 |

**전체 판정**: 수정 후 재검토 필요 (Critical 2건 수정 필수)

---

## Critical 이슈

### [C-01] `trap_controller.sv` — `always_comb` 블록 내 비트 셀렉트 할당 (합성 불가)

**위치**: `ch19_trap_controller.sv`, 149–155행 및 161–165행

**문제 설명**:

```systemverilog
// 문제 코드 — S_TRAP_MSTATUS 출력 로직
S_TRAP_MSTATUS: begin
   csr_we    = 1'b1;
   csr_waddr = CSR_MSTATUS;
   csr_wdata = csr_mstatus;
   csr_wdata[MPIE_BIT] = csr_mstatus[MIE_BIT]; // MPIE ← MIE
   csr_wdata[MIE_BIT]  = 1'b0;                  // MIE ← 0
end
```

`always_comb` 블록 내에서 `csr_wdata`를 먼저 전체 할당(`csr_wdata = csr_mstatus`)한 뒤, 동일 블록에서 특정 비트를 개별 재할당(`csr_wdata[MPIE_BIT] = ...`)하는 패턴은 IEEE 1800-2017 §9.2.2.2에 따라 **비결정적(non-deterministic) 동작**을 유발할 수 있습니다. 일부 합성 도구(특히 Vivado 2023.x)는 이 패턴을 허용하지 않거나 경고 후 의도치 않은 결과를 생성합니다. Synopsys VCS에서는 시뮬레이션 통과 가능하지만 합성 결과와 다를 수 있어 시뮬레이션/합성 불일치(Sim-Synth Mismatch)의 원인이 됩니다.

`S_MRET_MSTATUS` 상태(161–165행)에도 동일 패턴이 존재합니다.

**올바른 구현 방향**:

비트 단위 조작 대신 마스킹 연산으로 전체 값을 한 번에 생성해야 합니다:

```systemverilog
// 권장 수정 방향 — 마스킹 연산으로 단일 할당
S_TRAP_MSTATUS: begin
   csr_we    = 1'b1;
   csr_waddr = CSR_MSTATUS;
   // MPIE(bit7) ← MIE(bit3), MIE(bit3) ← 0, 나머지 비트 유지
   csr_wdata = (csr_mstatus & ~(32'h1 << MPIE_BIT) & ~(32'h1 << MIE_BIT))
             | (csr_mstatus[MIE_BIT] << MPIE_BIT);
end
```

**심각도**: 🔴 Critical — Vivado 합성 오류 또는 Sim-Synth Mismatch 유발

---

### [C-02] `exception_unit.sv` — 인터럽트 `mepc` 저장값 부정확 (RISC-V 스펙 위반)

**위치**: `ch19_exception_unit.sv`, 212–213행; `manuscripts/part8/chapter19.html`, 529행 (FAQ 설명), 664–665행 (코드)

**문제 설명**:

```systemverilog
// 문제 코드
trap_mepc = mem_pc + 32'd4;  // 간략화: MEM 스테이지 PC + 4 사용
```

RISC-V 특권 아키텍처 스펙 v1.12 §3.1.14에 따르면, 비동기 인터럽트에서 `mepc`에 저장해야 하는 값은 **인터럽트가 수용된 시점에 실행되지 못한(미완료된) 가장 오래된(프로그램 순서상 앞선) 명령어의 PC**입니다.

현재 파이프라인의 상태에 따라 저장되어야 하는 PC는 아래와 같이 달라집니다:
- WB 스테이지에 명령어가 없는 경우: `mem_pc`가 가장 오래된 미완료 명령어
- WB 스테이지에 명령어가 있는 경우: WB 스테이지 명령어가 사이클 내 완료 예정

`mem_pc + 4`는 **MEM 스테이지 명령어의 다음 명령어 PC**입니다. 이 값은 MEM 스테이지의 명령어 자체가 완료 후 복귀 지점으로는 적합하지만, 인터럽트 수용 시점의 맥락에서 EX/ID/IF 스테이지에 있는 명령어들이 플러시되었다면 MRET 후 `mem_pc + 4`부터 재실행하는 것이 맞습니다. 그러나 MEM 스테이지의 명령어 자체(A)가 완료 대기 중이라면, `mem_pc + 4`는 A 다음 명령어를 가리켜 A가 재실행되지 않는 결과를 낳습니다.

더 중요한 문제는, **이 설계에서 파이프라인이 완전 플러시되는 시점에 WB 스테이지의 명령어는 이미 완료 진행 중**입니다. 인터럽트 수용 시 파이프라인 상태에 따라 `mepc`의 올바른 값이 달라지므로 고정값 `mem_pc + 4` 사용은 항상 정확하지 않습니다. 특히 MEM 스테이지가 버블(NOP)인 경우 `mem_pc + 4`는 의미 없는 주소입니다.

**원문 HTML의 FAQ 설명 오류** (529행):
> "이 구현에서는 간략화로 `mem_pc + 4`를 사용합니다."

간략화임을 명시했으나, MEM 스테이지가 NOP인 경우의 처리나 실제 오동작 가능성에 대한 경고가 없어 독자가 이 제약을 인지하지 못할 위험이 있습니다. 본문에 **명시적 제약 조건과 교육적 목적을 위한 단순화임을 명확히 기술**해야 합니다.

**심각도**: 🔴 Critical — RISC-V 특권 아키텍처 스펙 §3.1.14 위반 가능 (특정 파이프라인 상태에서)

---

## Major 이슈

### [M-01] `exception_unit.sv` — `mtvec` 벡터 모드(Vectored Mode) 미처리

**위치**: `ch19_exception_unit.sv`, 49행, 182–184행; `ch19_trap_controller.sv`, 183행

**문제 설명**:

```systemverilog
// 현재 구현
trap_pc = mtvec;  // mtvec 전체 값을 PC로 사용
```

RISC-V 특권 아키텍처 스펙 v1.12 §3.1.7에 따르면, `mtvec`의 하위 2비트(MODE 필드)는 트랩 벡터 처리 모드를 지정합니다:
- `MODE = 2'b00` (Direct): PC ← `mtvec[31:2] << 2` (BASE)
- `MODE = 2'b01` (Vectored): 인터럽트의 경우 PC ← `(mtvec[31:2] << 2) + (cause × 4)`

현재 구현은 `mtvec` 전체를 PC로 사용합니다. `mtvec`의 하위 2비트가 0이 아닌 경우(Vectored 모드 또는 2비트 정렬이 아닌 주소), 이 값을 PC로 직접 사용하면 **잘못된 주소로 점프**합니다. 최소한 Direct 모드에서 하위 2비트를 마스킹하는 처리(`mtvec & ~32'h3`)가 필요합니다.

본 교재가 M-mode 전용 Direct 모드만 다룬다면, 이 제약을 명시하고 `mtvec[31:2] << 2` 방식으로 BASE 주소를 추출해야 합니다.

**교재 HTML 영향**: 19.4절의 트랩 진입 5단계 설명 및 관련 코드 예제 모두 수정 필요.

**심각도**: 🟡 Major — M-mode 직접 모드로 제한한다면 테스트벤치 주소(`mtvec = 32'h0000_1000`, 하위 2비트=0)에서는 동작하지만, 일반적인 사용에서 스펙 비준수

---

### [M-02] `trap_controller.sv` — 트랩 FSM 처리 중 파이프라인 플러시 지속 미구현

**위치**: `ch19_trap_controller.sv`, 175–191행

**문제 설명**:

```systemverilog
// 현재 PC 제어 및 파이프라인 플러시
if (trap_taken && state == S_IDLE) begin
   pc_trap        = 1'b1;
   pc_next        = csr_mtvec;
   pipeline_flush = 1'b1;
end
```

트랩 FSM이 `S_TRAP_MEPC → S_TRAP_MCAUSE → S_TRAP_MTVAL → S_TRAP_MSTATUS`를 처리하는 4사이클 동안 `pipeline_flush`가 **1사이클만 활성화**됩니다. 그러나 이 4사이클 동안 PC는 이미 `mtvec`로 변경되었으므로 파이프라인에 핸들러 명령어가 유입되기 시작합니다. CSR 쓰기가 완료(S_TRAP_MSTATUS 완료)되기 전에 핸들러 명령어가 CSR을 읽으면 **업데이트 전의 값을 읽는 RAW 해저드**가 발생합니다.

19.4절 설명(460행)에 "이 동안 파이프라인은 플러시 상태를 유지해야 합니다"라고 올바르게 기술되어 있으나, 실제 코드는 이를 구현하지 않습니다. 교재의 설명과 코드가 불일치합니다.

**올바른 구현 방향**: FSM이 `S_IDLE`이 아닌 상태(`S_TRAP_MEPC`, `S_TRAP_MCAUSE`, `S_TRAP_MTVAL`, `S_TRAP_MSTATUS`)에서도 `pipeline_flush = 1'b1`을 유지해야 합니다.

**심각도**: 🟡 Major — 핸들러 진입 직후 CSR 읽기 해저드 및 교재 설명-코드 불일치

---

### [M-03] `exception_unit.sv` — 인터럽트 수용 시 파이프라인 상태 고려 미흡

**위치**: `ch19_exception_unit.sv`, 152–160행

**문제 설명**:

현재 구현에서 인터럽트 펜딩 신호(`interrupt_pending`)는 파이프라인의 현재 상태와 무관하게 생성됩니다. RISC-V 스펙상 인터럽트는 명령어 경계(instruction boundary)에서만 수용되어야 합니다. 즉, 다중 사이클 연산(예: 나눗셈이 구현된 경우) 중간에 수용하면 안 되며, 더 중요하게는 **이미 트랩 FSM이 처리 중일 때** 새로운 인터럽트가 수용되면 안 됩니다.

현재 `exception_unit.sv`의 우선순위 로직에서 `interrupt_pending`은 `mem_exception`, `ex_exception`, `id_exception`이 모두 0일 때만 `trap_taken`을 활성화합니다(코드 209행). 그러나 트랩 FSM이 처리 중인 상태에서 `trap_controller.sv`가 파이프라인 플러시를 유지하지 않으므로([M-02] 참조), `exception_unit.sv`에 도달하는 스테이지 예외 신호가 다시 활성화될 수 있습니다. 두 모듈 간의 핸드쉐이킹 신호(e.g., `trap_in_progress`) 없이는 중첩 트랩 방지가 불완전합니다.

**심각도**: 🟡 Major — [M-02]와 연동된 설계 결함. 독립 구현 시 중첩 트랩 가능성

---

### [M-04] `exception_tb.sv` — `always_comb` DUT에 순서 의존 테스트 구조

**위치**: `ch19_exception_tb.sv`, 156–172행 (시나리오 1)

**문제 설명**:

```systemverilog
id_ecall = 1'b1;
id_pc    = 32'h0000_0100;
@(posedge clk);          // 클럭 엣지 대기

// 클럭 엣지 직후 assertion 실행
assert (trap_taken == 1'b1) ...
```

`exception_unit`의 출력(`trap_taken`, `trap_mcause` 등)은 `always_comb` 블록으로 구현된 순수 조합 로직입니다. 입력이 변경되면 **클럭 엣지 없이 즉시** 출력이 갱신됩니다. 따라서 `@(posedge clk)` 이후 assertion을 수행하는 구조는 기능적으로는 동작하지만, **assertion이 클럭 엣지 후 세틀링 시간을 고려하지 않아 글리치(glitch)에 취약**합니다.

조합 로직 검증의 올바른 패턴은 입력 인가 후 `#1` 또는 `@(posedge clk); #1`으로 세틀링을 보장한 뒤 assertion을 수행하는 것입니다. 또는 `clocking block`을 활용한 구조화된 테스트벤치로 개선하면 좋습니다.

더 중요한 문제는, 이 테스트벤치가 **`exception_unit`을 독립적으로 테스트하면서 `trap_controller`와의 통합 시나리오를 검증하지 않는다**는 점입니다. [M-02]의 FSM 플러시 지속 문제는 이 테스트벤치로 발견되지 않습니다.

**심각도**: 🟡 Major — 통합 테스트 부재로 [M-02] 결함 미검출

---

## Minor 이슈

### [m-01] `exception_unit.sv` — 불필요한 `clk`, `rst_n` 포트

**위치**: `ch19_exception_unit.sv`, 14–17행

**문제 설명**:

```systemverilog
module exception_unit (
   input  logic        clk,
   input  logic        rst_n,
   ...
);
```

`exception_unit`의 내부 로직은 전부 `assign`과 `always_comb`으로 구성된 순수 조합 로직입니다. `clk`과 `rst_n` 포트가 선언되어 있으나 모듈 내부 어디에서도 사용되지 않습니다. 사용되지 않는 포트는 합성 시 경고를 발생시키며, 독자가 모듈이 순수 조합 로직임을 즉시 파악하기 어렵게 만듭니다.

순수 조합 로직 모듈이라면 클럭/리셋 포트를 제거하는 것이 설계 의도를 명확하게 전달합니다.

**심각도**: 🟢 Minor — 기능에는 영향 없으나 코드 품질 및 합성 경고 발생

---

### [m-02] `chapter19.html` — 19.2절 EX 스테이지 예외 감지 코드 예제 누락

**위치**: `manuscripts/part8/chapter19.html`, 205~230행 (19.2절)

**문제 설명**:

19.2절에서 ID 스테이지 예외 감지 코드와 MEM 스테이지 예외 감지 코드는 각각 예제로 제시되어 있으나, **EX 스테이지 예외 감지 로직** (`ex_branch_misaligned` 신호 생성, `ex_cause = 32'd0` 설정)에 대한 코드 예제가 없습니다. 표 19.2에서 EX 스테이지가 Instruction Address Misaligned를 감지한다고 명시했고, `exception_unit.sv`에도 구현되어 있으나 본문에 코드 예제가 없어 설명이 불완전합니다.

**심각도**: 🟢 Minor — 교육적 완전성 관점에서 EX 스테이지 예제 추가 권고

---

### [m-03] `chapter19.html` — 19.2절 표의 mcause 설명이 코드와 순서 불일치

**위치**: `manuscripts/part8/chapter19.html`, 144~191행 (표 19.1)

**문제 설명**:

표 19.1에서 동기 예외 종류의 나열 순서는 `Illegal Instruction(ID) → Breakpoint(ID) → ECALL(ID) → Instruction Misaligned(EX) → Load Misaligned(MEM) → Store Misaligned(MEM)`입니다.

그러나 바로 뒤 코드 예제(213~229행)에서 우선순위 인코딩 순서는 `id_illegal_instr → id_ecall → id_ebreak`로, **ECALL이 EBREAK보다 우선**처리됩니다. 표와 코드 간에 ECALL/EBREAK 처리 순서가 반전되어 있어 독자에게 혼란을 줄 수 있습니다. (ECALL, EBREAK, Illegal Instruction은 동일 사이클에 동시 발생하기 어렵지만, 코드의 우선순위가 표의 나열 순서와 일치해야 명확합니다.)

**심각도**: 🟢 Minor — 기능에 영향 없으나 표와 코드 나열 순서 통일 권고

---

## 정확성 검증 결과 (이슈 없음)

아래 항목들은 검토 결과 RISC-V 스펙 및 SystemVerilog 표준에 부합하는 것으로 확인되었습니다.

### 동기 예외 우선순위 로직 (MEM > EX > ID)

`exception_unit.sv` 174–217행의 우선순위 결정 로직은 RISC-V 스펙의 정확한 예외(Precise Exception) 요구사항을 올바르게 구현합니다. 프로그램 순서상 가장 오래된(가장 앞선) 명령어가 MEM 스테이지에 위치하므로 MEM 예외를 최우선으로 처리하는 것은 정확합니다.

### 인터럽트 mcause 인코딩

```
MEI: 0x8000_000B (bit31=1, code=11) ✓
MSI: 0x8000_0003 (bit31=1, code=3)  ✓
MTI: 0x8000_0007 (bit31=1, code=7)  ✓
```

RISC-V 특권 아키텍처 스펙 표 3.6과 일치합니다.

### 동기 예외 mcause 코드

```
Illegal Instruction: 2  ✓
Breakpoint (EBREAK): 3  ✓
ECALL from M-mode: 11   ✓
Instr Addr Misaligned: 0 ✓
Load Addr Misaligned: 4  ✓
Store Addr Misaligned: 6 ✓
```

RISC-V 비특권 ISA 스펙 표 및 특권 아키텍처 스펙과 일치합니다.

### 인터럽트 우선순위 (MEI > MSI > MTI)

RISC-V 특권 아키텍처 스펙 §3.1.9의 권장 우선순위를 준수합니다.

### 3단 인터럽트 마스킹 구조

```systemverilog
assign mei_pending = ext_irq   & mie_meie & mstatus_mie;
assign msi_pending = sw_irq    & mie_msie & mstatus_mie;
assign mti_pending = timer_irq & mie_mtie & mstatus_mie;
```

`mstatus.MIE AND mie[bit] AND mip[bit]` 3단 조건을 올바르게 구현합니다. (※ `mip`은 외부 신호가 직접 입력으로 사용되는 간략화 구현이며, 교재 목적상 적절합니다.)

### MRET mstatus 복원 시퀀스

`csr_wdata[MIE_BIT] = csr_mstatus[MPIE_BIT]` (MIE ← MPIE), `csr_wdata[MPIE_BIT] = 1'b1` (MPIE ← 1) 구현은 RISC-V 특권 아키텍처 스펙 §3.3.2의 MRET 동작 명세와 일치합니다. M-mode 단일 특권 수준에서 MPP 필드 생략도 적절합니다.

### CSR 주소 상수

```
MSTATUS: 0x300 ✓
MTVEC:   0x305 ✓
MEPC:    0x341 ✓
MCAUSE:  0x342 ✓
MTVAL:   0x343 ✓
```

RISC-V 특권 아키텍처 스펙 표 2.5와 일치합니다.

### 플러시 신호 병합 로직

`exception_flush_* | branch_flush_*` OR 병합 방식은 설계적으로 올바릅니다. 예외 플러시(IF~MEM 전체 4개)가 분기 플러시(IF, ID 2개)의 상위 집합임을 올바르게 설명하고 있습니다.

### 테스트벤치 assertion 검증값

- ECALL: `mcause = 32'd11` ✓
- Illegal Instruction: `mcause = 32'd2` ✓
- Load Misaligned: `mcause = 32'd4`, `mtval = 비정렬 주소` ✓
- Timer Interrupt: `mcause = 32'h8000_0007` ✓
- 우선순위: 동기 예외 우선 (`mcause = 4` vs `0x80000007`) ✓

---

## 수정 권고 사항 요약

| 번호 | 파일 | 심각도 | 내용 | 수정 필요 |
|------|------|--------|------|----------|
| C-01 | `ch19_trap_controller.sv` L149–155, L161–165 | 🔴 Critical | `always_comb` 내 부분 비트 재할당 → 마스킹 연산으로 교체 | 필수 |
| C-02 | `ch19_exception_unit.sv` L213 + HTML L529, L665 | 🔴 Critical | 인터럽트 `mepc = mem_pc + 4` 오류 명확화 및 파이프라인 상태 조건 추가 | 필수 |
| M-01 | `ch19_exception_unit.sv` L182 + `ch19_trap_controller.sv` L183 | 🟡 Major | `mtvec` 하위 2비트(MODE) 처리 누락, 최소 `& ~32'h3` 마스킹 필요 | 권장 |
| M-02 | `ch19_trap_controller.sv` L175–191 | 🟡 Major | 트랩 FSM 처리 4사이클 동안 `pipeline_flush` 지속 미구현 | 권장 |
| M-03 | `ch19_exception_unit.sv` + `ch19_trap_controller.sv` | 🟡 Major | 두 모듈 간 트랩 진행 중 핸드쉐이킹 신호 부재 → 중첩 트랩 방지 불완전 | 권장 |
| M-04 | `ch19_exception_tb.sv` | 🟡 Major | `exception_unit` + `trap_controller` 통합 테스트 부재; [M-02] 미검출 | 권장 |
| m-01 | `ch19_exception_unit.sv` L14–17 | 🟢 Minor | 미사용 `clk`, `rst_n` 포트 제거 | 선택 |
| m-02 | `chapter19.html` 205–230행 | 🟢 Minor | EX 스테이지 예외 감지 코드 예제 추가 | 선택 |
| m-03 | `chapter19.html` 144–230행 | 🟢 Minor | 표와 코드의 ECALL/EBREAK 나열 순서 통일 | 선택 |

---

## 기술 내용 정확성 평가

**우수한 점**:
- 동기 예외의 스테이지별 분류(ID/EX/MEM)와 mcause 코드가 RISC-V 스펙과 정확히 일치
- 3단 마스킹(mstatus.MIE → mie → mip) 설명이 하드웨어 구현과 일관성 있게 연결됨
- 트랩 진입 5단계 시퀀스의 하드웨어 구현 흐름이 교육 목적에 적합
- FSM 기반 순차 CSR 쓰기 설계 선택과 그 이유(단일 포트 CSR 제약)에 대한 설명이 명확
- 정확한 예외(Precise Exception)의 In-Order 파이프라인 구현 이유 설명 정확

**개선 필요 사항**:
- [C-01], [M-02] 수정 없이는 실제 합성 및 시뮬레이션에서 올바른 동작 보장 불가
- [C-02] 수정 없이는 인터럽트 복귀 주소 오류로 MRET 후 프로그램 실행 이상
- M-mode 전용 단순화 구현의 제약 조건을 더 명확하게 교재에 기술 필요

---

*리뷰 완료: 2026-03-13*
*다음 단계: Critical 이슈(C-01, C-02) 수정 후 기술 저자 검토 → 종합 회의*
