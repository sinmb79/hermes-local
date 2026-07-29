[CmdletBinding()]
param()

$ErrorActionPreference = "Stop"
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
[System.Windows.Forms.Application]::EnableVisualStyles()

$toolRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$configPath = Join-Path $toolRoot "router-config.json"
$startServices = Join-Path $toolRoot "Start-Hermes-Services.ps1"
$restartServices = Join-Path $toolRoot "Restart-Hermes-Services.ps1"
$applyConfig = Join-Path $toolRoot "Apply-Hermes-Config.ps1"
$startHermes = Join-Path $toolRoot "Start-Hermes.ps1"

$profileMap = [ordered]@{
    "자동 선택 (권장)"                 = "auto"
    "최고 품질 - Qwen3.6 35B"         = "quality"
    "코딩 - Qwen3-Coder 30B"          = "coding"
    "빠른 도구 작업 - GPT-OSS 20B"    = "fast"
    "한국어 실험·수동 - Kakao Kanana-2" = "korean"
    "한국어 집필 - KT Mi:dm 2.0"      = "korean_writing"
    "한국어 고속 - SKT A.X 4.0 Light" = "korean_fast"
}

function Read-RouterConfig {
    Get-Content -LiteralPath $configPath -Raw -Encoding UTF8 | ConvertFrom-Json
}

function Save-RouterConfig {
    param([Parameter(Mandatory = $true)]$Config)
    $json = $Config | ConvertTo-Json -Depth 20
    $utf8NoBom = [System.Text.UTF8Encoding]::new($false)
    $tempPath = Join-Path (Split-Path -Parent $configPath) (
        ".router-config-$([guid]::NewGuid().ToString('N')).tmp"
    )
    try {
        [System.IO.File]::WriteAllText($tempPath, $json, $utf8NoBom)
        Get-Content -LiteralPath $tempPath -Raw -Encoding UTF8 |
            ConvertFrom-Json | Out-Null
        [System.IO.File]::Replace($tempPath, $configPath, $null)
    }
    finally {
        if (Test-Path -LiteralPath $tempPath) {
            Remove-Item -LiteralPath $tempPath -Force
        }
    }
}

$form = New-Object System.Windows.Forms.Form
$form.Text = "Hermes 로컬 LLM 설정"
$form.Size = New-Object System.Drawing.Size(760, 600)
$form.StartPosition = "CenterScreen"
$form.FormBorderStyle = "FixedDialog"
$form.MaximizeBox = $false
$form.BackColor = [System.Drawing.Color]::FromArgb(245, 247, 250)
$form.Font = New-Object System.Drawing.Font("Malgun Gothic", 10)

$title = New-Object System.Windows.Forms.Label
$title.Text = "Hermes 로컬 AI 제어판"
$title.Location = New-Object System.Drawing.Point(28, 22)
$title.Size = New-Object System.Drawing.Size(680, 34)
$title.Font = New-Object System.Drawing.Font("Malgun Gothic", 18, [System.Drawing.FontStyle]::Bold)
$form.Controls.Add($title)

$subtitle = New-Object System.Windows.Forms.Label
$subtitle.Text = "LLM 요청 경로는 이 컴퓨터의 127.0.0.1 안에서만 동작합니다."
$subtitle.Location = New-Object System.Drawing.Point(31, 61)
$subtitle.Size = New-Object System.Drawing.Size(680, 24)
$subtitle.ForeColor = [System.Drawing.Color]::FromArgb(70, 80, 95)
$form.Controls.Add($subtitle)

$profileLabel = New-Object System.Windows.Forms.Label
$profileLabel.Text = "모델 선택 방식"
$profileLabel.Location = New-Object System.Drawing.Point(32, 108)
$profileLabel.Size = New-Object System.Drawing.Size(140, 26)
$profileLabel.Font = New-Object System.Drawing.Font("Malgun Gothic", 10, [System.Drawing.FontStyle]::Bold)
$form.Controls.Add($profileLabel)

$profileCombo = New-Object System.Windows.Forms.ComboBox
$profileCombo.Location = New-Object System.Drawing.Point(178, 105)
$profileCombo.Size = New-Object System.Drawing.Size(390, 32)
$profileCombo.DropDownStyle = "DropDownList"
foreach ($name in $profileMap.Keys) {
    [void]$profileCombo.Items.Add($name)
}
$form.Controls.Add($profileCombo)

$saveButton = New-Object System.Windows.Forms.Button
$saveButton.Text = "선택 저장"
$saveButton.Location = New-Object System.Drawing.Point(584, 103)
$saveButton.Size = New-Object System.Drawing.Size(130, 36)
$saveButton.BackColor = [System.Drawing.Color]::FromArgb(42, 99, 230)
$saveButton.ForeColor = [System.Drawing.Color]::White
$saveButton.FlatStyle = "Flat"
$form.Controls.Add($saveButton)

$statusBox = New-Object System.Windows.Forms.TextBox
$statusBox.Location = New-Object System.Drawing.Point(32, 162)
$statusBox.Size = New-Object System.Drawing.Size(682, 248)
$statusBox.Multiline = $true
$statusBox.ReadOnly = $true
$statusBox.ScrollBars = "Vertical"
$statusBox.BackColor = [System.Drawing.Color]::White
$statusBox.Font = New-Object System.Drawing.Font("Consolas", 10)
$form.Controls.Add($statusBox)

$refreshButton = New-Object System.Windows.Forms.Button
$refreshButton.Text = "상태 새로고침"
$refreshButton.Location = New-Object System.Drawing.Point(32, 432)
$refreshButton.Size = New-Object System.Drawing.Size(150, 40)
$form.Controls.Add($refreshButton)

$serviceButton = New-Object System.Windows.Forms.Button
$serviceButton.Text = "로컬 서비스 재시작"
$serviceButton.Location = New-Object System.Drawing.Point(192, 432)
$serviceButton.Size = New-Object System.Drawing.Size(160, 40)
$form.Controls.Add($serviceButton)

$applyButton = New-Object System.Windows.Forms.Button
$applyButton.Text = "Hermes 연결 재적용"
$applyButton.Location = New-Object System.Drawing.Point(362, 432)
$applyButton.Size = New-Object System.Drawing.Size(170, 40)
$form.Controls.Add($applyButton)

$testButton = New-Object System.Windows.Forms.Button
$testButton.Text = "생성 연결 테스트"
$testButton.Location = New-Object System.Drawing.Point(542, 432)
$testButton.Size = New-Object System.Drawing.Size(172, 40)
$form.Controls.Add($testButton)

$launchButton = New-Object System.Windows.Forms.Button
$launchButton.Text = "Hermes 에이전트 실행"
$launchButton.Location = New-Object System.Drawing.Point(32, 492)
$launchButton.Size = New-Object System.Drawing.Size(330, 48)
$launchButton.BackColor = [System.Drawing.Color]::FromArgb(25, 135, 84)
$launchButton.ForeColor = [System.Drawing.Color]::White
$launchButton.FlatStyle = "Flat"
$form.Controls.Add($launchButton)

$folderButton = New-Object System.Windows.Forms.Button
$folderButton.Text = "설정 폴더 열기"
$folderButton.Location = New-Object System.Drawing.Point(382, 492)
$folderButton.Size = New-Object System.Drawing.Size(160, 48)
$form.Controls.Add($folderButton)

$closeButton = New-Object System.Windows.Forms.Button
$closeButton.Text = "닫기"
$closeButton.Location = New-Object System.Drawing.Point(554, 492)
$closeButton.Size = New-Object System.Drawing.Size(160, 48)
$form.Controls.Add($closeButton)

function Set-CurrentProfile {
    $config = Read-RouterConfig
    $selectedName = $profileMap.Keys | Where-Object { $profileMap[$_] -eq $config.mode } | Select-Object -First 1
    if (-not $selectedName) {
        $selectedName = "자동 선택 (권장)"
    }
    $profileCombo.SelectedItem = $selectedName
}

function Refresh-Status {
    $lines = New-Object System.Collections.Generic.List[string]
    try {
        $version = Invoke-RestMethod -Uri "http://127.0.0.1:11434/api/version" -TimeoutSec 2
        $lines.Add("Ollama       : 정상 (v$($version.version))")
    }
    catch {
        $lines.Add("Ollama       : 중지됨")
    }
    try {
        $health = Invoke-RestMethod -Uri "http://127.0.0.1:11435/health" -TimeoutSec 3
        $lines.Add("자동 라우터  : 정상")
        $lines.Add("현재 모드    : $($health.mode)")
        $lines.Add("Hermes 주소  : http://127.0.0.1:11435/v1")
        $lines.Add("")
        $lines.Add("[설치 모델]")
        foreach ($property in $health.models.PSObject.Properties) {
            $mark = if ($property.Value) { "[설치됨]" } else { "[미설치]" }
            $lines.Add(("{0,-18} {1}" -f $property.Name, $mark))
        }
    }
    catch {
        $lines.Add("자동 라우터  : 중지됨")
        $lines.Add("로컬 서비스 재시작 버튼을 눌러 주세요.")
    }
    $lines.Add("")
    $lines.Add("보안          : loopback 전용 / 프롬프트 원문 로그 없음")
    $statusBox.Lines = $lines.ToArray()
}

$saveButton.Add_Click({
    try {
        $config = Read-RouterConfig
        $config.mode = $profileMap[[string]$profileCombo.SelectedItem]
        Save-RouterConfig -Config $config
        [System.Windows.Forms.MessageBox]::Show(
            "선택이 저장됐습니다. 다음 요청부터 적용됩니다.",
            "Hermes 로컬 LLM",
            "OK",
            "Information"
        ) | Out-Null
        Refresh-Status
    }
    catch {
        [System.Windows.Forms.MessageBox]::Show($_.Exception.Message, "저장 실패", "OK", "Error") | Out-Null
    }
})

$refreshButton.Add_Click({ Refresh-Status })

$serviceButton.Add_Click({
    try {
        & $restartServices -Quiet
        Refresh-Status
    }
    catch {
        [System.Windows.Forms.MessageBox]::Show($_.Exception.Message, "시작 실패", "OK", "Error") | Out-Null
    }
})

$applyButton.Add_Click({
    try {
        & $applyConfig
        [System.Windows.Forms.MessageBox]::Show(
            "Hermes 로컬 연결 설정을 다시 적용했습니다.",
            "설정 완료",
            "OK",
            "Information"
        ) | Out-Null
    }
    catch {
        [System.Windows.Forms.MessageBox]::Show($_.Exception.Message, "적용 실패", "OK", "Error") | Out-Null
    }
})

$testButton.Add_Click({
    try {
        & $startServices -Quiet
        $bodyObject = @{
            model = "hermes-fast"
            messages = @(@{ role = "user"; content = "정확히 LOCAL_OK만 답하세요." })
            stream = $false
            max_tokens = 128
            temperature = 0
        }
        $bodyJson = $bodyObject | ConvertTo-Json -Depth 8
        $response = Invoke-RestMethod `
            -Method Post `
            -Uri "http://127.0.0.1:11435/v1/chat/completions" `
            -ContentType "application/json; charset=utf-8" `
            -Body ([System.Text.Encoding]::UTF8.GetBytes($bodyJson)) `
            -TimeoutSec 600
        $answer = [string]$response.choices[0].message.content
        if ($answer.Trim() -ne "LOCAL_OK") {
            throw "예상 응답 LOCAL_OK와 다릅니다: $answer"
        }
        [System.Windows.Forms.MessageBox]::Show(
            "로컬 생성 연결이 정상입니다.`r`n응답: $answer",
            "테스트 성공",
            "OK",
            "Information"
        ) | Out-Null
        Refresh-Status
    }
    catch {
        [System.Windows.Forms.MessageBox]::Show($_.Exception.Message, "테스트 실패", "OK", "Error") | Out-Null
    }
})

$launchButton.Add_Click({
    Start-Process -FilePath "powershell.exe" -ArgumentList @(
        "-NoProfile",
        "-ExecutionPolicy", "Bypass",
        "-NoExit",
        "-File", $startHermes
    )
})

$folderButton.Add_Click({ Start-Process -FilePath "explorer.exe" -ArgumentList $toolRoot })
$closeButton.Add_Click({ $form.Close() })

Set-CurrentProfile
Refresh-Status
[void]$form.ShowDialog()
