# Appendix D 기획: Basys 3 FPGA 리소스 및 핀 배치

## 목표
Ch01(환경 구축)부터 Ch22(최종 데모)까지 FPGA 합성 시 반복적으로 참조하는 Basys 3 보드의 하드웨어 사양을 집약. XC7A35T 리소스 제약, 전체 핀 배치, 클록/리셋 회로를 한 곳에서 확인할 수 있도록 구성하여, XDC 파일 작성과 리소스 예산 관리를 지원.

## 섹션 구분

1. **D.1 XC7A35T 리소스 요약** — Artix-7 FPGA의 전체 하드웨어 리소스와 본 프로젝트 사용 예산
2. **D.2 Basys 3 보드 I/O 배치 개요** — 보드 블록 다이어그램 및 주요 인터페이스
3. **D.3 전체 핀 배치 표 (XDC 레퍼런스)** — LED, 스위치, 버튼, 7-세그먼트, UART, PMOD, VGA 핀 매핑
4. **D.4 시스템 클록 및 리셋 회로** — 100MHz 클록 입력, 클록 분주/PLL, 리셋 동기화
5. **D.5 프로젝트 리소스 사용량 이력** — 챕터별 합성 결과 리소스 사용 비교

## 콘텐츠 항목 상세

### D.1 XC7A35T 리소스 요약
- **표 1개** (중형): 리소스 타입 × (전체 개수, 본 프로젝트 예상 사용량, 사용률)
  - 예상 행: 12행
  - 항목: CLB Slices, LUT (20,800), FF (41,600), BRAM 36Kb (50), BRAM 18Kb (100), DSP48E1 (90), IOB, BUFG (32), MMCM/PLL (5), GTP Transceiver (0)
  - 본 프로젝트 예상: 파이프라인+캐시+AMBA = LUT ~60-70%, BRAM ~30%, DSP ~5%
- **표 1개** (소형): BRAM 활용 계획 (~6행)
  - IMEM: 16KB = 4×36Kb BRAM
  - DMEM: 16KB = 4×36Kb BRAM
  - I-Cache Data: 4KB = 1×36Kb BRAM
  - I-Cache Tag: LUTRAM
  - D-Cache Data: LUTRAM (조합 읽기)

### D.2 Basys 3 보드 I/O 배치 개요
- **SVG 1개**: Basys 3 보드 블록 다이어그램 (`app_d_basys3_block.svg`)
  - FPGA 중앙, 주변에 LED×16, 스위치×16, 7-세그먼트×4, 버튼×5, USB-UART, PMOD×4, VGA
  - 크기: 약 800×500px
  - 각 인터페이스에 핀 개수 표시

### D.3 전체 핀 배치 표
- **표 5개**:
  1. **LED 16개** (~18행): LED[0]~LED[15] × (FPGA 핀, I/O 표준, XDC 구문)
  2. **스위치 16개** (~18행): SW[0]~SW[15] × (FPGA 핀, I/O 표준, XDC 구문)
  3. **버튼 5개** (~7행): btnC/U/L/R/D × (FPGA 핀, I/O 표준, XDC 구문)
  4. **7-세그먼트 디스플레이** (~14행): CA~CG, DP, AN[0]~AN[3] × (FPGA 핀, I/O 표준, XDC 구문)
  5. **UART + PMOD + 클록** (~12행): USB-UART TX/RX, PMOD JA~JD 핀, 100MHz 클록
  - 각 행에 바로 복사 가능한 XDC `set_property` 구문 포함

### D.4 시스템 클록 및 리셋 회로
- **SVG 1개**: 클록/리셋 회로 블록 다이어그램 (`app_d_clk_rst.svg`)
  - 100MHz 오실레이터 → MMCM/PLL → 50MHz 시스템 클록
  - 비동기 리셋 입력 (btnC) → 리셋 동기화기 (2단 FF) → 동기 리셋 출력
  - 크기: 약 700×300px
- **코드 2개** (각 15~20줄):
  1. 클록 분주/PLL 인스턴스 (`ch_appd_clk_gen.sv`): Vivado Clocking Wizard 또는 수동 MMCM 인스턴스
  2. 리셋 동기화기 (`ch_appd_rst_sync.sv`): 2단 FF 동기화 + 디바운서
- **텍스트**: 왜 비동기 리셋을 동기화해야 하는지, 메타스태빌리티 설명 (2~3문단)

### D.5 프로젝트 리소스 사용량 이력
- **표 1개** (대형): 챕터별 합성 결과 비교 (~8행)
  - 열: 챕터/구성, LUT, FF, BRAM, DSP, Fmax(MHz), WNS(ns)
  - 행: Ch06(단일사이클), Ch08(멀티사이클), Ch12(파이프라인), Ch13(+I-Cache), Ch14(+D-Cache), Ch15(+메모리컨트롤러), Ch17(+AMBA+주변장치), Ch22(최종 SoC)
  - 이 표는 실제 합성 결과로 채워야 하므로, 템플릿 상태로 제공 (추후 기입)

## 사용성

- **주 사용 시점**: Ch01(보드 설정), Ch06/Ch12(합성), Ch20(타이밍 최적화), Ch22(최종 데모)
- **선호 사용법**:
  1. XDC 파일 작성 시 핀 배치 표에서 구문 복사 (D.3)
  2. 합성 결과에서 리소스 사용률이 높을 때 예산 확인 (D.1)
  3. 클록/리셋 회로 설계 시 참조 코드 복사 (D.4)
  4. 챕터별 리소스 증가 추세 확인 (D.5)
- **인쇄 친화성**: A4 4~5페이지 (핀 배치 표가 큼)

## 예상 초안 생성 시간

- XC7A35T 리소스 표 + BRAM 계획: 0.5시간
- 보드 블록 다이어그램 SVG: 0.5시간
- 핀 배치 표 5개 (Basys 3 매뉴얼 대조): 1시간
- 클록/리셋 SVG + 코드 2개: 1시간
- 리소스 이력 표 템플릿 + HTML 포맷팅: 0.5시간
- **총 3.5시간**

## 리뷰 포인트 (기술 리뷰어 주력)

- 🔴 **Critical**:
  - XC7A35T 리소스 수치가 Xilinx 데이터시트(DS180)와 일치하는지
  - 핀 배치가 Basys 3 Reference Manual (Rev C) 및 공식 XDC 파일과 일치하는지
  - I/O 표준 (LVCMOS33 등)이 각 핀에 올바르게 지정됐는지
  - 클록 입력 핀 (W5)과 PLL 설정이 Basys 3 하드웨어와 일치하는지
- 🟡 **Major**:
  - 리셋 동기화 코드가 합성 가능하고 메타스태빌리티를 올바르게 처리하는지
  - BRAM 사용량 계획이 본문 캐시 설계(Ch13~15)와 일치하는지
  - MMCM/PLL 인스턴스 코드가 Artix-7 프리미티브와 호환되는지
- 🟢 **Minor**:
  - 보드 블록 다이어그램의 시각적 정확성
  - 핀 배치 표의 순서/그룹화 일관성
  - 리소스 이력 표의 열 정의 명확성

## 생성 파일

- `manuscripts/appendices/appendix_d.html` (450줄 예상)
- `figures/app_d_basys3_block.svg`
- `figures/app_d_clk_rst.svg`
- `code_examples/ch_appd_clk_gen.sv`
- `code_examples/ch_appd_rst_sync.sv`
- 총 SVG 2개, 코드 2개
