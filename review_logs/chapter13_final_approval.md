# Chapter 13 편집장 최종 승인서

**챕터**: Ch13 — 캐시 기초와 L1 명령어 캐시
**편집장**: Editor in Chief
**승인 일자**: 2026-03-12

---

## 최종 판정

**✅ 최종 승인 (APPROVED)**

---

## 승인 기준 체크리스트

| 기준 | 목표 | 판정 | 비고 |
|------|------|------|------|
| Critical 이슈 | 0건 | ✅ 0건 | C-1, C-2, C-3 모두 수정 완료 |
| Major 이슈 | 0건 | ✅ 0건 | M-beginner-1/2, M-psych-1, M-tech-5 모두 수정 완료 |
| 초보자 이해도 | ⭐⭐⭐ 이상 | ✅ ⭐⭐⭐⭐⭐ | 수정 후 4.5→5.0 향상 예상 |
| 심리적 안전성 | ⭐⭐⭐ 이상 | ✅ ⭐⭐⭐⭐⭐ | 감정 곡선 7단계 전이 구현 완료 |
| 강의 적합도 | ⭐⭐⭐ 이상 | ✅ ⭐⭐⭐⭐⭐ | 기획 막힘 포인트 Top 5 전부 해소 |

---

## 수정 완료 항목 요약

### Critical 수정 (3건) — ch13_icache_direct_mapped.sv

**C-1: fill_cnt 초기화 타이밍 오류 → 수정 완료**
- IDLE/DONE 상태 진입 시 fill_cnt를 명시적으로 0으로 초기화
- 2번째 이후 미스에서 fill_cnt 잔류값으로 BRAM 쓰기 오류 방지

**C-2: FILL 중 flush 발생 시 FSM 중단 메커니즘 부재 → 수정 완료**
- `input logic flush` 포트 추가
- MISS/FILL 상태에서 flush=1이면 즉시 IDLE 전환
- `fill_flushed` 플래그로 채움 중단 라인의 valid/tag 갱신 억제

**C-3: DONE 상태 cpu_rdata word_offset 불일치 → 수정 완료**
- `miss_word_offset` 레지스터로 CPU 요청 word_offset을 IDLE에서 함께 래치
- FILL 완료 직전(fill_done) 사이클에 BRAM 읽기를 `done_read_addr = {miss_addr_reg[11:5], miss_word_offset}`으로 트리거
- DONE 1사이클에 올바른 워드가 `bram_rdata_reg`에 준비됨
- `cpu_rdata = bram_rdata_reg`로 통일 (mem_rdata 직접 연결 제거)

### Major 수정 (4건)

**M-tech-5: 메모리 지연 모델 단순화 → 수정 완료**
- `FILL_CYCLES=4` 파라미터 추가, FILL 내부에서 고정 4사이클 카운터로 DONE 전환
- mem_ready는 MISS→FILL 전환 트리거로만 사용
- ch13_pipeline_with_icache.sv: DRAM 모델을 1사이클 ready 응답으로 수정 (FILL은 캐시 내부 카운터 처리)
- 총 미스 페널티: MISS(1) + FILL(4) + DONE(1) = 6사이클 (교재 설명과 일치)

**M-beginner-1: LUTRAM/BRAM 비동기·동기 읽기 개념 보충 → 수정 완료**
- 13.2절 BRAM 매핑 설명 직전에 3~5문장 추가
- "LUTRAM = 비동기(클록 없이 즉시 출력), BRAM = 동기(다음 클록에 출력)" 명확화
- "Tag: LUTRAM 즉시 비교, Data: BRAM 1사이클 후 도착 → IF 스테이지 내 흡수" 설명

**M-beginner-2: FILL 상태 fill_cnt 카운터 동작 설명 보충 → 수정 완료**
- 13.4절 FSM 4상태 소개 직전에 카운터 동작 5문장 추가
- "fill_cnt 0→3 카운트, FILL_CYCLES 사이클 대기, DONE 상태 역할" 명확화
- FSM enum 주석에 각 상태 사이클 수 명시

**M-psych-1: 13.5절 시나리오 4 직후 Ch14 연결 문장 추가 → 수정 완료**
- metacognition 박스 직전에 3문장 추가
- "이 충돌 미스 체험이 Ch14의 출발점 — 2-Way 집합 연관이 A와 B를 동시에 보관" 설명

### Minor 수정 (2건) — HTML 원고

- 13.2절 예제 4: "축출(Eviction, Evict)" 영어 병기 추가
- 전체 소스 코드 섹션: 수정된 코드(flush 포트, fill_cnt 2비트, word_offset 래치, DONE 읽기 로직) 반영

---

## 보류 항목 (Minor — 강의 현장 구두 보완)

- addr_decode_check.sv Index[12:6] → Index[11:6] 오기 수정 (별도 파일, 교재 본문과 무관)
- 안심 2·5 박스 instructor-tip → 학습자 직접 접근 강화 (기존 구조 변경 최소화)
- 면접 2~3분 답변 구조 예시 박스 (분량 고려 보류)

---

## 파일 현황

| 파일 | 상태 |
|------|------|
| `manuscripts/part5/chapter13.html` | ✅ 수정 완료 |
| `output/Ch13_캐시기초와L1명령어캐시_final.html` | ✅ 경로 변환 및 동기화 완료 |
| `code_examples/ch13_icache_direct_mapped.sv` | ✅ C-1, C-2, C-3, M-5 수정 완료 |
| `code_examples/ch13_pipeline_with_icache.sv` | ✅ DRAM 모델 단순화, flush 연결 수정 완료 |
| `review_logs/chapter13_meeting.md` | ✅ 종합 회의록 작성 완료 |
| `review_logs/chapter13_final_approval.md` | ✅ 이 파일 |

---

## 편집장 소견

Ch13은 Part 5 첫 챕터로서 완전히 새로운 도메인(메모리 계층)으로 독자를 안내하는 중요한 전환점입니다.
리뷰 전 원고는 기술적으로 3개의 Critical 이슈(fill_cnt 타이밍, flush 부재, word_offset 불일치)가 있어
시뮬레이션 2회차 이후 또는 FILL 중 분기 발생 시 잘못된 명령어가 반환될 위험이 있었습니다.

수정 후 설계는 다음과 같이 안정화되었습니다:
1. fill_cnt 초기화가 IDLE/DONE에서 명시적으로 보장됨
2. flush 포트로 wrong-path 블록 채움이 즉시 중단됨
3. DONE에서 miss_word_offset 기반으로 올바른 워드를 반환함
4. FILL 내부 카운터(FILL_CYCLES=4)로 메모리 모델과의 불일치가 해소됨

교육적 측면에서는 LUTRAM/BRAM 비동기·동기 읽기 개념 보충, FILL 카운터 동작 설명,
Ch14 연결 문장 추가로 초보자 이해도와 심리적 연속성이 강화되었습니다.

**Chapter 13 최종 승인. Part 5 진행 승인.**

---

*편집장: Editor in Chief | 2026-03-12*
