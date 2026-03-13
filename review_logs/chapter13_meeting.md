# Chapter 13 종합 리뷰 회의록

날짜: 2026-03-12

---

## 리뷰어별 핵심 피드백 요약

### 기술 리뷰어 (Technical Reviewer)

- **Critical 3건**: (C-1) fill_cnt 초기화 타이밍 오류 — 2번째 이후 미스에서 첫 워드가 fill_cnt=7 주소에 저장될 수 있음; (C-2) FILL 중 flush 발생 시 FSM 중단 메커니즘 부재 — wrong-path 블록을 끝까지 채움; (C-3) DONE 상태 cpu_rdata가 word_offset 무관하게 마지막 워드(fill_cnt=7)를 반환하는 오류.
- **Major 5건**: M-1(fill_cnt 쓰기 타이밍), M-2(LUTRAM 합성 추론 주의), M-3(valid 루프 초기화 경고), M-4(if_id_en_final flush 우선순위 명확화 주석 누락), M-5(메모리 모델이 1사이클 ready 펄스만 발생 → FILL 중 fill_cnt가 7까지 증가 불가).
- **Minor 4건**: HTML 이스케이프 전반 양호, addr_decode_check.sv Index 범위 오기(Index[12:6] → Index[11:6]), 테스트벤치 cache_hit 집계 타이밍, fill_cnt 오버플로우 설명 부재.
- 주소 분해 정확성·FSM 상태 전환·히트율 수치·FPGA 리소스 적합성 모두 검증 통과.

### 초보자 독자 (Beginner Reader)

- **Major 2건**: (M-beginner-1) LUTRAM 비동기 읽기 / BRAM 동기 읽기 차이 미설명으로 초보자가 "1사이클 지연이 파이프라인에서 자연 흡수된다"는 설계 결정을 이해하기 어려움; (M-beginner-2) FILL 상태 fill_cnt 카운터 동작을 본문에서 설명하지 않아 "왜 8번 기다리는가"가 코드와 본문 사이에서 연결되지 않음.
- **Minor 2건**: 3C 미스 분류를 면접 포인트 박스 내부에만 소개하지 않고 본문에 먼저 소개 권장; 예제 3의 이진수 표기 보완.
- 전체 이해도 ⭐⭐⭐⭐½ (4.5/5). 13.1, 13.3, 13.5, 13.6절은 개선 불필요 수준. 조건부 승인.

### 교육심리전문가 (Educational Psychologist)

- **Critical 0건.**
- **Major 1건**: (M-psych-1) 13.5절 시나리오 4 직후 "이 충돌 미스 체험이 바로 Ch14의 출발점"이라는 맥락 선언 부재. 13.6절 이전까지 좌절감이 해소되지 않은 구간이 존재함.
- **Minor 2건**: 안심 2·5의 instructor-tip → 학습자 직접 수신 강화; 버블정렬 성취 감정 에너지 명시적 전이 문장 추가.
- 전체 심리적 안전성 ⭐⭐⭐⭐⭐. 감정 곡선 7단계 전이 모두 구현됨. 안심 장치 5개 전부 확인됨.

### 교육전문강사 (Expert Instructor)

- **Critical 0건, Major 0건.**
- **Minor 3건**: 13.2절 본문에 "축출(Eviction, Evict)" 영어 병기 추가; FSM DONE 상태 역할 1~2문장 본문 설명 추가; 13.6절 면접 2~3분 답변 구조 예시 박스(선택 사항).
- 기획 단계 막힘 포인트 Top 5 모두 해소 확인. 강의 적합도 ⭐⭐⭐⭐⭐. 비유 3종 기술 정확성 검증 통과. aside 박스 18개 균등 배치 확인.

---

## Critical/Major 이슈 목록 (반영 결정)

### Critical — 3건 (코드 파일 수정)

| ID | 출처 | 내용 | 반영 파일 |
|----|------|------|---------|
| C-1 | 기술 | fill_cnt 초기화 타이밍: MISS→FILL 첫 사이클에 이전 값으로 BRAM 쓰기 오류 | ch13_icache_direct_mapped.sv |
| C-2 | 기술 | FILL 중 flush 입력 부재: wrong-path 블록을 끝까지 채움 | ch13_icache_direct_mapped.sv |
| C-3 | 기술 | DONE 상태 cpu_rdata word_offset 불일치: word_offset=2 요청 시 항상 fill_cnt=7 데이터 반환 | ch13_icache_direct_mapped.sv |

### Major — 반영 결정 (HTML + 코드)

| ID | 출처 | 내용 | 반영 파일 |
|----|------|------|---------|
| M-beginner-1 | 초보자 | LUTRAM 비동기 읽기 / BRAM 동기 읽기 개념 보충 | chapter13.html (13.2절) |
| M-beginner-2 | 초보자 | FILL 상태 fill_cnt 카운터 동작 설명 보충 | chapter13.html (13.4절) |
| M-psych-1 | 교육심리 | 시나리오 4 직후 Ch14 연결 문장 추가 | chapter13.html (13.5절) |
| M-tech-5 | 기술 | 메모리 지연 모델 단순화: 고정 5사이클 카운터로 mem_ready 무관 DONE 전환 | ch13_icache_direct_mapped.sv, ch13_pipeline_with_icache.sv |

---

## 반영 보류 피드백

| ID | 출처 | 내용 | 보류 이유 |
|----|------|------|---------|
| M-tech-2 | 기술 | LUTRAM 합성 추론 경고 → 교재 aside 추가 | Minor로 하향; 이미 실무 팁 박스에서 합성 속성 설명 충분 |
| M-tech-3 | 기술 | valid 루프 초기화 Vivado 경고 aside 추가 | 분량 고려, 기존 주석으로 충분 |
| M-tech-4 | 기술 | if_id_en_final flush 주석 명확화 | 기존 주석 "flush는 rv32i_pipeline_complete 내부 처리" 의미로 충분 |
| m-tech-2 | 기술 | addr_decode_check.sv Index[12:6] → Index[11:6] 수정 | Minor; 교재 본문과 무관한 보조 파일. 별도 처리 |
| m-tech-3 | 기술 | 테스트벤치 cache_hit 집계 타이밍 | Minor; 교육 목적 단순화 범위 내 |
| m-psych-1 | 교육심리 | 안심 2·5 instructor-tip → 학습자 직접 접근 강화 | Minor로 처리; 기존 구조 변경 최소화 |
| m-psych-2 | 교육심리 | 버블정렬 성취 감정 에너지 전이 문장 | Minor; 기존 13.1절 도입부로 충분 |
| m-instructor-3 | 강사 | 면접 2~3분 답변 구조 예시 박스 추가 | 분량 고려 보류 (강의 현장 구두 보완 권장) |
| Minor-instructor-1 | 강사 | "축출(Eviction, Evict)" 영어 병기 | 13.2절 예제 4 본문에 반영 |
| Minor-instructor-2 | 강사 | FSM DONE 상태 역할 본문 1~2문장 추가 | Minor; 반영 결정 |

---

## Action Items

| 우선순위 | 작업 | 담당 | 파일 |
|---------|------|------|------|
| 1 (Critical) | C-1: fill_cnt 초기화 — DONE/IDLE 상태에서 명시적 0 초기화 추가 | 기술 저자 | ch13_icache_direct_mapped.sv |
| 2 (Critical) | C-2: flush 포트 추가 및 FILL 중 flush=1 시 IDLE 전환 | 기술 저자 | ch13_icache_direct_mapped.sv |
| 3 (Critical) | C-3: DONE에서 cpu_rdata = data_mem[{miss_addr_reg[11:5], miss_word_offset}] 수정 | 기술 저자 | ch13_icache_direct_mapped.sv |
| 4 (Major) | M-tech-5: FILL 고정 사이클(FILL_CYCLES=5) 카운터 방식으로 단순화 | 기술 저자 | ch13_icache_direct_mapped.sv, ch13_pipeline_with_icache.sv |
| 5 (Major) | M-beginner-1: 13.2절 BRAM 매핑 설명 직후 비동기/동기 읽기 개념 3~5문장 추가 | 기술 저자 | chapter13.html |
| 6 (Major) | M-beginner-2: 13.4절 FSM 설명 중 fill_cnt 카운터 동작 2~3문장 추가 | 기술 저자 | chapter13.html |
| 7 (Major) | M-psych-1: 13.5절 시나리오 4 직후 Ch14 연결 2~3문장 추가 | 기술 저자 | chapter13.html |
| 8 (Minor) | "축출(Eviction)" 영어 병기 추가 (13.2절 예제 4) | 기술 저자 | chapter13.html |
| 9 (Minor) | FSM DONE 상태 역할 본문 1~2문장 추가 (13.4절) | 기술 저자 | chapter13.html |
| 10 (Minor) | 안심 2·5 박스 유형 검토 (instructor-tip → tip/faq) | 기술 저자 | chapter13.html |
| 11 | output 파일 경로 변환 및 동기화 | 기술 저자 | output/Ch13_캐시기초와L1명령어캐시_final.html |
| 12 | 편집장 최종 승인서 작성 | 편집장 | review_logs/chapter13_final_approval.md |
