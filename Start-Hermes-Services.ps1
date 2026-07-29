[CmdletBinding()]
param(
    [switch]$Quiet
)

$ErrorActionPreference = "Stop"
$toolRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$routerPath = Join-Path $toolRoot "router.py"
$routerConfig = Join-Path $toolRoot "router-config.json"
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
$hermesCommand = Get-Command "hermes.exe" -ErrorAction SilentlyContinue
$pythonExe = if (-not [string]::IsNullOrWhiteSpace($env:PYTHON_EXE)) {
    $env:PYTHON_EXE
}
elseif ($hermesCommand) {
    Join-Path (Split-Path -Parent $hermesCommand.Source) "python.exe"
}
else {
    Join-Path $env:LOCALAPPDATA "hermes\hermes-agent\venv\Scripts\python.exe"
}

function Get-ListenerProcessId {
    param([Parameter(Mandatory = $true)][int]$Port)
    try {
        $listener = Get-NetTCPConnection `
            -State Listen `
            -LocalAddress "127.0.0.1" `
            -LocalPort $Port `
            -ErrorAction Stop |
            Select-Object -First 1
        return [int]$listener.OwningProcess
    }
    catch {
        return 0
    }
}

function Test-OllamaEndpoint {
    try {
        $version = Invoke-RestMethod `
            -Uri "http://127.0.0.1:11434/api/version" `
            -TimeoutSec 2
        if ([string]::IsNullOrWhiteSpace([string]$version.version)) {
            return $false
        }
        $ownerProcessId = Get-ListenerProcessId -Port 11434
        if ($ownerProcessId -le 0) {
            return $false
        }
        $process = Get-CimInstance Win32_Process `
            -Filter "ProcessId=$ownerProcessId" `
            -ErrorAction Stop
        return [string]::Equals(
            [System.IO.Path]::GetFullPath([string]$process.ExecutablePath),
            [System.IO.Path]::GetFullPath($ollamaExe),
            [System.StringComparison]::OrdinalIgnoreCase
        )
    }
    catch {
        return $false
    }
}

function Test-RouterEndpoint {
    try {
        $health = Invoke-RestMethod `
            -Uri "http://127.0.0.1:11435/health" `
            -TimeoutSec 3
        if (
            $health.status -ne "ok" -or
            [string]$health.router.version -notlike "HermesLocalRouter/*"
        ) {
            return $false
        }
        $ownerProcessId = Get-ListenerProcessId -Port 11435
        if ($ownerProcessId -le 0 -or [int]$health.router.pid -ne $ownerProcessId) {
            return $false
        }
        $process = Get-CimInstance Win32_Process `
            -Filter "ProcessId=$ownerProcessId" `
            -ErrorAction Stop
        $commandLine = [string]$process.CommandLine
        return (
            $commandLine.IndexOf(
                $routerPath,
                [System.StringComparison]::OrdinalIgnoreCase
            ) -ge 0 -and
            $commandLine.IndexOf(
                $routerConfig,
                [System.StringComparison]::OrdinalIgnoreCase
            ) -ge 0
        )
    }
    catch {
        return $false
    }
}

if (-not (Test-Path -LiteralPath $ollamaExe)) {
    throw "Ollama 실행 파일을 찾지 못했습니다: $ollamaExe"
}
if (-not (Test-Path -LiteralPath $pythonExe)) {
    throw (
        "Python 실행 파일을 찾지 못했습니다: $pythonExe. " +
        "필요하면 PYTHON_EXE 환경변수로 지정해 주세요."
    )
}

if (-not (Test-OllamaEndpoint)) {
    $env:OLLAMA_HOST = "127.0.0.1:11434"
    $env:OLLAMA_NO_CLOUD = "1"
    $env:OLLAMA_MAX_LOADED_MODELS = "1"
    $env:OLLAMA_NUM_PARALLEL = "1"
    $env:OLLAMA_FLASH_ATTENTION = "1"
    $env:OLLAMA_KV_CACHE_TYPE = "q8_0"
    Start-Process -FilePath $ollamaExe -ArgumentList "serve" -WindowStyle Hidden

    $ollamaReady = $false
    for ($index = 0; $index -lt 30; $index++) {
        Start-Sleep -Milliseconds 500
        if (Test-OllamaEndpoint) {
            $ollamaReady = $true
            break
        }
    }
    if (-not $ollamaReady) {
        throw "Ollama가 15초 안에 시작되지 않았습니다."
    }
}

if (-not (Test-RouterEndpoint)) {
    Start-Process `
        -FilePath $pythonExe `
        -ArgumentList @($routerPath, "--config", $routerConfig) `
        -WorkingDirectory $toolRoot `
        -WindowStyle Hidden

    $routerReady = $false
    for ($index = 0; $index -lt 30; $index++) {
        Start-Sleep -Milliseconds 500
        if (Test-RouterEndpoint) {
            $routerReady = $true
            break
        }
    }
    if (-not $routerReady) {
        throw "Hermes 로컬 모델 라우터가 15초 안에 시작되지 않았습니다."
    }
}

if (-not $Quiet) {
    $health = Invoke-RestMethod -Uri "http://127.0.0.1:11435/health" -TimeoutSec 3
    Write-Host "Ollama       : 준비됨 (127.0.0.1:11434)" -ForegroundColor Green
    Write-Host "모델 라우터  : 준비됨 (127.0.0.1:11435)" -ForegroundColor Green
    Write-Host "선택 모드    : $($health.mode)" -ForegroundColor Cyan
}
