# 편집장 종합 회의록
## 일자: 2026-03-11
## 안건: Ch01~Ch05 Syntax Highlighting + 전체 소스 코드 섹션 수정

### 참여 에이전트
- 기술 리뷰어, 교육심리전문가, 교육전문강사, 총괄 편집장

---

### 이슈 처리 결과

| 이슈 | 분류 | 처리 | 결과 |
|------|------|------|------|
| M01 HTML 이스케이프 | 🟡 Major | 수정 완료 | Ch01·Ch04·Ch05 본문 코드 블록 내 `<=`, `&`, `<<`, `>>` 전체 이스케이프 처리. `&amp;`, `&lt;`, `&gt;` 이중 이스케이프 방지 로직 적용. |
| M02 언어 스크립트 | 🟡 Major | 수정 완료 | 5개 파일 모두 `verilog.min.js` 직후에 `tcl.min.js`, `bash.min.js` 스크립트 태그 삽입. |
| M03 클래스 오류 | 🟡 Major | 수정 완료 | `chapter04.html` VCS 명령어 블록의 `language-systemverilog` → `language-bash` 변경. 주석 스타일도 `//` → `#`로 일관성 있게 수정. |
| E01 섹션 위치 | 🟡 Major | 수정 완료 | 5개 파일 모두 `full-source-section`을 연습문제(exercises) 섹션 **이후**, Highlight.js 스크립트 **직전**으로 이동. Ch02는 `exercise-answers` 섹션 포함으로 그 이후 위치 확인. |
| N01 완충 텍스트 | 🟢 Minor | 수정 완료 | 5개 파일의 "전체 소스 코드" 섹션 도입부를 "지금 당장 전부를 이해하려 하지 않아도 됩니다" 안심 문구 포함 3문장으로 교체. Ch02는 기존 이론 설명 단락을 보존하고 안심 문구를 첫 번째 문단으로 추가. |

---

### 수정 파일 목록

| 파일 | 적용된 이슈 |
|------|------------|
| `manuscripts/part0/chapter01.html` | M01, M02, E01, N01 |
| `manuscripts/part1/chapter02.html` | M01(경미), M02, E01, N01 |
| `manuscripts/part1/chapter03.html` | M01(경미), M02, E01, N01 |
| `manuscripts/part2/chapter04.html` | M01, M02, M03, E01, N01 |
| `manuscripts/part2/chapter05.html` | M01, M02, E01, N01 |

---

### 검증 결과 (자동화 스크립트)

모든 5개 파일에 대해 아래 항목을 자동 검증하였으며, 전항 통과:

- **M01**: `<pre><code>` 블록 내 raw `<` 문자 없음 — CLEAN
- **M02**: `tcl.min.js`, `bash.min.js` 스크립트 태그 존재 — OK
- **E01**: `full-source-section` 위치 > `exercises` 위치 — OK
- **N01**: "지금 당장 전부를 이해하려 하지 않아도 됩니다" 문구 존재 — OK
- **M03**: Ch04 `language-bash` 클래스 확인 — OK

---

### 편집장 결정 사항

1. **이중 이스케이프 방지**: `&amp;`, `&lt;`, `&gt;`, `&#` 형태로 이미 이스케이프된 시퀀스는 보호 후 처리하여 이중 이스케이프 없음.
2. **"전체 소스 코드" 섹션 위치**: 학습자 성취감 정착 후 참조 가능하도록 연습문제 이후 배치. 학습 흐름: 본문 → 요약 → 연습문제 → 전체 소스 코드.
3. **Ch04 VCS 블록**: `//` 스타일 주석도 Bash 관행(`#`)으로 함께 수정하여 일관성 확보.

---

### 최종 승인

- Critical 이슈: 0개
- Major 이슈 수정: 5건 → 0건
- Minor 이슈 수정: 1건 → 0건
- 상태: ✅ APPROVED

> 총괄 편집장 확인: 2026-03-11
