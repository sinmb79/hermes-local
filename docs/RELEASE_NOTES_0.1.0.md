# Hermes Local Router 0.1.0

Windows에서 Hermes Agent를 로컬 Ollama 역할 모델에 연결하는 첫 공개판입니다.

## 핵심

- `127.0.0.1:11435/v1` OpenAI 호환 자동 라우터
- 일반·도구, 코딩, 한국어, 고품질·비전 역할 선택
- 약 13GB `Core`부터 시작하는 선택형 설치
- 일시적 오류만 대상으로 하는 capability-aware fallback
- PowerShell 설치·서비스·GUI·백업·검증 도구
- 한글 기본 설명과 영문 문서
- 모델 가중치·개인 설정·로그·자격증명 미포함

## 설치

```powershell
git clone https://github.com/sinmb79/hermes-local.git
Set-Location .\hermes-local
Set-ExecutionPolicy -Scope Process Bypass
.\Setup-Hermes-Local.ps1
.\Start-Hermes.ps1
```

모델은 저장소에서 배포하지 않습니다. 사용자가 명시적으로 설치 명령을
실행한 뒤 각 공식/제3자 경로에서 자신의 PC로 직접 내려받습니다.

`Full` 프리셋은 조건부 Kanana License를 읽고 동의한 경우에만
`-AcceptKananaLicense`로 설치할 수 있습니다.

자세한 내용은 [한국어 README](../README.md) 또는
[English README](../README.en.md)를 확인하십시오.
