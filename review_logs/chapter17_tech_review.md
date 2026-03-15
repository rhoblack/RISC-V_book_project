# Chapter 17 기술 검토 (Technical Review)
**검토자**: Technical Reviewer
**검토 대상**: manuscripts/part6/chapter17.html
**검토 일시**: 2026-03-15

---

## 검토 결과 요약

| 항목 | 판정 | 이슈 |
|------|------|------|
| **APB 프로토콜 정확성** | ✅ PASS | - |
| **AHB-to-APB 브리지 FSM** | ✅ PASS | - |
| **GPIO 컨트롤러** | ✅ PASS | - |
| **Timer 컨트롤러** | ✅ PASS | - |
| **UART 컨트롤러** | 🟡 MAJOR | 전체 코드 누락 |
| **합성 가능성** | ✅ PASS | - |
| **Basys 3 적합성** | ✅ PASS | - |

**최종 판정**: 🟡 **MAJOR 1건 수정 필요** → FAIL

---

## 1. APB 프로토콜 정확성 ✅

**신호 정의**: 정확 (PSEL, PENABLE, PWRITE, PWDATA, PRDATA, PREADY)
- ARM AMBA 3 APB Protocol v1.0 준수
- PSLVERR 선택사항으로 정확히 명시

**Setup/Enable 2단계**: 정확
- Setup Phase: PSEL=1, PENABLE=0 (최소 1클럭)
- Enable Phase: PSEL=1, PENABLE=1 (PREADY=1까지)
- 파이프라인 없음 설명 명확

**평가**: 🟢 표준 완벽 준수

---

## 2. AHB-to-APB 브리지 ✅

**FSM 상태 전이**: 정확
- ST_IDLE → ST_SETUP (htrans==NONSEQ 시)
- ST_SETUP → ST_ACCESS (항상 1클럭)
- ST_ACCESS → ST_IDLE/SETUP (pready 신호 기반)

**HREADY_OUT 제어**: 정확
- ST_IDLE: hready_out=1 (새 주소 수신 가능)
- ST_SETUP: hready_out=0 (addr_reg, write_reg 보호)
- ST_ACCESS: hready_out=pready (슬레이브 응답 전파)

**슬레이브 선택**: 정확
- One-hot 인코딩 (4KB 단위)
- addr[13:12] 기반 디코더

**평가**: 🟢 FSM/신호 제어 정확

---

## 3. UART 컨트롤러 🟡 MAJOR

**문서 내용**: 정확
- 8N1 포맷 (10비트/문자)
- 16× 오버샘플링 (노이즈 거부)
- 보드레이트 분주: baud_div = CLK_FREQ / (BAUD_RATE × 16)
- 115200 @ 100MHz: 54 (오차 0.47%)

**레지스터 맵**: 정확
- TX_DATA, RX_DATA, STATUS, CTRL, BAUD_DIV, INT_STATUS (W1C)

**⚠️ MAJOR 이슈**: 전체 코드 누락
- GPIO (17.4): 전체 코드 있음 (113줄)
- Timer (17.5): 전체 코드 있음 (164줄)
- UART: 스니펫만, 실제 모듈 구현 없음

**필요**: 17.3절에 apb_uart 전체 모듈 추가
- TX/RX FSM, FIFO, 보드레이트 분주기, 2-FF 동기화, W1C 인터럽트
- 예상 분량: 300~400줄

**심각도**: 🟡 MAJOR (교육 연속성 손상)

---

## 4. GPIO 컨트롤러 ✅

**메타안정성**: 정확 (2-FF 동기화기)
**출력 로직**: 정확 (gpio_out = out_reg & dir_reg, 버스 충돌 방지)
**인터럽트**: 정확 (상승 에지, 입력 핀만)

**평가**: 🟢 설계 정확

---

## 5. Timer 컨트롤러 ✅

**프리스케일러**: 정확
**업카운터**: 정확 (AUTO_RELOAD 주기적 인터럽트)
**W1C 인터럽트**: 정확 (단일 always_ff, if-else if 우선순위)

**평가**: 🟢 설계 정확

---

## 6. 시스템 통합 ✅

**PRDATA/PREADY MUX**: 정확
- One-hot psel
- pready=1'b1 (deadlock 방지)

**인터럽트**: 정확 (독립 배선)

**평가**: 🟢 통합 정확

---

## 7. 합성 가능성 ✅

**SystemVerilog**: IEEE 1800-2017 준수
**HTML 이스케이프**: 정확 (<→&lt;, >→&gt;, &→&amp;)

**평가**: 🟢 합성 가능

---

## 8. Basys 3 리소스 ✅

주변 장치 합계: ~500 LUT, ~400 FF (리소스의 1.5%, 0.6%)

**평가**: 🟢 리소스 여유

---

## 최종 판정

**Critical**: 0건
**Major**: 1건 (UART 코드 누락)
**Minor**: 0건

**전체**: 🟡 **FAIL** (수정 후 PASS 가능)

---

## 수정 지시사항

### M1: UART 전체 코드 추가

**파일**: manuscripts/part6/chapter17.html
**위치**: 17.3절 라인 699 이후
**내용**: apb_uart 전체 모듈 구현
**분량**: ~300~400줄

---

**검토 완료**: 2026-03-15
