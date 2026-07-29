# Contributing

Small, testable changes are welcome.

1. Do not commit model weights, logs, `.env`, Hermes `config.yaml`, private
   conversations, personal paths, or generated runtime state.
2. Keep all network listeners loopback-only.
3. Add or update a contract test for routing behavior changes.
4. Preserve UTF-8 BOM for PowerShell files with non-ASCII text.
5. Run:

```powershell
$env:PYTHONDONTWRITEBYTECODE = "1"
python -m unittest discover -s tests -p "test_*.py" -v
.\scripts\Test-PowerShellSyntax.ps1
python .\scripts\check_public_release.py
```

Model references must include an official source, current license, quantization
source where applicable, and an explanation of whether the model belongs in a
default or explicitly accepted preset.

Use GitHub private vulnerability reporting for security issues; do not include
real secrets or private data in an issue.
