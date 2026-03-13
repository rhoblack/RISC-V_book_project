# CLAUDE.md

This file provides guidance to Claude Code when working with this repository.

## 진행 현황 관리 (필수)

**모든 진행 현황 업데이트는 프로젝트 루트의 `MEMORY.md` 파일에 기록한다.**
- 경로: `d:/dev/AI/claude/RISC-V_book_project/MEMORY.md`
- 챕터 완료, 설계 결정 변경, 주요 이슈 해결 시 즉시 업데이트
- `~/.claude/projects/.../memory/MEMORY.md` (자동 메모리)는 사용하지 않음

---

## 프로젝트 정보
- **제목**: RISC-V 프로세서 설계 완전정복
- **대상 독자**: Verilog 경험이 있는 대학원생 (RTL 설계 기초 지식 보유)
- **목표**: RV32I 파이프라인 프로세서를 설계하고 FPGA에 구현할 수 있는 능력 배양
- **톤**: 격식 있는 문어체, 영어 전문 용어는 첫 등장 시 "한글(English)" 형태로 병기

## 개발 환경
- **OS**: Windows
- **HDL**: SystemVerilog
- **ISA**: RISC-V RV32I
- **시뮬레이션**: Vivado / VCS / Verdi
- **FPGA 보드**: Xilinx Basys 3
- **버스 프로토콜**: AMBA AHB, APB
- **프로젝트 루트**: d:/dev/AI/Claude_Code/RISC-V_book_project

---

## Claude Code Agent Teams 운영

이 프로젝트는 **Claude Code Agent Teams** 기능을 사용하여 7명의 전문가 팀을 운영합니다.

### 에이전트 팀 구성

| 역할 | 담당 | 정의 파일 |
|------|------|----------|
| 📋 Team Lead (총괄 편집장) | 프로젝트 관리, 최종 승인 | agents/editor_in_chief.md |
| ✍️ Teammate: 기술 저자 | 콘텐츠 집필, 코드·SVG 작성 | agents/technical_author.md |
| 🔍 Teammate: 기술 리뷰어 | 코드 정확성, 실무 적합성 | agents/technical_reviewer.md |
| 🎓 Teammate: 초보자 독자 | 이해도/난이도 평가 | agents/beginner_reader.md |
| 📐 Teammate: 교육 설계자 | 학습 흐름, 블룸 분류 | agents/instructional_designer.md |
| 🧠 Teammate: 교육심리전문가 | 학습 동기, 불안 관리 | agents/educational_psychologist.md |
| 🎤 Teammate: 교육전문강사 | 설명 품질, 비유 검증 | agents/expert_instructor.md |

### 챕터 집필 실행 (workflows/agent_team_workflow.md 참조)
Phase 1: 기획 회의 (3 teammates 병렬)
Phase 2: 초안 작성 (기술 저자 단독)
Phase 3: 병렬 리뷰 (4 teammates 동시)
Phase 4: 종합 회의 및 수정

### Agent Team 운영 규칙
1. Team Lead = 편집장
2. 각 Teammate 생성 시 **아래 에이전트 정의를 spawn prompt에 직접 복사** (agents/*.md 파일 별도 Read 불필요)
3. 독립적 리뷰는 반드시 병렬 실행
4. 파일 충돌 방지: 기술 저자만 HTML 수정, 리뷰어는 review_logs만
5. 작업 완료 후 "팀 정리해줘"
6. **세션 관리**: 챕터 완료 후 `/compact` 실행 또는 새 세션 시작

### 에이전트 역할 정의 (spawn prompt에 직접 사용)

#### 기술 저자 (Technical Author)
- HTML 원고 집필 (chapter_template.html 구조 준수)
- SystemVerilog 코드 예제 작성 (code_examples/)
- SVG 다이어그램 작성 (figures/)
- 비유와 실생활 예시 개발
- 원칙: 각 절 2000~4000자, 새 개념 시 비유 필수, 한 절에 신규 개념 3개 이하
- 금지: ASCII art, 영어 전문용어만 나열, 코드 없는 이론 설명

#### 기술 리뷰어 (Technical Reviewer)
- SystemVerilog 코드 정확성 (문법, 합성 가능성, 시뮬레이션 동작)
- RISC-V RV32I ISA 스펙 준수, AMBA AHB/APB 프로토콜 준수
- Basys 3 FPGA 리소스 적합성
- 분류: 🔴 Critical(기술 오류/합성 불가) · 🟡 Major(비효율/표준 미준수) · 🟢 Minor(스타일)
- 출력: review_logs/chapterNN_tech_review.md

#### 초보자 독자 (Beginner Reader)
- 대상: Verilog 경험 있는 대학원생 (always/assign/module, 디지털 논리 기초, ALU/레지스터/메모리)
- 이해도 ⭐(전혀 불가)~⭐⭐⭐⭐⭐(완벽) 5점 평가 (최소 ⭐⭐⭐ 이상이어야 승인)
- 설명 없이 등장하는 용어 목록, SVG 이해 도움 여부 평가
- 출력: review_logs/chapterNN_beginner_review.md

#### 교육 설계자 (Instructional Designer)
- 학습 목표 검증 ("~할 수 있다" 형태, 블룸 분류 동사)
- 학습 흐름 (도입→개념→예시→실습→정리), 인지 부하 분석
- 연습문제 품질 (블룸 분류 최소 3수준)
- 출력: review_logs/chapterNN_edu_review.md

#### 교육심리전문가 (Educational Psychologist)
- 학습 동기 유지, 자기효능감 관리 (첫 실습은 반드시 성공하도록)
- 학습 불안 지점 감지 및 완화, 감정 곡선 분석 (호기심→불안→이해→성취감)
- 실패 정상화, 메타인지 촉진 장치 평가
- 출력: review_logs/chapterNN_psych_review.md

#### 교육전문강사 (Expert Instructor)
- 설명 품질 (강의에서 그대로 쓸 수 있는 수준인가)
- 비유 검증: ①기술 사실과 매핑 ②한계 명시 ③오해 유발 여부 ④대안 비유
- 수강생 막힘 포인트 예측, 면접 연결 포인트 추가
- 출력: review_logs/chapterNN_instructor_review.md

#### 편집장 (Editor in Chief) — Team Lead
- 최종 승인 기준: Critical 0건 · Major 0건 · 초보자 이해도 ⭐⭐⭐ 이상
- 교육 설계/심리적 안전성/강의 적합도 각 ⭐⭐⭐ 이상
- 피드백 충돌 우선순위: 정확성 > 심리적 안전 > 이해도 > 분량

---

## 프로젝트 아키텍처

### 디렉터리 구조
(README.md 참조)

### 원고 파일 규칙
- 위치: manuscripts/partN/chapterNN.html
- CSS: ../../templates/book_style.css
- SVG: ../../figures/chNN_secNN_설명.svg
- 코드: <pre><code class="language-systemverilog">

### output 폴더 규칙
- 위치: output/ChNN_챕터제목.html
- CSS/SVG 경로: ../../ → ../ 변환

---

## HTML 원고 필수 구조

(templates/chapter_template.html 참조)

### aside 박스 종류
- <aside class="tip"> — 💡 실무 팁
- <aside class="faq"> — ❓ 수강생 단골 질문
- <aside class="interview"> — 🎯 면접 포인트
- <aside class="metacognition"> — 🔍 스스로 점검
- <aside class="instructor-tip"> — 📌 강사 꿀팁

---

## 다이어그램 규칙
- SVG만 사용 (ASCII art 금지)
- 네이밍: figures/chNN_secNN_설명.svg
- 색상: 파란 계열 (#2563EB 메인, #3B82F6 보조, #DBEAFE 배경)
- 폰트: Pretendard, monospace

## 코드 품질 기준
- SystemVerilog IEEE 1800-2017 표준 준수
- 들여쓰기 3칸, snake_case 명명규칙, 한국어 주석
- 합성 가능한(synthesizable) 코드 작성

## 콘텐츠 품질 기준
- 각 절 2000~4000자
- 새 개념 시 비유/실생활 예시 필수
- 전문 용어 첫 등장 시 괄호 안 한글 설명
- 이전 챕터 지식만으로 현재 챕터 이해 가능
- 감정 곡선: 호기심 → 불안 → 이해 → 성취감

## HTML 원고 코드 하이라이팅 (매 챕터 동일 적용)

```html
<!-- head 안에 -->
<link rel="stylesheet" href="https://cdnjs.cloudflare.com/ajax/libs/highlight.js/11.9.0/styles/atom-one-dark.min.css">

<!-- </body> 직전 -->
<script src="https://cdnjs.cloudflare.com/ajax/libs/highlight.js/11.9.0/highlight.min.js"></script>
<script src="https://cdnjs.cloudflare.com/ajax/libs/highlight.js/11.9.0/languages/verilog.min.js"></script>
<script>
  document.querySelectorAll('code.language-systemverilog').forEach(el => {
    el.classList.remove('language-systemverilog');
    el.classList.add('language-verilog');
  });
  hljs.highlightAll();
</script>
```

**코드 이스케이프 필수**: `<pre><code>` 내부 `<` → `&lt;` · `>` → `&gt;` · `&` → `&amp;`

**전체 소스 코드 섹션**: 연습문제 다음, Highlight.js 스크립트 직전에 배치
- 안심 문구 필수: "지금 당장 전부 이해하지 않아도 됩니다. 각 절 학습 후 참조용으로 활용하세요."

---

## 파이프라인 핵심 설계 (Ch09~12 완성 상태)

| 항목 | 값 |
|------|---|
| 최종 top 모듈 | `rv32i_pipeline_complete` (DATA_WIDTH/ADDR_WIDTH/RF_DEPTH 파라미터) |
| 포워딩 우선순위 | EX-EX(최우선) > MEM-EX > WB-ID |
| 스톨 우선순위 | flush > icache_stall > load_use_stall |
| WB-ID 포워딩 | 레지스터 파일 내부 처리 (`rs1_data = (reg_w_en && rd!=0 && rd==rs1) ? rd_data : rf[rs1]`) |
| NOP | 32'h0000_0013 |
| 성능 | 단일사이클 ~25MHz/CPI=1.0 · 멀티사이클 ~50MHz/CPI≈4.1 · 파이프라인 ~65MHz/CPI≈1.2 |
| Harvard 구조 | IMEM=조합논리 LUTRAM · DMEM=동기 쓰기/비동기 읽기 |

## Part 5 캐시 설계 파라미터 (Ch13~15 공통)

| 파라미터 | L1 I-Cache | L2 D-Cache |
|---------|-----------|-----------|
| 구조 | 직접 매핑 | 2-way 세트 연관 (Ch14) |
| 크기 | 4KB | 4KB (Ch14) |
| 블록 크기 | 32바이트 (8워드) | 32바이트 (Ch14) |
| 엔트리 수 | 128개 | 128세트 (Ch14) |
| Tag | [31:12] = 20비트 | 동일 |
| Index | [11:5] = 7비트 | 동일 |
| Offset | [4:0] = 5비트 | 동일 |
| BRAM 사용 | Data: BRAM · Tag: LUTRAM · Valid: FF | Ch14 추가 |
| 미스 페널티 | 5사이클 (단순화) | — |
| FSM | IDLE→MISS→FILL→DONE | — |
| stall 신호 | `icache_stall` (flush > icache_stall > load_use) | `dcache_stall` (Ch14) |

## 전체 목차
TABLE_OF_CONTENTS.md 참조
