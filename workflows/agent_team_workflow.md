# Agent Team 워크플로우 — RISC-V 프로세서 설계 완전정복

## Phase 1: 기획 회의

**참여**: 저자 + 교육설계자 + 강사 (3 teammates 병렬)
**출력**: `review_logs/chapterNN_plan.md`

**실행 프롬프트** (`[N]`=챕터번호, `[NN]`=두자리번호):
```
Chapter [N] 기획 회의를 위한 에이전트 팀을 만들어줘.

세 명의 teammate를 병렬로 생성해줘:

1. 기술 저자 teammate:
   - agents/technical_author.md 파일을 읽어 역할을 숙지해줘
   - TABLE_OF_CONTENTS.md에서 Chapter [N]의 절 목록을 분석해줘
   - 각 절의 핵심 메시지, 필요한 SystemVerilog 코드 예제 목록, SVG 다이어그램 목록을 작성해줘

2. 교육 설계자 teammate:
   - agents/instructional_designer.md 파일을 읽어 역할을 숙지해줘
   - Chapter [N]의 학습 목표 3~5개를 "~할 수 있다" 형태로 정의해줘
   - 블룸 분류체계 기준으로 인지 부하 설계 계획을 작성해줘

3. 교육전문강사 teammate:
   - agents/expert_instructor.md 파일을 읽어 역할을 숙지해줘
   - Chapter [N]에서 수강생이 막힐 것으로 예상되는 포인트 Top 5를 작성해줘
   - 각 막힘 포인트에 대한 사전 해소 방법을 제안해줘

세 teammate가 각자 작업 완료 후 서로의 의견을 검토하고 통합해서
review_logs/chapter[NN]_plan.md를 최종 완성한 다음 팀 리드에게 보고해줘.
완료 후 팀을 정리해줘.
```

---

## Phase 2: 초안 작성

**참여**: 기술 저자 (단독)
**출력**: `manuscripts/partN/chapterNN.html` + SVG + 코드

**실행 프롬프트**:
```
기술 저자 teammate를 생성해줘.

agents/technical_author.md 파일을 읽어 역할을 숙지한 후:

1. review_logs/chapter[NN]_plan.md를 읽어 기획 내용을 파악해줘
2. templates/chapter_template.html 구조를 따라
   manuscripts/part[N]/chapter[NN].html을 HTML로 집필해줘
3. 필요한 다이어그램은 figures/ 디렉터리에 SVG로 생성해줘
4. SystemVerilog 코드 예제는 code_examples/ 디렉터리에 별도 파일로 저장해줘

집필 중 각 절 완료 시 팀 리드에게 진행 상황을 보내줘.
전체 완료 후 팀 리드에게 보고해줘.
```

---

## Phase 3: 병렬 리뷰

**참여**: 리뷰어 + 독자 + 심리 + 강사 (4 teammates 동시)
**출력**: 4개 리뷰 파일

**실행 프롬프트**:
```
Chapter [N] 초안(manuscripts/part[N]/chapter[NN].html)에 대한
병렬 리뷰 팀을 만들어줘. 네 명의 teammate를 동시에 생성해줘:

1. 기술 리뷰어 teammate:
   - agents/technical_reviewer.md 역할
   - SystemVerilog 코드 정확성, RV32I 스펙 준수, AMBA 프로토콜 준수 검토
   - review_logs/chapter[NN]_tech_review.md에 [Critical/Major/Minor] 분류로 저장

2. 초보자 독자 teammate:
   - agents/beginner_reader.md 역할
   - 이해도 5점 척도 평가, 설명 없이 등장하는 용어 목록
   - review_logs/chapter[NN]_beginner_review.md에 저장

3. 교육심리전문가 teammate:
   - agents/educational_psychologist.md 역할
   - 학습 불안 지점, 자기효능감 위기 포인트, 감정 곡선 분석
   - review_logs/chapter[NN]_psych_review.md에 저장

4. 교육전문강사 teammate:
   - agents/expert_instructor.md 역할
   - 설명·비유 품질, 수강생 단골 질문 추가 제안, 강의 흐름 평가
   - review_logs/chapter[NN]_instructor_review.md에 저장

각 teammate가 리뷰 완료 후 서로의 리뷰 파일을 읽고 보완 의견을 교환한 다음
팀 리드에게 보고해줘. 완료 후 팀을 정리해줘.
```

---

## Phase 4: 종합 회의 및 수정

**참여**: 편집장 종합 → 기술 저자 수정 → 편집장 승인
**출력**: `review_logs/chapterNN_meeting.md` + 수정된 HTML

**실행 프롬프트**:
```
review_logs/chapter[NN]_*.md 파일을 모두 읽고 종합 회의록을 작성해줘.

회의록 형식 (review_logs/chapter[NN]_meeting.md):
- 각 리뷰어 피드백 요약
- Critical/Major 이슈 목록
- 반영할 피드백 vs 보류 피드백
- Action Items

그런 다음 기술 저자 teammate를 생성해서:
- agents/technical_author.md 역할
- Critical/Major 피드백을 우선 반영하여 chapter[NN].html을 수정
- 수정 완료 후 팀 리드에게 보고

수정 완료 후, 팀 리드(편집장)가 다음 기준으로 최종 승인 여부를 판단해줘:
- Critical 이슈 0개
- Major 이슈 0개
- 초보자 이해도 ⭐⭐⭐ 이상
- 교육 설계/심리적 안전성/강의 적합도 각 ⭐⭐⭐ 이상
```
