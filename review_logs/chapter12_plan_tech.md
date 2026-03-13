# Chapter 12 기획 회의 — 기술 저자 관점

## 날짜: 2026-03-12
## 작성자: 기술 저자 에이전트

---

## 0. Ch11 완성 상태 요약 (사전 조사 결과)

### 코드 연속성 인계 사항

`code_examples/ch11_pipeline_with_branch.sv` (rv32i_pipeline_branch) 분석 결과:

| 항목 | 상태 |
|------|------|
| 파이프라인 레지스터 4종 | IF/ID / ID/EX / EX/MEM / MEM/WB 완전 구현 |
| pc_next 4-way MUX | branch_taken_ex > jalr_taken_ex > jal_id > pc_plus4 확정 |
| if_id_flush | `branch_taken_ex \| jal_id \| jalr_taken_ex` 확정 |
| id_ex_flush | `load_use_stall \| branch_taken_ex \| jalr_taken_ex` 확정 |
| 포워딩 유닛 | EX-EX(2'b10) / MEM-EX(2'b01) / 레지스터파일(2'b00) |
| hazard_detection_unit | Load-Use 스톨 전용 |
| branch_unit | BEQ/BNE/BLT/BGE/BLTU/BGEU 6종 완전 구현 |
| WB 스테이지 | wb_sel 2'b00=ALU, 2'b01=MEM, 2'b10=PC+4 |

### IMEM/DMEM 구현 현황

Ch11 코드에서 인스턴스화된 메모리 구조:

```systemverilog
instruction_memory #(.DEPTH(IMEM_DEPTH), .INIT_FILE(IMEM_INIT)) u_imem (
   .addr  (pc),
   .rdata (instr)   // 조합 논리 읽기 (비동기)
);

data_memory #(.DEPTH(DMEM_DEPTH)) u_dmem (
   .clk   (clk),
   .addr  (ex_mem_alu_result),
   .wdata (ex_mem_rs2_data),
   .we    (ex_mem_mem_write),
   .re    (ex_mem_mem_read),
   .rdata (mem_rdata)   // 동기 쓰기 / 비동기 읽기
);
```

- **IMEM**: 조합 논리 읽기 (LUTRAM 추론, Ch09 설계 결정 유지)
- **DMEM**: 동기 쓰기 / 비동기 읽기 (BRAM 동기 추론 가능, Ch09 확정)
- **구조**: Harvard 구조 (명령어/데이터 분리 메모리) — Ch09에서 이미 채택

### 레지스터 파일 현황

```systemverilog
register_file u_rf (
   .clk      (clk),
   .rst_n    (rst_n),
   .rs1_addr (rs1_addr),
   .rs2_addr (rs2_addr),
   .rd_addr  (mem_wb_rd),       // WB 스테이지 rd
   .rd_data  (wb_data),         // WB 스테이지 쓰기 데이터
   .reg_w_en (mem_wb_reg_w_en), // WB 스테이지 쓰기 인에이블
   .rs1_data (rs1_data),
   .rs2_data (rs2_data)
);
```

- **포트 구조**: ID 스테이지에서 읽기, WB 스테이지에서 쓰기
- **WB-ID 포워딩 필요 조건**: WB 스테이지(사이클 N)가 쓰는 rd와 ID 스테이지(사이클 N)가 읽는 rs1/rs2가 동일한 경우

---

## 1. 12.1절 — 구조적 해저드: RV32I에서의 발생 조건

### 1.1 구조적 해저드(Structural Hazard)란?

**구조적 해저드(structural hazard, 구조적 위험)**는 여러 명령어가 파이프라인의 동일 하드웨어 자원을 동시에 사용하려 할 때 발생한다.

대표적인 발생 조건:
1. **단일 포트 메모리** (Princeton/Von Neumann 구조): IF 스테이지(명령어 읽기)와 MEM 스테이지(데이터 읽기/쓰기)가 동시에 메모리에 접근하면 포트 충돌
2. **단일 쓰기 포트 레지스터 파일**: 복수의 명령어가 동시에 레지스터 파일에 쓰려 할 때 (RV32I 5단 파이프라인에서는 WB가 1개이므로 발생 안 함)
3. **공유 ALU**: 멀티사이클에서 발생, 파이프라인에서는 스테이지별 ALU 사용이므로 발생 안 함

### 1.2 우리 설계에서의 발생 조건 분석

| 자원 | 발생 조건 | 우리 설계의 해결 |
|------|----------|----------------|
| 메모리 | Princeton 구조: IF + MEM 동시 접근 | ✅ Harvard 구조 (IMEM/DMEM 분리) — Ch09에서 이미 채택 |
| 레지스터 파일 읽기 포트 | 단일 읽기 포트: IF와 WB 동시 읽기 충돌 | ✅ 2개 읽기 포트 설계 — Ch04에서 해결 |
| 레지스터 파일 쓰기 포트 | 단일 쓰기 포트: 동시 WB 충돌 | ✅ WB 스테이지 1개 — 충돌 없음 |
| 레지스터 파일 동시 읽쓰기 | ID 읽기 + WB 쓰기 동일 레지스터 | ⚠️ WB-ID 포워딩 필요 (12.2절에서 해결) |

### 1.3 서술 방향

이미 Harvard 구조를 채택한 설계이므로, 12.1절의 서술 방향은:

1. **Princeton 구조에서 어떻게 문제가 생기는가** — 그림과 타이밍 다이어그램으로 설명
2. **Harvard 구조가 왜 이를 해결하는가** — IMEM/DMEM 분리의 하드웨어적 근거
3. **우리 설계는 Ch09에서 이미 Harvard 구조로 설계되었으므로 이 해저드가 없음** — 독자에게 안도감 제공
4. **단, 레지스터 파일 Read-During-Write는 아직 미처리** — 12.2절로 자연스럽게 연결

### 1.4 비유 아이디어

- **Princeton 구조의 구조적 해저드**: 한 창구에서 입금과 출금을 동시에 처리하려는 상황 (ATM이 하나뿐인 은행)
- **Harvard 구조의 해결**: 입금 창구와 출금 창구를 분리 — 동시 처리 가능

---

## 2. 12.2절 — WB-ID 포워딩 (레지스터 파일 포워딩)

### 2.1 현재 포워딩 유닛의 커버리지 분석

`ch10_forwarding_unit.sv` 분석:

현재 포워딩 유닛이 처리하는 경우:
- **EX-EX 포워딩**: EX/MEM.rd → EX 스테이지 rs1/rs2 (fwd = 2'b10)
- **MEM-EX 포워딩**: MEM/WB.rd → EX 스테이지 rs1/rs2 (fwd = 2'b01)

**커버되지 않는 경우 — WB-ID 해저드**:

```
사이클 N:   ADD x1, x2, x3   [WB 스테이지] — x1에 결과 쓰기
사이클 N:   ADDI x4, x1, 1   [ID 스테이지] — x1을 레지스터 파일에서 읽기
```

동일 사이클에 WB(쓰기)와 ID(읽기)가 같은 레지스터를 접근할 때:
- **Read-Before-Write**: 레지스터 파일이 먼저 읽히고 나중에 쓰인다면 → 구버전 값 읽음 (오류)
- **Write-Before-Read (Read-During-Write)**: 같은 사이클에 쓰기가 먼저, 읽기가 나중이면 → 최신값 읽음 (정상)

### 2.2 Vivado BRAM/LUTRAM 합성 시 동작 방식

| 구현 방식 | 합성 추론 | 동시 읽쓰기 동작 |
|----------|---------|----------------|
| `logic [31:0] rf [0:31]` + 비동기 읽기 (`assign` 또는 `always_comb`) | LUTRAM | 합성기에 따라 다름; Vivado는 기본적으로 **새 데이터(new data)** 반환 |
| `logic [31:0] rf [0:31]` + 동기 읽기 (`always_ff`) | BRAM | **이전 데이터(old data)** 반환 (레지스터 출력이 1클럭 지연) |

Ch04에서 레지스터 파일은 **비동기 읽기**로 설계됨 (LUTRAM 추론). Vivado는 LUT 기반 메모리에서 동시 읽쓰기 시 **새 데이터(Write-First)** 를 반환할 수 있지만, 이는 합성 옵션(RAM_STYLE, read_during_write 속성)과 Vivado 버전에 따라 달라질 수 있다.

**안전한 설계 원칙**: 합성기의 암묵적 동작에 의존하지 말고, **명시적 포워딩 로직**으로 해결한다.

### 2.3 WB-ID 포워딩 구현 방법

두 가지 접근 방식:

**방법 1: 레지스터 파일 내부에서 처리 (Read-During-Write 회로)**

```systemverilog
// 레지스터 파일 내부 포워딩
assign rs1_data = (reg_w_en && rd_addr != 0 && rd_addr == rs1_addr)
                  ? rd_data : rf[rs1_addr];
assign rs2_data = (reg_w_en && rd_addr != 0 && rd_addr == rs2_addr)
                  ? rd_data : rf[rs2_addr];
```

장점: 레지스터 파일 모듈이 자체적으로 처리 → 상위 설계 변경 최소
단점: 레지스터 파일 내부에 포워딩 로직이 숨겨짐 → 독자가 놓치기 쉬움

**방법 2: 포워딩 유닛 확장 (WB-ID 포워딩 신호 추가)**

포워딩 유닛에 WB→ID 포워딩 경로 추가:
- 새로운 MUX 선택 신호: `fwd_a_wb`, `fwd_b_wb` (또는 기존 2비트를 3비트로 확장)
- 조건: `mem_wb_reg_w_en && mem_wb_rd != 0 && mem_wb_rd == rs1_addr` (ID 스테이지 rs1)

실제로는 **방법 1 (레지스터 파일 내부 처리)**이 더 교육적으로 명확하고 실용적이다. 해당 방법을 채택하고, 이를 포워딩 유닛과의 관계도 함께 설명한다.

### 2.4 교육적 포인트

- **왜 Ch10의 포워딩 유닛이 이 경우를 다루지 않았는가?**: Ch10의 포워딩 유닛은 EX 스테이지 입력에 집중. ID 스테이지는 레지스터 파일 읽기 단계이므로 별도 처리.
- **실무 설계에서의 선택**: LUTRAM Write-First 모드 이용 vs 명시적 포워딩 — 두 방법 모두 언급, 우리는 명시적 방법 선택
- **Basys 3에서의 합성**: LUTRAM 비동기 읽기 + Write-First 모드로 추론될 수 있으나, 명시적 처리가 더 안전

---

## 3. 12.3절 — 5단계 파이프라인 통합

### 3.1 파라미터화 설계 계획

현재 `ch11_pipeline_with_branch.sv`에는 이미 파라미터가 있다:

```systemverilog
module rv32i_pipeline_branch #(
   parameter IMEM_DEPTH = 1024,
   parameter DMEM_DEPTH = 1024,
   parameter IMEM_INIT  = ""
)(
```

Ch12에서 추가할 파라미터:
- `DATA_WIDTH = 32`: 데이터 버스 폭 (RV32I 기준 32)
- `ADDR_WIDTH = 32`: 주소 버스 폭
- `RF_DEPTH = 32`: 레지스터 파일 깊이 (x0~x31)

단, Basys 3 대상이므로 과도한 파라미터화는 지양. 실용적인 파라미터만 포함.

### 3.2 최종 통합 모듈 연결 계획

`rv32i_pipeline_complete` (또는 `rv32i_pipeline_final`) 모듈에 연결할 서브모듈:

| 서브모듈 | 원산지 | 수정 여부 |
|---------|--------|---------|
| `instruction_memory` | Ch05 | 파라미터화만 (이미 DEPTH/INIT 파라미터 있음) |
| `data_memory` | Ch05 | 변경 없음 |
| `register_file` | Ch04 | **WB-ID 포워딩 추가 (12.2절)** |
| `imm_gen` | Ch04 | 변경 없음 |
| `control_unit` | Ch06 | 변경 없음 |
| `alu` | Ch04 | 변경 없음 |
| `branch_unit` | Ch11 | 변경 없음 |
| `forwarding_unit` | Ch10 | 변경 없음 (WB-ID는 레지스터 파일에서 처리) |
| `hazard_detection_unit` | Ch10 | 변경 없음 |

`ch11_pipeline_with_branch.sv` 기반 수정 사항:
1. 모듈명을 `rv32i_pipeline_complete`로 변경
2. `DATA_WIDTH`, `ADDR_WIDTH`, `RF_DEPTH` 파라미터 추가
3. `register_file` 모듈에 WB-ID 포워딩 로직 반영
4. `imm_gen`, `control_unit` 주석 처리된 부분을 실제 인스턴스로 연결
5. 헤더 주석 업데이트

### 3.3 ch11_pipeline_with_branch.sv의 현재 한계

- `imm_gen`, `control_unit`이 주석 처리되어 있음 (교육 목적으로 해당 신호들을 직접 계산하거나 외부 입력으로 처리)
- Ch12 통합 코드에서는 이 모듈들을 실제로 인스턴스화하여 완성된 설계 제시

---

## 4. 12.4절 — 전체 RV32I 프로그램 실행 검증

### 4.1 버블정렬 RISC-V 어셈블리 계획

```asm
# 버블정렬: a[0..N-1] 정렬 (N=8, 데이터는 DMEM에 사전 로딩)
# 레지스터 할당:
# x10 (a0) = 배열 베이스 주소
# x11 (a1) = 외부 루프 카운터 i
# x12 (a2) = 내부 루프 카운터 j
# x13 (a3) = N (배열 크기)
# x14 (a4) = 임시 값 a[j]
# x15 (a5) = 임시 값 a[j+1]
# x16 (a6) = 스왑 임시 레지스터

bubble_sort:
    li x13, 8        # N = 8
    li x10, 0        # 배열 베이스 = DMEM 주소 0
    li x11, 0        # i = 0
outer_loop:
    addi x16, x13, -1   # N-1
    bge  x11, x16, done  # i >= N-1이면 종료
    li   x12, 0          # j = 0
inner_loop:
    sub  x17, x16, x11   # N-1-i
    bge  x12, x17, outer_next  # j >= N-1-i이면 외부 루프 진행
    slli x18, x12, 2     # j*4 (바이트 오프셋)
    add  x19, x10, x18   # &a[j]
    lw   x14, 0(x19)     # a[j]
    lw   x15, 4(x19)     # a[j+1]
    ble  x14, x15, no_swap  # a[j] <= a[j+1]이면 스왑 불필요
    sw   x15, 0(x19)     # a[j] = a[j+1]
    sw   x14, 4(x19)     # a[j+1] = a[j]
no_swap:
    addi x12, x12, 1     # j++
    j    inner_loop
outer_next:
    addi x11, x11, 1     # i++
    j    outer_loop
done:
    nop
```

이 어셈블리를 기계어로 변환하여 `ch12_bubble_sort.hex` 파일 생성.

### 4.2 DMEM 초기화 방법

**방법 1: `$readmemh` 사용 (시뮬레이션)**

```systemverilog
// data_memory 모듈에 초기화 파일 파라미터 추가
module data_memory #(
   parameter DEPTH     = 1024,
   parameter INIT_FILE = ""     // DMEM 초기화 파일 (선택적)
)(...)
initial begin
   if (INIT_FILE != "")
      $readmemh(INIT_FILE, mem);
end
```

데이터 파일 `ch12_data_init.hex` 예시:
```
00000064  // a[0] = 100
00000005  // a[1] = 5
00000042  // a[2] = 66
0000001E  // a[3] = 30
...
```

**방법 2: 테스트벤치에서 직접 초기화**

```systemverilog
// 테스트벤치에서 DUT 내부 메모리 접근
initial begin
   dut.u_dmem.mem[0] = 32'd100;
   dut.u_dmem.mem[1] = 32'd5;
   // ...
end
```

교재에서는 방법 2(테스트벤치 직접 초기화)를 기본으로 설명하고, 방법 1을 부록 팁으로 제시.

### 4.3 시뮬레이션 결과 검증 전략

```systemverilog
// 시뮬레이션 완료 후 결과 확인
// 정렬 결과: [5, 30, 42, 64, 66, 77, 100, 128] (오름차순)
task check_sort_result;
   integer i;
   logic [31:0] prev, curr;
   begin
      $display("=== 버블정렬 결과 검증 ===");
      prev = 0;
      for (i = 0; i < 8; i++) begin
         curr = dut.u_dmem.mem[i];
         $display("a[%0d] = %0d", i, curr);
         if (curr < prev)
            $display("[FAIL] 정렬 오류: a[%0d]=%0d < a[%0d]=%0d", i, curr, i-1, prev);
         prev = curr;
      end
      $display("[PASS] 버블정렬 완료");
   end
endtask
```

### 4.4 Part 4 마일스톤: "버블정렬 FPGA 실행" 달성 전략

**시뮬레이션 우선 전략**:
1. Ch12 테스트벤치로 시뮬레이션 통과 확인
2. Vivado 합성 → 비트스트림 생성
3. Basys 3 FPGA에 다운로드 → LED/7-세그먼트로 결과 표시

**FPGA 결과 표시 방법** (간단한 방법):
- 정렬 전: 스위치로 인덱스 선택 → 7-세그먼트에 배열 값 표시
- 정렬 실행: 버튼으로 트리거
- 정렬 후: 스위치로 인덱스 선택 → 결과 확인

단, FPGA 구현 세부 사항은 Part 8(Ch20~22)에서 다루므로, 12.5절에서는 **시뮬레이션 검증 완료 + Vivado 합성 결과 수치** 제시로 한정.

---

## 5. 12.5절 — 단일 사이클 vs 멀티사이클 vs 파이프라인 3종 비교

### 5.1 예상 Vivado 합성 결과 (Basys 3 XC7A35T 기준)

| 구현 방식 | LUT | FF | BRAM | Fmax (예상) | CPI |
|----------|:---:|:--:|:----:|:-----------:|:---:|
| 단일 사이클 (Ch06) | ~1,500 | ~200 | 2 | ~20~25 MHz | 1.0 |
| 멀티사이클 (Ch08) | ~1,200 | ~400 | 2 | ~45~55 MHz | ~4.1 |
| 파이프라인 (Ch12) | ~2,200 | ~600 | 2 | ~50~65 MHz | ~1.2 |

*Fmax 예상치는 Artix-7 스피드 그레이드 -1 기준. 실제 합성 후 확인 필요.*

### 5.2 CPI 계산 공식 비교

**단일 사이클**: CPI = 1.0 (항상)

**멀티사이클**: CPI_avg = Σ(명령어 비율 × CPI_명령어)
- 가정: R(40%):I(20%):L(20%):S(10%):B(10%)
- CPI = 0.4×4 + 0.2×4 + 0.2×5 + 0.1×4 + 0.1×3 = 4.1

**파이프라인 (Ch11까지 구현 기준)**:
```
CPI = 1 + (branch 비율) × (taken 비율) × 2 + (load 비율) × (use 비율)

예: branch=10%, taken=50%, load=20%, use=30%
CPI = 1 + 0.1×0.5×2 + 0.2×0.3 = 1 + 0.1 + 0.06 = 1.16
```

**전체 성능 비교 (실행 시간 기준)**:
```
Time = (IC × CPI) / Fmax

단일: IC × 1.0 / 25MHz = IC × 40ns
멀티: IC × 4.1 / 50MHz = IC × 82ns
파이프: IC × 1.16 / 60MHz = IC × 19.3ns
```

→ **파이프라인이 단일 사이클 대비 약 2배, 멀티사이클 대비 약 4.2배 빠름**

### 5.3 교육적 임팩트 전략

- "파이프라인은 CPI를 낮추고, Fmax도 높인다" — 두 가지 이점이 동시에 실현됨을 수치로 체감
- Vivado 보고서 스크린샷 또는 표 형태로 세 구현의 `report_timing` 결과 직접 비교
- "대학원 졸업 후 반도체 회사 면접에서 이 표를 그릴 수 있으면 좋은 인상을 준다" — 동기 부여

---

## 6. SVG 다이어그램 계획

### 12.1절 — 구조적 해저드

| 파일명 | 내용 | 우선순위 |
|--------|------|---------|
| `figures/ch12_sec01_princeton_hazard.svg` | Princeton 구조에서 IF+MEM 동시 메모리 접근 충돌 타이밍 다이어그램 | 필수 |
| `figures/ch12_sec01_harvard_solution.svg` | Harvard 구조 IMEM/DMEM 분리 블록 다이어그램 (우리 설계와 대응) | 필수 |

### 12.2절 — WB-ID 포워딩

| 파일명 | 내용 | 우선순위 |
|--------|------|---------|
| `figures/ch12_sec02_wb_id_forwarding.svg` | WB 스테이지 → ID 스테이지 레지스터 파일 포워딩 경로 | 필수 |
| `figures/ch12_sec02_regfile_rdw.svg` | 레지스터 파일 내부 Read-During-Write 타이밍 | 선택 |

### 12.3절 — 5단계 파이프라인 통합

| 파일명 | 내용 | 우선순위 |
|--------|------|---------|
| `figures/ch12_sec03_complete_pipeline.svg` | 완성된 5단계 파이프라인 전체 블록 다이어그램 (모든 모듈, 포워딩 경로 포함) | 필수 |

### 12.4절 — 프로그램 실행 검증

| 파일명 | 내용 | 우선순위 |
|--------|------|---------|
| `figures/ch12_sec04_bubble_sort_flow.svg` | 버블정렬 알고리즘 흐름도 (어셈블리와 대응) | 필수 |

### 12.5절 — 3종 비교

| 파일명 | 내용 | 우선순위 |
|--------|------|---------|
| `figures/ch12_sec05_three_impl_comparison.svg` | 단일/멀티/파이프라인 성능 비교 막대 그래프 + 표 | 필수 |

**총 SVG: 6개 (필수 5개, 선택 1개)**

---

## 7. 코드 파일 계획

### 7.1 수정할 기존 파일

| 파일 | 수정 내용 |
|------|---------|
| `code_examples/ch04_register_file.sv` (또는 신규 버전) | WB-ID 포워딩(Read-During-Write) 로직 추가 |

### 7.2 새로 생성할 파일

| 파일명 | 내용 |
|--------|------|
| `code_examples/ch12_register_file_with_forwarding.sv` | WB-ID 포워딩이 추가된 레지스터 파일 |
| `code_examples/ch12_rv32i_pipeline_complete.sv` | 최종 완성 파이프라인 top 모듈 (imm_gen, control_unit 실제 인스턴스화) |
| `code_examples/ch12_bubble_sort.hex` | 버블정렬 RISC-V 기계어 (`$readmemh` 형식) |
| `code_examples/ch12_data_init.hex` | 정렬 대상 배열 초기값 데이터 파일 |
| `code_examples/ch12_pipeline_complete_tb.sv` | 완성 파이프라인 테스트벤치 (버블정렬 + 시나리오) |

**총 신규 파일: 5개**

---

## 8. 기술적 주의사항 및 결정 사항

### 8.1 WB-ID 포워딩 구현 방식 최종 결정

**결정**: 레지스터 파일 내부에서 명시적 포워딩 처리 (방법 1 채택)

근거:
- Ch10의 포워딩 유닛 구조를 변경하지 않아도 됨
- `ch11_pipeline_with_branch.sv`의 레지스터 파일 포트 연결 변경 최소화
- Vivado LUTRAM 합성 시 Write-First 모드와 결과가 일치 → 합성 후 검증 용이

**구현 코드 (register_file 수정)**:

```systemverilog
// 읽기 포트 — WB-ID 포워딩 포함
assign rs1_data = (reg_w_en && (rd_addr != 5'b0) && (rd_addr == rs1_addr))
                  ? rd_data : rf[rs1_addr];
assign rs2_data = (reg_w_en && (rd_addr != 5'b0) && (rd_addr == rs2_addr))
                  ? rd_data : rf[rs2_addr];
```

### 8.2 포워딩 우선순위 전체 체계 정리

Ch12에서 모든 포워딩을 통합 정리:

| 우선순위 | 포워딩 경로 | 담당 모듈 | 신호 |
|---------|-----------|---------|------|
| 1 (최우선) | EX-EX (ALU→ALU) | forwarding_unit | fwd_a=2'b10, fwd_b=2'b10 |
| 2 | MEM-EX (Mem→ALU) | forwarding_unit | fwd_a=2'b01, fwd_b=2'b01 |
| 3 | WB-ID (WB→레지스터 읽기) | register_file 내부 | 암묵적 (조합 논리) |
| — (특별) | Load-Use 스톨 | hazard_detection_unit | pc_en=0, if_id_en=0, id_ex_flush=1 |

### 8.3 `imm_gen`과 `control_unit` 인스턴스화

Ch11 코드에서 이 두 모듈은 주석 처리되어 있음. Ch12에서는 이들을 실제로 연결하거나, 주석 해제 가이드를 명시적으로 제공해야 함.

**교육적 서술 전략**: "Ch12에서는 처음으로 완전히 독립된 모듈 계층 구조를 갖춘 파이프라인을 완성합니다. 이제 제어 유닛과 즉치수 생성기도 별도 모듈로 분리되어 인스턴스화됩니다."

### 8.4 버블정렬 구현 범위 결정

**RV32I 명령어만 사용**: 곱셈(`MUL`) 없이 시프트 좌(SLLI)로 인덱스 × 4 계산. M 확장 없이 구현 가능.

**배열 크기**: 8개 원소 (`N=8`) — 시뮬레이션 시간과 교육적 명확성 균형

**스택 프레임 불필요**: 서브루틴 호출 없이 단순 루프 구조로 구현 → 재귀 함수는 Ch12 선택 실습으로 제시

### 8.5 JALR `& ~1` 처리 — Ch12에서 재확인

Ch11에서 aside로 명시된 "JALR 하위 비트 정렬 가정". 버블정렬 테스트에서 JALR이 사용되지 않는다면 이슈 없음. 재귀 함수에서 JAL/JALR이 사용될 경우, 테스트벤치에서 4바이트 정렬 주소만 사용되는지 확인 필요.

---

## 9. 절별 핵심 개념 수 제한 확인

| 절 | 신규 개념 | 개수 | 판정 |
|----|---------|:----:|:----:|
| 12.1 구조적 해저드 | 구조적 해저드, Princeton vs Harvard, 발생 조건 분류 | 3 | ✅ |
| 12.2 WB-ID 포워딩 | Read-During-Write, 레지스터 파일 포워딩, Write-First 모드 | 3 | ✅ |
| 12.3 통합 설계 | 파라미터화 설계, 모듈 계층 구조 완성 | 2 | ✅ |
| 12.4 검증 | 버블정렬 어셈블리, DMEM 초기화, 시뮬레이션 검증 전략 | 3 | ✅ |
| 12.5 비교 | CPI 공식 비교, Fmax 비교, 전체 성능(Time = IC×CPI/Fmax) | 3 | ✅ |

---

## 10. 감정 곡선 설계

| 단계 | 절 | 감정 목표 | 안심 장치 |
|------|---|----------|---------|
| 호기심 | 12.1 | "구조적 해저드? 우리 설계는 이미 해결했다!" | 도입부에 "이 절을 읽고 나면 안도감을 느낄 것입니다" |
| 긴장 | 12.2 | Read-During-Write: 새 개념이지만 간결 | 레지스터 파일 2줄 코드로 해결 → 코드량 최소화 |
| 성취 | 12.3 | "드디어 완성된 파이프라인!" | 전체 블록 다이어그램 SVG와 함께 "완성!" 선언 |
| 몰입 | 12.4 | 버블정렬 실행: 실제 프로그램 동작 체감 | 단계별 진행 + [PASS] 달성 가이드 |
| 자긍심 | 12.5 | "내가 만든 것이 단일/멀티보다 4배 빠르다" | 성능 비교표 + "당신은 이제 파이프라인 CPU를 만든 사람입니다" |

---

## 11. Ch12 집필 시 예상 난이도 및 분량

| 절 | 예상 분량 | 난이도 | 비고 |
|----|---------|-------|------|
| 12.1 | 2,000자 | 낮음 | 개념 정리 + 비유 중심 |
| 12.2 | 2,500자 | 중간 | 코드 포함 |
| 12.3 | 3,000자 | 중간 | 통합 코드 + 모듈 연결 설명 |
| 12.4 | 3,500자 | 높음 | 어셈블리 + 테스트벤치 + 검증 전략 |
| 12.5 | 2,500자 | 낮음 | 표/그래프 + 해석 |
| 12.6 요약 | 1,000자 | 낮음 | 표준 요약 절 |
| **합계** | **~15,000자** | — | 기준(2,000~4,000자/절) 내 |

---

## 12. Ch13 연결 예고 (12.6절 예고 내용)

12.6절에서 Ch13으로 이어지는 내용:

> "파이프라인 CPU를 완성했습니다. 그런데 실제 프로그램은 훨씬 더 큰 코드와 데이터를 다룹니다.
> IMEM과 DMEM이 FPGA 내부 BRAM에 모두 들어가는 지금은 괜찮지만,
> 대용량 메모리는 BRAM 바깥의 DDR SDRAM을 써야 합니다.
> DRAM 접근은 BRAM보다 10~100배 느립니다.
> 이 속도 차이를 숨겨주는 것이 **캐시(cache)**입니다."

---

*작성 완료: 2026-03-12*
*기술 저자 에이전트*
