# Chapter 19 기술 저자 기획안
**챕터**: Chapter 19 — 예외/인터럽트와 파이프라인 통합
**작성자**: 기술 저자 에이전트
**작성일**: 2026-03-13
**참조 파일**:
- `TABLE_OF_CONTENTS.md` — Ch19 절 구성 및 기술 의존성
- `manuscripts/part7/chapter18.html` — Ch18 연계 인터페이스 확인
- `code_examples/ch19_exception_unit.sv` — 예외 처리 유닛 구현 예제
- `code_examples/ch19_trap_controller.sv` — 트랩 컨트롤러 구현 예제
- `code_examples/ch19_exception_tb.sv` — 통합 테스트벤치
- `figures/ch19_sec0*.svg` — 6개 다이어그램 기확보

---

## 절 구성 제안 (7절)

TOC에 정의된 절 구성(19.1~19.7)을 기준으로 하며, 각 절의 구체적 집필 방향을 아래에 제시합니다.

### 19.1 파이프라인 구조 핵심 복습
- **핵심 내용**: Ch12 파이프라인 1페이지 요약 — 스톨/플러시 메커니즘 재확인, 파이프라인 레지스터 구조 복습, 포워딩 유닛 위치 재확인
- **집필 포인트**: 독자가 Ch12 이후 오랜 시간을 거쳐 이 챕터에 도달했으므로, "파이프라인 구조를 처음 보는 것처럼" 설명하는 것이 아니라 "빠르게 상기시키는" 톤으로 작성. 스톨/플러시 신호 이름(PC_en, IF/ID_en, ID/EX_flush 등)을 그대로 사용하여 연속성 유지
- **감정 곡선**: "불안 지점 #8 — 파이프라인 복습 박스로 안심 장치 제공"
- **SVG 연계**: `ch19_sec01_pipeline_review.svg` (기확보)
- **예상 분량**: 2,000자 내외 (복습 절이므로 간결하게)

### 19.2 동기 예외 처리
- **핵심 내용**: Illegal Instruction(mcause=2), EBREAK(mcause=3), Load/Store Misaligned(mcause=4,6), ECALL(mcause=11) — 각 예외의 발생 스테이지, RISC-V 스펙 필수 처리 여부
- **집필 포인트**: 예외는 "명령어 실행의 직접적 결과"이며 파이프라인의 특정 스테이지에서 감지된다는 점을 강조. `exception_unit.sv`의 스테이지별 감지 로직(id_exception, ex_exception, mem_exception)을 코드 예제로 활용
- **비유**: 공장 조립 라인의 불량 감지 센서 — ID 라인에서, EX 라인에서, MEM 라인에서 각각 감지
- **SVG 연계**: `ch19_sec02_sync_exception.svg` (기확보)
- **예상 분량**: 2,500~3,000자

### 19.3 비동기 인터럽트 처리
- **핵심 내용**: 외부 인터럽트(MEI), 소프트웨어 인터럽트(MSI), 타이머 인터럽트(MTI) — 인터럽트 마스킹 로직(mstatus.MIE AND mie AND mip), 우선순위(MEI > MSI > MTI)
- **집필 포인트**: Ch17의 타이머 컨트롤러가 생성한 `timer_irq` 신호가 이 절에서 실제로 처리됨을 명시하여 Part 6~7 연계성 부각. `exception_unit.sv`의 `mei_pending`, `msi_pending`, `mti_pending` 인코딩 로직 코드 예제로 활용. mcause의 인터럽트 비트(bit 31 = 1)와 예외 코드의 구조적 차이 설명 필수
- **비유**: 응급실 트리아지(triage) — 환자 중증도(우선순위)에 따라 처치 순서 결정
- **SVG 연계**: `ch19_sec03_interrupt_priority.svg` (기확보)
- **예상 분량**: 2,500~3,000자

### 19.4 트랩 진입/복귀 메커니즘
- **핵심 내용**: 트랩 진입 시퀀스(mepc ← PC, mcause ← 코드, mstatus.MPIE ← MIE, mstatus.MIE ← 0, PC ← mtvec), MRET 복귀 시퀀스(PC ← mepc, mstatus.MIE ← MPIE, mstatus.MPIE ← 1)
- **집필 포인트**: `trap_controller.sv`의 FSM(S_IDLE → S_TRAP_MEPC → S_TRAP_MCAUSE → S_TRAP_MTVAL → S_TRAP_MSTATUS → S_IDLE)을 코드 예제로 활용. 다중 CSR 쓰기가 여러 사이클에 걸쳐 이루어지는 이유(단일 포트 CSR 설계 제약) 설명. Ch18의 `csr_unit`이 트랩 컨트롤러의 쓰기 명령을 받아 CSR을 갱신하는 인터페이스 구조 명시
- **SVG 연계**: `ch19_sec04_trap_mechanism.svg` (기확보)
- **예상 분량**: 3,000~3,500자

### 19.5 파이프라인과 예외 처리 통합
- **핵심 내용**: 정확한 예외(Precise Exception) 보장 — 예외 발생 명령어 이전은 완료, 이후는 취소. 동기 예외 우선순위(MEM > EX > ID), 동기 예외 vs 비동기 인터럽트 우선순위. CSR 해저드 처리(CSR 읽기-쓰기 간 데이터 의존성, 파이프라인 스톨 또는 포워딩 처리)
- **집필 포인트**: `exception_unit.sv`의 우선순위 결정 로직 전체를 코드로 제시하고, "왜 MEM > EX > ID 순서인가"를 파이프라인 타이밍 다이어그램과 함께 설명. 인터럽트의 mepc 저장 시 "현재 실행 중 가장 오래된 명령어의 다음 PC"를 저장하는 이유 설명. CSR 해저드: CSRRW로 쓴 값을 다음 사이클에 CSRRS로 읽는 경우 1사이클 포워딩 필요
- **안심 장치**: `<aside class="instructor-tip">` — "정확한 예외는 산업 현장에서도 구현 오류가 가장 잦은 영역입니다. 구현이 틀려도 괜찮습니다. 파형에서 mcause 값과 플러시 타이밍을 추적하는 디버깅 가이드를 함께 제공합니다."
- **SVG 연계**: `ch19_sec05_precise_exception.svg` (기확보)
- **예상 분량**: 3,500~4,000자 (이 챕터 핵심 절)

### 19.6 예외/인터럽트 테스트벤치
- **핵심 내용**: `exception_tb.sv` 5개 시나리오 해설 — ECALL, Illegal Instruction, Load Misaligned, 타이머 인터럽트 응답 시간 측정, 동시 발생 우선순위 검증. VCS/Vivado Simulator 실행 방법, 파형에서 확인할 신호 목록(trap_taken, trap_mcause, flush_*)
- **집필 포인트**: 테스트벤치 코드 전체를 나열하는 대신, 각 시나리오의 "검증 의도 → 핵심 코드 → 기대 파형"의 3단 구성으로 설명. `$time / CLK_PERIOD`를 이용한 인터럽트 응답 시간 측정 방법 강조
- **SVG 연계**: `ch19_sec06_testbench_flow.svg` (기확보)
- **예상 분량**: 2,000~2,500자

### 19.7 요약 및 다음 단계
- **핵심 내용**: Ch19 핵심 개념 요약, 자가 점검 질문 3~5개, Ch20(FPGA 합성 최적화) 예고
- **집필 포인트**: "이 챕터를 마치면 완전한 RV32I 파이프라인 프로세서가 완성됩니다" — 달성감 강조. Ch20 FPGA 합성에서 예외 처리 로직이 타이밍에 미치는 영향 예고
- **예상 분량**: 1,500~2,000자

---

## 핵심 코드 예제 목록

| 파일명 | 설명 | 학습 목표 |
|--------|------|----------|
| `ch19_exception_unit.sv` | 예외 처리 유닛 — 스테이지별 동기 예외 감지 및 비동기 인터럽트 우선순위 결정 | 파이프라인 각 스테이지에서 예외를 감지하고 우선순위에 따라 트랩을 결정하는 combinational 로직 설계 능력 |
| `ch19_trap_controller.sv` | 트랩 컨트롤러 — FSM 기반 CSR 다중 쓰기 시퀀스 관리, MRET 복귀 처리 | 트랩 진입/복귀의 하드웨어 시퀀스를 FSM으로 설계하고, Ch18의 csr_unit과 연동하는 능력 |
| `ch19_exception_tb.sv` | 통합 테스트벤치 — 5개 시나리오(ECALL, Illegal, Misaligned, 타이머 IRQ, 우선순위) | 예외/인터럽트 처리의 정확성을 SystemVerilog assertion으로 자동 검증하는 능력 |

**19.5절에 추가 필요한 인라인 코드 스니펫 (원고 내 직접 작성)**:
- CSR 해저드 포워딩 로직 (약 20줄): WB 스테이지의 CSR 쓰기 결과를 ID 스테이지 CSR 읽기로 포워딩하는 조합 로직
- 파이프라인 최상위 모듈에서 `exception_unit` 및 `trap_controller` 인스턴스 연결 예시 (약 30줄)

---

## 필요한 SVG 다이어그램

아래 6개 SVG는 모두 `figures/` 디렉토리에 기확보되어 있습니다. 원고 집필 중 내용과 불일치 발견 시 수정 필요.

| 파일명 | 다이어그램 내용 | 사용 절 |
|--------|---------------|--------|
| `ch19_sec01_pipeline_review.svg` | 5단 파이프라인 블록 다이어그램 — 스톨/플러시 신호 경로 강조 표시 | 19.1절 |
| `ch19_sec02_sync_exception.svg` | 동기 예외 발생 스테이지 맵 — ID/EX/MEM 각 스테이지에서 감지되는 예외 유형과 mcause 코드 | 19.2절 |
| `ch19_sec03_interrupt_priority.svg` | 인터럽트 마스킹 로직 및 우선순위 계층 — mstatus.MIE, mie, mip 비트 관계도, MEI>MSI>MTI 우선순위 | 19.3절 |
| `ch19_sec04_trap_mechanism.svg` | 트랩 진입/복귀 시퀀스 타이밍 다이어그램 — 클럭 기준 mepc/mcause/mstatus 갱신 순서, MRET 복귀 흐름 | 19.4절 |
| `ch19_sec05_precise_exception.svg` | 정확한 예외 보장 메커니즘 — 파이프라인 타이밍 다이어그램에서 예외 발생 명령어 이전 완료/이후 취소 시각화 | 19.5절 |
| `ch19_sec06_testbench_flow.svg` | 테스트벤치 검증 흐름도 — 5개 시나리오의 입력→기대 출력 관계, 응답 시간 측정 포인트 | 19.6절 |

---

## 전 챕터 연계 포인트

### Ch18 (CSR과 시스템 명령어)에서 이어지는 개념

1. **CSR 인터페이스 직결 연계**: Ch18의 `csr_unit` 모듈이 출력하는 `trap_en`, `mret_en`, `irq_pending` 포트가 Ch19의 `trap_controller`와 `exception_unit`의 입력으로 연결됩니다. Ch18 18.5절 마지막에 "Ch17의 timer_irq → mip.MTIP → irq_pending → 파이프라인 플러시 → 핸들러 실행의 연결이 완성됩니다"라고 예고된 흐름이 이 챕터에서 완성됩니다.

2. **CSR 해저드 예고 해결**: Ch18 18.3절에서 "파이프라인 구현 시 읽기(ID)와 쓰기(WB) 사이의 해저드 발생 가능 — Ch19에서 해결"이라고 언급된 CSR 해저드를 19.5절에서 정식으로 처리합니다.

3. **mstatus 비트 조작 연속**: Ch18에서 구현한 CSRRS/CSRRC로 mstatus.MIE를 세트/클리어하는 기법이 그대로 트랩 진입(MIE←0)과 MRET 복귀(MIE←MPIE) 시퀀스에 활용됩니다.

4. **mtvec 활용**: Ch18에서 설정한 mtvec 레지스터 값이 트랩 핸들러 점프 주소(PC ← mtvec)로 직접 사용됩니다.

5. **Ch17 타이머 인터럽트 신호 종착점**: Ch17 17.5절에서 구현한 APB 슬레이브 타이머의 `timer_irq` 출력 신호가 이 챕터의 `exception_unit`에서 최종적으로 처리됩니다.

---

## 기술적 주의사항

### RISC-V 스펙 관련 사항

1. **Misaligned Access 예외 필수 처리**: RISC-V Unprivileged ISA Spec v20191213에 따라 Load/Store Misaligned access 예외는 하드웨어가 반드시 처리해야 합니다(소프트웨어 에뮬레이션 불가). `mem_load_misaligned` / `mem_store_misaligned` 신호는 ALU 결과(메모리 접근 주소)의 하위 비트를 조합하여 생성합니다. LW의 경우 `alu_result[1:0] != 2'b00`, LH/LHU의 경우 `alu_result[0] != 1'b0`.

2. **mcause 인터럽트 비트**: 인터럽트의 mcause는 bit 31 = 1, 예외 코드는 bit 31 = 0입니다. `ch19_exception_unit.sv`에서 타이머 인터럽트 mcause를 `32'h8000_0007`로 표기한 것이 이 규칙의 적용 예시입니다. 원고에서 이 인코딩 규칙을 표로 정리해야 합니다.

3. **인터럽트 mepc 저장값**: 비동기 인터럽트 발생 시 mepc에는 "인터럽트가 수용된 시점에 완료되지 않은 가장 오래된 명령어의 PC"를 저장해야 합니다. 구현 간략화(현재 예제: `mem_pc + 32'd4` 사용)의 한계와 완전 구현 방향을 원고에서 명시해야 합니다.

4. **MRET의 권한 수준 복원**: 완전한 MRET 구현은 MPP 필드(mstatus[12:11])에서 이전 특권 수준을 복원해야 하나, RV32I M-mode 전용 구현에서는 MPP 처리를 생략할 수 있습니다. 이 단순화 결정을 원고에서 명시해야 합니다.

### SystemVerilog 구현 주의사항

5. **트랩 컨트롤러 FSM — 멀티사이클 CSR 쓰기**: `trap_controller.sv`의 FSM은 트랩 발생 시 4사이클(mepc → mcause → mtval → mstatus)에 걸쳐 CSR을 순차 쓰기합니다. 이 동안 파이프라인은 플러시 상태를 유지해야 합니다. 원고에서 "플러시 지속 시간 = 트랩 처리 사이클 수"임을 타이밍 다이어그램으로 명시해야 합니다.

6. **csr_wdata 비트 필드 조작 주의**: `trap_controller.sv`의 `S_TRAP_MSTATUS` 블록에서 `csr_wdata = csr_mstatus; csr_wdata[MPIE_BIT] = ...`와 같이 packed 구조체 비트 필드를 수정하는 방식은 Vivado 합성에서 경고 없이 지원되나, 일부 도구에서 Unpacked Array와 혼동할 수 있습니다. 원고 코드에서 `always_comb begin ... end` 블록 내에서만 이 방식을 사용함을 명시하고, 합성 가능성 검증을 강조합니다.

7. **예외와 분기 플러시 충돌**: Ch11에서 구현한 분기 플러시(flush_if, flush_id)와 예외 플러시(exception_unit의 flush_if~flush_mem)가 동시에 발생할 수 있습니다. 우선순위 규칙: 예외 플러시가 분기 플러시를 포함(superset)하므로 OR 연산으로 합산합니다. 원고에서 이 신호 병합 방법을 명시해야 합니다.

8. **CSR 해저드 조건**: CSR을 ID 스테이지에서 읽고 WB 스테이지에서 쓰는 경우(CSRRW → 이후 CSRRS), RAW 해저드가 발생합니다. 간략화된 처리: CSR 명령어 감지 시 2사이클 스톨 삽입. 완전한 처리: WB→ID 포워딩 경로 추가. 원고에서 두 방법의 트레이드오프를 설명하고 어느 방법을 선택할지 명시해야 합니다.

9. **Basys 3 합성 영향**: 예외 처리 유닛과 트랩 컨트롤러 추가로 약 200~300 LUT 증가 예상. 임계 경로에는 영향이 적으나, `exception_unit`의 조합 논리(우선순위 결정)가 MEM 스테이지 지연에 추가될 수 있으므로 Vivado `report_timing`으로 확인 권장.

---

*기획안 작성 기준: TABLE_OF_CONTENTS.md Ch19 항목, manuscripts/part7/chapter18.html 연계 인터페이스 분석, code_examples/ch19_*.sv 코드 구조 분석*
*기술 저자 에이전트 — 2026-03-13*
