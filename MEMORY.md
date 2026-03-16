# RISC-V 교재 프로젝트 메모리

## 📊 현재 진행 현황 (2026-03-16)

**완료**: Ch01~Ch24 (24/25, 96%) — output 폴더에 _final.html 24개 배포
**진행중**: Ch25 Phase 2 (초안 작성) — 기획 완료, 원고 작성 준비 중
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

## Ch25 Phase 2 초안 완료 (2026-03-16)

**완성된 파일**:
- ✅ `review_logs/chapter25_plan.md` (기획 문서)
- ✅ `figures/ch25_sec01_mesi_states.svg` (MESI 상태 전이도)
- ✅ `figures/ch25_sec01_multicore_coherence.svg` (캐시 일관성 문제 시각화)
- ✅ `figures/ch25_sec02_spinlock_lr_sc.svg` (LR/SC 타이밍 다이어그램)
- ✅ `code_examples/ch25_mesi_tracker.sv` (MESI 상태 추적기)
- ✅ `code_examples/ch25_spinlock_lr_sc.sv` (LR/SC 실행 유닛)
- ✅ `code_examples/ch25_mesi_tracker_tb.sv` (MESI 테스트벤치)
- ✅ `code_examples/ch25_lr_sc_unit_tb.sv` (LR/SC 테스트벤치)
- ✅ `manuscripts/part9/chapter25.html` (1,341줄 원고 완성)

**원고 통계**:
- 전체 라인: 1,341
- 섹션: 2개 (25.1 MESI, 25.2 LR/SC)
- 학습 목표: 5개 (Remember~Create)
- Aside 박스: 8개 (tip 1, faq 2, interview 1, metacognition 1, instructor-tip 1 + 추가 2)
- 코드 예제: 4개 모두 포함 + 주석 상세
- SVG 다이어그램: 3개 모두 참조
- 비유: 4개 (도서관 필기본, Google Docs, 도서관 자리 예약, 은행 ATM/멀티프로세서 작업자)

**핵심 내용**:
- 25.1: MESI 상태 기계(M/E/S/I), 상태 전이 시나리오 6개, 버스 스누핑, 성능 분석
- 25.2: LR/SC 명령어 시맨틱스, 예약 메커니즘, 스핀락 구현, Lock-Free 개요

**다음 단계**: Phase 3 병렬 리뷰 (기술 리뷰어, 초보자 독자, 교육 설계자, 심리 전문가, 강사)

---

## output 폴더 상태 (2026-03-16 확인)

**배포 완료**:
- 24개 최종 HTML 파일 (Ch01~Ch24_*_final.html)
- 모든 파일 40~90KB 범위 (타임스탐프: 2026-03-15)

**준비 중**:
- `output/docx/` (Word 산출물)
- `output/ppt/` (PPT 강의자료)
- `output/workbook/` (연습문제 워크북)
