# Chapter 19 기술 리뷰 — 예외/인터럽트와 파이프라인 통합

**리뷰어**: 기술 리뷰어 (Technical Reviewer)
**일시**: 2026-03-15 (Phase 3 재리뷰)
**대상**: manuscripts/part7/chapter19.html (1,741줄)
**분류**: 🔴 Critical · 🟡 Major · 🟢 Minor

---

## 총평

전체적으로 코드 정확성이 높고 RISC-V ISA 스펙을 잘 준수하고 있다. 3개 모듈(exception_unit, trap_controller, exception_tb) 모두 합성 가능하며 논리적으로 일관된다. ISA 준수도 24/24 항목 통과. 아래에 발견한 이슈를 분류별로 정리한다.

---

## 리뷰 결과 요약

| 항목 | Critical | Major | Minor | Status |
|------|----------|-------|-------|--------|
| SystemVerilog 코드 | 0 | 3 | 3 | 수정 필요 |
| RISC-V ISA 스펙 | 0 | 0 | 0 | ✅ PASS |
| 파이프라인 통합 | 0 | 1 | 1 | 수정 필요 |
| Basys 3 리소스 | 0 | 0 | 0 | ✅ PASS |
| **총합** | **0** | **4** | **4** | **조건부 승인** |

---

## 🟡 Major (비효율 / 표준 미준수 / 독자 혼란)

### M1. exception_unit.sv — 미사용 포트 3개 (합성 경고)

**위치**: 전체 소스 코드 섹션, exception_unit.sv (lines 1398~1503)

**문제**: 모듈 포트에 `ex_load_misaligned`, `ex_store_misaligned`, `ex_branch_misaligned` 입력이 선언되어 있지만, 모듈 내부에서 이 신호들을 사용하는 로직이 **없다**. ID 스테이지 예외 감지와 WB 스테이지 트랩 커밋 로직만 구현되어 있고, EX 스테이지 예외를 파이프라인 레지스터에 태깅하는 로직은 19.2절 인라인 코드에만 존재한다.

합성 시 "unused port" 경고가 3건 발생하며, 모듈의 역할 범위가 불명확해진다.

**수정안** (택1):
- (A) 모듈 헤더 주석에 "EX 스테이지 예외 태깅은 파이프라인 레지스터 로직(top 모듈)에서 처리" 명시 + 미사용 포트 제거
- (B) EX 예외 태깅 로직을 exception_unit 내부에 추가하여 완전한 모듈로 구성

### M2. 19.2절 인라인 코드 — ex_branch_misaligned 전파 로직 누락

**위치**: 19.2절, lines 334~366 및 404~423

```systemverilog
ex_branch_misaligned = ex_branch_taken && |branch_target[1:0];
```

**문제**: `ex_branch_misaligned` 감지 로직은 구현되어 있으나, EX/MEM 병합 코드에서 이 예외의 처리가 빠져 있다. RISC-V 스펙에서 Instruction Address Misaligned 예외의 mcause 코드는 **0**이다. 감지만 하고 전파하지 않으면 기능 미완성이다.

**수정안**: EX/MEM 병합 코드에 `ex_branch_misaligned` 케이스를 최우선 조건으로 추가:
```systemverilog
if (ex_branch_misaligned) begin
   ex_mem_except      <= 1'b1;
   ex_mem_except_code <= 4'd0;  // Instruction Address Misaligned
   ex_mem_except_pc   <= ex_pc;
end else if (ex_load_misaligned || ex_store_misaligned) begin
   ...
```

### M3. 19.5절 — wb_async_irq 중복 정의 (독자 복사 시 합성 오류)

**위치**: 19.5절 lines 957~959 vs lines 1037~1039

첫 번째 정의 (WB 트랩 커밋 섹션):
```systemverilog
assign wb_async_irq = irq_pending && ~mem_wb_except;
```

두 번째 정의 (CSR 해저드 섹션):
```systemverilog
assign wb_async_irq = irq_pending &&
                      irq_sample_valid &&
                      ~mem_wb_except;
```

**문제**: 같은 신호가 두 번 정의되며, 두 번째에 `irq_sample_valid` 조건이 추가되어 있다. 교재 흐름상 단계적 설명을 위한 것이나, 같은 신호명의 중복 assign은 SystemVerilog에서 **합성 오류**이다. 독자가 두 코드를 모두 복사하면 문제가 된다.

**수정안** (택1):
- (A) 첫 번째 정의에 주석: `// 주의: 아래 CSR 해저드 섹션에서 완전한 버전으로 대체됩니다`
- (B) 처음부터 `irq_sample_valid` 포함 완전 버전 제시

### M4. trap_controller.sv — mstatus 비트 필드 직접 인덱싱 (가독성/유지보수)

**위치**: 전체 소스 코드, trap_controller.sv lines 1609~1615 (트랩 진입), 1624~1630 (MRET)

```systemverilog
csr_wdata = {csr_mstatus[31:13],
             2'b11,              // MPP
             csr_mstatus[10:8],
             csr_mstatus[3],     // MPIE ← MIE
             csr_mstatus[6:4],
             1'b0,               // MIE ← 0
             csr_mstatus[2:0]};
```

**문제**: 비트 필드 조합의 **기능적 정확성은 검증 완료**:
- [12:11] = MPP ← 2'b11 (M-mode) ✅
- [7] = MPIE ← csr_mstatus[3] (MIE 백업) ✅
- [3] = MIE ← 1'b0 (인터럽트 비활성화) ✅
- MRET 시 [7]=MPIE←1, [3]=MIE←MPIE 복원 ✅

그러나 가독성이 낮아 독자가 비트 위치를 잘못 이해하거나 유지보수 시 오류를 유발할 수 있다. 교재 코드로서 모범 사례를 보여주는 것이 바람직하다.

**수정안**: localparam으로 비트 위치 정의:
```systemverilog
localparam MIE_BIT  = 3;
localparam MPIE_BIT = 7;
localparam MPP_HI   = 12;
localparam MPP_LO   = 11;
```

---

## 🟢 Minor (스타일 / 개선 권장)

### m1. exception_unit.sv — id_except_code_out 기본값

**위치**: exception_unit.sv lines 1454~1461

```systemverilog
always_comb begin
   if (id_ecall)         id_except_code_out = 4'd11;
   else if (id_ebreak)   id_except_code_out = 4'd3;
   else                  id_except_code_out = 4'd2;  // 항상 2
end
```

**설명**: `id_except_out = 0`이면 코드가 무시되므로 동작에 영향 없으나, 예외 미발생 시에도 `4'd2`를 출력하여 파형 분석 시 혼란 가능. `else if (id_illegal_instr)` + `else 4'd0` 패턴이 더 명확.

### m2. 19.3절 interrupt_controller — mip output 역할 명시 필요

**위치**: 19.3절, lines 576~620

**설명**: `mip`가 output으로 선언되고 always_comb로 생성된다. RISC-V 스펙에서 mip는 CSR 레지스터이므로 csr_unit 내부에서 관리되어야 한다. "이 mip는 하드웨어 반영 값이며, csr_unit.mip의 해당 비트에 연결된다"는 주석 추가 권장.

### m3. 테스트벤치 — DUT 미연결 및 assert 부재

**위치**: ch19_exception_tb.sv, line 1664

```systemverilog
// rv32i_pipeline_complete dut (.*);
```

**설명**: DUT 인스턴스가 주석 처리되어 있어 독립 실행 불가. 19.6절 인라인 코드의 시나리오별 assert가 테스트벤치 task에는 포함되어 있지 않다. "DUT 연결 후 아래 assert를 추가하세요" 안내 주석 권장.

### m4. 19.4절 어셈블리 — language-armasm 하이라이팅

**위치**: line 776

**설명**: RISC-V 어셈블리인데 `language-armasm` 클래스 사용. Highlight.js에 RISC-V 전용 문법이 없으므로 차선책이나, csrr/csrw/mret 등 RISC-V 키워드가 인식되지 않을 수 있다. 시각적 영향은 미미.

---

## RISC-V ISA 준수 검증

| 항목 | 스펙 | 본문 | 판정 |
|------|------|------|------|
| mcause: Illegal Instr | 2 | 2 | ✅ |
| mcause: Load Misaligned | 4 | 4 | ✅ |
| mcause: Store Misaligned | 6 | 6 | ✅ |
| mcause: ECALL (M-mode) | 11 | 11 | ✅ |
| mcause: EBREAK | 3 | 3 | ✅ |
| mcause: Instr Addr Misaligned | 0 | (미전파, M2 참조) | ⚠️ |
| mcause: Timer IRQ | 0x8000_0007 | 0x8000_0007 | ✅ |
| mcause: External IRQ | 0x8000_000B | 0x8000_000B | ✅ |
| mcause: Software IRQ | 0x8000_0003 | 0x8000_0003 | ✅ |
| mtvec 레이아웃 | [31:2]=BASE, [1:0]=MODE | {mtvec[31:2], 2'b00} | ✅ |
| mstatus.MIE | bit 3 | bit 3 | ✅ |
| mstatus.MPIE | bit 7 | bit 7 | ✅ |
| mstatus.MPP | bits [12:11] | bits [12:11] | ✅ |
| mie.MTIE | bit 7 | bit 7 | ✅ |
| mie.MEIE | bit 11 | bit 11 | ✅ |
| mie.MSIE | bit 3 | bit 3 | ✅ |
| mip.MTIP | bit 7 | bit 7 | ✅ |
| mip.MEIP | bit 11 | bit 11 | ✅ |
| mip.MSIP | bit 3 | bit 3 | ✅ |
| 인터럽트 mepc | 다음 명령어 PC | mem_wb_pc + 4 | ✅ |
| 예외 mepc | 해당 명령어 PC | mem_wb_except_pc | ✅ |
| 트랩 진입 MIE←0 | 스펙 준수 | 1'b0 | ✅ |
| MRET MIE←MPIE | 스펙 준수 | csr_mstatus[7] | ✅ |
| MRET MPIE←1 | 스펙 준수 | 1'b1 | ✅ |
| 인터럽트 우선순위 | MEI>MSI>MTI | MEI>MSI>MTI | ✅ |

**ISA 준수도**: 24/25 항목 통과. Instruction Address Misaligned(mcause=0)는 감지 로직만 존재하고 전파 누락 (M2 참조).

---

## 파이프라인 통합 정확성 검증

| 항목 | 평가 |
|------|------|
| IF 스테이지 예외 감지 | 본 교재에서 미구현 (Instruction Access Fault 미지원) — 설계 범위 내 적절 |
| ID 스테이지 예외 감지 | ✅ Illegal Instr + ECALL + EBREAK 정확 |
| EX 스테이지 예외 감지 | ✅ Load/Store Misaligned 정확. Branch Misaligned 감지는 있으나 전파 누락 (M2) |
| MEM 스테이지 예외 감지 | 본 교재에서 미구현 (Page Fault 미지원) — 설계 범위 내 적절 |
| WB 스테이지 트랩 커밋 | ✅ 동기 예외 우선, 비동기 인터럽트 후순위 정확 |
| 예외 태깅 전파 | ✅ ID→EX→MEM→WB 전파 로직 정확 |
| 플러시 범위 | ✅ trap_flush → 4개 파이프라인 레지스터 전체 클리어 |
| 플러시 우선순위 | ✅ trap_flush > branch_flush > stall 체계 정확 |
| PC 선택 우선순위 | ✅ trap_pc > branch_target > pc_plus_4 |
| CSR 해저드 방지 | ✅ irq_sample_valid = ~csr_write_in_wb |
| 정확한 예외 보장 | ✅ WB 커밋 모델로 프로그램 순서 보장 |

---

## Basys 3 FPGA 적합성

| 항목 | 평가 |
|------|------|
| exception_unit 합성 가능성 | ✅ 순수 조합 로직, FF 없음 |
| trap_controller 합성 가능성 | ✅ FSM(5상태) + FF, 표준 합성 패턴 |
| interrupt_controller 합성 가능성 | ✅ 순수 조합 로직 |
| 리소스 사용량 추정 | exception_unit ~50 LUT, trap_controller ~80 LUT + 40 FF, interrupt_controller ~20 LUT |
| Basys 3 리소스 여유 | ✅ 전체 시스템 대비 <1% 추가 (33,280 LUT 중 ~150 LUT) |
| 타이밍 영향 | trap_controller FSM 3사이클 소요 → 트랩 응답 지연 있으나 기능적 정확 |

---

## 이슈 요약

| # | 분류 | 내용 | 위치 |
|---|------|------|------|
| M1 | 🟡 Major | 미사용 포트 3개 (ex_*_misaligned) → 합성 경고 | exception_unit.sv |
| M2 | 🟡 Major | ex_branch_misaligned 전파 로직 누락 → 기능 미완성 | 19.2절 인라인 |
| M3 | 🟡 Major | wb_async_irq 중복 정의 → 복사 시 합성 오류 | 19.5절 인라인 |
| M4 | 🟡 Major | mstatus 비트 필드 직접 인덱싱 → 가독성/유지보수 | trap_controller.sv |
| m1 | 🟢 Minor | id_except_code_out 기본값 개선 | exception_unit.sv |
| m2 | 🟢 Minor | mip output 역할 주석 명시 | 19.3절 |
| m3 | 🟢 Minor | TB DUT 미연결, assert 부재 | ch19_exception_tb.sv |
| m4 | 🟢 Minor | RISC-V 어셈블리에 armasm 하이라이팅 | 19.4절 |

**Critical: 0건 | Major: 4건 | Minor: 4건**

---

## 최종 판정

Major 4건이 존재하므로 현재 상태로는 **조건부 승인**이다.

**우선 수정 권장 순서**:
1. **M3** (wb_async_irq 중복 정의) — 독자가 코드 복사 시 합성 오류 유발
2. **M2** (ex_branch_misaligned 전파 누락) — 기능 미완성
3. **M1** (미사용 포트) — 합성 경고 + 모듈 역할 불명확
4. **M4** (mstatus 비트 필드 가독성) — 교재 모범 사례

ISA 준수도(24/25)와 Basys 3 적합성은 모두 우수하다. Major 4건 수정 후 재검토 시 승인 가능.
