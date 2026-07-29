[CmdletBinding()]
param()

$ErrorActionPreference = "Stop"
$projectRoot = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
$restartScript = Join-Path $projectRoot "Restart-Hermes-Services.ps1"
$startScript = Join-Path $projectRoot "Start-Hermes-Services.ps1"

if (-not (Test-Path -LiteralPath $restartScript)) {
    throw "서비스 재시작 스크립트가 없습니다."
}

$before = Invoke-RestMethod -Uri "http://127.0.0.1:11435/health" -TimeoutSec 5
& $restartScript -Quiet
$after = Invoke-RestMethod -Uri "http://127.0.0.1:11435/health" -TimeoutSec 5

if ([int]$before.router.pid -eq [int]$after.router.pid) {
    throw "재시작 뒤에도 라우터 PID가 바뀌지 않았습니다."
}
if ($after.status -ne "ok" -or [string]::IsNullOrWhiteSpace($after.router.instance_id)) {
    throw "재시작 뒤 라우터 상태가 정상이 아닙니다."
}

& $startScript -Quiet
$idempotent = Invoke-RestMethod -Uri "http://127.0.0.1:11435/health" -TimeoutSec 5
if ([int]$after.router.pid -ne [int]$idempotent.router.pid) {
    throw "일반 시작 명령이 정상 라우터를 중복 실행했습니다."
}

Write-Host "서비스 수명주기 검증: 정상" -ForegroundColor Green
