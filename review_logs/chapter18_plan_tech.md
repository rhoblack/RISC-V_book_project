# Chapter 18 — CSR과 시스템 명령어 (기술 저자 기획)

**작성일**: 2026-03-15
**담당**: 기술 저자

## 1. 장 구조 및 분량 계획

### 18.1 특권 수준과 CSR 레지스터 (1,500~2,500자)
- M-mode 개념, CSR 정의, 주소 공간
- 비유: "CSR = 프로세서의 설정창" (한계: 하드웨어 직접 영향)
- SVG 1: ch18_sec01_csr_overview.svg (프로세서 블록다이어그램)

### 18.2 핵심 CSR 구현 (1,500~2,500자)
- 7개 CSR: mstatus, mtvec, mepc, mcause, mie, mip, mscratch
- 비유: "mstatus = 자동차 대시보드" (한계: 제어 기능)
- SVG 2: ch18_sec02_mstatus_layout.svg (비트 구조)

### 18.3 CSR 명령어 구현 (2,000~3,000자)
- CSRRW, CSRRS, CSRRC, CSRRWI, CSRRSI, CSRRCI (I-타입)
- 원자성 보장
- SVG 3: ch18_sec03_csrrw_dataflow.svg (데이터 흐름)

### 18.4 CSR 동작 확인 미니 실습 (1,500~2,500자)
- 3단계: 읽기 → 쓰기 → 비트조작
- 코드 1: ch18_csr_register_file.sv (~200줄)
- 코드 2: ch18_csr_tb.sv (~150줄)

### 18.5 본 장 요약 (1,000~1,500자)
- 자가 점검 5개 질문, Ch19 예고

## 2. 신규 SVG 최종 목록
1. ch18_sec01_csr_overview.svg — 프로세서 블록다이어그램 + CSR
2. ch18_sec02_mstatus_layout.svg — mstatus 비트 레이아웃
3. ch18_sec03_csrrw_dataflow.svg — CSRRW 데이터 흐름

## 3. 신규 코드 최종 목록
1. ch18_csr_register_file.sv — 7개 CSR 저장소
2. ch18_csr_tb.sv — 3단계 시뮬레이션

## 4. 주요 비유
1. CSR = "프로세서의 설정창" (한계: 하드웨어 직접 영향)
2. M-mode = "관리자 권한" (한계: 프로세서의 모드)
3. mstatus = "프로세서 상태 플래그" (한계: 제어 기능)

**Phase 2 Ready**
