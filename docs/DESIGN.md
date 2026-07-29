# 라우팅 설계

[English](DESIGN.en.md)

## 목표

Hermes Agent에는 하나의 OpenAI 호환 endpoint(`hermes-auto`)만 보이게
하면서, Ollama의 역할별 로컬 모델을 요청 특성에 따라 선택합니다.

설계 우선순위는 다음과 같습니다.

1. LLM 요청 경로를 loopback에 제한
2. 필수 도구 호출을 지원하지 않는 모델로 보내지 않음
3. 설치하지 않은 선택 모델을 안전한 설치 모델로 대체
4. 잘못된 요청을 여러 모델에 반복 전송하지 않음
5. 프롬프트·응답 본문을 로그에 남기지 않음

## API

| endpoint | 동작 |
|---|---|
| `GET /health` | 라우터 인스턴스, 모드, 역할별 설치 상태 |
| `GET /v1/models` | `hermes-auto`와 설정된 역할 별칭 |
| `POST /v1/chat/completions` | OpenAI 호환 chat completions 프록시 |
| `POST /v1/embeddings` | 명시적 HTTP 501; 현재 미지원 |

그 밖의 경로는 HTTP 404를 반환합니다.

## 자동 선택 규칙

규칙은 위에서 아래 순서로 먼저 일치한 항목을 사용합니다.

| 조건 | 최초 프로필 | 이유 코드 |
|---|---|---|
| 사용자가 역할 별칭을 직접 지정 | 지정한 프로필 | `explicit-model` |
| GUI/설정에서 수동 모드 선택 | 수동 프로필 | `settings-override` |
| 이미지 포함 | `quality` | `vision` |
| 코드 단서 포함 | `coding` | `code` |
| 짧은 도구 작업 | `fast` | `short-tool-task` |
| 한국어 집필 단서 | `korean_writing` | `korean-writing` |
| 짧은 한국어 구조화 | `korean_fast` | `korean-short-structured` |
| 나머지 한국어·일반 작업 | `fast` | `korean-general-fast` / `general-fast` |

필수 도구 요청은 `tools` 능력이 없는 프로필을 선택하지 않습니다.
이미지는 `vision` 능력이 없는 설치 모델로 조용히 대체하지 않습니다.

## 설치 누락과 실패 대체

공개 기본 대체 순서는 다음과 같습니다.

```text
fast → coding → korean_writing → korean_fast → quality
```

- 최초 선택 모델이 설치되지 않았을 때 설치된 후보만 고려합니다.
- 필수 도구 요청은 `tools` 프로필만 고려합니다.
- 이미지 요청은 `vision` 프로필만 고려합니다.
- 최대 시도 횟수는 기본 3회입니다.
- HTTP 408, 429, 5xx와 연결·시간초과 오류만 대체 대상입니다.
- HTTP 400, 401, 403, 404, 422 등 요청 자체의 문제는 즉시 반환합니다.
- 스트리밍 응답을 클라이언트에 쓰기 시작한 뒤에는 다른 모델로 전환하지
  않습니다.

모델별 기본 timeout은 600초, 요청 전체 예산은 900초입니다. 후속 시도는
남은 전체 예산보다 길게 기다리지 않습니다.

## text 전용 모델

`korean_writing`, `korean_fast`, 실험적 `korean`은 공개 설정에서 text
전용입니다. 선택적 도구 스키마가 함께 들어오면 Ollama 호환성을 위해
`tools`, `tool_choice`, `parallel_tool_calls`를 upstream payload에서
제거합니다. `tool_choice=required`인 요청은 도구 지원 모델로 다시
선택합니다.

## 설정 재읽기

라우터는 `router-config.json`의 수정 시간을 확인해 실행 중에 다시
읽습니다. GUI가 파일을 쓰는 짧은 순간 JSON이 불완전하면 마지막으로
검증된 설정을 계속 사용합니다.

다음 조건은 설정 로드 단계에서 거부됩니다.

- `listen_host`가 loopback이 아님
- `ollama_base_url`이 HTTP loopback이 아님
- URL에 사용자명·비밀번호·query·fragment가 포함됨
- 모드, 프로필 또는 timeout 값이 유효하지 않음

## 로그와 개인정보

회전 로그에는 다음 메타데이터만 기록합니다.

- 선택 프로필과 모델 별칭
- 이유 코드
- 시도 번호와 HTTP 상태
- stream 여부와 경과 시간
- 예외 **유형**(메시지·본문 제외)

프롬프트, 응답, tool arguments, Authorization 헤더는 기록하지 않습니다.

## 모델 없는 테스트

`tests/test_router.py`는 임시 loopback 포트에 가짜 Ollama HTTP 서버를
실행합니다. 실제 모델, 자격증명, 외부 네트워크 없이 다음 계약을
검증합니다.

- loopback 설정 검증
- last-known-good 설정
- 모델 카탈로그와 health identity
- 역할 선택과 capability 필터
- text 전용 도구 필드 제거
- 재시도 가능 상태와 불가능 상태
- 전체 timeout 예산
- 실제 HTTP proxy fallback

운영 환경의 실제 모델 생성은 `Test-Hermes-Local.ps1 -Generation`,
Hermes 통합은 `Test-Hermes-E2E.ps1`로 별도 검증합니다.
