[CmdletBinding()]
param(
    [ValidateSet("Core", "Developer", "Korean", "Full")]
    [string]$Preset = "Core",
    [switch]$InstallDesktopShortcuts,
    [switch]$SkipGenerationTest,
    [switch]$AcceptKananaLicense
)

$ErrorActionPreference = "Stop"
$toolRoot = Split-Path -Parent $MyInvocation.MyCommand.Path

if ($Preset -eq "Full") {
    Write-Warning (
        "Full includes the experimental Kanana profile. " +
        "Read THIRD_PARTY_NOTICES.md and the Kanana License before continuing."
    )
}
if ($Preset -eq "Full" -and -not $AcceptKananaLicense) {
    throw (
        "Full 프리셋은 -AcceptKananaLicense를 명시해야 설치할 수 있습니다."
    )
}

Write-Host "1/4 모델 설치 및 역할 별칭 생성" -ForegroundColor Cyan
& (Join-Path $toolRoot "Install-Hermes-Models.ps1") `
    -Preset $Preset `
    -PullMissing `
    -AcceptKananaLicense:$AcceptKananaLicense

Write-Host "2/4 로컬 서비스 시작" -ForegroundColor Cyan
& (Join-Path $toolRoot "Start-Hermes-Services.ps1")

Write-Host "3/4 Hermes Agent 설정 연결" -ForegroundColor Cyan
& (Join-Path $toolRoot "Apply-Hermes-Config.ps1")

Write-Host "4/4 설치 검증" -ForegroundColor Cyan
$testArguments = @{
    Preset = $Preset
}
if (-not $SkipGenerationTest) {
    $testArguments.Generation = $true
}
& (Join-Path $toolRoot "Test-Hermes-Local.ps1") @testArguments

if ($InstallDesktopShortcuts) {
    & (Join-Path $toolRoot "Install-Desktop-Shortcuts.ps1")
}

Write-Host ""
Write-Host "설치가 완료됐습니다. .\Start-Hermes.ps1 로 시작하세요." -ForegroundColor Green
