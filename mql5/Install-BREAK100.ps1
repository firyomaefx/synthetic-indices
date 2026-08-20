#Requires -Version 5.1
<#
.SYNOPSIS
  Copy BREAK100 into every MT5 data folder and compile with MetaEditor CLI.
  You still attach the EA on the chart. This does not send orders.
#>
$ErrorActionPreference = "Stop"
$Root = Split-Path -Parent $MyInvocation.MyCommand.Path
$Src  = Join-Path $Root "MQL5"
if (-not (Test-Path (Join-Path $Src "Experts\BREAK100.mq5"))) {
  throw "Run this from the unzipped BREAK100-MT5 folder. Missing MQL5\Experts\BREAK100.mq5"
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
  Copy-Item (Join-Path $Src "Experts\BREAK100.mq5") (Join-Path $mql5 "Experts\") -Force
  Copy-Item (Join-Path $Src "Indicators\BREAK100_Channel.mq5") (Join-Path $mql5 "Indicators\") -Force
  Copy-Item (Join-Path $Src "Include\Break100\*") (Join-Path $mql5 "Include\Break100\") -Force
  Write-Host "  copied -> $mql5"
}

function Compile-One([string]$editor, [string]$file, [string]$include) {
  $log = [System.IO.Path]::ChangeExtension($file, ".log")
  if (Test-Path $log) { Remove-Item $log -Force }
  Write-Host "  compile $(Split-Path $file -Leaf)"
  & $editor "/compile:$file" "/include:$include" "/log:$log" | Out-Null
  if (-not (Test-Path $log)) {
    Write-Warning "No log for $file — MetaEditor may have failed to start."
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

Write-Host "BREAK100 v1.42  laptop install"
Write-Host "Observe/Shadow only. No orders. Real account OK for data."
Write-Host ""

$termRoot = Join-Path $env:APPDATA "MetaQuotes\Terminal"
if (-not (Test-Path $termRoot)) {
  throw "No MetaQuotes Terminal folder. Install desktop MT5 first (not the iPhone app)."
}

$targets = Get-ChildItem $termRoot -Directory | Where-Object {
  Test-Path (Join-Path $_.FullName "MQL5")
} | ForEach-Object { Join-Path $_.FullName "MQL5" }

if (-not $targets) { throw "No MQL5 data folder under $termRoot" }

Write-Host "Installing into $($targets.Count) terminal(s):"
$targets | ForEach-Object { Install-Into $_ }

$editor = Find-MetaEditor
if (-not $editor) {
  Write-Warning "metaeditor64.exe not found. Files are copied. Open MT5, press F4, F7 on the indicator then the EA."
  Write-Host "Then attach BREAK100 to Boom 100 M1. AutoTrading OFF."
  exit 2
}
Write-Host "MetaEditor: $editor"

$ok = $true
foreach ($mql5 in $targets) {
  $ind = Join-Path $mql5 "Indicators\BREAK100_Channel.mq5"
  $ea  = Join-Path $mql5 "Experts\BREAK100.mq5"
  if (-not (Compile-One $editor $ind $mql5)) { $ok = $false }
  if (-not (Compile-One $editor $ea  $mql5)) { $ok = $false }
}

Write-Host ""
if ($ok) {
  Write-Host "Compile OK. In MT5 Navigator, right-click Experts -> Refresh."
  Write-Host "Attach BREAK100 to Boom 100 Index M1. AutoTrading OFF."
  Write-Host "issued stays NO_TRADE. Real account is fine for ticks."
  exit 0
}
Write-Host "Compile reported errors. Open the .log next to the .mq5, or F4 and compile there."
exit 1
