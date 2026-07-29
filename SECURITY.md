# Security policy

[한국어](#한국어) · [English](#english)

## 한국어

### 지원 범위

보안 수정은 최신 `0.1.x` 릴리스와 기본 브랜치를 대상으로 합니다.

다음 문제를 보안 취약점으로 취급합니다.

- loopback 제한 우회 또는 외부 인터페이스 노출
- 프롬프트·응답·토큰·환경변수의 의도하지 않은 로그 기록
- 다른 프로세스를 잘못 식별해 종료하는 서비스 수명주기 결함
- 설정 백업·복구 과정의 비밀정보 노출
- 공개 저장소에 개인 경로, 자격증명 또는 모델 가중치가 포함되는 문제

### 비공개 신고

GitHub 저장소의 **Security → Report a vulnerability**에서 비공개로
신고해 주십시오. 재현 단계, 영향 범위, 확인한 버전을 포함하되 실제 API
키, 개인 대화, `.env`, Hermes `config.yaml` 또는 모델 가중치는 첨부하지
마십시오.

비공개 신고 기능을 사용할 수 없다면 민감한 내용을 공개 이슈에 올리지
말고, 세부정보 없이 보안 연락 채널이 필요하다는 이슈만 남겨 주십시오.

### 운영 주의사항

- `127.0.0.1`은 네트워크 노출을 줄이지만 인증 수단은 아닙니다.
- Hermes의 shell·web·메신저 도구 권한은 라우터의 로컬 추론 경계와
  별개입니다.
- 비밀이 노출되었다면 저장소에서 파일만 삭제하지 말고 해당 키를 즉시
  폐기·재발급하십시오.
- 모델 출력은 신뢰할 수 없는 입력으로 취급하고, 중요한 작업은 사람의
  승인을 거치십시오.

## English

Security fixes target the latest `0.1.x` release and the default branch.

Report loopback bypasses, sensitive logging, unsafe process termination,
config-backup leaks, or accidental publication of credentials/private paths
through **Security → Report a vulnerability** on GitHub. Include reproduction
steps, impact, and the affected version, but never attach real credentials,
private conversations, `.env`, Hermes `config.yaml`, or model weights.

If private vulnerability reporting is unavailable, do not post sensitive
details in a public issue. Open a minimal issue requesting a secure contact
channel.

Remember that loopback is not authentication, Hermes tools have permissions
outside the inference router, leaked credentials must be revoked, and model
output should be treated as untrusted.
