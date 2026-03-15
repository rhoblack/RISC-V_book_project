# RISC-V 교재 프로젝트 메모리

## 📊 현재 진행 현황 (2026-03-15)

**완료**: Ch01~Ch24 (24/25, 96%)
**진행중**: Ch25 Phase 2 (초안 작성) — 일시 정지
**부록**: A~F (미계획)

---

## Ch24 최종 승인 완료

**상태**: ✅ Critical 0, Major 0

**파일**:
- 원고: `manuscripts/part9/chapter24.html` (1,341줄)
- 코드: 10개 모듈 (600줄)
- SVG: 4개 다이어그램
- Output: `output/Ch24_RV32I_확장_M_F_표준_확장_final.html`

**평가**: ⭐⭐⭐⭐⭐ (모든 항목)

**내용**: M확장(MUL/MULH/DIV/REM 등), F확장(IEEE 754), Zicntr(성능카운터), 파이프라인통합

---

## 에이전트 팀 운영

- 역할 정의: CLAUDE.md 섹션 참조
- 워크플로우: 4 Phase (기획→초안→리뷰→회의)
- 팀 정리: 각 Phase 완료 후 TeamDelete 실행

## Ch25 Phase 1 기획 완료 (2026-03-15)

**팀**: ch25-planning (3명 병렬 기획)

**기획 내용**:
- **기술 저자**: 25.1 (MESI), 25.2 (LR/SC) 각 절 핵심 메시지, 코드 예제(4~5개), SVG 다이어그램(3개) 정의
- **교육설계자**: 학습목표 5개(Understanding→Creation), 블룸 수준별 인지부하, 파이프라인과의 연결고리 분석
- **교육전문강사**: 막힘 포인트 Top 5 (병렬사고전환, MESI복잡도, LR/SC예약, 버스스누핑, 성능한계) + 해소 전략

**기획 문서**: `review_logs/chapter25_plan.md`

**주요 설계 결정**:
- 2코어 모델 고정 (4코어는 복잡도 폭증)
- MESI + LR/SC 구현 (실무 표준)
- Basys 3 시뮬레이션 주력 (구현은 선택사항)
- 실생활 비유 병행 (은행ATM, 도서관자리, 스마트폰멀티코어)

## Ch25 Phase 2 일시 정지 (2026-03-15)

**현재까지 생성된 파일**:
- ✅ `review_logs/chapter25_plan.md` (기획 문서 완성)
- ✅ `figures/ch25_sec01_mesi_states.svg`
- ✅ `figures/ch25_sec01_multicore_coherence.svg`
- ✅ `figures/ch25_sec02_spinlock_lr_sc.svg`
- ✅ `code_examples/ch25_mesi_tracker.sv`
- ✅ `code_examples/ch25_spinlock_lr_sc.sv`
- ✅ `code_examples/ch25_mesi_tracker_tb.sv`
- ✅ `code_examples/ch25_lr_sc_unit_tb.sv`
- ⏳ `manuscripts/part9/chapter25.html` (진행 중)
