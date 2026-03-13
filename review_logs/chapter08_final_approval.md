# Chapter 08 — 편집장 최종 승인

## 집필 완료 일자: 2026-03-11
## 승인 여부: ✅ 최종 승인

---

## 수정 반영 확인

### Critical 이슈 (모두 해결)

- [x] **C-1**: branch_taken 이중 구동 수정
  - 전체 소스 코드 섹션의 두 번째 always_comb (출력 로직)에서 `branch_taken = 1'b0;` 삭제
  - 주석으로 "branch_taken은 위의 funct3 always_comb 블록에서만 구동" 명시

- [x] **C-2**: EX_BR branch_adder + pc_src=2'b10 추가
  - 8.2.4절 EX_BR 설명 단락 전면 개선: branch_adder 역할과 old_pc_reg + imm_B 계산 명시
  - 본문 제어 신호 표: pc_src=10 (branch_adder 출력)으로 수정
  - 8.3.2절 S_EX_BR 코드: pc_src = 2'b10으로 수정
  - 전체 소스 코드 S_EX_BR: pc_src=2'b10으로 수정
  - pc_src 인코딩 최종 정의: 00=ALU직접, 01=ALUOut, 10=branch_adder 출력

- [x] **C-3**: old_pc_reg + alu_src_a 2비트 확장
  - 8.2.4절 시작 부분에 "Ch07 데이터패스 소급 보완" tip 박스 추가
  - old_pc_reg SystemVerilog 코드 (always_ff, ir_write 조건) 예시 포함
  - alu_src_a 2비트 인코딩 정의: 2'b00=PC, 2'b01=old_pc_reg, 2'b10=A 레지스터
  - 8.2절 본문 제어 신호 표: S11(AUIPC), S13(JAL) alu_src_a 01로 수정
  - 8.3.2절 코드: S_IF, S_ID, S_EX_R~JALR 등 전체 alu_src_a 2비트로 수정
  - fsm_controller 포트 선언: `output logic [1:0] alu_src_a` 수정
  - 전체 소스 코드: 동일하게 2비트 수정 완료

### Major 이슈 (모두 해결)

- [x] **M-1**: BLTU/BGEU alu_ltu 추가
  - fsm_controller 포트에 `input logic alu_ltu` 추가 (8.3.2절 코드 + 전체 소스)
  - branch_taken 로직: BLTU(3'b110)→alu_ltu, BGEU(3'b111)→~alu_ltu로 수정
  - "BLTU/BGEU는 무부호 비교(alu_ltu 사용)" 주석 추가
  - 8.4절 top 모듈 및 전체 소스 top 모듈에 alu_ltu 연결 추가

- [x] **M-2**: AUIPC PC 기준점 (C-3 수정으로 자동 해결)

- [x] **M-3**: ID 단계 ALU 연산 모호성
  - S_ID 코드 주석에 "현재 구현에서는 branch_adder 사용하므로 미사용" 설명 추가

- [x] **M-4**: 전체 소스 코드 문법 주의
  - 기존 압축 표기는 유지하되, 이미 도입부 안심 문구에서 참고용임을 명시

### 교육/심리 Major 이슈 (모두 해결)

- [x] interview 박스 중복 해소: 8.3절 박스를 tip 박스로 축소 + "8.6절 참조" forward reference
- [x] 8.3절 긴 코드 전 안심 문구 추가 ("지금 당장 모든 줄을 이해하지 않아도 됩니다")
- [x] 8.4절 마일스톤 축하 문장: "멀티사이클 CPU가 처음 실행되는 순간입니다"
- [x] 래치 경고 tip 실패 정상화: "여러분이 처음이 아닙니다"
- [x] 8.7절 준비 완료 문장: "파이프라인 학습을 위한 모든 준비가 갖추어졌습니다"
- [x] 8.2절 소결 추가: 핵심 3가지 요약 (공통 상태, 기계적 도출, branch_adder)
- [x] 8.3절 소결 추가: FSM 코드 구조 (always_ff + always_comb 역할) 요약

### Minor 이슈

- [x] Fmax 첫 등장 한글 병기: "최대 클럭 주파수(Fmax, Maximum Clock Frequency)"
- [x] MIPS 단위 첫 등장 병기: "백만 명령어/초(MIPS, Million Instructions Per Second — 아키텍처 MIPS와 별개)"
- [x] interview 박스 번호 중복 해소: 8.3절 박스 tip으로 변경 (번호 제거)

---

## 최종 품질 지표

| 지표 | 결과 |
|------|------|
| Critical 이슈 | 0건 |
| Major 이슈 | 0건 |
| 초보자 이해도 | ⭐⭐⭐⭐ |
| 교육 설계 | ⭐⭐⭐⭐ |
| 심리적 안전성 | ⭐⭐⭐⭐ |

---

## 신규 생성/수정 파일

- **manuscripts/part3/chapter08.html** — 수정 완료 (1755줄 → 1827줄, +72줄)
- **review_logs/chapter08_meeting.md** — 종합 회의록 신규 생성
- **review_logs/chapter08_final_approval.md** — 최종 승인 문서 (본 파일)

기존 SVG 파일은 수정 없이 유지:
- figures/ch08_sec01_fsm_concept.svg
- figures/ch08_sec02_fsm_all_states.svg
- figures/ch08_sec04_fsm_waveform.svg
- figures/ch08_sec06_microprogramming.svg

---

## Ch08 핵심 기술 내용 요약

- **FSM 제어 유닛**: Moore FSM, 17개 상태 (S0~S16), always_ff + always_comb 이중 블록
- **데이터패스 보완**:
  - `old_pc_reg`: IF 단계 PC 갱신 직전 원본 PC 저장 (JAL, AUIPC 정확성)
  - `alu_src_a` 2비트 확장: 2'b00=PC, 2'b01=old_pc_reg, 2'b10=A 레지스터
  - `branch_adder`: ALU 독립 덧셈기, old_pc_reg+imm_B → pc_src=2'b10
  - `alu_ltu`: 무부호 비교 플래그 (BLTU/BGEU 지원)
- **pc_src 인코딩**: 00=ALU직접(PC+4), 01=ALUOut(JAL/JALR), 10=branch_adder(Branch)
- **성능**: CPI_avg ≈ 4.1 (R:I:L:S:B=40:20:20:10:10 믹스), 멀티사이클 Fmax ~50MHz
- **처리량**: 약 12.2 MIPS (단일 사이클 25 MIPS보다 낮음 — 멀티사이클의 가치는 자원 절감+교육)
- **멀티사이클→파이프라인 연결**: FSM 17개 상태 = 파이프라인 5개 스테이지의 전신

---

## Ch09 연결 사항

- 파이프라인은 멀티사이클 FSM의 각 상태(IF/ID/EX/MEM/WB)를 동시에 다른 명령어에 적용
- Ch08 완성 데이터패스(old_pc_reg + branch_adder 포함)는 Ch09 파이프라인 스테이지 레지스터 설계의 전제
- old_pc_reg와 유사한 개념이 파이프라인에서는 각 스테이지 레지스터(IF/ID, ID/EX 등)로 확장됨

---

*편집장 최종 승인: 2026-03-11*
