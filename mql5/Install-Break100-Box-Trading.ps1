#Requires -Version 5.1
<#
.SYNOPSIS
  Pull the repo, copy Break100 Box Trading (EA), RES-SUP OCO (Script) and their
  Include\Break100 files into MT5 data folders, and compile both with the
  MetaEditor CLI. You still attach the EA and drag the script onto the chart —
  MT5 gives no way to script that part.

  The EA (Break100 Box Trading.mq5) sends no broker orders in any mode as of
  v2.33 -- it only detects, draws, alerts and logs.
  The SCRIPT (RES-SUP OCO.mq5) is the order path, and as of v1.01 it WILL
  trade a real account by default (InpAllowLiveTrading defaults to true, no
  account allowlist -- owner-authorised, DECISION_LOG D-007). Demo-test it
  before you ever drag it onto a live chart. See its own header comment.
.PARAMETER TerminalDataPath
  Install into this terminal data folder only (the one containing MQL5\).
  Omit to install into every terminal found, which is the historical behaviour.
.PARAMETER Pull
  Run 'git pull' in the repo before copying, so you're always installing what's
  actually on the branch. No-ops with a warning if this isn't a git checkout
  (e.g. an unzipped release with no .git folder).
.PARAMETER SyncHF
  After a clean compile, run tools\break100_hf_sync.py (needs
  Common\Files\BREAK100_hf.txt with a token= and dataset= already in place --
  this script does not create or edit that file). No-ops with a warning if
  Python or the sync script can't be found.
.EXAMPLE
  .\Install-Break100-Box-Trading.ps1 -Pull -SyncHF
.EXAMPLE
  .\Install-Break100-Box-Trading.ps1 -TerminalDataPath "$env:APPDATA\MetaQuotes\Terminal\EF93522F4797E00CA50A6ECBF84A0568"
#>
param(
  [string]$TerminalDataPath = "",
  [switch]$Pull,
  [switch]$SyncHF
)
$ErrorActionPreference = "Stop"
$Root = Split-Path -Parent $MyInvocation.MyCommand.Path
# Two layouts are supported: the repo (mql5\Experts\...) and an unzipped
# distribution folder that nests everything under MQL5\.
$Src = if (Test-Path (Join-Path $Root "MQL5\Experts")) { Join-Path $Root "MQL5" } else { $Root }
if (-not (Test-Path (Join-Path $Src "Experts\Break100 Box Trading.mq5"))) {
  throw "Run this from the repo's mql5 folder. Missing Experts\Break100 Box Trading.mq5"
}
# Only meaningful in the repo layout ($Src -eq $Root): the folder one level up
# from mql5\ is the repo root, and it either has a .git folder or it doesn't.
$RepoRoot = if ($Src -eq $Root) { Split-Path -Parent $Root } else { $null }

function Invoke-Pull {
  if (-not $RepoRoot -or -not (Test-Path (Join-Path $RepoRoot ".git"))) {
    Write-Warning "-Pull: not a git checkout (or running from an unzipped distribution) -- skipped."
    return
  }
  Write-Host "git pull in $RepoRoot"
  git -C $RepoRoot pull
  if ($LASTEXITCODE -ne 0) {
    throw "git pull failed (exit $LASTEXITCODE). Resolve it by hand, then re-run without -Pull."
  }
}

function Find-MetaEditor {
  $cands = @()
  $cands += Get-ChildItem "C:\Program Files" -Filter "metaeditor64.exe" -Recurse -ErrorAction SilentlyContinue
  $cands += Get-ChildItem "C:\Program Files (x86)" -Filter "metaeditor64.exe" -Recurse -ErrorAction SilentlyContinue
  $termRoot = Join-Path $env:APPDATA "MetaQuotes\Terminal"
  if (Test-Path $termRoot) {
    Get-ChildItem $termRoot -Directory | ForEach-Object {
      $origin = Join-Path $_.FullName "origin.txt"
      if (Test-Path $origin) {
        $exeDir = (Get-Content $origin -TotalCount 1).Trim()
        $me = Join-Path $exeDir "metaeditor64.exe"
        if (Test-Path $me) { $cands += Get-Item $me }
      }
    }
  }
  $cands | Select-Object -ExpandProperty FullName -Unique | Select-Object -First 1
}

function Install-Into([string]$mql5) {
  New-Item -ItemType Directory -Force -Path (Join-Path $mql5 "Experts") | Out-Null
  New-Item -ItemType Directory -Force -Path (Join-Path $mql5 "Indicators") | Out-Null
  New-Item -ItemType Directory -Force -Path (Join-Path $mql5 "Include\Break100") | Out-Null
  New-Item -ItemType Directory -Force -Path (Join-Path $mql5 "Scripts") | Out-Null
  Copy-Item (Join-Path $Src "Experts\Break100 Box Trading.mq5") (Join-Path $mql5 "Experts\") -Force
  Copy-Item (Join-Path $Src "Scripts\Break100 Box Trading History Export.mq5") (Join-Path $mql5 "Scripts\") -Force
  Copy-Item (Join-Path $Src "Scripts\RES-SUP OCO.mq5") (Join-Path $mql5 "Scripts\") -Force
  Copy-Item (Join-Path $Src "Indicators\BREAK100_Channel.mq5") (Join-Path $mql5 "Indicators\") -Force
  Copy-Item (Join-Path $Src "Include\Break100\*") (Join-Path $mql5 "Include\Break100\") -Force
  Write-Host "  copied -> $mql5"
}

function Compile-One([string]$editor, [string]$file, [string]$include) {
  $log = [System.IO.Path]::ChangeExtension($file, ".log")
  if (Test-Path $log) { Remove-Item $log -Force }
  Write-Host "  compile $(Split-Path $file -Leaf)"
  # Paths must be quoted *inside* each switch. Without this, MetaEditor silently
  # does nothing for any path containing a space and writes no log at all.
  Start-Process -FilePath $editor -Wait -WindowStyle Hidden -ArgumentList @(
    "/compile:`"$file`"", "/inc:`"$include`"", "/log:`"$log`""
  ) | Out-Null
  if (-not (Test-Path $log)) {
    Write-Warning "No log for $file - MetaEditor may have failed to start."
    return $false
  }
  $text = Get-Content $log -Raw -ErrorAction SilentlyContinue
  # MetaEditor writes UTF-16 logs
  if ([string]::IsNullOrEmpty($text)) {
    $text = [IO.File]::ReadAllText($log, [Text.Encoding]::Unicode)
  }
  Write-Host $text
  return ($text -match "0 error")
}

function Invoke-HFSync {
  if (-not $RepoRoot) {
    Write-Warning "-SyncHF: not running from the repo layout -- skipped."
    return
  }
  $py = Join-Path $RepoRoot "tools\break100_hf_sync.py"
  if (-not (Test-Path $py)) {
    Write-Warning "-SyncHF: $py not found -- skipped."
    return
  }
  $cmd = Get-Command python -ErrorAction SilentlyContinue
  if (-not $cmd) {
    Write-Warning "-SyncHF: no 'python' on PATH -- skipped. Run it yourself: python `"$py`""
    return
  }
  $cfg = Join-Path $env:APPDATA "MetaQuotes\Terminal\Common\Files\BREAK100_hf.txt"
  if (-not (Test-Path $cfg)) {
    Write-Warning "-SyncHF: $cfg missing (no token=/dataset=) -- skipped. Copy it from mql5\BREAK100_hf.txt.example first."
    return
  }
  Write-Host ""
  Write-Host "HF sync: python `"$py`""
  python $py
  if ($LASTEXITCODE -ne 0) {
    Write-Warning "HF sync exited $LASTEXITCODE -- check the output above."
  }
}

Write-Host "Break100 Box Trading  install"
Write-Host "EA sends no broker orders in any mode (v2.33: detect/draw/alert/log only)."
Write-Host "RES-SUP OCO.mq5 (Script) IS the order path and trades LIVE accounts by"
Write-Host "default as of v1.01 -- demo-test it before dragging it onto a live chart."
Write-Host ""

if ($Pull) { Invoke-Pull }

if ($TerminalDataPath) {
  $one = Join-Path $TerminalDataPath "MQL5"
  if (-not (Test-Path $one)) { throw "No MQL5 folder under $TerminalDataPath" }
  $targets = @($one)
} else {
  $termRoot = Join-Path $env:APPDATA "MetaQuotes\Terminal"
  if (-not (Test-Path $termRoot)) {
    throw "No MetaQuotes Terminal folder. Install desktop MT5 first (not the iPhone app)."
  }
  $targets = Get-ChildItem $termRoot -Directory | Where-Object {
    Test-Path (Join-Path $_.FullName "MQL5")
  } | ForEach-Object { Join-Path $_.FullName "MQL5" }
  if (-not $targets) { throw "No MQL5 data folder under $termRoot" }
}

Write-Host "Installing into $($targets.Count) terminal(s):"
$targets | ForEach-Object { Install-Into $_ }

$editor = Find-MetaEditor
if (-not $editor) {
  Write-Warning "metaeditor64.exe not found. Files are copied. Open MT5, press F4, F7 on each file."
  Write-Host "Then: attach the EA, drag the script only after a demo test. AutoTrading OFF until you mean it."
  exit 2
}
Write-Host "MetaEditor: $editor"

$ok = $true
foreach ($mql5 in $targets) {
  $ind = Join-Path $mql5 "Indicators\BREAK100_Channel.mq5"
  $ea  = Join-Path $mql5 "Experts\Break100 Box Trading.mq5"
  $exp = Join-Path $mql5 "Scripts\Break100 Box Trading History Export.mq5"
  $oco = Join-Path $mql5 "Scripts\RES-SUP OCO.mq5"
  if (-not (Compile-One $editor $ind $mql5)) { $ok = $false }
  if (-not (Compile-One $editor $ea  $mql5)) { $ok = $false }
  if (-not (Compile-One $editor $exp $mql5)) { $ok = $false }
  if (-not (Compile-One $editor $oco $mql5)) { $ok = $false }
}

Write-Host ""
if ($ok) {
  Write-Host "Compile OK (0 errors on every file). In MT5 Navigator, right-click Experts -> Refresh"
  Write-Host "and right-click Scripts -> Refresh."
  Write-Host ""
  Write-Host "Attach 'Break100 Box Trading' (Experts) to a BREAK100 M30 chart -- detection/HUD/"
  Write-Host "Telegram/Shadow ledger only, sends no orders."
  Write-Host ""
  Write-Host "*** 'RES-SUP OCO' (Scripts) places the actual orders and trades LIVE money by"
  Write-Host "*** default. Drag it onto a DEMO account chart first and read its own header"
  Write-Host "*** comment before you ever run it live."
  Write-Host ""
  Write-Host "History export: Navigator -> Scripts -> 'Break100 Box Trading History Export'."
  if ($SyncHF) { Invoke-HFSync }
  exit 0
}
Write-Host "Compile reported errors. Open the .log next to the .mq5, or F4 and compile there."
exit 1
