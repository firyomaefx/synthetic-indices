#Requires -Version 5.1
# Register a 15-minute task so Common Files and Hugging Face stay in sync.
# Does not send broker orders.
$ErrorActionPreference = "Stop"
$Here = Split-Path -Parent $MyInvocation.MyCommand.Path
$Py = Join-Path $Here "break100_hf_sync.py"
if (-not (Test-Path $Py)) { throw "Missing $Py" }

$Common = Join-Path $env:APPDATA "MetaQuotes\Terminal\Common\Files"
New-Item -ItemType Directory -Force -Path $Common | Out-Null
$ex = Join-Path $Here "..\mql5\BREAK100_hf.txt.example"
if (-not (Test-Path $ex)) { $ex = Join-Path $Here "BREAK100_hf.txt.example" }
$cfg = Join-Path $Common "BREAK100_hf.txt"
if (-not (Test-Path $cfg) -and (Test-Path $ex)) {
  Copy-Item $ex $cfg
  Write-Host "Created $cfg  — edit token= and dataset="
}

python -m pip install -q -r (Join-Path $Here "requirements-hf.txt")

$tr = "python `"$Py`""
schtasks /Create /TN "BREAK100-HF-Sync" /TR $tr /SC MINUTE /MO 15 /F | Out-Null
Write-Host "Scheduled BREAK100-HF-Sync every 15 minutes."
Write-Host "Edit $cfg then run:  python `"$Py`""
Write-Host "Both sides stay current. Not a profit claim."
