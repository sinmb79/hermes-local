[CmdletBinding()]
param(
    [switch]$IncludeOllama,
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
$ollamaAppExe = Join-Path (Split-Path -Parent $ollamaExe) "ollama app.exe"
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

function Test-CommandContainsPath {
    param(
        [AllowEmptyString()][string]$CommandLine,
        [Parameter(Mandatory = $true)][string]$Path
    )
    return $CommandLine.IndexOf(
        $Path,
        [System.StringComparison]::OrdinalIgnoreCase
    ) -ge 0
}

function Wait-ListenerStopped {
    param([Parameter(Mandatory = $true)][int]$Port)
    $deadline = (Get-Date).AddSeconds(10)
    do {
        Start-Sleep -Milliseconds 250
        $listener = Get-NetTCPConnection `
            -LocalAddress "127.0.0.1" `
            -LocalPort $Port `
            -State Listen `
            -ErrorAction SilentlyContinue
    } while ($listener -and (Get-Date) -lt $deadline)

    if ($listener) {
        throw "$Port 포트의 관리 대상 프로세스가 종료되지 않았습니다."
    }
}

$routerListener = Get-NetTCPConnection `
    -LocalAddress "127.0.0.1" `
    -LocalPort 11435 `
    -State Listen `
    -ErrorAction SilentlyContinue |
    Select-Object -First 1

if ($routerListener) {
    $routerProcess = Get-CimInstance `
        Win32_Process `
        -Filter "ProcessId = $($routerListener.OwningProcess)"
    if (
        $null -eq $routerProcess -or
        -not (Test-CommandContainsPath -CommandLine ([string]$routerProcess.CommandLine) -Path $routerPath) -or
        -not (Test-CommandContainsPath -CommandLine ([string]$routerProcess.CommandLine) -Path $routerConfig)
    ) {
        throw "11435 포트 프로세스가 이 폴더에서 시작한 Hermes 라우터가 아닙니다."
    }
    $routerProcessIds = @([int]$routerProcess.ProcessId)
    $routerParent = Get-CimInstance `
        Win32_Process `
        -Filter "ProcessId = $($routerProcess.ParentProcessId)" `
        -ErrorAction SilentlyContinue
    if ($routerParent) {
        $parentExecutable = [System.IO.Path]::GetFullPath(
            [string]$routerParent.ExecutablePath
        )
        $expectedPython = [System.IO.Path]::GetFullPath($pythonExe)
        if (
            $parentExecutable.Equals(
                $expectedPython,
                [System.StringComparison]::OrdinalIgnoreCase
            ) -and
            (Test-CommandContainsPath -CommandLine ([string]$routerParent.CommandLine) -Path $routerPath) -and
            (Test-CommandContainsPath -CommandLine ([string]$routerParent.CommandLine) -Path $routerConfig)
        ) {
            $routerProcessIds += [int]$routerParent.ProcessId
        }
    }
    Stop-Process -Id ($routerProcessIds | Sort-Object -Unique) -Force
    Wait-ListenerStopped -Port 11435
    if (-not $Quiet) {
        Write-Host "Hermes 로컬 라우터를 중지했습니다." -ForegroundColor Yellow
    }
}

if ($IncludeOllama) {
    $ollamaListener = Get-NetTCPConnection `
        -LocalAddress "127.0.0.1" `
        -LocalPort 11434 `
        -State Listen `
        -ErrorAction SilentlyContinue |
        Select-Object -First 1

    if ($ollamaListener) {
        $ollamaProcess = Get-CimInstance `
            Win32_Process `
            -Filter "ProcessId = $($ollamaListener.OwningProcess)"
        $actualExecutable = [System.IO.Path]::GetFullPath(
            [string]$ollamaProcess.ExecutablePath
        )
        $expectedExecutable = [System.IO.Path]::GetFullPath($ollamaExe)
        if (
            $null -eq $ollamaProcess -or
            -not $actualExecutable.Equals(
                $expectedExecutable,
                [System.StringComparison]::OrdinalIgnoreCase
            )
        ) {
            throw "11434 포트 프로세스가 관리 대상 Ollama가 아닙니다."
        }
        $ollamaProcessIds = @([int]$ollamaProcess.ProcessId)
        $ollamaParent = Get-CimInstance `
            Win32_Process `
            -Filter "ProcessId = $($ollamaProcess.ParentProcessId)" `
            -ErrorAction SilentlyContinue
        if ($ollamaParent) {
            $parentExecutable = [System.IO.Path]::GetFullPath(
                [string]$ollamaParent.ExecutablePath
            )
            $expectedAppExecutable = [System.IO.Path]::GetFullPath($ollamaAppExe)
            if ($parentExecutable.Equals(
                $expectedAppExecutable,
                [System.StringComparison]::OrdinalIgnoreCase
            )) {
                $ollamaProcessIds += [int]$ollamaParent.ProcessId
            }
        }
        Stop-Process -Id ($ollamaProcessIds | Sort-Object -Unique) -Force
        Wait-ListenerStopped -Port 11434
        if (-not $Quiet) {
            Write-Host "Ollama를 중지했습니다." -ForegroundColor Yellow
        }
    }
}
