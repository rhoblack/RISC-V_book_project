# RISC-V 프로세서 설계 완전정복 — 프로젝트 진행 기록

**최종 업데이트**: 2026-03-11

---

## 전체 진행 요약

| 구분 | 완료 | 전체 | 진행률 |
|------|------|------|--------|
| 원고 (HTML) | 5 챕터 | 25 챕터 | 20% |
| SVG 다이어그램 | 122개 | 122개 | 100% |
| 코드 예제 | 94개 | 94개 | 100% |
| 리뷰 로그 | 21개 | — | — |

---

## 챕터별 상태

### Part 0 — 시작하기 전에
| 챕터 | 제목 | 상태 | 원고 | 줄수 | 크기 | 리뷰 방식 |
|------|------|------|------|------|------|-----------|
| Ch01 | 프로젝트 소개와 개발 환경 구축 | ✅ APPROVED | chapter01.html | 1,052줄 | 57KB | 4단계 정규 워크플로우 |

### Part 1 — RISC-V ISA 이해
| 챕터 | 제목 | 상태 | 원고 | 줄수 | 크기 | 리뷰 방식 |
|------|------|------|------|------|------|-----------|
| Ch02 | RISC-V 아키텍처 개요 | ✅ APPROVED | chapter02.html | 1,357줄 | 69KB | 4단계 정규 워크플로우 (4인 병렬 리뷰) |
| Ch03 | RV32I 명령어 세트 완전 분석 | ✅ APPROVED | chapter03.html | 1,352줄 | 64KB | 편집장 겸직 리뷰 |

### Part 2 — 단일 사이클 프로세서 구현
| 챕터 | 제목 | 상태 | 원고 | 줄수 | 크기 | 리뷰 방식 |
|------|------|------|------|------|------|-----------|
| Ch04 | 데이터패스 기초: ALU와 레지스터 파일 | ✅ APPROVED | chapter04.html | 1,186줄 | 57KB | 편집장 겸직 리뷰 |
| Ch05 | 메모리 서브시스템 설계 | ✅ APPROVED | chapter05.html | 1,185줄 | 57KB | 편집장 겸직 리뷰 |
| Ch06 | 제어 유닛과 단일 사이클 통합 | ⬜ 미착수 | — | — | — | — |

### Part 3~9 — 미착수
| Part | 챕터 범위 | 상태 |
|------|----------|------|
| Part 3 | Ch07~08 (멀티사이클) | ⬜ 미착수 |
| Part 4 | Ch09~12 (파이프라인) | ⬜ 미착수 |
| Part 5 | Ch13~15 (캐시) | ⬜ 미착수 |
| Part 6 | Ch16~17 (AMBA 버스) | ⬜ 미착수 |
| Part 7 | Ch18~19 (예외/인터럽트) | ⬜ 미착수 |
| Part 8 | Ch20~22 (FPGA 구현) | ⬜ 미착수 |
| Part 9 | Ch23~25 (심화) | ⬜ 미착수 |

---

## 산출물 목록

### 1. 원고 파일 (manuscripts/)
```
manuscripts/part0/chapter01.html  — 1,052줄, 57KB
manuscripts/part1/chapter02.html  — 1,357줄, 69KB
manuscripts/part1/chapter03.html  — 1,352줄, 64KB
manuscripts/part2/chapter04.html  — 1,186줄, 57KB
manuscripts/part2/chapter05.html  — 1,185줄, 57KB
```

### 2. 리뷰 로그 (review_logs/)

#### 목차(TOC) 리뷰 — 5개
- TOC_tech_review.md, TOC_edu_review.md, TOC_psych_review.md
- TOC_beginner_review.md, TOC_instructor_review.md

#### Chapter 01 — 7개
- ch01_authoring_plan.md (기획)
- ch01_instructor_planning.md (강사 기획)
- chapter01_tech_review.md, chapter01_beginner_review.md
- chapter01_psych_review.md, chapter01_instructor_review.md
- chapter01_meeting.md (최종 승인)

#### Chapter 02 — 6개
- ch02_authoring_plan.md (기획)
- chapter02_tech_review.md, chapter02_beginner_review.md
- chapter02_psych_review.md, chapter02_instructor_review.md
- chapter02_meeting.md (최종 승인)

#### Chapter 03~05 — 각 1개 (회의록만)
- chapter03_meeting.md (최종 승인)
- chapter04_meeting.md (최종 승인)
- chapter05_meeting.md (최종 승인)

### 3. SVG 다이어그램 (figures/) — 122개
- Ch01: 4개 (processor_overview, sv_vs_verilog, vivado_flow 등)
- Ch02: 4개 (isa_modular, register_file, memory_model, instruction_formats)
- Ch03: 7개 (r/i/s/b/u/j_type_encoding, risb_comparison)
- Ch04: 4개 (datapath_modules, alu_block, register_file, imm_gen)
- Ch05: 4개 (datapath_memory, imem_structure, dmem_byte_enable, memory_map)
- Ch06~Ch25: 나머지 ~99개 (전 챕터 사전 생성 완료)

### 4. 코드 예제 (code_examples/) — 94개
- Ch01: 3개 (led_blinker.sv, led_blinker_tb.sv, basys3.xdc)
- Ch03: 1개 (fibonacci.s)
- Ch04: 5개 (alu.sv, register_file.sv, imm_gen.sv + TB 2개)
- Ch05: 3개 (instruction_memory.sv, data_memory.sv, memory_tb.sv)
- Ch06~Ch25: 나머지 ~82개 (전 챕터 사전 생성 완료)

---

## 워크플로우 이력

### 정규 4단계 워크플로우 (Ch01, Ch02)
```
Phase 1: 기획 회의 → 저자+설계자+강사 3명 병렬 → authoring_plan.md
Phase 2: 초안 작성 → 기술 저자 단독 → chapterNN.html
Phase 3: 병렬 리뷰 → 리뷰어+독자+심리+강사 4명 동시 → 4개 리뷰 파일
Phase 4: 종합 회의 → 편집장 통합 → meeting.md + 수정 → APPROVED
```

### 편집장 겸직 리뷰 (Ch03~Ch05)
```
Phase 2: 초안 작성 → 기술 저자 단독
Phase 4: 편집장이 4가지 관점(기술/초보자/교육설계/교육심리) 겸직 검토
         → meeting.md → APPROVED
```
- Phase 1(기획), Phase 3(병렬 리뷰) 생략됨
- 별도 리뷰어 파일 없이 회의록에 통합

---

## 주요 품질 지표

### Ch02 (4인 병렬 리뷰 기준)
| 평가 영역 | 수정 전 | 수정 후 |
|----------|---------|---------|
| 기술 정확도 | 4.3/5 | 4.5+ |
| 초보자 이해도 | 4/5 | 4+ |
| 심리적 안전성 | 3.5/5 | 4+ |
| 강의 적합도 | 4.5/5 | 4.5+ |
| Critical 이슈 | 3개 | 0개 |
| Major 이슈 | 15개 | 0개 |

### Ch03~05 (편집장 겸직 리뷰 기준)
| 챕터 | Critical 해결 | Minor | 인코딩 정확성 | 코드 품질 |
|------|:------------:|:-----:|:------------:|:---------:|
| Ch03 | 4/4 ✅ | 2개 (수정 불필요) | 전체 통과 | IEEE 1800-2017 준수 |
| Ch04 | 3/3 ✅ | 1개 (수정 불필요) | — | IEEE 1800-2017 준수 |
| Ch05 | 3/3 ✅ | 0개 | — | IEEE 1800-2017 준수 |

---

## 다음 단계

1. **Chapter 06** — 제어 유닛과 단일 사이클 통합 (Part 2 마지막)
   - 명령어 디코더, 제어 신호 정의, 데이터패스 통합, Basys 3 합성
   - Part 2 완성으로 **피보나치 실행 마일스톤** 달성 예정

2. 이후 진행 순서:
   - Part 3 (Ch07~08): 멀티사이클 프로세서
   - Part 4 (Ch09~12): 5단계 파이프라인 (교재 핵심)
   - Part 5~9: 캐시, AMBA, 예외/인터럽트, FPGA, 심화
