# Ch23 기술 리뷰 — 성능 최적화 기법

**리뷰어**: 기술 리뷰어 (Technical Reviewer)
**대상 원고**: manuscripts/part9/chapter23.html
**대상 코드**: ch23_dual_issue_checker.sv, ch23_tournament_predictor.sv, ch23_reservation_station_sim.sv, ch23_dual_issue_top.sv, ch23_tournament_predictor_tb.sv
**일자**: 2026-03-15

---

## 1. 코드 정확성

### ch23_dual_issue_checker.sv
- **평가**: 정확함
- RAW 해저드 검사 로직이 올바름: `a_reg_wen && (a_rd != 5'd0)` 조건으로 x0 포워딩 오류를 정확히 방지
- 자원 충돌(메모리 포트 단일) 검사 정확
- 제어 의존성(A가 분기 시 B 차단) 정확
- 순수 조합 로직으로 합성에 문제 없음

### ch23_tournament_predictor.sv (독립 코드 파일)
- **평가**: 정확하나 Minor 이슈 있음
- GHR 시프트, 2-bit 포화 카운터 상태 전이 모두 정확
- 선택기 갱신 로직(두 예측이 다를 때만 갱신) 정확
- gshare 인덱싱이 본문(HTML)과 독립 코드 파일에서 **다른 방식**으로 구현됨 (M1 참조)
- `predict_en_i` 기반 출력 게이팅은 좋은 설계

### ch23_reservation_station_sim.sv
- **평가**: 정확함 (behavioral 모델)
- `synthesis translate_off/on` 적절히 사용
- CDB 브로드캐스트 수신 → 오퍼랜드 갱신 로직 정확
- 빈 엔트리/실행 가능 엔트리 우선순위 검색 정확
- 이슈와 실행이 같은 사이클에 발생할 때의 동작이 명확 (이슈가 먼저, 실행이 나중)

### ch23_dual_issue_top.sv
- **평가**: 정확함
- `dual_issue_fetch_unit`: PC+8 증가, 64비트 인출, NOP 삽입, flush/stall 처리 모두 정확
- `simple_decoder`: RV32I opcode 매핑 정확 (R-type, I-type, Load, Store, B-type, LUI, AUIPC, JAL, JALR)
- SYSTEM 명령어(ECALL/EBREAK, opcode 7'b1110011)는 미구현이나, 스켈레톤 수준이므로 적합
- Way B는 ALU 전용이라는 제약이 파일 헤더에만 명시되고 코드에는 반영되지 않음 (스켈레톤이므로 OK)

### ch23_tournament_predictor_tb.sv
- **평가**: 정확함
- 4가지 테스트 시나리오(루프, 교대, 중첩 루프, 상관 분기) 적절
- 예측률 측정 로직 정확
- `do_branch` 태스크에서 예측→갱신 순서가 올바름
- VCD 파형 덤프 포함

---

## 2. ISA 준수

- **RV32I opcode 필드**: `simple_decoder`에서 사용한 opcode 값들이 모두 RV32I 스펙에 정확히 부합
  - R-type: 7'b0110011 ✅
  - I-type ALU: 7'b0010011 ✅
  - Load: 7'b0000011 ✅
  - Store: 7'b0100011 ✅
  - B-type: 7'b1100011 ✅
  - LUI: 7'b0110111 ✅
  - AUIPC: 7'b0010111 ✅
  - JAL: 7'b1101111 ✅
  - JALR: 7'b1100111 ✅
- rs1/rs2/rd 비트 필드 위치 정확: rs1=[19:15], rs2=[24:20], rd=[11:7]
- 의존성 검사에서 x0 특수 처리 정확 (`a_rd != 5'd0`)

---

## 3. 합성 가능성

### 합성 가능 코드 (3개)
| 파일 | 합성 가능 | 비고 |
|------|----------|------|
| ch23_dual_issue_checker.sv | ✅ | 순수 조합 로직, 문제 없음 |
| ch23_tournament_predictor.sv | ✅ | 메모리 배열은 LUTRAM으로 합성됨 |
| ch23_dual_issue_top.sv | ✅ | fetch unit + decoder, 스켈레톤 |

### Behavioral 코드 (2개)
| 파일 | 합성 불가 명시 | 비고 |
|------|--------------|------|
| ch23_reservation_station_sim.sv | ✅ (파일 헤더에 명시) | `synthesis translate_off/on` 적절 |
| ch23_tournament_predictor_tb.sv | ✅ (테스트벤치) | `$display`, `$finish` 사용 |

- tournament_predictor.sv의 `integer i` 선언과 `for` 루프 초기화는 합성 도구에서 지원됨 (Vivado/Quartus 모두 OK)
- 독립 코드 파일의 `int` 타입 사용 (dual_issue_top.sv의 simple_decoder)도 합성 가능

---

## 4. Basys 3 리소스

### tournament_predictor.sv 리소스 추정
- **Global PHT**: 256 × 2-bit = 512 FF (또는 1 LUTRAM)
- **Local PHT**: 64 × 2-bit = 128 FF
- **LHR**: 256 × 8-bit = 2048 FF (또는 LUTRAM)
- **GHR**: 8 FF
- **Chooser**: 256 × 2-bit = 512 FF
- **총 추정**: ~3,200 FF 또는 LUTRAM 4~6개
- **Basys 3 (XC7A35T)**: FF 41,600개, LUT 20,800개 → **적합** (약 8% FF 사용)

### dual_issue_checker.sv
- 순수 조합 로직, 비교기 2개 + AND/OR 게이트 → LUT 수 개 수준 → **적합**

### dual_issue_top.sv (완성 시)
- 스켈레톤이므로 정확한 추정 불가하나, 2-이슈 파이프라인 완성 시 Basys 3에는 타이트할 수 있음
- 본문에서 "Basys 3에서 합성 가능한 수준은 토너먼트 예측기뿐"이라고 명시하여 적절

---

## 5. Critical 이슈

**(없음)**

모든 코드에서 기술 오류나 합성 불가 문제가 발견되지 않았습니다.

---

## 6. Major 이슈

### 🟡 M1: HTML 본문과 독립 코드 파일의 토너먼트 예측기 구현 불일치

**위치**: HTML (line 294~393) vs ch23_tournament_predictor.sv

HTML 본문의 토너먼트 예측기와 독립 코드 파일의 구현이 **인터페이스와 내부 구조 모두** 다릅니다:

| 항목 | HTML 본문 버전 | 독립 코드 파일 버전 |
|------|---------------|-------------------|
| 파라미터 이름 | PHT_BITS, GHR_BITS, LHR_BITS, LHT_BITS | PC_WIDTH, LOCAL_DEPTH, GLOBAL_DEPTH, GHR_WIDTH, LOCAL_HIST_W |
| 전역 인덱싱 | `PC XOR GHR` (gshare) | `GHR`만 사용 (PC XOR 없음) |
| 포트 이름 | pred_pc, pred_taken, update_valid, update_pc, update_taken | pc_i, predict_taken_o, update_en_i, update_pc_i, actual_taken_i |
| predict_en | 없음 (항상 예측) | 있음 (predict_en_i) |
| 선택기 갱신 | 갱신 전 예측값 기반 | 갱신 후 PHT 값 기반 |

**문제점**:
1. **전역 인덱싱**: 독립 코드 파일(line 107)은 `ghr[IDX_W-1:0]`만 사용하여 PC를 XOR하지 않음. 이는 본문에서 설명하는 gshare 방식이 아님. 동일 GHR 상태에서 서로 다른 PC의 분기가 같은 PHT 엔트리를 공유하게 되어 alias 문제가 발생함.
2. **선택기 갱신 타이밍**: 독립 코드 파일(line 141-142)은 갱신 시점에 이미 변경된 PHT 값(같은 always_ff 블록 내 non-blocking이므로 실제로는 이전 값)을 읽는데, 이는 의도한 동작이지만 본문의 `upd_global_pred`/`upd_local_pred` (갱신 전 조합 로직으로 미리 계산)와 접근 방식이 다름.
3. 테스트벤치가 독립 코드 파일 버전을 테스트하므로 TB 자체는 정합성 있음.

**권고**: 두 버전을 통일하거나, 본문에 "전체 소스 코드 섹션의 구현은 교육적 명확성을 위해 단순화한 버전"임을 명시.

### 🟡 M2: 독립 코드 파일 tournament_predictor.sv — 전역 PHT 인덱싱에 PC XOR 누락

**위치**: ch23_tournament_predictor.sv, line 107-108

```systemverilog
assign global_pht_pred_idx = ghr[IDX_W-1:0];
assign global_pht_upd_idx  = ghr[IDX_W-1:0];
```

본문에서 gshare 방식(`PC XOR GHR`)을 핵심 개념으로 설명하고 있으나, 독립 코드 파일에서는 GHR만으로 인덱싱합니다. 이는:
- 서로 다른 PC 주소의 분기가 동일 GHR 상태에서 같은 PHT 엔트리를 사용 → alias 증가
- 본문의 그림 23.3("GHR XOR PC")과 불일치

**권고**: `global_pht_pred_idx = pc_i[IDX_W+1:2] ^ ghr[IDX_W-1:0]` 으로 수정하여 gshare 구현.

### 🟡 M3: HTML 본문 내 코드에서 `integer i` 사용

**위치**: HTML line 356

```systemverilog
integer i;
always_ff @(posedge clk or negedge rst_n) begin
```

SystemVerilog에서는 `integer` 대신 `int` 또는 `for (int i = ...)` 블록 내 선언이 권장됩니다. 독립 코드 파일에서는 `int`를 사용하여 일관성이 없습니다. `integer`는 합성에 문제는 없으나, IEEE 1800-2017 스타일로는 `int`가 표준입니다.

**권고**: 본문 코드를 독립 코드 파일과 동일하게 `for (int i = ...)` 방식으로 통일.

---

## 7. Minor 이슈

### 🟢 m1: dual_issue_checker — WAW 해저드 미검사

**위치**: ch23_dual_issue_checker.sv

본문 FAQ에서 "in-order에서는 WAW가 자연스럽게 해결된다"고 설명하고 있으나, 2-이슈에서는 동일 사이클에 두 명령어가 같은 rd에 쓸 경우 WB 포트 충돌이 발생할 수 있습니다. FAQ 답변(line 811-814)에서 이를 언급하고 있으나, 발급 검사기 코드에 WAW 검사를 추가하는 것이 더 안전합니다.

**권고**: 발급 검사기에 `waw_hazard = a_reg_wen && b_reg_wen && (a_rd == b_rd) && (a_rd != 5'd0)` 추가를 고려. 또는 본문에서 "단순화를 위해 생략, 실제 구현 시 추가 필요"라고 명시.

### 🟢 m2: reservation_station_sim — 동시 이슈+CDB+실행 우선순위 경합

**위치**: ch23_reservation_station_sim.sv, line 92-146

같은 사이클에 CDB 수신, 이슈, 실행 해제가 모두 발생할 때:
- CDB가 먼저 처리되고 (rdy 갱신)
- 이슈가 다음 (새 엔트리 추가)
- 실행 해제가 마지막 (busy 클리어)

이 순서는 non-blocking 할당으로 인해 모두 같은 사이클 끝에 반영되므로 정확하지만, 같은 엔트리에 이슈와 해제가 동시에 발생하면 예측 불가능한 동작이 될 수 있습니다. Behavioral 모델이므로 문제는 아니지만, 교육적으로 주석을 추가하면 좋겠습니다.

### 🟢 m3: 명령어 추적 예제 — I2 실행 시작 타이밍

**위치**: HTML line 568-572

I2(`ADD x2, x1, x3`)는 C6에 CDB로 x1 값을 수신한다고 설명하나, 실행 시작이 C7, 실행 완료도 C7로 되어 있습니다. ADD가 1사이클이므로 C7 시작/C7 완료는 정확합니다. 다만 "C6에 x1 수신" 후 "C7에 실행 시작"이라는 1사이클 갭이 CDB 수신 → 다음 사이클 디스패치라는 것을 본문에서 명시적으로 설명하면 좋겠습니다.

### 🟢 m4: HTML 전체 소스 코드 섹션 — reservation_station_sim 누락

**위치**: HTML line 950~1121

전체 소스 코드 섹션에 3개 파일만 포함(dual_issue_checker, tournament_predictor, dual_issue_top). `ch23_reservation_station_sim.sv`와 `ch23_tournament_predictor_tb.sv`가 누락되어 있습니다.

**권고**: 전체 소스 코드 섹션에 5개 파일 모두 포함, 또는 behavioral 모델과 TB는 별도 안내 문구 추가.

### 🟢 m5: HTML 본문과 전체 소스 코드 섹션의 tournament_predictor 불일치

**위치**: HTML line 294~393 (본문) vs line 993~1074 (전체 소스)

본문의 코드(gshare 방식, PHT_BITS 파라미터)와 전체 소스 코드 섹션의 코드가 동일한 반면, 독립 코드 파일(ch23_tournament_predictor.sv)과는 다릅니다. 본문+전체소스 vs 독립파일의 이원 구조가 혼란을 줄 수 있습니다.

---

## 8. 종합 평가

| 항목 | 평가 |
|------|------|
| 기술 정확성 | ⭐⭐⭐⭐ (4/5) — 코드 자체는 정확하나 본문/독립파일 불일치 |
| 코드 품질 | ⭐⭐⭐⭐ (4/5) — 주석 충실, 구조 명확, 스타일 일관성 Minor 이슈 |
| ISA 준수 | ⭐⭐⭐⭐⭐ (5/5) — RV32I opcode/필드 완벽 준수 |
| 합성 가능성 | ⭐⭐⭐⭐⭐ (5/5) — 합성 가능/불가 구분 명확 |
| Basys 3 적합성 | ⭐⭐⭐⭐⭐ (5/5) — 합성 대상 모듈 리소스 적합 |
| Part 9 심화 수준 적합성 | ✅ — 개념 이해 중심, 합성 범위 명확히 구분 |

### 최종 판정

- **Critical**: 0건
- **Major**: 3건 (M1, M2, M3)
- **Minor**: 5건 (m1~m5)

**Major 이슈 핵심**: HTML 본문에서 gshare(PC XOR GHR)를 핵심으로 설명하면서 독립 코드 파일에서는 GHR만 사용하는 불일치가 가장 큰 문제입니다. 학생이 본문을 읽고 코드를 보면 혼란이 예상됩니다. M1과 M2를 해결하면 Major 0건 달성 가능합니다.
