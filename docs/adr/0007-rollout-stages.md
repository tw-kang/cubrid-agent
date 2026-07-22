# 롤아웃은 3단계로 가고, Stage 2는 로컬 세션의 팀 공유다

외부 핸드오버 문서 2종(v1 배포 설계 = k8s CronJob/Indexed Job/dispatcher/GlusterFS 중심, v2 TC 작성 웹검증판 = oracle/회귀/결정성/리뷰 중심)을 재료로 롤아웃을 **PoC → Stage 2(팀내 수동 트리거) → Stage 3(무인 자동 서비스)**로 나눈다. 상세 분류·설계는 [staging.md](../staging.md).

핵심 결정: **Stage 2는 k8s Job이 아니라 PoC의 로컬 Claude Code 흐름을 팀이 재현하도록 패키징한 것**(스킬 + 셋업 문서 + hook 하드 게이트)이다. 배포 인프라(CronJob, Indexed Job, dispatcher, GlusterFS overlay, pod 검증(ADR 0001), rate-limit 게이트, self-healing/에스컬레이션, 무인 관측, 야간 배치)는 전부 Stage 3로 미룬다. 이유: 사용자가 "자동화 배포 전에 사람이 수동 트리거하는 형태로 팀내 먼저 배포"를 원했고, 로컬 흐름은 PoC에서 이미 검증됐으므로, 값이 큰 것(팀이 쓸 수 있게 + 게이트 강제)만 먼저 하고 인프라 리스크는 뒤로 미루는 것이 비용 대비 효과가 크다.

## 단계별로 언제 무엇이 켜지나 (grilling 확정)

- **fail→pass 실측 회귀 계약**은 **PoC부터**. fix 이전 빌드에서 TC가 실제로 FAIL함을 확인(v2 §4.2). "뭘 해도 통과하는 TC"를 논리 판단이 아니라 실측으로 막는다.
- **CCI 교차 검증**(`run_cci`/`.answer_cci`, 공식 9단계 step 6)은 **Stage 2부터**. PoC는 기본 sql(JDBC) 단일 경로로 fail→pass·결정성에 집중.
- **Jira 쓰기**(Resolved→Test 전이 + 코멘트)는 **Stage 3부터**. 전이-as-완료마커는 무인 self-healing 루프의 장치라, 사람이 PR을 검토·전이하는 Stage 2까지는 읽기 전용.
- **하드 게이트의 hook 강제**는 **Stage 2부터**. 스킬·CLAUDE.md는 '요청'이라 우회 가능하므로, 팀 공유 시점에 fail→pass·결정성 미통과 제출 차단을 hook으로 '보장'한다(v2 §7.6).

## Considered Options
- Stage 2 = 수동 트리거 k8s Job: 배포 plumbing을 일찍 검증하고 Stage 3 직행. 그러나 pod 검증(ADR 0001)을 지금 구축해야 하고, 사용자가 원한 것은 "팀이 수동으로 쓰는 형태"이지 인프라가 아니었다 → 기각.
- Stage 2 = 공유 호스트 headless CLI: 중앙화되나 동시 실행 자원 경합·격리를 직접 다뤄야 하고 pod 장점도 못 씀 → 기각.
