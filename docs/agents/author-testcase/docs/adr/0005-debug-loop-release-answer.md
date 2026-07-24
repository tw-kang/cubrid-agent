---
status: PoC 범위에서 ADR 0006(로컬 검증)으로 조정. 배포(pod build-cache) 단계에는 유효.
---

# 피드백 루프는 debug 빌드로 돌고, `.answer`는 release 빌드 출력으로 확정한다

> 적용 범위: **배포 단계**(pod에 debug/release 두 빌드 상주 전제). 로컬(PoC/Stage 2)은 release 단일(ADR 0006). 불변식은 ".answer는 release=CI mode 출력으로 확정". 본문 빌드 해시는 배포 단계에서 재선정 대상.

운영 sql/medium CI는 release 빌드로 TC를 실행한다(`cubridci` entrypoint가 `build.sh`를 기본 모드로 호출, 기본값 `release`). 따라서 저장소에 커밋되는 `.answer`는 release 출력이어야 하며, debug 빌드가 만든 `.answer`는 CI에서 diff fail을 낼 수 있다. 한편 사용자는 루프 검증에 debug 빌드(assertion 등 진단력)를 선택했다. 절충으로: 피드백 루프(작성·개선·재검증)는 debug 빌드(`50f89208`, engine a569a3ee) pod에서 돌고, 3게이트 통과 후 **release 빌드(`d67bdd75`, 동일 엔진) pod에서 최종 재검증하여 `.answer`를 release 출력으로 확정**한다. 두 빌드의 출력이 다르면 자동 진행을 멈추고 리뷰에 보고한다. build-cache에 같은 엔진의 debug/release 빌드가 모두 존재하기에 가능한 구성이다.
