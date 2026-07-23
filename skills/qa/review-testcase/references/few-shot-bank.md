# review-testcase L2 few-shot bank

L2 도메인 리뷰 서브에이전트 프롬프트에 주입하는 **실제 사람 리뷰 예시 모음**. 5년 마이닝(2021-07~2026-07, `work/tc-review-mining/`)에서 렌즈별로 재사용 가능한 패턴이 뚜렷한 사례를 선별·구조화했다. 관점 카탈로그 정본은 [review-perspectives.md](./review-perspectives.md).

## 사용법
- review-testcase L2가 PR 성격에 맞는 렌즈 섹션의 엔트리를 few-shot으로 프롬프트에 넣는다: **신규형→coverage-expansion**, **변경형→answer-vs-spec**, **공통→determinism-convention·plan-stability**(플랜 TC).
- 각 엔트리: **상황**(맥락) → **지적**(실제 코멘트 인용) → **패턴**(LLM이 일반화할 재사용 규칙) → **출처**(PR/리뷰어).
- **패턴이 핵심**이다 — 봇이 이 규칙을 새 PR에 적용하게 만드는 게 목적. 인용 문구를 그대로 복붙하는 게 아니라 패턴을 따르게 한다.

## 백테스트 격리 (중요)
특정 PR을 백테스트할 때는 그 **출처 PR의 엔트리를 제외**하고 주입한다(정답 유출 방지). 각 엔트리에 출처 PR을 표기한 이유다.

## 주의 — 성격 태그
원본 마이닝 파일 4번째 필드(`NEW`/`y1`)는 **시기 버킷**(1년치 y1 / 4년 확장 NEW)이지 PR 성격(신규형/변경형)이 아니다. PR 성격은 이 문서의 **렌즈 배정**으로 판단한다.

---

## coverage-expansion (신규형 지배 렌즈 — P4 커버리지·P8 중복·P9 러닝타임·P14 최소성)

### [P4] 상위 개념(계열)의 형제 함수까지 확장
- **상황**: ORDERBY_NUM() 함수를 다루는 TC
- **지적**: "Orderby_num()의 상위목록 'ROWNUM함수'에 ROWNUM, INST_NUM, GROUP_NUM도 포함됩니다. 이들에 대한 TC 추가가 필요하지 않을지 검토 바랍니다" + 예시 `select ROWNUM rrnum,rnum,col_a,col_b from (select ROWNUM rnum,col_a,col_b from tbl order by col_a) where ROWNUM < 5 order by rnum desc`
- **패턴**: 테스트 대상 함수가 더 큰 분류(상위 개념)의 여러 함수 중 하나면, 같은 분류의 나머지 함수를 모두 나열하고 각각 동일 형태의 SQL 케이스를 제안하라.
- **출처**: PR1790 / bagus-kim

### [P4] 한 DML에만 적용된 힌트·옵션을 다른 DML에 대칭 추가
- **상황**: 힌트 조합을 delete문에서만 검증하던 TC
- **지적**: "cbrd_25382_2에서 delete문에 사용한 힌트 15~21도 update문에 추가하는 것이 좋겠습니다" (select문에도 같은 문구로 반복)
- **패턴**: 특정 DML(delete)에만 적용된 힌트·옵션 집합을 발견하면, 같은 힌트가 유효한 다른 DML(update·select)에도 동일 번호의 힌트 세트를 빠짐없이 대칭 추가하라고 제안하라.
- **출처**: PR1936 / ssihil

### [P4] 위임 체인 중간 노드 삭제 후 잔존 상태 확인
- **상황**: 유저 삭제 시 권한 처리 TC
- **지적**: "u1이 u2에 조회·권한부여, u3엔 조회만; u2가 u3에 조회·권한부여(u3는 u1·u2 양쪽에서 받음) → u2 삭제 → u3에 u1으로부터 받은 권한만 남는지 확인" (+case #2)
- **패턴**: 권한·소유권처럼 A→B→C로 위임되는 체인 기능은 "중간 노드(B)를 삭제하면 나머지(C)에 무엇이 남는지"를 다단계 시나리오(2단계 이상 부여 → 중간 삭제 → 잔존 확인 쿼리)로 제안하라.
- **출처**: PR1950 / kwonhoil

### [P4] 시스템 카탈로그 검증 쿼리에 식별 컬럼·정렬·노이즈 필터 보강
- **상황**: 여러 권한(grant/revoke) TC의 결과 확인용 select (4개 PR에 반복 지적)
- **지적**: "select grantor_name, grantee_name, object_name, auth_type, is_grantable from db_auth where grantee_name != 'PUBLIC' order by grantor_name, grantee_name; — object_name·auth_type 값이 여러 행에서 동일하니 바꾸는 게 좋다", "object_type, object_name, auth_type 추가; 동일 쿼리는 파일 내 모두 고쳐달라"
- **패턴**: 시스템 카탈로그(db_auth 등)로 결과를 확인하는 검증 쿼리는 (1) `!= 'PUBLIC'` 같은 노이즈 필터, (2) 행을 구별할 충분한 컬럼, (3) 여러 키 컬럼 order by를 갖추게 하라. 같은 형태 쿼리가 파일에 여러 번이면 전부 동일하게 고치라고 요구. (4개 PR 반복 = 재사용성 높음)
- **출처**: PR1948·1950·1956·1957 / ssihil·kwonhoil

### [P4] 타입 변환·정밀도는 자리수 경계값으로
- **상황**: NUMERIC을 프로시저 파라미터로 넘기는 변환 TC 4건
- **지적**: `call numeric_test(1234567890123456789.1234567890123456789);` / `call t_NUMERIC_CHAR('NUMERIC(8,4)', 'CHAR', cast(0.123456789 as numeric(8,4)));` (VARCHAR·DOUBLE에도 반복)
- **패턴**: 타입 변환·정밀도 TC엔 선언 자리수를 꽉 채우거나 넘기는 값, 반올림·절삭이 실제로 일어나는 소수점 값을 넣어 경계 동작을 확인하는 케이스를 SQL로 제안하라. 변환 대상 타입이 여러 개(CHAR/VARCHAR/DOUBLE)면 같은 경계값을 각 타입에 반복 적용.
- **출처**: PR1683·1687 / ssihil

### [P4] 함수 낀 predicate는 연산자×논리결합×부호 조합 매트릭스로
- **상황**: abs() 함수가 낀 predicate를 key range/data filter로 분류하는 번호 매긴 조합 TC(17개 이상)
- **지적**: "predicate: (ta.b <= abs(tb.b) or ta.c > abs(tb.b)) key range: ((abs(tb.b)>=ta.b) or (abs(tb.b)<ta.c))", "predicate: (ta.b <= -abs(tb.b) or ta.c > abs(tb.b)) key range: NULL"
- **패턴**: 함수 낀 predicate는 비교연산자(>=,<=,=,<,>) × 논리결합(and/or) × 부호(양/음) 조합을 전부 번호 매겨 나열하고, 조합마다 옵티마이저가 key range로 타는지 data filter/NULL(풀스캔)로 미루는지 기대값을 명시. or결합·음수 abs처럼 빠지기 쉬운 조합이 비면 채우라고 지적.
- **출처**: PR1884 / youngjinj

### [P4] 접두사·축약형으로 짝을 이루는 함수군은 전부 나열
- **상황**: SYS_DATE류 시간 함수 TC에 새 시나리오 추가
- **지적**: "개발팀이 SYS_DATE, SYS_DATETIME, SYS_TIME, SYS_TIMESTAMP, SYSDATE, SYSDATETIME, SYSTIME, SYSTIMESTAMP 8개 모두 추가 요청" + "실행마다 값이 달라지니 기존 bfn_datetime_sysdatetime.sql처럼 값이 안 바뀌는 형태로 8개 모두 작성"
- **패턴**: 이름이 접두사(SYS_)·축약형으로 짝을 이루는 함수군은 전부 빠짐없이 나열해 추가하고, 현재시각처럼 실행마다 바뀌는 함수는 고정 기준값·안정 파생값만 확인하도록 기존 유사 TC를 참조해 재작성 요구.
- **출처**: PR1961 / kiho-um·ssihil

### [P4] 제약조건은 생성만 말고 add→drop 수명주기, 복합키까지
- **상황**: 외래키(FK) 제약조건 TC
- **지적**: "alter table b_child add constraint fk_id_name2 FOREIGN KEY(id,name) REFERENCES a_parent(id,name); alter table b_child drop constraint fk_id_name2;"
- **패턴**: 제약조건 기능은 생성(add)만 테스트하지 말고 같은 케이스에 제거(drop)까지 붙여 수명주기를 제안. 단일 컬럼 FK만 있으면 복합(2개 이상 컬럼) FK 케이스도 함께 추가.
- **출처**: PR1844 / kwonhoil

### [P4] positive 케이스엔 짝이 되는 negative(없는 대상·오탈자)
- **상황**: 권한 에러 케이스 TC
- **지적**: "에러케이스 추가: 'show grant for 없는user명;' 에러·메시지 확인, grant/revoke 오탈자 명령 실행 에러메시지 확인"
- **패턴**: positive 위주면 짝이 되는 negative(존재하지 않는 대상 지정, 명령어 오타)를 실제 에러 메시지까지 확인하는 형태로 대칭 추가 제안.
- **출처**: PR1901 / kwonhoil

### [P8] 커버리지 확장 제안엔 "기존 중복 먼저 확인" 단서
- **상황**: 권한 재부여(WITH GRANT OPTION) 조합 TC
- **지적**: "select 권한은 재부여 가능, insert 권한은 재부여 불가일 것 같습니다. TC 추가 검토 (관련 TC가 존재하면 생략 가능)"
- **패턴**: 커버리지 확장을 제안할 때 항상 "이미 같은 걸 검증하는 TC가 있는지 먼저 찾고, 있으면 생략하라"는 단서를 붙여, 새 제안이 기존과 겹치지 않는지 점검하게 하라.
- **출처**: PR1944 / kwonhoil

### [카테고리적합성] OOM·서버다운·무한루프는 sql이 아니라 shell
- **상황**: 문자열 길이 한계 테스트(.todo 상태)
- **지적**: "SQL 테스트는 DB 재시작 없이 각 질의를 수행하므로, OOM이 발생할 수 있는 이 케이스는 shell 기반 테스트에 추가하는 게 좋겠습니다."
- **패턴**: sql 카테고리는 같은 DB 프로세스에서 질의를 연달아 실행한다. OOM·서버다운·무한루프처럼 프로세스·서버에 영향 주는 케이스는 sql이 아니라 shell 카테고리로 옮기라고 지적.
- **출처**: PR1754 / hgryoo

### [P14] 바꾼 system parameter·세션 설정은 끝에서 명시 원복
- **상황**: 인덱스 관련 system parameter를 바꿔 검증하는 TC의 마무리
- **지적**: "set system parameters 'deduplicate_key_level=default'; — 명시적으로 default를 추가해 다른 케이스가 default로 동작함을 보장"
- **패턴**: 테스트 중 system parameter·세션 설정을 바꿨으면 케이스 끝에서 명시적으로 default로 되돌리는 문장을 추가하라. 뒤 TC가 영향받지 않게 — "최소 재현"을 이유로 이 원복을 생략하면 안 된다.
- **출처**: PR1844 / tw-kang

---

## answer-vs-spec (변경형 지배 렌즈 — P7 답지정당성·P11 이슈의도·P12 버그/스펙·P15 불변식)

### [P7] 성공/실패 여부와 answer 상태가 반대로 기록됨
- **상황**: 파라미터 타입 변환 TC 3개 파일에서 실제 실행 결과와 answer의 성공/실패 표시가 반대
- **지적**: "It's a failure, but the answer file it was successful. Need to check." / "It's a success, but the answer file it was fail." — 한 PR에서 파일 바꿔가며 3번
- **패턴**: answer의 성공/실패(정상 결과 vs 에러)와 실제 실행 성공/실패가 맞는지부터 확인. 같은 불일치가 한 PR 여러 파일에 반복되면 개별 문제가 아니라 answer 생성 방식(빌드 버전·환경)을 의심하고 파일명을 짚어 재확인 요구.
- **출처**: PR1687 / ssihil

### [P7] .sql만 고치고 .answer 방치 — 짝은 항상 함께
- **상황**: .sql 케이스가 수정됐는데 짝 .answer에 미반영
- **지적**: "As you modify the .sql file, the .answer must also be modified."
- **패턴**: diff에 .sql만 바뀌고 .answer(/.answer_cci)가 그대로거나, 반대로 answer만 바뀌고 .sql의 비교 리터럴이 그대로면 하나가 방치된 것. 두 파일은 항상 짝으로 바뀌어야 함을 확인.
- **출처**: PR2004 / ssihil

### [P7] answer 상태는 바뀌었는데 .sql 주석의 상태 태그는 그대로
- **상황**: bit_length answer가 에러→정상으로 바뀌었는데 .sql 주석에 옛 "[er]" 태그 잔존
- **지적**: ".answer 수정뿐 아니라 .sql 주석도 수정 필요. '[er]' 삭제 필요."
- **패턴**: answer의 성공/실패 상태가 바뀌면 .sql의 상태 주석·prefix 태그([er], -- error)도 같이 바뀌어야 한다. answer diff만 보지 말고 옆 .sql 주석이 새 상태와 모순 없는지 맞춰본다.
- **출처**: PR1939 / tw-kang·kwonhoil

### [P7] 반올림·절삭된 값이 의도된 변환인지 확인
- **상황**: DOUBLE/FLOAT을 INT/NUMERIC 파라미터로 넘기는 TC의 answer에 반올림·절삭 값
- **지적**: "double 1234.56789가 int 1235로 반올림됐는데 문제없나요?" / "float 16777.217이 16777.21로 잘린 것 같습니다. 확인 부탁."
- **패턴**: 타입 변환 케이스에서 answer 값이 입력값과 자릿수·소수점이 다르면(반올림/절삭/정밀도 손실) 스펙상 맞는 변환인지, 실행 결과를 그대로 옮긴 것인지 구분해 묻는다. "왜 이 값인지" 설명 없이 통과시키지 않음.
- **출처**: PR1934 / swi0110

### [P7] NULL 처리로 answer에서 결과 줄이 사라짐
- **상황**: procedure 기본값 TC에서 빈 문자열 케이스의 answer 출력 줄이 통째로 빠짐
- **지적**: "빈 문자열이 null로 처리되어 답지에 '5: p_empty_string' 결과가 없는 것 같습니다. '5: '로 출력됐어야 맞을 것 같습니다."
- **패턴**: answer에서 특정 케이스 출력 줄이 사라졌으면 "값이 없는 것"과 "NULL 처리돼 안 찍힌 것"을 헷갈렸을 가능성부터 의심. 빈 문자열/NULL 경계값일 때 "출력 없음"이 맞는지 스펙과 맞춰본다.
- **출처**: PR2022 / swi0110

### [P11] 이슈 원문의 "기대 동작"을 인용해 TC와 대조
- **상황**: 권한 이슈의 하위 항목 검증 TC
- **지적**: "이슈 기대 동작: DBA에게 권한 부여 시 소유자에게 부여하는 경우와 동일하게 에러 출력해야 함. 이 이슈를 진행할지 확인하거나 다른 계정으로 변경 검토해 주세요."
- **패턴**: TC가 이슈를 제대로 겨냥하는지 볼 때 이슈 본문의 "기대 동작" 문장을 그대로 가져와 TC 검증 내용과 나란히 대조. 안 맞으면 TC를 고치라기 전에 이 이슈를 지금 방식대로 진행할지부터 재확인.
- **출처**: PR1944 / kwonhoil

### [P11] 에러 없는 케이스가 애초에 이 이슈 범위가 맞는지 확인
- **상황**: view 생성 시 타입 불일치면 "생성은 되고 조회 때 에러"가 나야 하는 이슈인데 에러 안 나는 케이스도 섞임
- **지적**: "케이스마다 select 실행해 에러 나는지 확인 필요. 에러 안 나는 것은 본 이슈 해당 TC인지도 확인 바랍니다."
- **패턴**: 이슈가 "특정 조건에서 에러가 나야 한다"면 에러 안 나는 케이스를 "정상 케이스"로 넘기지 말고 애초에 이 이슈 시나리오가 맞는지 되묻는다. 이슈 범위 밖 케이스가 잘못 끼어 있을 수 있음.
- **출처**: PR1923 / kwonhoil

### [P12] 이상한 동작은 버그/스펙을 개발자에게 바로 질문
- **상황**: rewrite된 쿼리엔 leading 힌트가 있는데 view 테이블엔 적용 안 됨
- **지적**: "뷰테이블에 leading 힌트 적용 안 되는 게 스펙인지 개발자 문의" → "뷰테이블도 적용돼야 하는 게 스펙. 개발자 수정중."
- **패턴**: 동작이 이상한데 버그인지 스펙인지 리뷰어 선에서 판단 안 서면 그 동작에 맞춰 answer만 고쳐 넘어가지 않는다. 먼저 "이게 스펙 맞냐"를 개발자에게 묻고, 버그면 TC는 수정 전제로 유지하며 이슈로 남긴다.
- **출처**: PR1736 / kwonhoil·zionyun

### [P12] 컴포넌트 간 기준 불일치는 이슈 등록·매뉴얼 반영까지
- **상황**: PL/CSQL character(N) 길이 기준(문자 vs 바이트)이 SQL과 다르게 동작 의심
- **지적**: "sql에선 문자길이. 일관성 위해 문자길이가 맞을 듯. 기준이 다르면 관련 이슈에 꼭 작성하고 매뉴얼에도 추가돼야 함."
- **패턴**: 서로 다른 컴포넌트(SQL vs PL/CSQL) 사이 같은 개념 기준이 다르면 그 자리서 answer만 맞추고 넘어가지 않는다. 의도된 차이인지 확인하고, 아니면 새 이슈+매뉴얼 수정까지 요구. 판정 전까진 TC 보류.
- **출처**: PR1997 / kwonhoil·swi0110

### [P15] 연도를 answer에 고정하면 해가 바뀌는 순간 깨짐
- **상황**: default 파라미터 timestamp 값에 연도가 빠져 지금은 실행 연도와 우연히 일치
- **지적**: "년도가 없어 현재는 2025로 answer와 동일하지만 내년엔 2026으로 처리되며 실패. 년도 포함을 고려."
- **패턴**: 현재 시각(연도·월)에 암묵 의존하는 입력값이 있고 answer가 "지금 이 순간의 값"으로 고정되면 시간이 지나면 반드시 깨진다. 값에 연도를 명시 박아 고정하거나 DATE_FORMAT 등으로 변동 부분을 출력에서 빼라고 요구.
- **출처**: PR2010 / ssihil

### [P15] 매번 바뀌는 sys_date 값은 answer로 고정 비교 불가
- **상황**: PL/CSQL sys_date류 내장함수 호출 케이스
- **지적**: "sys_date 등은 테스트마다 값이 변경돼 answer와 비교 불가. bfn_datetime_sysdatetime.sql 참조해 재작성이 좋겠습니다."
- **패턴**: 실행마다 값이 달라지는 함수(현재 시각·난수) 결과가 그대로 노출되면 그 값을 answer에 박을 수 없음을 먼저 지적. 정확한 값 대신 "형식만 확인"으로 재작성 요구, 같은 문제를 이미 푼 기존 파일이 있으면 그 방식 따르게.
- **출처**: PR1961 / ssihil

### [P15] order by 없는 다중 로우 결과는 순서 비보장
- **상황**: 여러 CTE 조합에서 order by 없는 select 결과를 answer로 굳히려 함
- **지적**: "order by를 쓰는 이유는 답지가 안 바뀌게 하기 위함. 생략 가능한 건 count(*)·결과 1건뿐. 그 외엔 order by가 있어야 regression마다 답지가 안 흔들림."
- **패턴**: order by 없는 다중 로우 select는 옵티마이저·저장 구조에 따라 순서가 달라지는 비보장 값. count(*)이거나 1건 보장이 아니면 order by 없이 나온 결과를 answer로 확정하지 말고 order by 추가 요구.
- **출처**: PR1767 / kwonhoil

---

## determinism-convention (공통 — P2 결정성·P5 격리·P6 컨벤션·P10 언어. L1 정적 규칙으로 못 잡는 판단형만)

### [P2] ORDER BY가 있어도 정렬 키가 유일하지 않으면 순서 비결정
- **상황**: db_auth 조회에 `order by grantor_name`만 사용
- **지적**: "order by가 grantor_name이라 출력 순서가 바뀔 수도. grantor_name, auth_type 순으로 처리하는 게 좋겠습니다."
- **패턴**: ORDER BY 유무만 보지 말고 정렬 키가 결과를 유일하게 구분하는지(동률 가능성)까지 본다. 앞 키 값이 중복되면 뒤 순서는 여전히 비결정이므로 tie-breaker 컬럼 추가 요구.
- **출처**: PR1944 / kwonhoil

### [P2] 결과 0건 쿼리엔 ORDER BY 불요 — 지적이 엉뚱한 쿼리를 가리키는지도 확인
- **상황**: package 정보 확인 쿼리
- **지적**: "본 쿼리는 결과가 없습니다. 정렬 조건 추가가 불필요합니다. 수정 대상 쿼리가 잘못된 것 아닌가요?"
- **패턴**: ORDER BY 없다고 무조건 지적 금지. 실제로 행을 반환하는 쿼리인지 먼저 확인(0건 확정이면 예외)하고, 한 파일에 쿼리가 여럿이면 지적이 정확히 어느 쿼리를 가리키는지 짚는다 — 자동 제안이 엉뚱한 쿼리에 붙는 실수가 실제로 있었다.
- **출처**: PR2036 / ssihil

### [P2] 결정성이 깨지는 건 행 순서만이 아니라 실행 계획 선택일 수도 — CTE는 MATERIALIZE로 고정
- **상황**: SQL Trace·core dump 재현 목적 CTE TC 3건(한 PR에서 3번 반복 지적)
- **지적**: "INLINE CTE가 되면 초기 테스트 목적과 다른 테스트가 됩니다. `/*+ MATERIALIZE */` 힌트를 쓰는 게 좋겠습니다."
- **패턴**: 테스트 목적이 특정 실행 계획(CTE 구체화)에 의존하면, 옵티마이저가 나중에 다른 계획(inline)을 골라도 의도가 유지되도록 힌트로 계획을 고정. 결정성 붕괴 지점은 "행 순서"만이 아니라 "계획 선택"일 수도 있다.
- **출처**: PR2187 / youngjinj

### [P5] 기술적으로 중복인 cleanup도 순서 관례로 남길 수 있다 — 강요 말고 의도 확인
- **상황**: 테이블 삭제 전 인덱스를 명시 DROP하는 TC
- **지적**: ssihil "drop table 시 함께 삭제되므로 불필요" / 작성자 "한 테이블 삭제 시 순서적으로 삭제하는 게 맞다고 봄"
- **패턴**: "DROP TABLE이 인덱스까지 지우니 중복"이라는 사실만으로 삭제를 강요하지 않는다. 만든 역순 정리 대칭 관례일 수 있고 정답·오답이 아닌 스타일 판단 → 강한 "지워라"보다 의도 확인 수준으로.
- **출처**: PR1859 / ssihil·kiho-um

### [P5] 러너별 실행 제외 규칙을 알아야 격리 위반을 잡는다
- **상황**: 주석에 "HA 동기화 테스트"라 적은 SQL 카테고리 TC
- **지적**: "ha_repl은 파싱 단계에서 DDL/DML이 아닌 것(AUTOCOMMIT/ROLLBACK/COMMIT/$/SHOW/CALL/SELECT)은 실행 안 함. call login에 의한 사용자 변경 포함 → ha_shell tc로 작성 필요."
- **패턴**: TC가 여러 실행 컨텍스트(SQL 러너·ha_repl)에 걸치면 특정 러너가 특정 statement(CALL)를 조용히 건너뛸 수 있다. 문법상 문제없어도 카테고리별 실행 규칙 차이로 다른 카테고리(ha_shell)로 분리해야 하는 경우가 있다.
- **출처**: PR1904 / ssihil

### [P5] 방어적 DROP IF EXISTS는 내가 아니라 남(다른 TC)을 방어
- **상황**: 공유 DB TC의 테이블 생성 전 처리
- **지적**: "생성 전에 drop table if exists로 다른 tc에서 삭제 안 되고 남아 있을 경우를 대비하는 게 좋습니다."
- **패턴**: DROP-before-CREATE를 "내가 만든 걸 내가 지우는 습관"으로만 보지 않는다. 공유 DB 환경에선 "다른 TC의 정리 실패"까지 방어하는 게 목적 — 이 TC가 다른 TC의 격리 실패로부터 스스로를 지키는지 본다.
- **출처**: PR1911 / ssihil

### [P6] 이미 고쳐진 BUG 주석은 삭제 — 주석은 리뷰 시점 상태를 반영해야
- **상황**: %TYPE 절차 리턴값 TC
- **지적**: "CBRD-25557에서 수정돼 develop에 반영됨(결과 0.1). 이 주석은 지워져야 합니다."
- **패턴**: BUG/TODO 주석은 작성 시점 상태일 뿐 영구히 맞지 않다. 리뷰 시점에 해당 이슈가 develop에 반영돼 고쳐졌는지 확인하고, 고쳐졌으면 주석 삭제 요구 — 주석 문구만으론 판단 불가, 외부 상태 확인 필요.
- **출처**: PR1847 / hyunikn

### [P6] 기대와 실제가 다르면 그 자체가 BUG — 주석을 지우면 안 되는 경우
- **상황**: PLCSQL 컬렉션 타입 파라미터 전달 TC
- **지적**: "컬렉션 타입은 PLCSQL 미지원이라 에러를 기대했으나 정상 처리됨 → BUG 주석 유지."
- **패턴**: 스펙상 "미지원이라 에러가 나야 정상"인데 에러 없이 처리됐다면 그 불일치 자체가 회귀/미문서화 변화. "에러 안 나니 통과"로 보지 말고 기대 동작과 실제 동작의 방향(에러 예상 vs 성공)까지 맞춰야 BUG 주석 유지 여부 판단 가능.
- **출처**: PR1687 / kwonhoil

### [P6] trace가 불필요해 보여도 검증 대상이 trace 출력 자체일 수 있다
- **상황**: 해시 조인 빌드 스킵 여부 확인 TC
- **지적**: ssihil "trace 쓸 이유 없어 보임" / 작성자 "결과 없으면 해시 테이블 빌드 안 해야 하고, sql trace의 hash_method: skip으로 확인함"
- **패턴**: "trace on/off 페어가 맞는가"를 넘어 trace 사용이 그 TC의 검증 목적과 직결되는지 본다. 목적과 무관해 보여도 실제론 trace 출력이 유일한 검증 수단인 경우가 있어 "이유 없어 보임"만으로 지적하면 안 된다.
- **출처**: PR1936 / ssihil·youngjinj

---

## plan-stability (공통, 플랜 TC — P3 fix 경로·P13 플랜 안정성)

### [P3] 케이스 라벨은 select 아닌 evaluate — 불필요한 queryPlan 억제
- **상황**: 신규 TC 케이스 설명(라벨)에 select문 사용
- **지적**: "select 대신 evaluate를 쓰는 건 어떤가요? select는 불필요한 queryPlan을 출력합니다."
- **패턴**: 케이스 라벨에는 select가 아니라 evaluate. select는 그 자체로 queryPlan을 출력해 진짜 검증 대상(recompile 힌트 select)의 plan 출력과 뒤섞여 노이즈가 된다. 라벨용 select 발견 시 evaluate 치환 요구.
- **출처**: PR1792 / youngjinj (반복 PR1849 / ssihil)

### [P3] 힌트 오타로 조용히 TABLE SCAN — answer를 결과에 맞춰 덮지 않기
- **상황**: answer가 INDEX SCAN을 기대하는데 실제 plan은 TABLE SCAN
- **지적**: "인덱스 힌트 이름에 오타가 있어 TABLE SCAN이 수행된 듯. 오타 수정 후 answer도 같이 변경 요망." (+ "FORCE로 USING INDEX를 써야 확실히 INDEX SCAN")
- **패턴**: ① USING INDEX는 FORCE를 붙여야 확실히 강제, 없으면 optimizer가 다른 경로 택함. ② 인덱스명 오타면 에러 없이 힌트가 조용히 무시되고 sscan으로 우회. answer를 실제 출력(오타 상태)에 맞춰 승인하면 fix 경로(index scan)를 영영 검증 못 하는 상태가 회귀 기준으로 굳는다 — answer 승인 전 힌트 문자열이 실제 인덱스명과 일치하는지 확인.
- **출처**: PR1884 / youngjinj

### [P3] 뷰 머징이 별칭을 바꿔 힌트를 무효화
- **상황**: NO_USE_HASH(ab) 힌트를 줬는데 hash-join으로 처리됨
- **지적**: "뷰 머징으로 별칭 a→ab가 되어 힌트의 ab와 달라 no_use_hash(ab)가 무시됨. no_merge 힌트를 함께 써야 함."
- **패턴**: 인라인 뷰가 머지되면 내부 별칭이 자동으로 바뀌어 옛 별칭 힌트가 매칭 안 돼 조용히 무시된다. 별칭 참조 힌트가 걸린 TC는 뷰 머징 여부를 점검하고, 힌트가 먹은 결과를 보려면 no_merge로 별칭 고정.
- **출처**: PR1936 / youngjinj(지적 ssihil)

### [P3] 모호한 인덱스명 → USING INDEX 힌트 무시
- **상황**: 기존 TC의 plan 변화
- **지적**: "예전엔 인덱스가 없으면 오류가 났으나 최근엔 힌트가 무시됨. 현재는 인덱스명이 모호하여 무시된 경우."
- **패턴**: 인덱스명이 여러 테이블에 걸쳐 모호하면 USING INDEX가 에러 없이 무시된다. 힌트가 있다고 안심 말고 실제 plan에서 그 인덱스가 선택됐는지 확인, 모호한 이름은 table.index로 한정 요구.
- **출처**: PR2381 / shparkcubrid

### [P3] 등호조건으로 이미 자명한 정렬 — 위양성 커버리지
- **상황**: "order by skip" 검증 목적이라 주장된 쿼리
- **지적**: "order by skip은 인덱스로 정렬이 불필요할 때. 첫 쿼리는 order by의 upper(a)에 ='A' 등호조건이 있어 인덱스 무관하게 정렬 불필요 → order by skip 테스트로 보기 어렵다."
- **패턴**: TC 의도가 "인덱스 덕분에 정렬 스킵"이라도 WHERE절이 이미 order by 컬럼을 등호로 고정하면 인덱스 유무와 무관하게 정렬 불필요 = fix 경로를 검증 못 하는 위양성 커버리지. "이 조건은 인덱스 없어도 성립하는가?"를 먼저 따진다.
- **출처**: PR2369 / HyunukLee

### [P13] 인덱스+통계 추가로 plan 고정
- **상황**: 다중 테이블 조인 TC에서 인덱스 부재로 plan이 흔들릴 수 있음
- **지적**: "create index … ; update statistics on ta,tb,tc; 플랜 고정·안정성 확보 차원에서 옵티마이저 변화에 영향받지 않게 인덱스 추가가 좋겠습니다."
- **패턴**: 조인·스캔이 통계 부재·비용 동률로 run마다 흔들릴 위험이 있으면 관련 컬럼에 인덱스를 만들고 update statistics를 명시 실행해 plan을 특정 경로로 고정. 우연 통과가 아니라 항상 같은 경로를 타게.
- **출처**: PR2466 / shparkcubrid

### [P13] 조인순서 변경은 동률 비용·선택도 계산까지 추적
- **상황**: answer의 조인 처리순서가 a,b,c,d → a,c,d,b로 바뀜
- **지적**: (질문) "조인순서가 변경된 이유는?" / (답변) "유니크라 NL조인은 어떤 순서든 동일 cost. 변경 전 b,c 우선은 조인조건 2건이라 선택도가 과소평가된 것(이전 1/MIN(3*3,9), 변경 1/MIN(3*3,3))"
- **패턴**: 조인 순서가 바뀐 answer는 "NL조인이 유리"라는 정성 설명만으론 승인 불가. cost가 이론상 동률(tie)일 때 실제 순서를 가르는 건 다중조건 인덱스의 선택도 계산 방식 — 계산이 바뀌면 tie가 깨지는 방향도 바뀐다. 선택도·비용 공식 수준까지 추적 요구.
- **출처**: PR2462 / kwonhoil·shparkcubrid

### [P13] 무관한 변경으로 흔들리는 trace — 최소 diff 안정화와 신규 커버리지 분리
- **상황**: 엔진 parallel scan 확장으로 기존 회귀 TC의 INSERT 행 순서·NLJOIN trace가 흔들림
- **지적**: "이 PR은 신규 커버리지가 아니라 기존 cbrd_24148.sql이 흔들린 것을 안정화하는 수정. 원 케이스는 CBRD-24148 회귀 목적이라 의도 유지 선에서 최소 변경만. parallel scan 회귀는 별도 케이스로 분리."
- **패턴**: 엔진 변경이 기존 회귀 TC의 부수 산출물(행 순서·trace)만 흔들어 flaky해지면 "새 기능 커버리지"와 "기존 케이스 안정화"를 한 PR에 섞지 않는다. 최소 diff로 원 의도를 지켜 안정화하고 새 경로 커버리지는 별도 케이스로 분리.
- **출처**: PR2827 / xmilex-git

### [P13] answer 갱신은 수치 근거로 "회귀 은폐 아님"을 증명
- **상황**: 조인 순서/스캔 방식이 바뀌어 answer 갱신, 회귀 은폐 여부가 쟁점
- **지적**: "이 갱신은 회귀 은폐가 아니라 옵티마이저의 합리적 선택. cc는 5 rows, aa/bb는 ~512 rows. 5행 cc를 sscan으로 outer에 두고 aa로 index probe하는 건 정당한 plan."
- **패턴**: plan이 바뀌어 answer를 갱신할 땐 "옵티마이저가 왜 그렇게 선택했는지"를 행 수·카디널리티 수치로 제시. 근거 없는 "그냥 바뀌어 갱신"은 반려 대상 — 수치 근거가 있어야 회귀를 answer 갱신으로 은폐한 건지 정당한 cost 기반 선택인지 구분 가능.
- **출처**: PR2704 / xmilex-git

### [P13] cost-model 계열 변화는 policy 판정과 근거 커밋 문서화
- **상황**: 엔진 비용 모델(overhead) 변경으로 여러 TC(Q101/Q121/Q123)의 plan이 한꺼번에 skip ORDER BY 쪽으로 바뀜
- **지적**: "policy A로 수용. overhead=1(엔진 PR #7262)로 비커버링 인덱스 스캔이 비용 경쟁력을 얻어 skip ORDER BY가 적용되는 의도된 변경. Q101 evaluate 설명 갱신(commit 1098cec1f)."
- **패턴**: 엔진 cost-model 변경으로 다수 TC의 plan이 계열적으로 바뀌면 케이스별로 "의도된 변경(policy)"인지 판정 후 evaluate/answer 설명을 새 동작에 맞게 갱신하고 근거 엔진 commit/PR 번호를 남긴다. policy·근거 문서화로 동일 변화 재발 시 반복 조사를 줄인다.
- **출처**: PR2871 / shparkcubrid

---

## 출처·규모
`work/tc-review-mining/lens_*.txt` (5년 마이닝, gitignore)에서 선별. 총 **44 엔트리**(coverage-expansion 12·answer-vs-spec 12·determinism-convention 9·plan-stability 11). 백테스트 정답지와 동일 데이터이므로 위 '백테스트 격리' 규칙을 지킨다. 마이닝 재추출 시 이 bank도 갱신 대상.
