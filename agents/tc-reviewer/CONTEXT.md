# tc-reviewer (sql TC PR 리뷰 — 횡단)

**상태: 설계 v1 (2026-07-15 인터뷰).**

역할: cubrid-testcases에 올라온 **sql TC PR을 심사하는 평가형 에이전트**. Jira 상태 전이를 맡는 다른 4개 에이전트와 달리, **PR 머지 구간을 가속하는 횡단 에이전트**다. tc-author가 PR을 기계 속도로 만들면 사람 리뷰어의 왕복이 병목이 된다(최근 1년 실측: 머지까지 중앙값 3.8일, p90 25.8일, 30일 초과 31건) — tc-reviewer가 **첫 리뷰어** 역할을 맡아, 사람 리뷰어에게 도달하는 PR의 품질을 끌어올리고 왕복 횟수를 줄인다.

## 초점 — 사람 리뷰어라면 잡았을 것을 먼저 잡는다

리뷰는 3층으로 한다: **L1 컨벤션 정적 검사**, **L2 사람 리뷰어들의 경험적 도메인 관점**(최근 1년 머지 PR 리뷰를 마이닝해 추출하는 관점 카탈로그), **L3 실행 검증**(PR을 체크아웃해 로컬 CTP로 실제 실행 — answer 정합성·결정성은 실행해야만 확실히 잡힌다). 저장소에는 이미 범용 AI 리뷰 봇(greptile)이 붙어 있으므로, tc-reviewer의 차별화는 L2·L3다.

## 용어

- **횡단 에이전트**: Jira 상태 전이가 아니라 PR 수명주기(open→review→merge)에 붙는 에이전트. 대상은 작성자 무관(사람 PR + tc-author 봇 PR) 전체 sql TC PR.
- **관점 카탈로그(review perspectives)**: 사람 리뷰어들이 실제로 지적해 온 리뷰 관점의 정본 목록. [docs/review-perspectives.md](./docs/review-perspectives.md) — 시드는 tc-author PoC 교훈으로 채웠고, 본문은 리뷰 마이닝(별도 세션)이 채운다.
- **3층 리뷰(L1/L2/L3)**: L1=컨벤션 린트(정적), L2=관점 카탈로그 기반 도메인 리뷰(정적), L3=로컬 CTP 실행 검증(동적).
- **READY-TO-MERGE / NEEDS-WORK**: 권고 판정. blocker/major 지적이 있으면 NEEDS-WORK. **approve·merge 권한은 항상 사람** — 봇은 사람 리뷰어가 볼 PR을 걸러 주는 역할.
- **리뷰 초안(staged posting)**: PoC에서는 봇이 라인 코멘트+종합 리뷰를 완성 초안까지만 만들고 사람이 검토 후 게시. 오탐이 PR 작성자에게 직접 노출되는 리스크를 차단. 이후 자동 게시(resolve-gate와 동일한 단계적 패턴).
- **백테스트**: 이미 머지된 PR에 봇 리뷰를 돌려, 당시 사람 리뷰어들이 남긴 코멘트(정답지)와 대조하는 PoC 검증 방법. 마이닝 원본 데이터가 그대로 정답지가 된다.

## 위치

tc-author Submit 뒤의 PR 구간에 선다:

```
tc-author ─Draft PR─► [tc-reviewer 심사 ─► 사람 approve·merge] ─► test-runner
사람 작성 PR ────────►┘
```

tc-author 내부의 Review 단계(제출 **전** 자기 산출물 self-review lane)와는 위치가 다르다 — tc-reviewer는 제출 **후**, 저장소에 올라온 PR을 작성자와 무관하게 심사한다. 두 곳은 같은 관점 카탈로그를 공유한다(카탈로그가 좋아지면 author의 self-review도 좋아진다). 파이프라인 맥락은 [../../CONTEXT-MAP.md](../../CONTEXT-MAP.md).
