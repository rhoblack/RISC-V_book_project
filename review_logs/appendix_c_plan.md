# Appendix C 기획: AMBA 프로토콜 퀵 레퍼런스

## 목표
Ch16~17(AMBA 버스) 학습 및 디버깅 시 신호 이름/방향/타이밍을 즉시 확인할 수 있는 프로토콜 참조 문서. AHB-Lite와 APB의 전체 신호를 한눈에 비교하고, 타이밍 다이어그램으로 전송 시퀀스를 확인하며, AHB-to-APB 브리지 FSM 상태 전이를 참조할 수 있도록 구성.

## 섹션 구분

1. **C.1 AHB-Lite 신호 목록 및 설명** — 전체 AHB-Lite 신호의 이름, 방향, 비트 폭, 설명
2. **C.2 AHB 타이밍 다이어그램** — 기본 전송, 파이프라인 전송, 웨이트 스테이트, 버스트 전송
3. **C.3 APB 신호 목록 및 설명** — 전체 APB 신호의 이름, 방향, 비트 폭, 설명
4. **C.4 APB 타이밍 다이어그램** — 쓰기/읽기 전송, 웨이트 스테이트
5. **C.5 AHB-to-APB 브리지 상태 전이도** — 프로토콜 변환 FSM 상세

## 콘텐츠 항목 상세

### C.1 AHB-Lite 신호 목록
- **표 1개** (중형): 약 18개 신호 × (신호명, 방향(Master/Slave), 비트 폭, 설명)
  - 예상 행: 20행
  - Master 신호: HADDR[31:0], HTRANS[1:0], HWRITE, HSIZE[2:0], HBURST[2:0], HWDATA[31:0], HPROT[3:0]
  - Slave 신호: HRDATA[31:0], HREADY, HREADYOUT, HRESP
  - 기타: HCLK, HRESETn, HSELx, HMASTLOCK
  - 본 교재 구현 범위 표시 (Ch16에서 사용하는 신호 강조)
- **표 1개** (소형): HTRANS 인코딩 (IDLE=00, BUSY=01, NONSEQ=10, SEQ=11)
- **표 1개** (소형): HBURST 인코딩 (SINGLE, INCR, WRAP4, INCR4, WRAP8, INCR8, WRAP16, INCR16)
- **표 1개** (소형): HSIZE 인코딩 (Byte, Halfword, Word, ...)

### C.2 AHB 타이밍 다이어그램
- **SVG 4개**:
  1. 기본 단일 전송 (`app_c_ahb_single.svg`): NONSEQ 전송의 주소 phase → 데이터 phase
  2. 파이프라인 전송 (`app_c_ahb_pipeline.svg`): 연속 NONSEQ 전송, 주소-데이터 오버랩
  3. 웨이트 스테이트 (`app_c_ahb_wait.svg`): HREADY=0 삽입, Master 주소 유지
  4. 버스트 전송 (`app_c_ahb_burst.svg`): INCR4 버스트, SEQ 전송 시퀀스
  - 각 SVG 크기: 약 800×250px
  - 파형 스타일: 클록, 신호명, 유효 데이터 구간 색상 표시

### C.3 APB 신호 목록
- **표 1개** (중형): 약 10개 신호 × (신호명, 방향(Requester/Completer), 비트 폭, 설명)
  - 예상 행: 12행
  - Requester(구 Master): PADDR[31:0], PSEL, PENABLE, PWRITE, PWDATA[31:0], PSTRB[3:0]
  - Completer(구 Slave): PRDATA[31:0], PREADY, PSLVERR
  - 기타: PCLK, PRESETn
  - 본 교재 구현 범위 표시 (Ch17에서 사용하는 신호 강조)

### C.4 APB 타이밍 다이어그램
- **SVG 2개**:
  1. APB 쓰기 전송 (`app_c_apb_write.svg`): SETUP → ACCESS phase, PSEL/PENABLE 타이밍
  2. APB 읽기 전송 + 웨이트 스테이트 (`app_c_apb_read_wait.svg`): PREADY=0 삽입
  - 각 SVG 크기: 약 800×200px

### C.5 AHB-to-APB 브리지 FSM
- **SVG 1개**: 브리지 FSM 상태 전이도 (`app_c_ahb2apb_fsm.svg`)
  - 상태: IDLE → AHB_DECODE → APB_SETUP → APB_ACCESS → AHB_RESP
  - 전이 조건: HSELx, HTRANS, PENABLE, PREADY
  - 크기: 약 700×400px
- **표 1개** (중형): FSM 각 상태별 출력 신호 값 (~6행)
- **코드 1개** (20~25줄): 브리지 FSM 핵심 로직 코드 조각 (Ch17에서 작성한 코드의 축약 참조)

## 사용성

- **주 사용 시점**: Ch16~17 학습 중 + Ch20(FPGA 합성) 시 버스 디버깅
- **선호 사용법**:
  1. 시뮬레이션 파형에서 AHB/APB 신호 의미 확인 (C.1, C.3)
  2. 전송 시퀀스가 정상인지 타이밍 다이어그램과 대조 (C.2, C.4)
  3. 브리지 FSM 동작이 예상과 다를 때 상태 전이도 참조 (C.5)
  4. 프로토콜 위반 디버깅 시 신호 방향/비트 폭 확인 (C.1, C.3)
- **인쇄 친화성**: A4 3~4페이지 (타이밍 다이어그램은 가로 레이아웃 권장)

## 예상 초안 생성 시간

- AHB 신호 표 + 인코딩 표: 0.5시간
- AHB 타이밍 SVG 4개: 1.5시간 (파형 SVG는 정밀한 클록 정렬 필요)
- APB 신호 표 + 타이밍 SVG 2개: 1시간
- 브리지 FSM SVG + 상태 표 + 코드: 0.5시간
- HTML 포맷팅: 0.5시간
- **총 4시간**

## 리뷰 포인트 (기술 리뷰어 주력)

- 🔴 **Critical**:
  - AHB-Lite 신호 목록이 ARM AMBA 3 AHB-Lite 스펙과 일치하는지
  - APB 신호 목록이 ARM AMBA APB 스펙(AMBA 2 또는 APB4)과 일치하는지
  - 타이밍 다이어그램에서 HREADY 동작: Slave가 LOW로 내릴 때 Master가 주소/제어 신호를 유지하는지 정확히 표현
  - 파이프라인 전송에서 주소-데이터 phase 오버랩이 정확한지
- 🟡 **Major**:
  - 브리지 FSM 상태 전이 조건이 Ch17 구현과 일치하는지
  - HTRANS/HBURST/HSIZE 인코딩 값의 정확성
  - 본 교재 구현 범위 표시가 Ch16~17 코드와 일치하는지
- 🟢 **Minor**:
  - 타이밍 다이어그램 시각적 명확성 (유효 데이터 구간 구분)
  - AHB/APB 신호 표 정렬 및 방향 표기 통일

## 생성 파일

- `manuscripts/appendices/appendix_c.html` (350줄 예상)
- `figures/app_c_ahb_single.svg`
- `figures/app_c_ahb_pipeline.svg`
- `figures/app_c_ahb_wait.svg`
- `figures/app_c_ahb_burst.svg`
- `figures/app_c_apb_write.svg`
- `figures/app_c_apb_read_wait.svg`
- `figures/app_c_ahb2apb_fsm.svg`
- 총 SVG 7개, 코드 조각 1개 (HTML 내장)
