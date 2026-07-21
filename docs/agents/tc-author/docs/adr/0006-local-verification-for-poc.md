---
status: accepted (ADR 0001 을 PoC 범위에서 supersede; 배포 단계에는 0001 유효. work/ 격리·PoC conf 항목은 2026-07-21 D7에 의해 supersede — deployment.md)
---

# PoC 검증은 pod 대신 로컬 CTP로 수행한다

사용자가 PoC 검증을 로컬 실행으로 결정했다. pod + build-cache overlay 마운트(ADR 0001)는 **배포 단계**에서 사용하고, PoC 동안은 이 머신에서 CTP를 직접 돌린다. 이유: 반복 루프의 회전 속도(pod 기동·빌드 마운트 대기 수 분 제거)와 디버깅 편의.

## 로컬 CUBRID 확보

검증 대상 빌드는 사내 빌드서버(`http://192.168.1.91:8080`)의 자기추출 `.sh` 인스톨러로 설치한다. PoC에서 쓰는 빌드:
- release: `CUBRID-11.5.0.2300-04192d6-Linux.x86_64.sh` (주 빌드 — `.answer`가 CI와 동일 mode)
- debug: 같은 버전 `-debug.sh` (진단 필요 시에만 설치)

`04192d6`은 두 PoC 대상 fix(CBRD-25913 `49a95b91b`, CBRD-26799 `f57fe4393`)를 모두 포함한다.

## 설치 위치: `run_cubrid_install` 로 `/home/dev/CUBRID` (표준 경로)

`run_cubrid_install <release-url>`로 `/home/dev/CUBRID`에 설치한다. 처음엔 공용 파일 보호를 위해 `HOME` 오버라이드로 `work/cubrid-rel`에 격리 설치했으나, 두 가지가 그 방식을 무르게 했다:

1. **소켓 경로 108자 한계** — 격리 경로가 너무 길어 CUBRID Unix 도메인 소켓(`$CUBRID/var/CUBRID_SOCK/…`)이 `sockaddr_un`의 108자 한계를 초과, broker/master 기동이 "socket path is too long"으로 실패했다. `/home/dev/CUBRID`(15자)는 넉넉히 만족한다.
2. **위치 확보 + 지시** — jdbc 인스턴스가 정리되어 `/home/dev/CUBRID`가 비었고, 사용자가 이 위치·표준 CTP 설치를 지시했다.

`run_cubrid_install` + `~/.cubrid.sh` 표준 플로우는 CTP `sql.conf`(`scenario=${HOME}/cubrid-testcases/sql`)와 verify 스킬이 그대로 기대하는 형태이기도 하다. 단, TC 검증 시 scenario는 PoC용 conf에서 `work/cubrid-testcases/sql`로 덮어써 봇의 브랜치 TC를 대상으로 한다(사용자 `~/cubrid-testcases` 불가침).

> **supersede (2026-07-21, D7)**: 위 "PoC conf로 scenario 덮어쓰기·work/ 격리"는 $HOME 런타임 표준으로 대체됐다 — 원본 `sql.conf`를 그대로 쓰고(`scenario=${HOME}/cubrid-testcases/sql`), 격리가 필요한 머신만 `CUBRID_TESTCASES` 오버라이드. [deployment.md](../../../../deployment.md) D7 참조. 소켓 108자·JDK·비기본 포트 등 나머지 규명 사실은 그대로 유효.

## 소켓 경로 제약 (재발 방지)

로컬 CUBRID 설치 경로는 반드시 짧아야 한다 — `<CUBRID>/var/CUBRID_SOCK/<sock>` 전체가 108자 이하라야 broker/master가 뜬다. `/tc-author` 스킬은 CUBRID를 짧은 경로(`/home/dev/CUBRID`)에 설치해야 한다. (배포 단계 pod는 build-cache overlay 마운트라 무관 — ADR 0001.)

## 포트 / JDK

CTP `sql.conf`는 비기본 포트(cubrid_port_id=1822, BROKER_PORT=33120)를 이미 써 호스트 CUBRID와 충돌하지 않는다. Java SP 클래스 컴파일에는 JRE가 아닌 **JDK**가 필요하다 — `JAVA_HOME`을 javac 있는 JDK 루트(예: `/usr/lib/jvm/java-1.8.0-openjdk-…`, `jre` 하위 아님)로 설정한다.

## 로컬에서의 debug/release (ADR 0005 조정)

ADR 0005는 build-cache에 두 빌드가 상주하는 pod 전제에서 "루프=debug, 최종=release"를 정했다. 로컬에서는 release를 주 빌드로 설치해 루프·`.answer` 확정에 모두 쓰고, debug는 이상 출력 진단이 필요할 때만 추가 설치한다. `.answer`가 release(=CI mode)로 확정된다는 핵심 불변식은 유지된다.
