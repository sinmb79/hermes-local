[CmdletBinding()]
param(
    [ValidateSet("Core", "Developer", "Korean", "Full")]
    [string]$Preset = "Core",
    [switch]$PullMissing,
    [switch]$Recreate,
    [switch]$AcceptKananaLicense
)

$ErrorActionPreference = "Stop"
$toolRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$ollamaCommand = Get-Command "ollama.exe" -ErrorAction SilentlyContinue
$ollamaExe = if (-not [string]::IsNullOrWhiteSpace($env:OLLAMA_EXE)) {
    $env:OLLAMA_EXE
}
elseif ($ollamaCommand) {
    $ollamaCommand.Source
}
else {
    Join-Path $env:LOCALAPPDATA "Programs\Ollama\ollama.exe"
}

if (-not (Test-Path -LiteralPath $ollamaExe)) {
    throw "Ollama 실행 파일을 찾지 못했습니다: $ollamaExe"
}
if ($Preset -eq "Full" -and -not $AcceptKananaLicense) {
    throw (
        "Full 프리셋에는 별도 조건의 Kanana 모델이 포함됩니다. " +
        "THIRD_PARTY_NOTICES.md와 Kanana License를 읽고 동의하는 경우에만 " +
        "-AcceptKananaLicense를 추가해 주세요."
    )
}

$profiles = @(
    [pscustomobject]@{
        Name = "최고 품질"
        Base = "qwen3.6:35b"
        Alias = "hermes-quality"
        Modelfile = "quality.Modelfile"
        Presets = @("Full")
    },
    [pscustomobject]@{
        Name = "코딩"
        Base = "qwen3-coder:30b"
        Alias = "hermes-coder"
        Modelfile = "coding.Modelfile"
        Presets = @("Developer", "Full")
    },
    [pscustomobject]@{
        Name = "빠른 도구 작업"
        Base = "gpt-oss:20b"
        Alias = "hermes-fast"
        Modelfile = "fast.Modelfile"
        Presets = @("Core", "Developer", "Korean", "Full")
    },
    [pscustomobject]@{
        Name = "한국어 에이전트"
        Base = "hf.co/deul/Kanana-2-30b-a3b-instruct-2601-GGUF:Q4_K_M"
        Alias = "hermes-korean-agent"
        Modelfile = "korean.Modelfile"
        Presets = @("Full")
    },
    [pscustomobject]@{
        Name = "한국어 집필"
        Base = "hf.co/mykor/Midm-2.0-Base-Instruct-gguf:Q6_K"
        Alias = "hermes-korean-writing"
        Modelfile = "korean-writing.Modelfile"
        Presets = @("Korean", "Full")
    },
    [pscustomobject]@{
        Name = "한국어 고속"
        Base = "hf.co/mykor/A.X-4.0-Light-gguf:Q6_K"
        Alias = "hermes-korean-fast"
        Modelfile = "korean-fast.Modelfile"
        Presets = @("Korean", "Full")
    }
)

function Test-OllamaModel {
    param([Parameter(Mandatory = $true)][string]$Name)
    $previousErrorAction = $ErrorActionPreference
    $ErrorActionPreference = "Continue"
    & $ollamaExe show $Name *> $null
    $exitCode = $LASTEXITCODE
    $ErrorActionPreference = $previousErrorAction
    return $exitCode -eq 0
}

$selectedProfiles = @(
    $profiles | Where-Object { $_.Presets -contains $Preset }
)

Write-Host "설치 프리셋: $Preset ($($selectedProfiles.Count)개 역할 모델)" -ForegroundColor Cyan

foreach ($profile in $selectedProfiles) {
    if (-not (Test-OllamaModel -Name $profile.Base)) {
        if (-not $PullMissing) {
            throw "기본 모델이 없습니다: $($profile.Base). -PullMissing으로 다시 실행해 주세요."
        }
        Write-Host "다운로드: $($profile.Base)" -ForegroundColor Cyan
        & $ollamaExe pull $profile.Base
        if ($LASTEXITCODE -ne 0) {
            throw "모델 다운로드 실패: $($profile.Base)"
        }
    }

    if ($Recreate -or -not (Test-OllamaModel -Name $profile.Alias)) {
        $modelfilePath = Join-Path (Join-Path $toolRoot "modelfiles") $profile.Modelfile
        Write-Host "프로필 생성: $($profile.Alias) ($($profile.Name))" -ForegroundColor Cyan
        & $ollamaExe create $profile.Alias -f $modelfilePath
        if ($LASTEXITCODE -ne 0) {
            throw "프로필 생성 실패: $($profile.Alias)"
        }
    }
    else {
        Write-Host "프로필 확인: $($profile.Alias)" -ForegroundColor DarkGray
    }
}

Write-Host "Hermes $Preset 프리셋 모델 $($selectedProfiles.Count)종이 준비됐습니다." -ForegroundColor Green
