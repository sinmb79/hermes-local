[CmdletBinding()]
param(
    [string]$ProjectRoot
)

$ErrorActionPreference = "Stop"
if ([string]::IsNullOrWhiteSpace($ProjectRoot)) {
    $ProjectRoot = Split-Path -Parent $PSScriptRoot
}
$failures = New-Object System.Collections.Generic.List[string]
$files = Get-ChildItem -LiteralPath $ProjectRoot -Recurse -File -Filter "*.ps1" |
    Where-Object { $_.FullName -notmatch "[\\/]\.git[\\/]" }

foreach ($file in $files) {
    $tokens = $null
    $parseErrors = $null
    [void][System.Management.Automation.Language.Parser]::ParseFile(
        $file.FullName,
        [ref]$tokens,
        [ref]$parseErrors
    )
    foreach ($parseError in @($parseErrors)) {
        $failures.Add(
            "$($file.FullName):$($parseError.Extent.StartLineNumber): " +
            $parseError.Message
        )
    }

    $bytes = [System.IO.File]::ReadAllBytes($file.FullName)
    $hasNonAscii = @($bytes | Where-Object { $_ -gt 127 }).Count -gt 0
    $hasUtf8Bom = (
        $bytes.Length -ge 3 -and
        $bytes[0] -eq 0xEF -and
        $bytes[1] -eq 0xBB -and
        $bytes[2] -eq 0xBF
    )
    if ($hasNonAscii -and -not $hasUtf8Bom) {
        $failures.Add("$($file.FullName): non-ASCII PowerShell file lacks UTF-8 BOM")
    }
}

if ($failures.Count -gt 0) {
    $failures | ForEach-Object { Write-Error $_ }
    throw "PowerShell static checks failed: $($failures.Count)"
}

Write-Host "PowerShell static checks passed: $($files.Count) files" -ForegroundColor Green
