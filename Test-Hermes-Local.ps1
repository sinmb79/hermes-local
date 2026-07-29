[CmdletBinding()]
param(
    [ValidateSet("Core", "Developer", "Korean", "Full")]
    [string]$Preset = "Core",
    [switch]$Generation
)

$ErrorActionPreference = "Stop"
$toolRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
& (Join-Path $toolRoot "Start-Hermes-Services.ps1") -Quiet

$health = Invoke-RestMethod -Uri "http://127.0.0.1:11435/health" -TimeoutSec 5
if ($health.status -ne "ok") {
    throw "라우터 상태가 정상이 아닙니다."
}
if (
    $null -eq $health.router -or
    [int]$health.router.pid -le 0 -or
    [string]::IsNullOrWhiteSpace([string]$health.router.instance_id)
) {
    throw "실행 중인 라우터가 최신 버전이 아닙니다. 서비스를 재시작해 주세요."
}

$presetProfiles = @{
    Core = @("fast")
    Developer = @("fast", "coding")
    Korean = @("fast", "korean_writing", "korean_fast")
    Full = @("quality", "coding", "fast", "korean", "korean_writing", "korean_fast")
}
$expectedProfiles = @($presetProfiles[$Preset])
foreach ($profile in $expectedProfiles) {
    $profileProperty = $health.models.PSObject.Properties[$profile]
    if ($null -eq $profileProperty) {
        throw "라우터 프로필 누락: $profile"
    }
    if (-not [bool]$profileProperty.Value) {
        throw "필수 모델 미설치: $profile"
    }
}

$modelCatalog = Invoke-RestMethod -Uri "http://127.0.0.1:11435/v1/models" -TimeoutSec 5
$catalogIds = @($modelCatalog.data | ForEach-Object { [string]$_.id })
$expectedModelIds = @(
    "hermes-auto",
    "hermes-quality",
    "hermes-coder",
    "hermes-fast",
    "hermes-korean-agent",
    "hermes-korean-writing",
    "hermes-korean-fast"
)
foreach ($modelId in $expectedModelIds) {
    if ($catalogIds -notcontains $modelId) {
        throw "라우터 모델 목록 누락: $modelId"
    }
}

Write-Host "라우터 상태: 정상 / 모드: $($health.mode) / 검증 프리셋: $Preset" -ForegroundColor Green
foreach ($property in $health.models.PSObject.Properties) {
    $state = if ($property.Value) { "설치됨" } else { "미설치" }
    Write-Host ("  {0,-16} {1}" -f $property.Name, $state)
}

if ($Generation) {
    $payload = @{
        model = "hermes-fast"
        messages = @(
            @{ role = "user"; content = "정확히 LOCAL_OK만 답하세요." }
        )
        stream = $false
        max_tokens = 128
        temperature = 0
    } | ConvertTo-Json -Depth 8
    $response = Invoke-RestMethod `
        -Method Post `
        -Uri "http://127.0.0.1:11435/v1/chat/completions" `
        -ContentType "application/json; charset=utf-8" `
        -Body ([System.Text.Encoding]::UTF8.GetBytes($payload)) `
        -TimeoutSec 600
    $text = [string]$response.choices[0].message.content
    if ($text -notmatch "LOCAL_OK") {
        throw "생성 검증 실패 (finish_reason=$($response.choices[0].finish_reason)): $text"
    }
    Write-Host "생성 검증: LOCAL_OK" -ForegroundColor Green
}
