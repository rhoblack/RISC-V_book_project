# Chapter 14 최종 승인서

**챕터**: Chapter 14 — L1 데이터 캐시와 쓰기 정책
**승인 날짜**: 2026-03-12
**편집장**: 편집장 (Editor in Chief)

---

## 최종 파일 경로

| 구분 | 경로 |
|------|------|
| 원고 | `manuscripts/part5/chapter14.html` |
| output | `output/Ch14_L1_데이터_캐시와_쓰기_정책_final.html` |

---

## Phase 3 리뷰 결과 요약

| 리뷰어 | 최종 점수 | Critical | Major |
|--------|----------|---------|-------|
| 기술 리뷰어 | — | **0건** | **0건** |
| 초보자 독자 | ⭐⭐⭐⭐ | 0건 | 0건 (수정 적용) |
| 교육 설계자 | ⭐⭐⭐⭐⭐ | 0건 | 0건 |
| 교육심리전문가 | ⭐⭐⭐⭐ | 0건 | 0건 |

---

## Phase 4 수정 사항 (7건 모두 적용 완료)

| # | 위치 | 수정 내용 | 우선순위 |
|---|------|----------|---------|
| 1 | 14.1절 비유 | 도서관 비유 한계 문구 추가 | High |
| 2 | 14.3절 비유 | 지정석 비유 한계 문구 추가 | High |
| 3 | 14.2절 FSM 표 | 14.5절 FSM 상태 전이도 참조 안내 문단 삽입 | High |
| 4 | 14.3절 | `latched_replace_way` 직관적 설명 문단 삽입 | High |
| 5 | 14.4절 | Byte Enable 출처 (funct3 → byte_en) 설명 추가 | High |
| 6 | 14.6절 | FENCE.I 코드 의사코드 명시 + 코드 주석 보완 | High |
| 7 | 14.7절 | 마무리 문장 1문단 → 3문단으로 보강 (성취감 + Ch15 예고) | High |

---

## 승인 기준 최종 점검

| 기준 | 요구값 | 달성값 | 판정 |
|------|--------|--------|------|
| Critical 건수 | 0건 | **0건** | ✅ PASS |
| Major 건수 (기술 기준) | 0건 | **0건** | ✅ PASS |
| 초보자 이해도 | ⭐⭐⭐ 이상 | **⭐⭐⭐⭐** | ✅ PASS |
| 교육 설계 | ⭐⭐⭐ 이상 | **⭐⭐⭐⭐⭐** | ✅ PASS |
| 심리적 안전성 | ⭐⭐⭐ 이상 | **⭐⭐⭐⭐** | ✅ PASS |

---

## 챕터 주요 설계 내용 (기록)

- **Write-Back 정책**: Dirty 비트로 수정 라인 추적, Eviction 시에만 메모리 기록
- **D-Cache 구조**: 4KB / 직접 매핑 → 4KB / 2-Way 세트 연관 (64세트 × 2Way × 32B)
- **주소 분해 (2-Way)**: Tag 21비트[31:11], Index 6비트[10:5], Offset 5비트[4:0]
- **D-Cache FSM 5상태**: IDLE → TAG_CHECK → (Hit: IDLE / Clean: REFILL → UPDATE → IDLE / Dirty: WRITE_BACK → REFILL → UPDATE → IDLE)
- **LRU**: 세트당 1비트, 접근된 Way의 반대편을 LRU로 표시
- **latched_replace_way**: TAG_CHECK에서 결정된 교체 대상 Way를 WRITE_BACK/REFILL에서 일관 사용
- **dcache_stall**: D-Cache 미스 시 전체 파이프라인 동결 (PC + 전 스테이지 Hold)
- **Byte Enable**: funct3 → byte_en (SW=4'b1111, SH=4'b0011, SB=4'b0001)
- **캐시 일관성**: 하버드 구조에서 FENCE.I로 I-Cache 전체 무효화

---

## 편집장 최종 결정

Chapter 14는 Phase 3 리뷰의 모든 필수 수정(7건)을 완료하였으며, 최종 승인 기준을 전항목 충족합니다.

**✅ Chapter 14 — 최종 승인 (APPROVED)**

다음 단계: Chapter 15 — 메모리 컨트롤러와 캐시-메모리 인터페이스
