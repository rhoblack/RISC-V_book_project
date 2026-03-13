# Ch16 종합 리뷰 회의록

작성자: 편집장 (Editor in Chief)
작성일: 2026-03-13
대상: manuscripts/part6/chapter16.html

---

## 편집장 최종 판정

**현재 상태: 미승인 — 수정 필수 항목 12건 완료 후 승인 가능**

| 리뷰어 | 평가 | 비고 |
|--------|------|------|
| 기술 리뷰어 | Critical 4건, Major 6건 | C1·C3·C4·M1·M5 즉시 수정 필요 |
| 초보자 독자 | ⭐⭐⭐⭐⭐ | 조건부 승인 (B항목 권고) |
| 교육 설계자 | ⭐⭐⭐⭐ | E1·E2 수정 후 승인 |
| 교육심리전문가 | ⭐⭐⭐⭐ | P2 수정 후 승인 |
| 교육전문강사 | ⭐⭐⭐⭐ | I1·I2·I3 수정 후 승인 |

**피드백 충돌 처리 원칙 적용**: 정확성(C항목) → 심리적안전(P항목) → 이해도(B·I항목) → 분량(E항목) 순으로 우선 처리.

---

## 수정 필수 항목 (승인 전 완료)

### C1: ahb_master_bridge — addr_lat 래치 타이밍 오류

- **위치**: 16.5절 코드 본문 (라인 575~579), 전체 소스 코드 섹션 (라인 1405~1407)
- **문제**: `state == M_ADDR && HREADY` 조건으로 래치하면, M_ADDR에서 HREADY=0이 되어 M_WAIT으로 전이할 때 래치가 갱신되지 않아 addr_lat에 리셋 초기값(0)이 남는다. 이 상태에서 M_WAIT의 HADDR 출력이 실제 요청 주소가 아닌 0을 구동하므로 AHB 프로토콜 위반이다.
- **수정 지시**: 래치 조건을 `state == M_IDLE && cache_req`로 변경한다. M_IDLE 마지막 사이클(M_ADDR 진입 직전)에 래치하면, 이후 M_ADDR에서 HREADY=0이 되어 M_WAIT으로 전이되더라도 올바른 값을 보유한다.
- **원본 코드**:
  ```
  // 주소 페이즈 진입 시 정보 래치
  // HREADY=0이면 갱신하지 않음 (신호 동결)
  if (state == M_ADDR && HREADY) begin
     addr_lat  <= cache_addr;
     write_lat <= cache_write;
     wdata_lat <= cache_wdata;
  end
  ```
- **수정 코드**:
  ```
  // M_IDLE → M_ADDR 전이 결정 사이클에 래치
  // (HREADY 조건 제거 — M_IDLE 마지막 사이클에서 캡처)
  if (state == M_IDLE && cache_req) begin
     addr_lat  <= cache_addr;
     write_lat <= cache_write;
     wdata_lat <= cache_wdata;
  end
  ```
- **적용 위치**: 16.5절 코드 본문 + 전체 소스 코드 섹션 두 곳 모두 수정.
- **C2 자동 해소**: C1 수정으로 wdata_lat도 올바르게 래치되므로 M_DATA의 HWDATA 오류도 해소됨.

---

### C3: ahb_sram_slave — Wait State FSM 실제 지연 수가 교재 설명과 불일치

- **위치**: 16.6절 Wait State FSM 코드 및 파라미터 주석 (라인 765~795)
- **문제**: S_WAIT + S_DONE 2상태 구조이므로 `WAIT_CYCLES=1`일 때 실제 지연은 S_WAIT(1사이클) + S_DONE(1사이클) = **2사이클**이다. 그러나 코드 주석과 파라미터 설명에 "WAIT_CYCLES=1이면 1사이클 Wait"이라 되어 있어 교재 설명과 실제 동작이 불일치한다. S_DONE 상태를 유지하되 파라미터 의미를 재정의하는 방향으로 수정한다.
- **수정 지시**:
  1. 파라미터 주석을 `// Wait State 수: 실제 지연 = WAIT_CYCLES + 1 (S_WAIT N사이클 + S_DONE 1사이클)`로 변경한다.
  2. 16.6절 본문에 "S_DONE은 HREADY_out=1을 올리는 '완료 공지' 사이클이므로, WAIT_CYCLES=1 설정 시 실제 HREADY_out=0 구간은 1사이클(S_WAIT)이고, 총 지연은 2사이클(S_WAIT + S_DONE)이다"라는 설명 박스를 추가한다.
- **원본 코드 (파라미터 부분)**:
  ```
  parameter WAIT_CYCLES = 1             // 삽입할 Wait State 수 (0이면 즉시 응답)
  ```
- **수정 코드**:
  ```
  parameter WAIT_CYCLES = 1             // HREADY=0 구간 사이클 수 (0이면 즉시 응답)
                                         // 실제 총 지연 = WAIT_CYCLES + 1 (S_DONE 사이클 포함)
  ```

---

### C4: ahb_sram_slave — 쓰기 always_ff에 HRESETn 비동기 리셋 없음

- **위치**: 16.6절 쓰기 동작 코드 (라인 801~805), 전체 소스 코드 섹션 (라인 1504~1507)
- **문제**: `always_ff @(posedge HCLK)`로만 선언되어 HRESETn 없다. Vivado에서 BRAM으로 추론될 경우 시뮬레이션 초기에 X-propagation이 발생할 수 있다.
- **수정 지시**: `initial` 블록을 추가하여 시뮬레이션 초기화를 처리한다. 합성 시에는 `initial` 블록이 무시되므로 기존 `always_ff` 구조는 유지한다.
- **원본 코드**:
  ```
  // ---- 쓰기 동작 (동기 로직) ----
  // 데이터 페이즈에서 HWDATA를 메모리에 기록
  // HREADY_out=1 AND write_lat=1 AND sel_lat=1 조건
  always_ff @(posedge HCLK) begin
     if (sel_lat && write_lat && HREADY_out) begin
        mem[addr_lat[($clog2(MEM_DEPTH)-1):0]] <= HWDATA;
     end
  end
  ```
- **수정 코드**:
  ```
  // ---- 메모리 초기화 (시뮬레이션 전용) ----
  // 합성 도구는 initial 블록을 무시함 — BRAM 초기화는 $readmemh 사용 권장
  initial begin
     for (int i = 0; i &lt; MEM_DEPTH; i++) mem[i] = 32'h0;
  end

  // ---- 쓰기 동작 (동기 로직) ----
  // 데이터 페이즈에서 HWDATA를 메모리에 기록
  // HREADY_out=1 AND write_lat=1 AND sel_lat=1 조건
  always_ff @(posedge HCLK) begin
     if (sel_lat &amp;&amp; write_lat &amp;&amp; HREADY_out) begin
        mem[addr_lat[($clog2(MEM_DEPTH)-1):0]] &lt;= HWDATA;
     end
  end
  ```

---

### M1: ahb_master_bridge — M_DATA에서 HREADY 미확인

- **위치**: 16.5절 다음 상태 로직 (라인 615~618), 전체 소스 코드 섹션 (라인 1423)
- **문제**: `M_DATA: next_state = M_DONE;`이 HREADY 확인 없이 무조건 전이한다. 데이터 페이즈에서도 슬레이브가 HREADY=0으로 추가 Wait을 요청할 수 있으므로 프로토콜 위반이다.
- **수정 지시**: M_DATA 상태에서 HREADY=1일 때만 M_DONE으로 전이하도록 수정한다.
- **원본 코드**:
  ```
  M_DATA: begin
     // 데이터 페이즈 완료
     next_state = M_DONE;
  end
  ```
- **수정 코드**:
  ```
  M_DATA: begin
     // HREADY=1일 때만 완료 (슬레이브가 추가 Wait을 요청할 수 있음)
     if (HREADY)
        next_state = M_DONE;
     // HREADY=0이면 M_DATA 유지 (HWDATA 동결)
  end
  ```
- **전체 소스 코드 섹션도 동일하게 수정**: `M_DATA: next_state = M_DONE;` → `M_DATA: if (HREADY) next_state = M_DONE;`

---

### M2: ahb_interconnect — HREADY MUX 제한사항 주석 추가

- **위치**: 16.7절 HREADY MUX 코드 (라인 929~936)
- **문제**: 현재 HREADY MUX는 현재 주소 페이즈 HSEL 기준으로 동작한다. 단일 전송(NONSEQ→IDLE) 패턴에서는 기능적으로 동작하지만, 연속 전송 시나리오에서는 오동작 가능성이 있다. 독자가 이 인터커넥트를 범용으로 사용하려 할 때 오류를 유발하지 않도록 제한사항을 명시한다.
- **수정 지시**: HREADY MUX 코드 블록 직전에 제한사항 주석을 추가한다.
- **원본 코드**:
  ```
  // ---- HREADY MUX (현재 사이클 HSEL 사용) ----
  // HREADY는 현재 진행 중인 전송의 슬레이브 준비 여부를 반영
  always_comb begin
     if      (HSEL_imem && HTRANS[1]) HREADY = HREADY_imem;
  ```
- **수정 코드**:
  ```
  // ---- HREADY MUX (현재 사이클 HSEL 사용) ----
  // HREADY는 현재 진행 중인 전송의 슬레이브 준비 여부를 반영
  // 주의: 이 HREADY MUX는 단일 전송(NONSEQ→IDLE) 패턴에만 올바르게 동작합니다.
  // 연속 전송(back-to-back NONSEQ) 또는 버스트 전송 시에는
  // hsel_imem_d/hsel_dmem_d 기반의 HREADY MUX로 변경해야 합니다.
  always_comb begin
     if      (HSEL_imem &amp;&amp; HTRANS[1]) HREADY = HREADY_imem;
  ```

---

### M5: SVA — `|=>` → `|->` 수정 (overlapping implication)

- **위치**: 16.8절 SVA 1번 p_addr_stable_on_wait (라인 1152~1155), SVA 2번 p_htrans_stable_on_wait (라인 1160~1163)
- **문제**: `|=>`는 "다음 사이클에 후행 조건 성립"을 의미하지만, AHB 스펙 요구사항은 "현재 사이클에 이미 안정적이어야 한다"이다. 따라서 `|->`(overlapping implication, 현재 사이클)로 수정해야 어서션이 프로토콜을 올바르게 표현한다.
- **수정 지시**: SVA 1번과 2번 모두 `|=>` → `|->`로 변경한다.
- **원본 코드 (SVA 1번)**:
  ```
  (HTRANS[1] &amp;&amp; !HREADY) |=&gt; $stable(HADDR);
  ```
- **수정 코드 (SVA 1번)**:
  ```
  (HTRANS[1] &amp;&amp; !HREADY) |-&gt; $stable(HADDR);
  ```
- **원본 코드 (SVA 2번)**:
  ```
  (HTRANS[1] &amp;&amp; !HREADY) |=&gt; $stable(HTRANS);
  ```
- **수정 코드 (SVA 2번)**:
  ```
  (HTRANS[1] &amp;&amp; !HREADY) |-&gt; $stable(HTRANS);
  ```

---

### E1: 16.4절 말미 중간 정리 박스 추가

- **위치**: 16.4절 "인터커넥트에서의 HREADY" 단락 직후 (`</section>` 태그 앞)
- **문제**: 16.4절은 Wait State 메커니즘과 마스터 의무를 설명하는 핵심 절이지만, 절 말미에 학습 내용을 정리하는 박스가 없어 독자가 다음 절로 넘어가기 전 점검 기회를 갖지 못한다.
- **수정 지시**: 16.4절 끝에 `<aside class="metacognition">` 중간 정리 박스를 추가한다.
- **추가 내용**:
  ```html
  <aside class="metacognition">
    <strong>🔍 16.4절 중간 정리 — Wait State 핵심 3가지:</strong>
    <ol>
      <li><strong>누가 HREADY를 구동하는가?</strong> 슬레이브(HREADY_out). 마스터는 읽기만 한다.</li>
      <li><strong>HREADY=0일 때 마스터가 해야 하는 것?</strong> HADDR, HTRANS, HSIZE, HWRITE, HWDATA, HBURST 전부 동결.</li>
      <li><strong>인터커넥트 HRDATA MUX는 무엇을 기준으로 선택하는가?</strong> 1사이클 지연된 HSEL_d. 현재 HSEL이 아님.</li>
    </ol>
    이 세 가지를 막힘 없이 말할 수 있다면 16.5절 코드 구현을 이해할 준비가 된 것입니다.
  </aside>
  ```

---

### E2: 16.3절 HTRANS 4종 표 — BUSY·SEQ 미사용 안내 순서 조정

- **위치**: 16.3절 HTRANS 표 직후 단락 (라인 306~310)
- **문제**: 표에 BUSY·SEQ가 먼저 등장하고, "이 챕터에서는 NONSEQ와 IDLE만 사용한다"는 안내가 표 아래에 위치한다. 학습자가 BUSY·SEQ를 먼저 보고 불필요한 인지 부하를 받을 수 있다.
- **수정 지시**: 표 앞에 "이 챕터에서는 NONSEQ와 IDLE만 사용합니다. BUSY와 SEQ는 버스트 전송(연습문제 4번)에서 다루므로 지금은 이름과 인코딩만 파악하면 됩니다"라는 안내 문장을 추가한다.

---

### P2: 실패 정상화 문구 추가

- **위치**: 16.5절 aside 팁 박스 또는 16.8절 테스트벤치 섹션 도입부
- **문제**: HWDATA 타이밍 오류는 AHB를 처음 구현하는 모든 설계자가 겪는 실수지만, 교재에 이를 정상화하는 문구가 없다. 학습자가 시뮬레이션에서 오류가 나면 자신만 실패한 것으로 느낄 수 있다.
- **수정 지시**: 16.5절 `<aside class="tip">` 박스에 아래 문구를 추가한다.
- **추가 내용**: "HWDATA 타이밍 오류는 AHB를 처음 구현하는 모든 설계자가 반드시 한 번씩 겪는 통과의례입니다. 시뮬레이션에서 Write 후 Read 값이 다르게 나왔다면 먼저 HWDATA가 HADDR보다 정확히 1사이클 늦게 유효해지는지 파형을 확인하십시오."

---

### I1: 고속도로 비유 — "서행" → "신호등 정지"로 수정

- **위치**: 16.4절 비유 박스 (라인 399)
- **문제**: "전방 공사 중, 서행하시오" 비유는 마스터가 속도를 늦추는 것을 암시하지만, AHB에서 HREADY=0은 완전한 정지(클록 사이클 동안 신호 유지)를 의미한다. "서행"은 부분적 감속을 연상시켜 오개념을 유발할 수 있다.
- **수정 지시**: "전방 공사 중, 서행하시오" → "전방 신호등 적색, 정지하시오"로 변경한다.
- **원본**:
  ```
  HREADY=0은 "전방 공사 중, 서행하시오" 표지판과 같습니다.
  ```
- **수정**:
  ```
  HREADY=0은 "전방 신호등 적색, 정지하시오" 표지판과 같습니다.
  신호등이 초록으로 바뀔 때(HREADY=1)까지 모든 신호를 그대로 유지해야 합니다.
  ```

---

### I2: 16.6절 Wait State FSM 텍스트 설명 추가

- **위치**: 16.6절 슬레이브 코드 직전 본문 (라인 710 이후, 코드 블록 시작 전)
- **문제**: 슬레이브 코드의 Wait State FSM(S_IDLE → S_WAIT → S_DONE) 동작을 텍스트로 설명하는 부분이 없다. 코드만 제시되어 있어 초보자가 FSM 상태 전이 의도를 파악하기 어렵다.
- **수정 지시**: 코드 블록 직전에 아래 설명 단락을 추가한다.
- **추가 내용**:
  ```
  <h3>Wait State FSM 동작</h3>
  <p>
    슬레이브는 3상태 FSM으로 Wait State를 관리합니다.
    <strong>S_IDLE</strong>: 유효한 전송이 감지되면(valid_transfer=1) S_WAIT으로 진입합니다. WAIT_CYCLES=0이면 즉시 HREADY_out=1을 유지합니다.
    <strong>S_WAIT</strong>: HREADY_out=0을 구동하여 마스터를 대기시킵니다. wait_cnt가 WAIT_CYCLES-1에 도달하면 S_DONE으로 전이합니다.
    <strong>S_DONE</strong>: HREADY_out=1을 구동합니다. 이 사이클에 마스터가 HRDATA를 캡처하고, 슬레이브는 S_IDLE로 복귀합니다.
    WAIT_CYCLES=1 설정 시 S_WAIT 1사이클 + S_DONE 1사이클 = 총 2사이클 지연이 발생합니다.
  </p>
  ```

---

### I3: HTRANS 표에 BUSY·SEQ 미사용 이유 안내 문구 추가

- **위치**: 16.3절 HTRANS 표 내 BUSY 및 SEQ 행 (라인 289~302)
- **문제**: 표에 BUSY와 SEQ가 등장하지만 이 챕터에서 사용하지 않는 이유가 명시되지 않아 학습자가 "왜 배우는가?"라는 의문을 가질 수 있다.
- **수정 지시**: 표 하단에 `<tfoot>` 또는 표 아래 `<p class="table-note">` 형태로 안내 문구를 추가한다.
- **추가 내용**:
  ```
  ※ 본 챕터(단일 전송)에서는 NONSEQ와 IDLE만 사용합니다.
     BUSY와 SEQ는 INCR4/INCR8 버스트 전송(연습문제 4번, Ch20 심화)에서 사용됩니다.
  ```

---

## 수정 권고 항목 (Optional)

### B1: HWDATA 1사이클 지연 인과 관계 보강 (16.3절)
- 타이밍 다이어그램 설명에서 "왜 HWDATA가 T2에서 유효한가"를 파이프라인 레지스터 비유와 명시적으로 연결하는 1~2문장 추가 권고.

### B2: M_WAIT 래치 변수 전제 조건 안내 (16.5절)
- M_WAIT 상태에서 `addr_lat`을 사용하는 코드 직전에 "이 변수는 M_IDLE → M_ADDR 전이 시점에 래치되었습니다(위 always_ff 블록 참조)"라는 주석 1줄 추가 권고.

### B3: HRDATA MUX vs HREADY MUX 차이 설명 (16.7절)
- HRDATA MUX는 HSEL_d(지연), HREADY MUX는 HSEL(현재)를 사용하는 이유를 표 또는 aside 박스로 병치 설명 추가 권고.

### B4: SVA 문법 한국어 의사코드 주석 (16.8절)
- `|->` 및 `$stable` 등 SVA 문법에 한국어 의사코드 주석 추가 권고.
  - 예: `// "현재 사이클에 HTRANS[1]=1이고 HREADY=0이면, 동시에 HADDR이 안정적이어야 한다"`

### E3: 자가 점검 질문 4 → 5개로 보강 (16.9절)
- 현재 4개의 자가 점검 질문에 1개 추가 권고.
  - 예: "M_WAIT 상태에서 addr_lat를 사용하는 이유를 한 문장으로 설명하십시오."

### E4: 16.6절 슬레이브 코드 후 3조건 래치 중간 정리 (16.6절)
- 슬레이브 코드 직후 `aside.tip` 박스에 HSEL, HTRANS[1], HREADY_in 3가지 래치 조건을 표 형식으로 정리 추가 권고.

### E5: 연습문제 블룸 L4 보강
- 연습문제 4번(적용, L3)과 6번(분석/평가, L5) 사이에 L4(분석) 수준 문항 추가 권고.
  - 예: "Wait State FSM에서 S_DONE 상태가 없고 S_WAIT 마지막 사이클에서 직접 HREADY_out=1을 올리는 방식으로 수정할 경우, 회로 동작과 WAIT_CYCLES 파라미터 의미에 어떤 변화가 생기는지 분석하십시오."

### P3: 챕터 완료 후 위상 명시 (16.9절)
- 16.9절 마무리 문단에 "Ch16을 완료하면 산업 표준 버스를 구현한 설계자가 된 것입니다. 이 챕터의 코드는 실제 Cortex-M 기반 SoC와 동일한 구조입니다" 등 위상 확인 문구 추가 권고.

### P4: 16.8절 TB 코드 일부 단계별 분해
- 테스트벤치 `initial` 블록의 시나리오 1~3을 코드 블록 밖에서 단계별 텍스트로 미리 안내 추가 권고.

### I4: 면접 포인트 분산
- 현재 16.7절에 면접 포인트가 집중되어 있다. 16.4절(HREADY 메커니즘)과 16.5절(Master FSM) 각 절에 1개씩 추가 분산 권고.

### I5: M_DONE 존재 이유 설명 추가 (16.5절)
- M_DONE 상태 설명에 "cache_ack=1을 1사이클 동안만 출력하기 위해 별도 상태가 필요하다. M_DATA에서 바로 M_IDLE로 전이하면 cache_ack 타이밍 처리가 복잡해진다"는 설계 의도 설명 추가 권고.

---

## 최종 승인 조건

| 항목 | 조건 | 현재 상태 |
|------|------|----------|
| Critical | 0건 | ❌ 4건 (C1~C4) |
| Major | 0건 | ❌ 6건 (M1~M6) |
| 초보자 이해도 | ⭐⭐⭐ 이상 | ✅ ⭐⭐⭐⭐⭐ |
| 교육 설계 | ⭐⭐⭐ 이상 | ⚠️ ⭐⭐⭐⭐ (E1·E2 수정 후 ⭐⭐⭐⭐⭐ 예상) |
| 심리적 안전성 | ⭐⭐⭐ 이상 | ⚠️ ⭐⭐⭐⭐ (P2 수정 후 ⭐⭐⭐⭐⭐ 예상) |
| 강의 적합도 | ⭐⭐⭐ 이상 | ⚠️ ⭐⭐⭐⭐ (I1~I3 수정 후 ⭐⭐⭐⭐⭐ 예상) |

**수정 완료 후 재검토 없이 자동 승인** (모든 수정 필수 항목 처리 시).

**수정 담당**: 기술 저자
**수정 순서**: C1 → C3 → C4 → M1 → M2 → M5 → E1 → E2 → P2 → I1 → I2 → I3
