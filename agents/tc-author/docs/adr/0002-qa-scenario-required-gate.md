# Select는 QA Scenario가 Not Required가 아닌 이슈에서 Reproduction 존재를 요구한다

원 요구사항은 "description/comment에 reproduction이 존재하는 이슈"만이 선정 기준이었다. 그러나 조직은 Jira 커스텀 필드 QA Scenario(`cf[210565]`, 값 Required/Not Required/Not Yet)로 TC 필요 여부를 공식적으로 판정하고 있음이 확인됐다(과거 jira-trim 세션에서 Not Required ∩ repro 없음이 close 대상으로 처리된 선례). 따라서 Select는 **QA Scenario ∈ {Required, Not Yet} ∩ Reproduction 존재**를 요구한다. repro만으로 선정하면 Not Required(예: EPIC, 검증 케이스 추가)에 불필요한 TC를 만들 위험이 있고, 필드가 있는데도 무시하는 셈이 되기 때문이다.

## 개정 (2026-07-06, 같은 설계 세션)

최초 결정은 Required만 포함하고 Not Yet(판단 보류)을 제외했다. 그러나 과거 수동 triage(`~/workspace/jira/tc_triage.md`)와 대조한 결과, 가장 확실하고 쉬운 SQL 후보인 CBRD-25913(결정적 syntax error 재현, 공수 최하)이 Not Yet이라는 이유만으로 본문 판독 없이 탈락함이 드러났다. Not Yet은 "판단을 아직 안 했다"는 뜻이므로, 봇이 TC 초안을 Draft PR로 제안하는 것 자체가 판단 재료가 된다. 이에 **Not Yet도 포함**하고 Not Required만 제외하는 것으로 개정했다. 내용 판단(repro·SQL 재현성 게이트)은 동일하게 적용되므로 불필요한 TC 양산 위험은 그대로 차단된다.
