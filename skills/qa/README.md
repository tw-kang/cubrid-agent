# skills

CUBRID skills for Claude Code (oh-my-claudecode)

## Skills

### shell-create

CTP shell testcase 초안을 생성하는 스킬. CBRD 이슈 번호와 테스트 시나리오를 기반으로 CTP 규칙을 준수하는 `.sh` 파일을 생성합니다.

**설치:**
```bash
# npx skills (권장)
npx skills add tw-kang/skills --skill shell-create

# 수동 복사
cp -r shell-create ~/.claude/skills/
```

**사용 예시:**
- "CBRD-12345 버그픽스 shell tc 만들어줘"
- "create shell tc for CBRD-12345"
- "shell testcase 초안 작성해줘"

---

### shell-review

CTP shell testcase diff를 리뷰하는 스킬. 경로 규칙, 라이프사이클 계약, CTP 헬퍼 사용, 이식성, 안정성 등을 점검하고 구조화된 리뷰 리포트를 출력합니다.

**설치:**
```bash
# npx skills (권장)
npx skills add tw-kang/skills --skill shell-review

# 수동 복사
cp -r shell-review ~/.claude/skills/
```

**사용 예시:**
- "이 shell tc PR 리뷰해줘"
- "shell testcase가 CTP 규칙을 따르는지 확인해줘"

---

### shell-runone

로컬 머신에서 CTP shell testcase 한 건을 실행하고 결과를 리포트하는 스킬. CUBRID 빌드 설치, 테스트 수행, 실패 진단까지 처리합니다.

**설치:**
```bash
# npx skills (권장)
npx skills add tw-kang/skills --skill shell-runone

# 수동 복사
cp -r shell-runone ~/.claude/skills/
```

**사용 예시:**
- "cbrd_12345 테스트 돌려봐 (빌드 URL: http://...)"
- "이 shell tc 패스하는지 확인해줘"
- "run shell tc cbrd_12345"

---

## 전체 설치

세 스킬을 한 번에 설치하려면:

```bash
# npx skills (권장)
npx skills add tw-kang/skills --all

# 수동 복사
cp -r shell-create shell-review shell-runone ~/.claude/skills/
```

설치 후 Claude Code를 재시작하거나 새 세션을 열면 스킬이 활성화됩니다.
