# CUBRID TC 작성 에이전트 — Handoff 문서 (v2, 웹검증 보강판)

> 외부 AI 도구로 작성된 TC 작성 방법론 정리본(웹검증 근거 첨부). jira-resolve-agent의 재료로 보존. 분류는 [../staging.md](../staging.md) 참조.
> 원칙: 충돌 시 문서의 권위 서열을 따르되, `[검증됨]`은 공개 문서 기준이므로 사내 private repo가 다르면 repo 우선.

## 0. 가장 먼저 — 정찰(Recon)
코드 전에 재료를 읽는다. tc create skill → 규약/템플릿, ctp(cubrid-testtools) → 실행 계약(`CTP/README.md`, `doc/sql_guide.md`, `doc/ctp_install_guide.md`), tc repo → 대표 TC 5~10개 샘플링(공개는 `CUBRID/cubrid-testcases`, +private/-private-ex), cubrid-jira CLI → 이슈↔커밋 링크, cubrid repo → 엔진 diff↔TC 경로 매핑(이슈번호 `cbrd_xxxxx`가 조인 키). 산출물: 재료 요약 + 공개/사내 차이 + 불명확 지점 → 사람 확인 후 진행.

## 1. 목표
이슈/커밋 diff → 맥락 수집 → TC 초안 → 기대값(oracle) 실행 생성 → 회귀 계약 검증(fail→pass) → 결정성 반복 검증 → CCI 교차 → 근거 패킷 첨부 → 리뷰. 산출물 3종: (A) 작성 에이전트 스킬 (B) 실행·검증 파이프라인 (C) 리뷰 체계.

## 2. 재료·권위
cubrid repo(소스·diff)=최상위, tc repo=컨벤션 기준, cubrid-jira=코드 아래, ctp=실행 기준(절대 준수), tc create skill=방법론. 충돌 서열: **머지된 코드 > 이슈 결론 > 이슈 논의**.

## 3. [검증됨] CTP/TC 실행 계약
- 카테고리: `sql|medium|shell|ha_repl|isolation|jdbc|unittest`(+cci 등). 실행 `ctp.sh <cat> -c <conf>`. `--interactive`로 단일 케이스/폴더 실행 = 에이전트 실행 루프 기본 도구. 제외 목록 `CTP/conf/exclusions.txt`. medium은 백업파일에서 DB 적재하는 SQL 변형.
- 구조·네이밍: `folder/cases/x.sql` + `folder/answers/x.answer`(동일 파일명), `.answer_WIN`(Windows 상이), `.answer_cci`(CCI 상이). 버그수정 `sql/_13_issues/{yy}_{1|2}h/cases/`에 `cbrd_xxxxx.sql`/`_1`/`_xasl` 등. 기능 `sql/{no}{release_code}/cbrd_xxxxx_{feature}/cases/`.
- **공식 answer 생성 9단계 요지**: ctp.sh sql interactive → 준비 대기 → 케이스 폴더에 빈 answer 생성 후 케이스 실행 → **결과를 쿼리 하나하나 검증한 뒤** answer로 복사("Never submit incorrect answer") → 재실행 success 확인 → `run_cci`로 CCI에서도 실행해 차이 확인 → (커밋·리뷰). 시사점: (a) 기대값은 실행으로 만든다=CUBRID 공식과 일치 (b) "하나하나 검증"은 사람 몫(빌드 자체가 버그면 오답이 answer가 됨) (c) 재실행=결정성 게이트, CCI=인터페이스 교차 게이트의 공식 근거.
- 환경 고정값: 타임존 `Asia/Seoul` 요구. `db_charset`/`java_stored_procedure`/`test_mode`/`ha_mode`가 conf로 주입 → 에이전트는 임의로 안 바꿈.

## 4. Non-negotiables
1. **oracle은 실행 산출물이다.** 근거: 공식 절차가 실행→검증→복사; LLM 생성 assertion 62.4% 부정확(DeCon 2025); 잘못된 테스트 다수가 oracle 오류.
2. **버그수정 TC는 회귀 계약을 증명.** fix 전 **fail** / fix 후 **pass**. 둘 다 pass면 무가치.
3. **결정성.** flaky 상위 원인 Async Wait 45%/Concurrency 20%/Order Dependency 12%(Luo FSE2014); "정렬 기대했으나 무순서 결과"(SAP HANA); 75%가 추가 시점부터 flaky(Lam) → **생성 시점 N회 반복 게이트 필수**.
4. **격리·자기완결.** setup/teardown, 잔여물 없음, 순서 무관, 멱등.
5. **harness(ctp) 계약 준수.**

## 5. 작성 관점 렌즈
정확성/oracle(NULL·3치, 타입·정밀도·캐스팅, 정렬·collation), 입력공간/경계값, 상태/맥락(격리수준·동시성·DDL·플랜), 견고성(negative 에러코드까지·리소스·crash recovery), E2E/워크로드(드라이버 JDBC/CCI, 버전 업/다운 동일성).
[검증됨] 고급 오라클(SQLancer, 선택): TLP/NoREC/PQS/DQE/CERT — 기대값 없이 논리버그 탐지. diff가 옵티마이저/실행기 건드릴 때 보조.

## 6. 리뷰 (2층 × 2트랙)
- A층(믿을 수 있나, 최우선): 실제 그 버그/기능 잡나(fail→pass), oracle이 실행 산출물인가(provenance), 통과 이유 올바른가(vacuous pass 방지).
- B층(좋은 TC인가): 커버리지·범위, 결정성·flaky 저항(ORDER BY 없는 순서의존·하드코딩·N회), **oracle brittleness**(과도하게 빡빡해 정상 변동에 깨짐, Eck 17%), 격리·harness 계약(.answer_WIN/_cci 필요 여부), 주석-동작 일치, 복붙 잔재.
- 2트랙: 기계 게이트(돈다 → fail→pass → N회 → 단독+순서셔플 → CCI 교차 → 린트) + 사람 판단(oracle 신뢰성·커버리지·주석일치·brittleness). 근거 패킷: 겨냥 이슈/diff·기대값 생성 빌드·fail→pass 로그·N회 결과·CCI 결과.

## 7. Claude Code 운영
1. CLAUDE.md에 권위서열+원칙5 상단 배치. 2. Phase마다 plan mode. 3. 증거 기반 보고(커맨드·출력·로그). 4. fresh-context 리뷰(별도 subagent). 5. 산출물(A)는 `.claude/skills/<name>/SKILL.md`로 버전관리 공유. 6. 필수 게이트는 hook으로 강제(CLAUDE.md·스킬은 요청이지 보장 아님).

## 8. Phasing
Phase0 정찰(멈추고 확인) → Phase1 수동 파일럿(이슈 1건 공식 절차 그대로) → Phase2 스킬화 → Phase3 검증 자동화(기계 게이트) → Phase4 리뷰 체계 → Phase5 안티패턴 환류.

## 9. 사람(QA) 결정사항
대상 repo(public/private/-ex), 접근·인증, pre/post 빌드 확보 방법(캐시? 체크아웃 빌드?), 신뢰 빌드 정의·위치, 타깃 버전/브랜치, 결정성 N·임계, flaky 이력 DB, 설정 매트릭스 축, 실행 환경(로컬/CI).

## 10. 출처(요약)
CTP: github.com/CUBRID/cubrid-testtools; TC: cubrid-testcases(+private/-ex); SQLancer(PQS/NoREC/TLP/DQE); LLM oracle 리스크 DeCon(arXiv:2501.02901) 등; flaky Luo FSE2014·SAP HANA·Lam; Claude Code best practices.

### 요약 한 줄
"oracle은 실행해서 얻고, 버그는 fail→pass로 증명하고, 소스가 이슈보다 우선한다." + v2: 생성 시점 N회 게이트, CCI 교차, brittleness 균형.
