# Chapter 01 — 프로젝트 소개와 개발 환경 구축: 기술 저자 기획안

> **작성자**: 기술 저자 (Technical Author)
> **작성일**: 2026-03-11
> **상태**: Phase 1 기획 완료, Phase 2 초안 작성 대기

---

## 절별 상세 기획

---

### 1.1 이 책으로 무엇을 만드는가

#### 핵심 메시지
이 교재를 끝까지 따라가면 RV32I 5단계 파이프라인 프로세서를 직접 설계하여 FPGA 위에서 C 프로그램을 실행할 수 있다. 지금부터 만들 프로세서의 완성된 모습을 먼저 조감하고, 25개 챕터에 걸친 여정의 전체 로드맵을 파악한다.

#### SystemVerilog 코드 예제 목록
| # | 코드 | 설명 |
|---|------|------|
| 1 | 최소 모듈 스켈레톤 | `module rv32i_top(...)` 형태의 최상위 모듈 포트 선언만 보여주어 "최종 목표물"의 인터페이스를 미리 체감시킴. 내부 구현은 `// 이 교재에서 채워 나갑니다` 주석 처리. |

> **참고**: 이 절은 동기 부여 절이므로 코드 비중은 최소로 유지하고 시각 자료에 집중한다.

#### SVG 다이어그램 목록
| # | 파일명 | 상태 | 설명 |
|---|--------|------|------|
| 1 | `ch01_sec01_processor_overview.svg` | **기존** | RV32I 5단계 파이프라인 프로세서 전체 조감도 (그림 1.1). IF/ID/EX/MEM/WB 스테이지, 파이프라인 레지스터, 포워딩 경로, 제어 유닛 포함. |
| 2 | `ch01_sec01_book_roadmap.svg` | **추가 필요** | 25개 챕터 로드맵. Part 0~9를 시각적 타임라인으로 표현. 각 Part의 마일스톤(LED 점멸, 피보나치, 버블정렬 FPGA, 최종 SoC 데모)을 이정표로 표시. |

#### 절 분량 추정
- **약 2,500자**
- 비유(건축 설계도 조감도), 프로세서 구조 개관, 교재 로드맵, 학습 방법 안내
- aside: `<aside class="tip">` (교재 활용법), `<aside class="metacognition">` ("이 그림이 아직 이해되지 않아도 괜찮습니다")

---

### 1.2 개발 환경 설치 및 검증

#### 핵심 메시지
Vivado 2024.x, VCS/Verdi, Basys 3 드라이버를 올바르게 설치하고 "Hello Vivado" 수준의 검증까지 완료해야 이후 실습이 원활하다. 환경 설정 실패는 가장 흔한 첫 좌절 원인이므로 FAQ 박스로 대비한다.

#### SystemVerilog 코드 예제 목록
| # | 코드 | 설명 |
|---|------|------|
| 1 | 환경 검증용 최소 모듈 | `module hello_vivado(input logic clk, output logic led);` — 단순 assign으로 LED 하나를 켜는 코드. Vivado 프로젝트 생성 확인 용도. |
| 2 | 시뮬레이션 검증 테스트벤치 | `$display("Vivado Simulator is working!");`을 출력하는 최소 테스트벤치. VCS에서도 동일 코드 실행 확인. |

#### SVG 다이어그램 목록
| # | 파일명 | 상태 | 설명 |
|---|--------|------|------|
| 1 | `ch01_sec02_dev_environment.svg` | **추가 필요** | 개발 환경 구성도. PC(Windows) — Vivado — Basys 3 보드 연결 다이어그램. VCS/Verdi는 별도 영역으로 표시(대학원 라이선스 환경). |

#### 절 분량 추정
- **약 3,500자**
- Vivado 설치 단계(요약 + App.E 참조), Basys 3 드라이버 설치, VCS/Verdi 설정(선택), 검증 절차
- aside: `<aside class="faq">` (설치 오류 해결 TOP 5), `<aside class="tip">` (Vivado 무료 라이선스 vs 유료 차이)

> **교육심리전문가 권고 반영**: 설치 실패 시 좌절 방지를 위해 "설치 오류 해결 FAQ" 박스와 App.E 참조 링크를 반드시 배치.

---

### 1.3 SystemVerilog 필수 문법 복습

#### 핵심 메시지
Verilog를 아는 독자가 SystemVerilog로 전환할 때 반드시 알아야 할 세 가지 핵심 변화는 `logic` 통합 타입, `always_ff`/`always_comb` 명시적 블록, 열거형(`typedef enum`)이다. 이 절에서 확립한 코딩 규칙이 이후 전체 교재의 기준선이 된다.

#### SystemVerilog 코드 예제 목록
| # | 코드 | 설명 |
|---|------|------|
| 1 | `logic` vs `reg`/`wire` 비교 | Verilog `reg`/`wire` 코드와 동일 기능의 SystemVerilog `logic` 코드를 나란히 제시. |
| 2 | `always_comb` 조합 논리 예제 | 2:1 MUX를 `always_comb`로 구현. 래치(latch) 방지 검사 동작 설명. `always @(*)` 대비 장점 설명. |
| 3 | `always_ff` 순차 논리 예제 | D 플립플롭을 `always_ff @(posedge clk or negedge rst_n)`으로 구현. 비동기 리셋 패턴 확립. |
| 4 | 블로킹(`=`) vs 논블로킹(`<=`) 할당 규칙 | `always_comb`에서 `=`, `always_ff`에서 `<=` 사용 규칙을 위반 사례와 함께 설명. |
| 5 | `typedef enum logic` 상태 정의 | 간단한 2-상태 FSM (IDLE/ACTIVE)으로 열거형 사용법 시연. |
| 6 | `assign`과 `always_comb` 차이 | 단순 와이어 연결은 `assign`, 복합 조합 논리는 `always_comb` — 사용 기준 제시. |

#### SVG 다이어그램 목록
| # | 파일명 | 상태 | 설명 |
|---|--------|------|------|
| 1 | `ch01_sec03_sv_vs_verilog.svg` | **기존** | SystemVerilog vs Verilog 5대 핵심 비교 (데이터 타입, 조합 논리, 순차 논리, 상태 정의, 모듈 포트). (그림 1.2) |
| 2 | `ch01_sec03_blocking_nonblocking.svg` | **추가 필요** | 블로킹/논블로킹 할당의 시뮬레이션 타이밍 차이를 파형으로 시각화. `always_comb` + `=` vs `always_ff` + `<=`의 하드웨어 추론 결과 비교. |

#### 절 분량 추정
- **약 3,800자** (코드 예제가 많으므로 상한에 가까움)
- 6개 코드 예제 + 2개 SVG 다이어그램
- aside: `<aside class="interview">` (면접 빈출 #9: always_ff vs always_comb 차이), `<aside class="faq">` ("reg는 정말 레지스터인가?"), `<aside class="tip">` (Vivado 합성 시 래치 경고 해석법)

> **기술 리뷰어 주석 반영**: 이 절에서 확립하는 코딩 규칙(`reg` 대신 `logic`, `always_comb`/`always_ff` 구분, 블로킹/논블로킹 규칙)이 이후 모든 코드의 기준선. 일관성 유지를 위해 "본 교재의 코딩 규칙" 박스를 명시적으로 배치.

---

### 1.4 첫 번째 합성 실습: LED 점멸

#### 핵심 메시지
Vivado 프로젝트를 처음부터 생성하고, SystemVerilog 코드를 작성하여, XDC 제약 파일을 통해 Basys 3 보드의 LED를 점멸시키는 전체 과정을 경험한다. 이것이 FPGA 설계의 최소 완전 사이클(코드 작성 -> 합성 -> 비트스트림 -> 보드 구동)이다.

#### SystemVerilog 코드 예제 목록
| # | 코드 | 설명 |
|---|------|------|
| 1 | `led_blinker.sv` — LED 점멸 모듈 | 100MHz 클록을 분주하여 1Hz LED 점멸. 27비트 카운터 + `always_ff` 패턴. 1.3절에서 배운 `always_ff`, `logic` 즉시 적용. |
| 2 | `basys3_led.xdc` — XDC 제약 파일 (발췌) | `set_property PACKAGE_PIN W5 [get_ports clk]`, LED 핀 매핑. `create_clock -period 10.0` 클록 제약. |
| 3 | `led_blinker_tb.sv` — 테스트벤치 | 합성 전 시뮬레이션 검증. `#5 clk = ~clk;` 클록 생성, `$finish` 사용. |

#### SVG 다이어그램 목록
| # | 파일명 | 상태 | 설명 |
|---|--------|------|------|
| 1 | `ch01_sec04_vivado_flow.svg` | **기존** | Vivado FPGA 설계 플로우 — 소스 입력 -> 합성 -> 구현 -> 비트스트림 -> Basys 3, 병행하여 시뮬레이션 플로우. (그림 1.3) |
| 2 | `ch01_sec04_basys3_led_pinout.svg` | **추가 필요** | Basys 3 보드 LED/클록 핀 배치 간략도. W5(clk), U16(LED0) 등 이 실습에서 사용하는 핀만 하이라이트. |

#### 절 분량 추정
- **약 3,500자**
- 단계별 실습 가이드 (Vivado 프로젝트 생성 -> 소스 추가 -> 합성 -> 구현 -> 비트스트림 -> 프로그래밍)
- aside: `<aside class="tip">` (Vivado Tcl 콘솔 유용 명령어), `<aside class="faq">` ("합성 후 경고가 많이 나오는데 괜찮은가?"), `<aside class="metacognition">` ("LED가 점멸했다면, 당신은 방금 FPGA 설계의 전체 사이클을 완주한 것입니다")

> **감정 곡선**: 이 절이 Part 0의 마일스톤("LED 점멸 성공"). 성취감 극대화를 위해 절 말미에 축하 메시지 + 자기 점검 배치.

---

### 1.5 시뮬레이션 환경 설정

#### 핵심 메시지
합성 전 시뮬레이션은 디버깅 시간을 10배 이상 절약하는 필수 과정이다. Vivado Simulator(무료)와 VCS/Verdi(대학원 라이선스)의 기본 사용법을 익히고, 파형 뷰어에서 신호를 추적하는 방법을 배운다.

#### SystemVerilog 코드 예제 목록
| # | 코드 | 설명 |
|---|------|------|
| 1 | `simple_adder.sv` — 32비트 가산기 | 시뮬레이션 대상 모듈. `assign sum = a + b;` 단순 조합 논리. |
| 2 | `simple_adder_tb.sv` — 테스트벤치 | `$dumpfile`/`$dumpvars`(VCS용), Vivado Simulator용 `$time` 사용, 자동 검증 `assert`. |
| 3 | VCS 컴파일/실행 명령어 | `vcs -sverilog -full64 simple_adder.sv simple_adder_tb.sv -o simv` + `./simv` (코드 블록이 아닌 터미널 명령어). |
| 4 | Vivado Simulator 실행 순서 | Vivado GUI에서 시뮬레이션 설정 및 실행 (스크린샷 대신 텍스트 단계 기술). |

#### SVG 다이어그램 목록
| # | 파일명 | 상태 | 설명 |
|---|--------|------|------|
| 1 | `ch01_sec05_waveform_anatomy.svg` | **추가 필요** | 파형 뷰어 해부도. 시간축, 신호 이름, 값 표시, 커서, 줌 기능을 시각적으로 설명. 초보자가 파형 뷰어를 처음 볼 때 "무엇을 보는 것인지" 안내. |

#### 절 분량 추정
- **약 3,000자**
- Vivado Simulator 사용법, VCS 기본 명령어, 파형 뷰어 사용 기초
- aside: `<aside class="tip">` (파형 뷰어에서 유용한 단축키), `<aside class="faq">` ("Vivado Simulator vs VCS, 어떤 것을 쓰면 좋은가?"), `<aside class="instructor-tip">` ("시뮬레이션 습관은 이 시점에 확립해야 합니다")

---

### 1.6 본 챕터 요약 및 다음 단계

#### 핵심 메시지
Chapter 01에서 개발 환경을 구축하고 SystemVerilog 기본 문법을 확인하며 첫 FPGA 실습을 완료했다. 다음 챕터에서는 실제로 구현할 RISC-V ISA의 구조와 명령어를 학습한다.

#### SystemVerilog 코드 예제 목록
- 없음 (요약 절)

#### SVG 다이어그램 목록
| # | 파일명 | 상태 | 설명 |
|---|--------|------|------|
| 1 | `ch01_sec06_chapter_summary.svg` | **추가 필요** (선택) | Chapter 01에서 달성한 것들의 체크리스트 시각화. 환경 설치, 문법 복습, LED 점멸, 시뮬레이션의 4단계를 완료 아이콘으로 표시. |

> **참고**: 이 SVG는 선택 사항. 텍스트 기반 핵심 정리 목록으로 대체 가능.

#### 절 분량 추정
- **약 2,000자** (하한)
- 핵심 개념 정리 (불릿 5~7개), 자가 점검 질문 3~5개, Ch02 예고
- aside: `<aside class="metacognition">` (자가 점검 질문)

---

## 전체 요약

### 분량 총계

| 절 | 추정 분량 | 코드 예제 수 | SVG 수 (기존/추가) |
|----|----------|------------|-------------------|
| 1.1 | 2,500자 | 1 | 1 기존 + 1 추가 |
| 1.2 | 3,500자 | 2 | 0 기존 + 1 추가 |
| 1.3 | 3,800자 | 6 | 1 기존 + 1 추가 |
| 1.4 | 3,500자 | 3 | 1 기존 + 1 추가 |
| 1.5 | 3,000자 | 4 | 0 기존 + 1 추가 |
| 1.6 | 2,000자 | 0 | 0 기존 + 1 추가 (선택) |
| **합계** | **~18,300자** | **16** | **3 기존 + 5~6 추가** |

### 추가 필요 SVG 다이어그램 정리

| # | 파일명 | 절 | 우선순위 | 설명 |
|---|--------|----|---------|------|
| 1 | `ch01_sec01_book_roadmap.svg` | 1.1 | 높음 | 25챕터 로드맵 타임라인 |
| 2 | `ch01_sec02_dev_environment.svg` | 1.2 | 높음 | 개발 환경 구성도 (PC-Vivado-Basys3) |
| 3 | `ch01_sec03_blocking_nonblocking.svg` | 1.3 | 높음 | 블로킹/논블로킹 할당 타이밍 파형 비교 |
| 4 | `ch01_sec04_basys3_led_pinout.svg` | 1.4 | 중간 | Basys 3 LED/클록 핀 배치 간략도 |
| 5 | `ch01_sec05_waveform_anatomy.svg` | 1.5 | 높음 | 파형 뷰어 해부도 |
| 6 | `ch01_sec06_chapter_summary.svg` | 1.6 | 낮음 (선택) | 챕터 성취 체크리스트 |

### aside 박스 배치 계획

| aside 유형 | 배치 절 | 내용 요약 |
|-----------|---------|----------|
| `<aside class="interview">` | 1.3 | 면접 빈출 #9: `always_ff` vs `always_comb` 차이 |
| `<aside class="faq">` | 1.2, 1.3, 1.4, 1.5 | 설치 오류 FAQ, reg/wire 혼동, 합성 경고, 시뮬레이터 선택 |
| `<aside class="tip">` | 1.1, 1.2, 1.3, 1.4, 1.5 | 교재 활용법, Vivado 라이선스, 래치 경고, Tcl 명령어, 파형 단축키 |
| `<aside class="metacognition">` | 1.1, 1.4, 1.6 | 이해도 자가 점검 |
| `<aside class="instructor-tip">` | 1.5 | 시뮬레이션 습관 확립 강조 |

### 교재 코딩 규칙 확립 (1.3절에서 선언)

이후 전체 교재에 적용되는 코딩 규칙을 1.3절 말미에 박스로 정리:

1. 데이터 타입: `logic`만 사용 (`reg`/`wire` 사용하지 않음)
2. 조합 논리: `always_comb` + 블로킹 할당(`=`)
3. 순차 논리: `always_ff @(posedge clk or negedge rst_n)` + 논블로킹 할당(`<=`)
4. 상태 정의: `typedef enum logic [N-1:0] {...}` 열거형
5. 명명 규칙: `snake_case`, 모듈명/신호명 모두
6. 들여쓰기: 3칸 스페이스
7. 주석: 한국어
8. 리셋: 비동기 액티브-로우 (`rst_n`)

---

*기술 저자 기획 완료. Phase 2(초안 작성) 및 Phase 3(병렬 리뷰) 대기.*
