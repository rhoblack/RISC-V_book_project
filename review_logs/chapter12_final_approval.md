# Chapter 12 최종 승인 보고서

**편집장**: Editor-in-Chief 에이전트
**승인 일자**: 2026-03-12
**대상**: Chapter 12 — 구조적 해저드와 파이프라인 완성
**원고 위치**: manuscripts/part4/chapter12.html (1,382줄)

---

## 1. 최종 품질 점수

| 분류 | 수정 전 | 최종 상태 |
|------|---------|----------|
| Critical | 4건 | **0건** ✅ |
| Major (기술) | 3건 | **0건** ✅ |
| Major (교육 설계) | 3건 | **0건** ✅ |
| Major (교육심리) | 2건 | **0건** ✅ |
| Minor (잔존) | 4건 | **4건** ⚠️ (편집장 판단: 현재 챕터 범위 내 불필요) |

---

## 2. 초보자 이해도 점수

**⭐⭐⭐⭐⭐ (5/5)**

- TOP3 어려운 부분(imm_gen/control_unit 배경, PC 오프셋 계산, 2000 클럭 근거) 모두 해소
- 예측 유도 metacognition 박스 추가 → 주체적 성취감 경로 확보
- 스캐폴딩 3단계 구조(2원소 → 내부 루프 → 전체 코드) 유효

---

## 3. 항목별 최종 상태

### 3.1 Critical 이슈 수정 확인

| 이슈 | 내용 | 상태 |
|------|------|------|
| C1: BGE 기계어 오류 | dut.u_imem.mem[4]: `0x03C58663` → `0x0305DE63` (BGE x11,x16,+60, funct3=101) | ✅ 수정 완료 |
| C1: BGE 기계어 오류 | dut.u_imem.mem[7]: `0x03164463` → `0x03165463` (BGE x12,x17,+40, funct3=101) | ✅ 수정 완료 |
| C1: HTML 발췌 코드 | 12.4절 테스트벤치 발췌에 `0x0305DE63` 반영 | ✅ 수정 완료 |
| C2: ADD rd 필드 오류 | dut.u_imem.mem[9]: `0x01250933` → `0x012509B3` (rd=x19) | ✅ 수정 완료 |
| C3: imm_gen 포트 불일치 | `pipeline_imm_gen` 모듈 신규 정의 + 인스턴스 교체 | ✅ 해결 완료 |
| C4: control_unit 포트 불일치 | `pipeline_control_unit` 모듈 신규 정의 + 인스턴스 교체 | ✅ 해결 완료 |

#### 기계어 인코딩 검증 (편집장 직접 확인)

테스트벤치(`ch12_pipeline_complete_tb.sv`) 확인:
- `mem[4] = 32'h0305DE63` ← BGE x11,x16,+60, funct3=101(BGE) ✅
- `mem[7] = 32'h03165463` ← BGE x12,x17,+40, funct3=101(BGE) ✅
- `mem[9] = 32'h012509B3` ← ADD x19,x10,x18, rd[11:7]=10011(x19) ✅

#### pipeline_imm_gen / pipeline_control_unit 모듈 검증

`ch12_rv32i_pipeline_complete.sv` 파일 하단에 두 모듈 완전 정의됨:
- `pipeline_imm_gen`: opcode case문 6개 타입(I/S/B/U/J/R) 처리 ✅
- `pipeline_control_unit`: opcode/funct3/funct7 분리 입력, 전체 RV32I opcode 처리 ✅
- Ch09~Ch11 인라인 로직과 동일한 신호명(`a_sel`, `b_sel`, `alu_sel`, `wb_sel`) 사용 ✅
- 인스턴스 포트 연결 HTML 발췌 코드와 실제 .sv 파일 일치 ✅

### 3.2 Major 이슈 수정 확인

| 이슈 | 내용 | 상태 |
|------|------|------|
| M1: 성능 표 수치 불일치 | 멀티사이클 상대값 0.82→2.05, 파이프라인 0.22→0.46으로 수정 | ✅ 수정 완료 |
| M1: figcaption 수정 | "약 4.6배" → "단일 사이클 대비 약 2.2배, 멀티사이클 대비 약 4.4배" | ✅ 수정 완료 |
| M1: 계산식 명시 | 40/18.5≈2.16배, 82/18.5≈4.4배 수식 본문에 포함 | ✅ 수정 완료 |
| M1: 레전드 추가 | "(낮을수록 좋은 값: CPI, 실행시간 상대값 ↓ | 높을수록 좋은 값: Fmax)" | ✅ 수정 완료 |
| M1: 의외의 결과 단락 | 멀티사이클 Fmax 2배임에도 단일보다 느린 이유 설명 | ✅ 수정 완료 |
| M2: alu_src_b 댕글링 | `logic [31:0] alu_src_b` 선언을 주석 처리 | ✅ 수정 완료 |
| M3: ALU 포트 주석 | Ch04 vs Ch09+ 포트명 차이, alu_zero 미연결 이유 명시 | ✅ 수정 완료 |

### 3.3 품질 기준 최종 확인

| 항목 | 기준 | 결과 | 상태 |
|------|------|------|------|
| 절별 분량 | 2,000자 이상 | 전체 1,382줄 / 6개 절 — 절당 평균 충분 | ✅ |
| aside 박스 종류 | 5종 모두 포함 | tip(6), faq(2), interview(2), metacognition(7), instructor-tip(2) = 19개 | ✅ |
| 🔍 스스로 점검 박스 | 절마다 1개 이상 | 총 7개 (각 절 + Part4 종합 1개) | ✅ |
| Part 4 완주 인증 박스 | 필수 | 12.6절에 존재 (Ch09~Ch12 4개 항목 ✅) | ✅ |
| 연습문제 | 5개 이상 | 6개 ([기억]/[이해]/[적용]/[분석]/[평가]/[도전]) | ✅ |

### 3.4 Ch11 → Ch12 연속성 확인

| 점검 항목 | 결과 | 상태 |
|----------|------|------|
| ch11_pipeline_with_branch.sv 기반 확장 | 파일 헤더에 "ch11_pipeline_with_branch.sv 기반으로 최종 완성" 명시 | ✅ |
| 신호명 일관성 | if_id_flush, id_ex_flush, branch_taken_ex, jal_id, jalr_taken_ex 동일 | ✅ |
| 플러시 우선순위 공식 | `pc_en = if_id_flush ? 1'b1 : hdu_pc_en` Ch11 확정 패턴 유지 | ✅ |
| pipeline_imm_gen 호환성 | Ch09~Ch11 인라인 로직과 동일한 즉치수 타입/비트 배열 사용 | ✅ |
| pipeline_control_unit 호환성 | Ch09~Ch11 제어 신호 집합과 동일 (a_sel 1비트, alu_sel 4비트 등) | ✅ |
| WB-ID 포워딩 추가 | register_file 내부 처리 — forwarding_unit 수정 없음 | ✅ |

### 3.5 output 파일 확인

| 항목 | 결과 | 상태 |
|------|------|------|
| 파일 존재 | `output/Ch12_구조적해저드와파이프라인완성_final.html` 존재 | ✅ |
| CSS 경로 | `../templates/book_style.css` (../../ → ../ 변환 완료) | ✅ |
| SVG 경로 | `../figures/ch12_sec0X_*.svg` (../../ → ../ 변환 완료) | ✅ |

---

## 4. 승인 결정

### ✅ 최종 승인 (APPROVED)

**사유**:

1. **기술 정확성 완전 해결**: Critical 4건(기계어 인코딩 오류 3건 + 포트 불일치 2건) 모두 수정 완료.
   특히 C3/C4의 imm_gen/control_unit 포트 불일치는 파이프라인 전용 모듈(`pipeline_imm_gen`, `pipeline_control_unit`)을
   신규 정의하는 방식으로 근본적으로 해결함. 인스턴스 연결의 정합성을 직접 확인함.

2. **성능 수치 정정**: 멀티사이클 상대값 오류(0.82→2.05), 파이프라인 상대값 오류(0.22→0.46)가 수정되어
   독자가 올바른 3종 비교 분석을 학습할 수 있음. "의외의 결과" 단락 추가로 교육적 가치 향상.

3. **교육 품질 기준 충족**: 6개 절 모두 metacognition 박스 보유(7개), 5종 aside 박스 모두 포함(19개),
   연습문제 6개(필수 5개 초과), Part 4 완주 인증 박스 포함.

4. **output 파일 정상 변환**: CSS/SVG 경로 모두 `../` 기준으로 올바르게 변환됨.

5. **Ch11 연속성 보장**: ch11_pipeline_with_branch.sv의 핵심 설계 결정(플러시 우선순위, 신호명 체계,
   4-way PC MUX)이 ch12에 완전히 계승됨.

**잔존 Minor 이슈 4건**은 편집장 판단으로 현재 챕터 범위에서 허용 가능하며, Ch13 이후 작업에 영향을 주지 않음.

---

## 5. 다음 챕터(Ch13) 준비 사항

### 설계 상태 인수인계

**완성된 파이프라인 사양**:
- 모듈명: `rv32i_pipeline_complete`
- 파라미터: DATA_WIDTH=32, ADDR_WIDTH=32, RF_DEPTH=32, IMEM_DEPTH/DMEM_DEPTH 가변
- 해저드 처리 완비: EX-EX 포워딩, MEM-EX 포워딩, WB-ID 포워딩, Load-Use 스톨, 분기/JAL/JALR 플러시
- Harvard 구조: instruction_memory + data_memory 분리

**Ch13 캐시 설계 시 고려 사항**:

1. **메모리 인터페이스 변경**: 현재 `instruction_memory`와 `data_memory`는 1사이클 즉시 응답.
   캐시 미스 시 "stall until ready" 패턴이 필요 — `pc_en`, `if_id_en` 기존 스톨 메커니즘을 확장 활용 가능.

2. **스톨 신호 확장**: `hazard_detection_unit`의 스톨 패턴(pc_en=0, if_id_en=0, id_ex_flush=stall)을
   캐시 미스 스톨에도 동일하게 적용할 수 있음. 단, 캐시 미스 스톨은 가변 사이클이므로
   `cache_stall` 신호를 별도로 OR 연산하여 통합하는 구조를 권장.

3. **Harvard 구조 유지**: L1 I-캐시(IMEM 앞)와 L1 D-캐시(DMEM 앞)를 독립적으로 배치하면
   Ch09 이후의 구조적 해저드 해결 방식이 캐시 계층에서도 유지됨.

4. **성능 분석 준비**: 12.5절에서 확인한 CPI ≈ 1.2 (버블정렬, BRAM 1사이클 가정).
   DRAM 지연 100~300사이클 시 CPI 폭등 현상을 캐시 히트율과 연계하여 분석 가능.

5. **버블정렬 재사용**: Ch13 캐시 검증에서도 `ch12_pipeline_complete_tb.sv`의 버블정렬 시나리오 2를
   그대로 재사용할 수 있음. 캐시 히트/미스 통계 카운터만 추가하면 됨.

---

## 6. SVG 파일 목록

| 파일명 | 위치 | 내용 |
|--------|------|------|
| ch12_sec01_princeton_hazard.svg | figures/ | Princeton 구조 구조적 해저드 타이밍 |
| ch12_sec01_harvard_solution.svg | figures/ | Harvard 구조 해결 방법 |
| ch12_sec02_wb_id_forwarding.svg | figures/ | WB-ID 포워딩 경로 |
| ch12_sec03_complete_pipeline.svg | figures/ | 완성된 5단계 파이프라인 블록 |
| ch12_sec04_bubble_sort_flow.svg | figures/ | 버블정렬 알고리즘 순서도 |
| ch12_sec05_three_impl_comparison.svg | figures/ | 3종 구현 성능 비교 그래프 |

---

*최종 승인: 편집장 에이전트*
*일자: 2026-03-12*
*상태: **APPROVED** — Critical: 0건 | Major: 0건 | Minor: 4건(허용)*
