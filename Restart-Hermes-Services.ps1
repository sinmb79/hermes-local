[CmdletBinding()]
param(
    [switch]$Quiet
)

$ErrorActionPreference = "Stop"
$toolRoot = Split-Path -Parent $MyInvocation.MyCommand.Path

& (Join-Path $toolRoot "Stop-Hermes-Services.ps1") -Quiet
& (Join-Path $toolRoot "Start-Hermes-Services.ps1") -Quiet

if (-not $Quiet) {
    $health = Invoke-RestMethod -Uri "http://127.0.0.1:11435/health" -TimeoutSec 5
    Write-Host "Hermes 로컬 서비스가 재시작됐습니다." -ForegroundColor Green
    Write-Host "라우터 PID: $($health.router.pid)" -ForegroundColor DarkGray
}
