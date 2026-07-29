[CmdletBinding()]
param()

$ErrorActionPreference = "Stop"
$toolRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$desktop = [Environment]::GetFolderPath("Desktop")
$powershellExe = Join-Path $env:SystemRoot (
    "System32\WindowsPowerShell\v1.0\powershell.exe"
)

if (-not (Test-Path -LiteralPath $powershellExe)) {
    throw "Windows PowerShell 실행 파일을 찾지 못했습니다: $powershellExe"
}

$shell = New-Object -ComObject WScript.Shell

function New-HermesShortcut {
    param(
        [Parameter(Mandatory = $true)][string]$Name,
        [Parameter(Mandatory = $true)][string]$ScriptPath,
        [switch]$KeepOpen
    )

    $shortcutPath = Join-Path $desktop "$Name.lnk"
    $shortcut = $shell.CreateShortcut($shortcutPath)
    $shortcut.TargetPath = $powershellExe
    $noExit = if ($KeepOpen) { "-NoExit " } else { "" }
    $shortcut.Arguments = (
        "-NoProfile -ExecutionPolicy Bypass {0}-File `"{1}`"" -f
        $noExit,
        $ScriptPath
    )
    $shortcut.WorkingDirectory = $toolRoot
    $shortcut.IconLocation = "$powershellExe,0"
    $shortcut.Save()
    Write-Host "바로가기 생성: $shortcutPath" -ForegroundColor Green
}

New-HermesShortcut `
    -Name "Hermes Local Agent" `
    -ScriptPath (Join-Path $toolRoot "Start-Hermes.ps1") `
    -KeepOpen
New-HermesShortcut `
    -Name "Hermes Local Settings" `
    -ScriptPath (Join-Path $toolRoot "Hermes-Local-Settings.ps1")
