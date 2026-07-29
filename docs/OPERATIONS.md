# 운영 가이드

[English](OPERATIONS.en.md)

## 1. 설치 전 확인

Ollama와 Hermes Agent를 각 공식 설치 문서에 따라 먼저 설치합니다.

```powershell
ollama --version
hermes --version
```

이 저장소는 모델 가중치를 포함하지 않습니다. `modelfiles/`의 `FROM`
경로를 사용자가 명시적으로 실행할 때 Ollama가 각자의 PC로 내려받습니다.

## 2. 프리셋 설치

```powershell
# 설치 상태와 참조 경로만 확인
.\Install-Hermes-Models.ps1 -Preset Core

# 누락 모델을 이 PC로 다운로드하고 역할 별칭 생성
.\Install-Hermes-Models.ps1 -Preset Core -PullMissing

# 기존 별칭을 Modelfile 기준으로 다시 생성
.\Install-Hermes-Models.ps1 -Preset Core -Recreate
```

프리셋은 `Core`, `Developer`, `Korean`, `Full`입니다. `Full`은 Kanana
License 확인 후에만 실행할 수 있습니다.

```powershell
.\Install-Hermes-Models.ps1 `
    -Preset Full `
    -PullMissing `
    -AcceptKananaLicense
```

## 3. Hermes 설정 연결

```powershell
.\Start-Hermes-Services.ps1
.\Apply-Hermes-Config.ps1
```

`Apply-Hermes-Config.ps1`은 다음을 수행합니다.

1. 기존 `%LOCALAPPDATA%\hermes\config.yaml`을
   `config.before-local-<timestamp>.yaml`로 백업
2. `http://127.0.0.1:11435/v1`을 `local-router` provider로 등록
3. 기본 모델과 보조 작업을 `hermes-auto`로 연결
4. 직접 Ollama 대체 모델을 `hermes-fast`로 설정
5. `hermes config check` 실행
6. 적용 실패 시 백업을 자동 복원

Hermes 호환 설정은 문맥 65,536, 압축 시작 10%, 목표 비율 20%입니다.
이는 모든 기초 모델의 원생 문맥이 64K라는 뜻이 아닙니다.

## 4. 서비스 수명주기

```powershell
# Ollama와 라우터를 필요할 때만 시작
.\Start-Hermes-Services.ps1

# 이 저장소의 라우터만 재시작
.\Restart-Hermes-Services.ps1

# 이 저장소의 라우터만 중지
.\Stop-Hermes-Services.ps1

# 이 스크립트가 관리하는 Ollama까지 중지
.\Stop-Hermes-Services.ps1 -IncludeOllama
```

스크립트는 포트만 보고 임의의 프로세스를 종료하지 않습니다. 실행 파일,
명령줄의 `router.py`, 설정 경로를 확인한 관리 대상만 중지합니다.

## 5. 상태와 생성 검증

```powershell
Invoke-RestMethod http://127.0.0.1:11435/health |
    ConvertTo-Json -Depth 6

ollama list
ollama ps

.\Test-Hermes-Local.ps1 -Preset Core -Generation
.\Test-Hermes-E2E.ps1
```

Hermes terminal 도구 검증은 실제 로컬 명령 실행 권한을 사용하므로
명시적으로 켭니다.

```powershell
.\Test-Hermes-E2E.ps1 -IncludeTool
```

## 6. 라우팅 모드 변경

```powershell
.\Hermes-Local-Settings.ps1
```

GUI에서 `auto`, `fast`, `coding`, `quality`, `korean`,
`korean_writing`, `korean_fast`를 선택할 수 있습니다. 설치하지 않은
프로필을 강제 선택하면 요청이 대체 순서로 이동하거나 설치 오류를
반환할 수 있습니다.

JSON을 직접 편집하려면 변경 전에 백업하고, `listen_host`와
`ollama_base_url`을 loopback 이외의 주소로 바꾸지 마십시오. 라우터는
외부 주소 설정을 거부합니다.

## 7. 로그

```powershell
Get-Content .\logs\router.log -Tail 50
```

라우터 로그에는 시간, 선택 프로필, 모델, 선택 이유, 시도, 상태, 경과
시간만 기록합니다. 프롬프트와 응답 본문은 기록하지 않습니다. 로그는
2MB 단위로 회전하며 백업 3개를 유지합니다.

## 8. 이전 Hermes 설정 복원

먼저 서비스를 중지하고 원하는 백업을 확인합니다.

```powershell
.\Stop-Hermes-Services.ps1

$hermesRoot = Join-Path $env:LOCALAPPDATA "hermes"
Get-ChildItem $hermesRoot -Filter "config.before-local-*.yaml"
```

선택한 파일을 직접 지정해 복원합니다.

```powershell
$backup = Join-Path $env:LOCALAPPDATA (
    "hermes\config.before-local-YYYYMMDD-HHMMSS.yaml"
)
$config = Join-Path $env:LOCALAPPDATA "hermes\config.yaml"
Copy-Item -LiteralPath $backup -Destination $config -Force
hermes config check
```

설정 파일 내용을 공개 이슈나 로그에 붙여넣지 마십시오.

기본 설치 위치가 아닌 경우에는 현재 PowerShell 세션에서 경로를 명시할
수 있습니다.

```powershell
$env:OLLAMA_EXE = "D:\Apps\Ollama\ollama.exe"
$env:HERMES_EXE = "D:\Apps\Hermes\Scripts\hermes.exe"
$env:PYTHON_EXE = "D:\Apps\Hermes\Scripts\python.exe"
$env:HERMES_CONFIG = "D:\HermesData\config.yaml"
```

실제 경로는 각자의 설치 위치로 바꾸고, 이 값들을 저장소 파일에
커밋하지 마십시오.

## 9. 제거

저장소 폴더를 삭제하기 전에 이전 설정을 복원하고 서비스를 중지합니다.
모델은 사용자가 선택해 Ollama에서 별도로 제거합니다.

```powershell
ollama rm hermes-fast
ollama rm hermes-coder
ollama rm hermes-quality
ollama rm hermes-korean-writing
ollama rm hermes-korean-fast
ollama rm hermes-korean-agent
```

기초 모델까지 제거하려면 `ollama list`에서 다른 프로젝트가 사용하지
않는지 먼저 확인하십시오.

## 10. 문제 해결

### 11434 포트를 다른 프로세스가 사용함

```powershell
Get-NetTCPConnection -LocalPort 11434 -State Listen
```

스크립트는 관리 대상 Ollama가 아닌 프로세스를 대신 종료하지 않습니다.

### 11435 라우터가 시작되지 않음

```powershell
python .\router.py --config .\router-config.json
```

전면 실행에서 오류를 확인한 뒤 종료하고 정상 시작 스크립트를 다시
사용하십시오.

### 모델이 없음

```powershell
.\Install-Hermes-Models.ps1 -Preset Core -PullMissing
```

### 메모리 부족

`Core`만 설치하고, `quality`와 64K KV 캐시가 동시에 메모리에 올라가지
않도록 `OLLAMA_MAX_LOADED_MODELS=1` 설정을 유지하십시오.
