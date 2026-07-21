# Select는 QA Scenario가 Not Required가 아닌 이슈에서 Reproduction 존재를 요구한다

원 요구사항은 "description/comment에 reproduction이 존재하는 이슈"만이 선정 기준이었다. 그러나 조직은 Jira 커스텀 필드 QA Scenario(`cf[210565]`, 값 Required/Not Required/Not Yet)로 TC 필요 여부를 공식적으로 판정한다. 따라서 Select는 **QA Scenario ∈ {Required, Not Yet} ∩ Reproduction 존재**를 요구한다.

- repro만으로 선정하면 Not Required(예: EPIC, 검증 케이스 추가)에 불필요한 TC를 만들 위험이 있고, 필드가 있는데도 무시하는 셈이 된다.
- **Not Yet(판단 보류)을 포함**하는 이유: Not Yet은 "판단을 아직 안 했다"는 뜻이라, 봇이 TC 초안을 Draft PR로 제안하는 것 자체가 판단 재료가 된다. Required만 받으면 확실하고 쉬운 후보가 본문 판독 없이 탈락한다(과거 수동 triage 대조로 확인). 내용 판단(repro·SQL 재현성 게이트)은 동일하게 적용되므로 불필요한 TC 양산 위험은 그대로 차단된다.
