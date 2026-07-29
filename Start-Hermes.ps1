[CmdletBinding()]
param()

$ErrorActionPreference = "Stop"
$OutputEncoding = [Console]::OutputEncoding = [System.Text.UTF8Encoding]::new($false)
$toolRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$hermesCommand = Get-Command "hermes.exe" -ErrorAction SilentlyContinue
$hermesExe = if (-not [string]::IsNullOrWhiteSpace($env:HERMES_EXE)) {
    $env:HERMES_EXE
}
elseif ($hermesCommand) {
    $hermesCommand.Source
}
else {
    Join-Path $env:LOCALAPPDATA "hermes\hermes-agent\venv\Scripts\hermes.exe"
}

if ($host.Name -eq "ConsoleHost") {
    $host.UI.RawUI.WindowTitle = "Hermes Agent - 로컬 자동 모델"
}

try {
    & (Join-Path $toolRoot "Start-Hermes-Services.ps1")
}
catch {
    Write-Host ""
    Write-Host "로컬 AI 서비스 시작 실패: $($_.Exception.Message)" -ForegroundColor Red
    Write-Host "바탕화면의 'Hermes 로컬 LLM 설정'에서 상태를 확인해 주세요." -ForegroundColor Yellow
    return
}

if (-not (Test-Path -LiteralPath $hermesExe)) {
    Write-Host "Hermes 실행 파일을 찾지 못했습니다: $hermesExe" -ForegroundColor Red
    return
}

Write-Host ""
Write-Host "Hermes를 시작합니다. 업무에 따라 모델이 자동 선택됩니다." -ForegroundColor Cyan
Write-Host "  일반·도구 작업 : GPT-OSS 20B" -ForegroundColor DarkGray
Write-Host "  코딩           : Qwen3-Coder 30B-A3B" -ForegroundColor DarkGray
Write-Host "  한국어 집필    : KT Mi:dm 2.0 12B" -ForegroundColor DarkGray
Write-Host "  한국어 고속    : SKT A.X 4.0 Light" -ForegroundColor DarkGray
Write-Host "  수동 고품질    : Qwen3.6 35B-A3B (메모리 사용량 큼)" -ForegroundColor DarkGray
Write-Host "  수동 실험      : Kakao Kanana-2 30B-A3B" -ForegroundColor DarkGray
Write-Host ""

& $hermesExe
