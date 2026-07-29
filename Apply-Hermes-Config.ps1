[CmdletBinding()]
param(
    [switch]$NoBackup
)

$ErrorActionPreference = "Stop"
$defaultHermesRoot = Join-Path $env:LOCALAPPDATA "hermes"
$hermesCommand = Get-Command "hermes.exe" -ErrorAction SilentlyContinue
$hermesExe = if (-not [string]::IsNullOrWhiteSpace($env:HERMES_EXE)) {
    $env:HERMES_EXE
}
elseif ($hermesCommand) {
    $hermesCommand.Source
}
else {
    Join-Path $defaultHermesRoot "hermes-agent\venv\Scripts\hermes.exe"
}
$configPath = if (-not [string]::IsNullOrWhiteSpace($env:HERMES_CONFIG)) {
    $env:HERMES_CONFIG
}
else {
    Join-Path $defaultHermesRoot "config.yaml"
}
$hermesRoot = Split-Path -Parent $configPath

if (-not (Test-Path -LiteralPath $hermesExe)) {
    throw "Hermes 실행 파일을 찾지 못했습니다: $hermesExe"
}
if (-not (Test-Path -LiteralPath $configPath)) {
    throw "Hermes 설정 파일을 찾지 못했습니다: $configPath"
}

$backupPath = $null
if (-not $NoBackup) {
    $stamp = Get-Date -Format "yyyyMMdd-HHmmss"
    $backupPath = Join-Path $hermesRoot "config.before-local-$stamp.yaml"
    Copy-Item -LiteralPath $configPath -Destination $backupPath
    Write-Host "기존 설정 백업: $backupPath" -ForegroundColor DarkGray
}

function Set-HermesConfig {
    param(
        [Parameter(Mandatory = $true)][string]$Key,
        [Parameter(Mandatory = $true)][string]$Value
    )
    $previousErrorAction = $ErrorActionPreference
    $ErrorActionPreference = "Continue"
    $commandOutput = & $hermesExe config set $Key $Value 2>&1
    $commandExitCode = $LASTEXITCODE
    $ErrorActionPreference = $previousErrorAction
    if ($commandExitCode -ne 0) {
        throw "Hermes 설정 실패 ($Key): $($commandOutput -join ' ')"
    }
}

$routerUrl = "http://127.0.0.1:11435/v1"
$ollamaUrl = "http://127.0.0.1:11434/v1"

try {
Set-HermesConfig "providers.local-router.name" "Hermes Local Auto Router"
Set-HermesConfig "providers.local-router.api" $routerUrl
Set-HermesConfig "providers.local-router.transport" "chat_completions"
Set-HermesConfig "providers.local-router.default_model" "hermes-auto"
Set-HermesConfig "providers.local-router.context_length" "65536"
Set-HermesConfig "providers.local-router.discover_models" "true"

Set-HermesConfig "providers.local-ollama.name" "Local Ollama Direct"
Set-HermesConfig "providers.local-ollama.api" $ollamaUrl
Set-HermesConfig "providers.local-ollama.transport" "chat_completions"
Set-HermesConfig "providers.local-ollama.default_model" "hermes-fast"
Set-HermesConfig "providers.local-ollama.context_length" "65536"
Set-HermesConfig "providers.local-ollama.discover_models" "true"

Set-HermesConfig "model.provider" "local-router"
Set-HermesConfig "model.base_url" $routerUrl
Set-HermesConfig "model.default" "hermes-auto"
Set-HermesConfig "model.api_mode" "chat_completions"
Set-HermesConfig "model.context_length" "65536"
Set-HermesConfig "model.ollama_num_ctx" "65536"
Set-HermesConfig "compression.enabled" "true"
Set-HermesConfig "compression.threshold" "0.10"
Set-HermesConfig "compression.target_ratio" "0.20"
Set-HermesConfig "compression.protect_last_n" "8"

Set-HermesConfig "fallback_model.provider" "local-ollama"
Set-HermesConfig "fallback_model.model" "hermes-fast"
Set-HermesConfig "fallback_model.base_url" $ollamaUrl
Set-HermesConfig "fallback_model.api_mode" "chat_completions"

Set-HermesConfig "delegation.provider" "local-router"
Set-HermesConfig "delegation.model" "hermes-auto"
Set-HermesConfig "delegation.base_url" $routerUrl
Set-HermesConfig "delegation.api_mode" "chat_completions"
Set-HermesConfig "delegation.max_concurrent_children" "1"
Set-HermesConfig "delegation.max_spawn_depth" "1"
Set-HermesConfig "delegation.subagent_auto_approve" "false"

$auxiliaryAssignments = @(
    "web_extract",
    "title_generation",
    "triage_specifier",
    "skills_hub",
    "compression",
    "vision",
    "approval",
    "kanban_decomposer",
    "profile_describer"
)

foreach ($taskName in $auxiliaryAssignments) {
    $prefix = "auxiliary.$taskName"
    Set-HermesConfig "$prefix.provider" "local-router"
    Set-HermesConfig "$prefix.model" "hermes-auto"
    Set-HermesConfig "$prefix.base_url" $routerUrl
    Set-HermesConfig "$prefix.api_mode" "chat_completions"
}

$previousErrorAction = $ErrorActionPreference
$ErrorActionPreference = "Continue"
$checkOutput = & $hermesExe config check 2>&1
$checkExitCode = $LASTEXITCODE
$ErrorActionPreference = $previousErrorAction
if ($checkExitCode -ne 0) {
    throw "Hermes 설정 검증 실패: $($checkOutput -join ' ')"
}
}
catch {
    if ($backupPath -and (Test-Path -LiteralPath $backupPath)) {
        Copy-Item -LiteralPath $backupPath -Destination $configPath -Force
        Write-Warning "설정 적용에 실패해 백업으로 자동 복구했습니다: $backupPath"
    }
    throw
}

Write-Host "Hermes가 로컬 자동 라우터를 사용하도록 설정했습니다." -ForegroundColor Green
Write-Host "기본 모델: hermes-auto / Hermes 호환 문맥: 65,536 / 10% 조기 압축" -ForegroundColor Cyan
