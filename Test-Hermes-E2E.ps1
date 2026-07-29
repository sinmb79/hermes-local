[CmdletBinding()]
param(
    [switch]$IncludeTool
)

$ErrorActionPreference = "Stop"
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

if (-not (Test-Path -LiteralPath $hermesExe)) {
    throw "Hermes 실행 파일을 찾지 못했습니다: $hermesExe"
}

& (Join-Path $toolRoot "Start-Hermes-Services.ps1") -Quiet

function Invoke-HermesCheck {
    param(
        [Parameter(Mandatory = $true)][string[]]$Arguments,
        [Parameter(Mandatory = $true)][string]$Expected
    )

    $previousErrorAction = $ErrorActionPreference
    $ErrorActionPreference = "Continue"
    $output = & $hermesExe @Arguments 2>&1
    $exitCode = $LASTEXITCODE
    $ErrorActionPreference = $previousErrorAction

    if ($exitCode -ne 0) {
        throw "Hermes E2E 실패 ($Expected, exit=$exitCode)"
    }

    $matched = @($output | ForEach-Object { ([string]$_).Trim() }) -contains $Expected
    if (-not $matched) {
        throw "Hermes E2E 예상 응답 누락: $Expected"
    }
    Write-Host "Hermes E2E: $Expected" -ForegroundColor Green
}

Invoke-HermesCheck `
    -Arguments @(
        "-z",
        "도구를 사용하지 말고 정확히 HERMES_LOCAL_OK만 답하세요."
    ) `
    -Expected "HERMES_LOCAL_OK"

if ($IncludeTool) {
    Invoke-HermesCheck `
        -Arguments @(
            "-t",
            "terminal",
            "-z",
            "terminal 도구를 정확히 한 번 사용해서 echo HERMES_TOOL_OK 명령을 실행한 뒤, 그 결과를 정확히 HERMES_TOOL_OK로 답하세요."
        ) `
        -Expected "HERMES_TOOL_OK"
}
