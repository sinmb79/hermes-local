# Operations guide

[한국어](OPERATIONS.md)

## Prerequisites and downloads

Install Ollama and Hermes Agent from their official Windows documentation.

```powershell
ollama --version
hermes --version
```

No model weights are stored here. Ollama follows the `FROM` paths in
`modelfiles/` only after a user explicitly runs a download command.

```powershell
# Inspect model references and installed state
.\Install-Hermes-Models.ps1 -Preset Core

# Download missing models to this computer and create role aliases
.\Install-Hermes-Models.ps1 -Preset Core -PullMissing

# Recreate existing aliases from their Modelfiles
.\Install-Hermes-Models.ps1 -Preset Core -Recreate
```

Available presets are `Core`, `Developer`, `Korean`, and `Full`. Full requires
an explicit acknowledgement after reviewing the Kanana License.

```powershell
.\Install-Hermes-Models.ps1 `
    -Preset Full `
    -PullMissing `
    -AcceptKananaLicense
```

## Connect Hermes

```powershell
.\Start-Hermes-Services.ps1
.\Apply-Hermes-Config.ps1
```

The apply command backs up `%LOCALAPPDATA%\hermes\config.yaml`, registers the
router at `http://127.0.0.1:11435/v1`, routes the main and auxiliary tasks
through `hermes-auto`, configures `hermes-fast` as a direct Ollama fallback,
runs `hermes config check`, and automatically restores the backup on failure.

The Hermes compatibility settings use a 65,536-token context, compression from
10%, and a 20% target ratio. This does not claim that every base model has a
native 64K context.

## Lifecycle

```powershell
.\Start-Hermes-Services.ps1
.\Restart-Hermes-Services.ps1
.\Stop-Hermes-Services.ps1
.\Stop-Hermes-Services.ps1 -IncludeOllama
```

The scripts verify executable and command-line ownership; they do not terminate
an arbitrary process merely because it owns a port.

## Health and generation checks

```powershell
Invoke-RestMethod http://127.0.0.1:11435/health |
    ConvertTo-Json -Depth 6
ollama list
ollama ps

.\Test-Hermes-Local.ps1 -Preset Core -Generation
.\Test-Hermes-E2E.ps1
```

The terminal-tool test can execute a local command and is therefore opt-in.

```powershell
.\Test-Hermes-E2E.ps1 -IncludeTool
```

## Modes and logs

Open `.\Hermes-Local-Settings.ps1` to choose `auto`, `fast`, `coding`,
`quality`, `korean`, `korean_writing`, or `korean_fast`.

```powershell
Get-Content .\logs\router.log -Tail 50
```

Logs contain routing metadata and timing, never raw prompts or response bodies.
They rotate at 2MiB with three backups.

## Restore the previous Hermes config

```powershell
.\Stop-Hermes-Services.ps1
$hermesRoot = Join-Path $env:LOCALAPPDATA "hermes"
Get-ChildItem $hermesRoot -Filter "config.before-local-*.yaml"

$backup = Join-Path $env:LOCALAPPDATA (
    "hermes\config.before-local-YYYYMMDD-HHMMSS.yaml"
)
$config = Join-Path $env:LOCALAPPDATA "hermes\config.yaml"
Copy-Item -LiteralPath $backup -Destination $config -Force
hermes config check
```

Never paste config contents into a public issue or log.

For non-default installations, set explicit paths in the current PowerShell
session:

```powershell
$env:OLLAMA_EXE = "D:\Apps\Ollama\ollama.exe"
$env:HERMES_EXE = "D:\Apps\Hermes\Scripts\hermes.exe"
$env:PYTHON_EXE = "D:\Apps\Hermes\Scripts\python.exe"
$env:HERMES_CONFIG = "D:\HermesData\config.yaml"
```

Replace these examples with your own paths and never commit the values into the
repository.

## Removal and troubleshooting

Restore the previous config and stop services before deleting the repository.
Remove only aliases you no longer need:

```powershell
ollama rm hermes-fast
ollama rm hermes-coder
ollama rm hermes-quality
ollama rm hermes-korean-writing
ollama rm hermes-korean-fast
ollama rm hermes-korean-agent
```

Check port ownership with `Get-NetTCPConnection`, run
`python .\router.py --config .\router-config.json` in the foreground to inspect
a router startup error, and return to `Core` if memory pressure is high.
