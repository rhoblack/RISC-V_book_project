# 산출물 생성 가이드

교재 원본(HTML)에서 3종류의 산출물을 생성합니다.

```
교재 HTML ─┬──→ 강의 PPT
           ├──→ 워크북 (HTML / DOCX / PPT)
           └──→ 교재 Word
```

---

## 1. 강의용 PPT

### 도구
- pptxgenjs (Node.js)
- `npm install -g pptxgenjs`

### 제작 원칙
- **코드 제외**, 이론 + 다이어그램 + 표 + 비유 중심
- 한 슬라이드 = 하나의 메시지
- 페이지 수 제한 없음, 내용을 충실하게
- 한 페이지에 글을 너무 많이 쓰지 않고 페이지를 늘리는 방식

### 디자인 적용 방법
1. 사용자가 Canva 등에서 템플릿 PPTX를 제공
2. 템플릿 분석 (thumbnail.py + unpack.py + markitdown)
   - 색상 팔레트 추출 (srgbClr)
   - 폰트 추출 (typeface)
   - 글씨 크기 추출 (sz)
   - 레이아웃 유형 파악
3. 분석 결과를 코드의 디자인 상수로 반영
4. 모든 슬라이드에 일관된 스타일 적용

### 슬라이드 구성 (교재 챕터당)
```
표지 → 목차 → 절별 내용 (이론 + 다이어그램 + 표 + 비유)
→ FAQ → 면접 포인트 → 핵심 정리 → 면접 키워드 → Thank You
```

### 교재 → PPT 변환 규칙
| 교재 요소 | PPT 표현 |
|----------|---------|
| 절 제목 (h2) | 슬라이드 제목 |
| 본문 텍스트 | 슬라이드 본문 (한 페이지에 적정량) |
| 코드 예제 | **제외** (라이브코딩으로 별도 진행) |
| 표 (table) | PPT 표로 변환 |
| SVG 다이어그램 | pptxgenjs 도형으로 재구성 |
| aside (tip) | 💡 카드 박스 |
| aside (faq) | ❓ FAQ 슬라이드 |
| aside (interview) | 🎯 면접 슬라이드 |
| aside (instructor-tip) | 📌 강사 꿀팁 슬라이드 |
| aside (metacognition) | 포함하지 않음 (수업 중 구두로) |

### QA
```bash
# PDF 변환 + 이미지 생성 + 썸네일
python scripts/office/soffice.py --headless --convert-to pdf output.pptx
pdftoppm -jpeg -r 150 output.pdf slide
python scripts/thumbnail.py output.pptx
```

---

## 2. 워크북

### 가이드 레벨
| 레벨 | 설명 | 용도 |
|------|------|------|
| L1 | 풀 가이드 (체크리스트 + 내용 포함) | 처음 수강생 |
| L2 | 반 가이드 (체크리스트 + 핵심만) | 복습용 |
| L3 | 최소 가이드 (체크리스트만) | 실력 점검 |
| L4 | 빈칸만 | 시험/평가용 |

### 워크북 구성 (5~6페이지)
```
Page 1: 학습 목표 체크표 + 핵심 프로세스/구조
Page 2: Feature/스펙 체크리스트 (구현/통과 체크박스)
Page 3: 구현 단계별 체크리스트
Page 4: 전략/비교표 + 빌드/실행 명령어 + 에러 대응
Page 5: 디버깅 챌린지 (빈칸 답변 공간)
Page 6: 면접 대비 핵심 답변 + 키워드
```

### 출력 형식
- **HTML** (기본) — 브라우저 인쇄로 A4 출력
- **DOCX** (docx-js) — Word 파일
- **PPT** (pptxgenjs) — 프로젝터 출력용

---

## 3. 교재 Word

### 도구
- docx-js (Node.js)
- `npm install -g docx`

### 제작 원칙
- 출판용 편집 원고
- A4 기준, 바인딩 여백 확보
- 헤더/푸터 (챕터명 + 페이지 번호)
- 목차 자동 생성 (HeadingLevel)

### 파일 규칙
- 교재 HTML의 모든 내용을 포함 (코드 포함)
- 구문 하이라이트는 폰트 색상으로 대체
- SVG 다이어그램은 PNG로 변환하여 삽입
- aside 박스는 테두리 + 배경색 표로 변환
