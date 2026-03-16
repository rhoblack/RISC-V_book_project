# Appendix C 기술 리뷰 결과

> **리뷰어**: 기술 리뷰어
> **리뷰 대상**: manuscripts/appendices/appendix_c.html (496줄)
> **리뷰 일자**: 2026-03-16
> **검증 기준**: ARM IHI 0033A (AHB-Lite), ARM IHI 0024B (APB), 본문 Ch16~17 크로스 체크

---

## 🔴 Critical Issues (기술 오류)

### C-C1: AHB-Lite 신호 목록 완전성 ✅ PASS
모든 주요 신호 수록 확인:
- Global: HCLK, HRESETn ✅
- Master: HADDR[31:0], HTRANS[1:0], HWRITE, HSIZE[2:0], HBURST[2:0], HPROT[3:0], HWDATA[31:0], HMASTLOCK ✅
- Decoder: HSELx ✅
- Slave: HRDATA[31:0], HREADY, HREADYOUT, HRESP ✅

### C-C2: HTRANS 인코딩 ✅ PASS
- IDLE=2'b00, BUSY=2'b01, NONSEQ=2'b10, SEQ=2'b11 ✅ (IHI 0033A Table 3-2)

### C-C3: HBURST 인코딩 ✅ PASS
- SINGLE=000, INCR=001, WRAP4=010, INCR4=011, WRAP8=100, INCR8=101, WRAP16=110, INCR16=111 ✅ (IHI 0033A Table 3-3)

### C-C4: HSIZE 인코딩 ✅ PASS
- Byte=000, Halfword=001, Word=010, Doubleword=011 ✅ (IHI 0033A Table 3-1)

### C-C5: AHB Address Phase → Data Phase 파이프라인 ✅ PASS
- 그림 C.2 (파이프라인 전송) 설명: "전송 A의 Data Phase 동안 전송 B의 Address Phase가 동시 진행" ✅

### C-C6: HREADY Wait State 동작 ✅ PASS
- 215~216행: "HREADY=0일 때 Master는 주소/제어 신호를 변경하면 안 된다" ✅ (IHI 0033A Sec. 3.1)

### C-C7: APB 신호 목록 ✅ PASS
- Global: PCLK, PRESETn ✅
- Requester: PADDR[31:0], PSEL, PENABLE, PWRITE, PWDATA[31:0], PSTRB[3:0] ✅
- Completer: PRDATA[31:0], PREADY, PSLVERR ✅

### C-C8: APB 상태 전이 ✅ PASS
- 364행: SETUP Phase (PSEL=1, PENABLE=0) → ACCESS Phase (PSEL=1, PENABLE=1) ✅ (IHI 0024B Sec. 2.1)

### C-C9: APB PREADY Wait State 동작 ✅ PASS
- 그림 C.6 설명: "Completer가 PREADY=0으로 대기 상태 삽입" ✅

### C-C10: AHB-to-APB 브리지 FSM — 본문 Ch17 불일치 🔴

**본문 Ch17 브리지 FSM과 상태 수 불일치**
- **App C (464행)**: 4상태 — `ST_IDLE, ST_AHB_DECODE, ST_APB_SETUP, ST_APB_ACCESS`
- **본문 Ch17**: 3상태 — `ST_IDLE, ST_SETUP, ST_ACCESS`
- **Ch17 코드 (444~446행)**: `ST_IDLE = 2'b00, ST_SETUP = 2'b01, ST_ACCESS = 2'b10`

**상세 분석**:
1. App C의 `ST_AHB_DECODE` 상태는 Ch17에 존재하지 않음
2. App C에서 `ST_AHB_DECODE`의 HREADY=1, PSEL=0 — 이 상태는 Ch17에서 ST_IDLE 상태에서 주소 래치를 처리하는 것과 동일 기능
3. Ch17은 ST_IDLE에서 직접 `htrans == HTRANS_NONSEQ` 확인 후 ST_SETUP으로 전이
4. App C의 `HREADY` 출력도 다름:
   - App C `ST_APB_SETUP`: HREADY=0 ✅
   - Ch17 `ST_SETUP`: HREADY=0 ✅ (일치)
   - App C `ST_AHB_DECODE`: HREADY=1
   - Ch17: 해당 상태 없음

**수정 제안**: App C의 브리지 FSM을 Ch17과 동일한 3상태(ST_IDLE, ST_SETUP, ST_ACCESS)로 통일. 또는 "본 부록의 4상태 FSM은 개념적 설명이며, 실제 구현(Ch17)은 3상태로 최적화되었다"는 주석 추가.

---

## 🟡 Major Issues

### C-M1: 신호 활성 수준 표기 ✅ PASS
- HRESETn: "액티브 로우 리셋" 명시 ✅
- PRESETn: "액티브 로우 리셋" 명시 ✅

### C-M2: AHB-Lite 전용 명시 ✅ PASS
- 52행: "AHB-Lite는 단일 마스터(Single Master) 버전" 명시 ✅

### C-M3: PSLVERR 포함 ✅ PASS
- 343~346행: PSLVERR 포함, Ch17 사용 표시 ✅

### C-M4: APB 신호 방향 표기 불일치 🟡
- **위치**: 288~309행
- **문제**: APB 신호의 방향을 "Requester" / "Completer"로 표기했는데, 이는 AMBA 5 APB 용어임. 본문 Ch17에서는 "Master" / "Slave" 용어를 사용할 가능성이 높음. 또한 AHB 섹션에서는 "Master" / "Slave" 사용.
- **수정 제안**: AHB와 APB 간 용어 통일. APB도 "Master" / "Slave" 또는 둘 다 병기: "Requester(Master)"

### C-M5: HRESP 비트폭 설명 보완 필요 🟡
- **위치**: 162행
- **문제**: "0=OKAY, 1=ERROR (AHB-Lite에서 1비트)"로 표기. 정확하지만, Full AHB에서는 2비트(OKAY/ERROR/RETRY/SPLIT)라는 차이점을 명시하면 이해에 도움
- **수정 제안**: 비고에 "(Full AHB는 2비트)" 추가

### C-M6: 브리지 FSM 코드에서 HREADY 출력 로직 오류 🟡
- **위치**: 464~465행
- **문제**: `assign hready_out = (state == ST_APB_SETUP) ? 1'b0 : (state == ST_APB_ACCESS) ? pready : 1'b1;`
  - ST_AHB_DECODE에서 HREADY=1로 출력하는데, 이때 AHB Master는 다음 주소를 보낼 수 있음. 실제로는 ST_AHB_DECODE 상태에서 HREADY를 즉시 1로 하면 다음 전송의 Address Phase가 시작될 수 있어 back-to-back 전송 시 문제 발생 가능
- **수정 제안**: Ch17의 3상태 FSM으로 통일하면 이 이슈도 해결됨

---

## 🟢 Minor Issues

### C-m1: 다이어그램 색상 코딩 — SVG 미확인
- SVG 파일이 존재하는지 확인 필요 (app_c_ahb_single.svg 등). 내용 검증은 SVG 파일 리뷰 시 수행

### C-m2: AMBA 버전 표기 🟢
- **위치**: 482행 footer
- **문제**: "ARM AMBA 3 AHB-Lite Protocol Specification | ARM AMBA APB Protocol Specification (APB4)"
- APB를 "APB4"로 표기했으나, 실제 PSTRB(APB4 전용)은 미사용으로 표시. APB4를 지칭할 것인지, APB3를 지칭할 것인지 명확히 해야 함
- **수정 제안**: 본문에서 PSLVERR 사용(APB3+), PSTRB 미사용이므로 "AMBA 3 APB (APB3)"가 더 정확. 또는 "AMBA APB Protocol Specification v2.0 (IHI 0024B)"로 표기

---

## 본문 일관성 크로스 체크

| 항목 | App C | Ch17 본문 | 일치 |
|------|-------|----------|------|
| 브리지 FSM 상태 수 | 4상태 | 3상태 | ❌ **불일치** |
| 브리지 상태 이름 | ST_IDLE, ST_AHB_DECODE, ST_APB_SETUP, ST_APB_ACCESS | ST_IDLE, ST_SETUP, ST_ACCESS | ❌ **불일치** |
| HREADY 출력 (SETUP) | 0 | 0 | ✅ |
| HREADY 출력 (ACCESS) | pready | pready | ✅ |
| AHB 신호명 | HADDR, HTRANS 등 | 동일 | ✅ |
| APB 신호명 | PADDR, PSEL 등 | 동일 | ✅ |

---

## 요약

| 분류 | 건수 | 상세 |
|------|:----:|------|
| 🔴 Critical | **1건** | C-C10(브리지 FSM 본문 불일치: 4상태 vs 3상태) |
| 🟡 Major | **3건** | C-M4(Requester/Master 용어 불일치), C-M5(HRESP 비고), C-M6(HREADY 로직) |
| 🟢 Minor | **2건** | C-m1(SVG 미확인), C-m2(AMBA 버전 표기) |

**기술 리뷰어 판정**: Critical 1건(브리지 FSM 불일치) 수정 필수. Ch17 본문과 통일이 최우선.
