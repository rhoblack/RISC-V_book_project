# CLAUDE.md

This file provides guidance to Claude Code when working with this repository.

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
2. 각 Teammate 생성 시 agents/*.md 파일을 spawn prompt에 명시
3. 독립적 리뷰는 반드시 병렬 실행
4. 파일 충돌 방지: 기술 저자만 HTML 수정, 리뷰어는 review_logs만
5. 작업 완료 후 "팀 정리해줘"

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

## 전체 목차
TABLE_OF_CONTENTS.md 참조
