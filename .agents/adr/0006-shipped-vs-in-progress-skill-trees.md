# 배포분과 개발 중을 디렉토리로 가른다 — `skills/qa/`는 배포분만, 나머지는 `skills/in-progress/`

## 배경

스킬 22종이 모두 `skills/qa/`에 있고, 그중 플러그인이 로드하는 6종은 `plugin.json`만 안다([ADR 0001](./0001-repackage-as-plugin.md) "구조 C"). 구조 C는 **무엇을 로드하나**를 정했지만 **어디에 두나**는 한 곳으로 뭉쳐뒀다. 그 결과 디렉토리를 봐도 배포 여부를 알 수 없고, 실제로 문서가 부품 16종을 플러그인 스킬처럼 안내했다(CUBRIDQA-1472). 등재 여부는 매니페스트를 열어야 알 수 있는 사실이었다.

## 결정

배포 여부를 **디렉토리가 말하게** 한다.

- **`skills/qa/` = 배포분만.** `plugin.json`의 `skills[]`와 정확히 일치한다(등재분 전부가 여기 있고, 여기 있는 전부가 등재된다).
- **`skills/in-progress/` = 아직 배포하지 않는 것.** 부품 16종(`create-*`·`verify-*`)과 준비되지 않은 스킬. **개발도 여기서 한다.**
- **승격 = 이동 + 등재, 한 커밋에서.** 둘 중 하나만 하면 `check-invariants.sh`가 막는다.
- **규칙 검사는 두 트리를 모두 훑는다**(`skills/*/…`). 승격이 규칙 맞추기 라운드가 되지 않게 — in-progress 스킬도 첨부 규칙·헤더 범위·memory 비의존·description 1024자를 이미 지켜야 한다.

## 근거

- **디렉토리가 곧 답이다.** 매니페스트를 열지 않아도 무엇이 나가는지 알기 때문에 1472(문서가 미로드 스킬을 안내)의 재발 표면이 사라진다. 기계 검사가 가능한 형태이기도 하다 — 사람이 지키는 규약에서 훅이 판정하는 사실로 옮겼다(DP6).
- **미완성이 배포분 옆에 있으면 새 나간다.** 같은 자리에 두면 "곧 되겠지"로 등재되기 쉽다.

## 이 결정이 바꾸지 않는 것

- **등재 6종과 always-on 비용** — ADR 0001 그대로. 이동 후 실제 설치를 확인했다: `claude plugin details`가 스킬 6종(같은 이름)·hook 3개를 그대로 보고한다. **로드 대상이 안 바뀌었으므로 이동은 비용을 바꾸지 않는다.** (그 상시 비용 자체는 자란다 — ADR 0001의 2026-07-29 실측 ~1,185 tok이 07-31엔 ~1,988 tok이었다. 원인은 description이 길어진 것이고 이 결정과 무관하다. 그래서 숫자는 `claude plugin details`로 읽고 산문에 박지 않는다.)
- **채널 2(`npx skills add`) 발견성** — skills CLI는 트리를 스캔하므로 `skills/in-progress/<name>/SKILL.md`도 찾는다. 이동 전후로 `npx skills add tw-kang/cubrid-agent -l`이 **둘 다 22종**을 발견함을 확인했다(등재 6종은 "Cubrid Agent", 나머지 16종은 "General"로 묶여 나온다). 즉 부품을 개별 설치하는 경로는 그대로다.
- ADR 0002의 "스킬은 `skills/qa/<name>/` 카탈로그 레이아웃을 유지해야 CLI가 발견한다"는 문장 중 **`qa`라는 이름에 묶인 부분만** 이 ADR이 대체한다. 카탈로그 레이아웃(`skills/<카테고리>/<스킬>/SKILL.md`) 자체는 유지된다 — 스킬 디렉토리를 루트로 올리면 여전히 깨진다.

## Considered Options

- **현행 유지(전부 `skills/qa/`) + 문서로 구분**: 변경 0이지만 이미 실패한 방식이다 — 문서가 어긋났던 게 1472다. 기각.
- **미배포 스킬을 별도 repo로 분리**: 배포 여부가 가장 뚜렷하지만 정본 분열·버전 스큐를 되살린다(ADR 0001이 흡수로 없앤 문제). 기각.
- **`plugin.json`에 22종 전부 등재**: 디렉토리 하나로 단순해지지만 always-on 비용이 **3배**(ADR 0001 실측: ~1,185 → ~3,593 tok). 기각.

## Consequences

- 부품 16종이 `git mv`로 `skills/in-progress/`로 이동(이력 보존, `git log --follow` 유지).
- `check-invariants.sh`: 분리 검사 1개 추가, 규칙 검사 globs를 `skills/qa/…` → `skills/*/…`로 확장.
- 문서: README·CONTEXT·`docs/setup.md`·`docs/deployment.md`·`.agents/domain.md`의 배치 서술을 2트리로 정정.
- 남은 작업(부품 16종의 grounding 이관 등)은 `skills/in-progress/`에서 진행되고, 완성된 것만 `skills/qa/`로 올라온다. 티켓: CUBRIDQA-1492.
