#Requires -Version 5.1
<#
.SYNOPSIS
  Read-only doctor. Reports what is ACTUALLY deployed in every MT5 terminal on
  this machine, and what the repo checkout holds, so "my update did not take
  effect" can be answered from evidence instead of guesswork.

  Changes nothing: no copy, no compile, no git write. Safe to run any time.

  It answers the three things that look identical from inside MT5:
    1. files were never copied here          -> source .mq5 missing
    2. copied into a terminal MT5 is not using -> files present in the wrong folder
    3. copied but never compiled             -> .ex5 missing, or older than .mq5

  MT5 loads the compiled .ex5, never the .mq5. A stale .ex5 keeps the old EA
  running no matter how many times you refresh Navigator.

  IMPORTANT: this scans %APPDATA%\MetaQuotes\Terminal\*. A portable or Microsoft
  Store install can keep its data elsewhere. The authority on which folder your
  running terminal actually uses is MT5's own  File -> Open Data Folder.
  Compare that path against the ones listed below.
.PARAMETER RepoPath
  Repo checkout to inspect. Defaults to the folder above this script, which is
  correct when running it from the repo's mql5\ folder.
.EXAMPLE
  .\Check-Break100-Install.ps1
#>
param(
  [string]$RepoPath = ""
)
$ErrorActionPreference = "Continue"

# Kept textually identical to the copy in Install-Break100-Box-Trading.ps1 so the
# two can never disagree about what version a file claims to be.
function Get-MqlVersion([string]$file) {
  if (-not (Test-Path $file)) { return $null }
  $text = Get-Content $file -Raw -ErrorAction SilentlyContinue
  if ([string]::IsNullOrEmpty($text)) {
    $text = [IO.File]::ReadAllText($file, [Text.Encoding]::Unicode)
  }
  $m = [regex]::Match($text, '#property\s+version\s+"([^"]+)"')
  if ($m.Success) { return $m.Groups[1].Value }
  return $null
}

# One .mq5 plus its compiled sibling, as a single line of evidence.
function Report-Pair([string]$label, [string]$mq5) {
  $ex5 = [System.IO.Path]::ChangeExtension($mq5, ".ex5")
  if (-not (Test-Path $mq5)) {
    Write-Host "    $label  SOURCE MISSING  ($mq5)"
    if (Test-Path $ex5) {
      Write-Host "      but a compiled .ex5 IS here from an older install:"
      Write-Host "      $((Get-Item $ex5).LastWriteTime)  $ex5"
    }
    return "missing"
  }
  $v = Get-MqlVersion $mq5
  $srcT = (Get-Item $mq5).LastWriteTime
  Write-Host "    $label  source v$v   (written $srcT)"
  if (-not (Test-Path $ex5)) {
    Write-Host "      NO .ex5 -- never compiled. MT5 cannot load this."
    return "uncompiled"
  }
  $binT = (Get-Item $ex5).LastWriteTime
  if ($binT -lt $srcT) {
    Write-Host "      .ex5 is OLDER than the source ($binT) -- STALE BUILD."
    Write-Host "      MT5 keeps running the previous version until you recompile."
    return "stale"
  }
  Write-Host "      .ex5 built $binT -- looks current."
  return "ok"
}

Write-Host ""
Write-Host "BREAK100 install doctor  (read-only, changes nothing)"
Write-Host "====================================================="
Write-Host "Expecting: EA 2.33 and RES-SUP OCO 1.01"
Write-Host ""

# ---------- repo checkout ----------
$Here = Split-Path -Parent $MyInvocation.MyCommand.Path
if (-not $RepoPath) { $RepoPath = Split-Path -Parent $Here }
Write-Host "REPO CHECKOUT: $RepoPath"
if (Test-Path (Join-Path $RepoPath ".git")) {
  $branch = (git -C $RepoPath rev-parse --abbrev-ref HEAD 2>$null)
  $commit = (git -C $RepoPath log --oneline -1 2>$null)
  Write-Host "  branch: $branch"
  Write-Host "  commit: $commit"
  $dirty = (git -C $RepoPath status --short 2>$null)
  if ($dirty) {
    Write-Host "  uncommitted changes present:"
    $dirty | ForEach-Object { Write-Host "    $_" }
  }
  if ($branch -and $branch -ne "master") {
    Write-Host "  NOTE: everything ships on master. On another branch a pull may"
    Write-Host "        fetch an older tree -- this is the usual cause."
  }
} else {
  Write-Host "  not a git checkout (no .git). If this is an unzipped download,"
  Write-Host "  that is fine -- just make sure it is a recent ZIP of master."
}
$repoEa  = Join-Path $RepoPath "mql5\Experts\Break100 Box Trading.mq5"
$repoOco = Join-Path $RepoPath "mql5\Scripts\RES-SUP OCO.mq5"
Write-Host "  EA source in repo:     $(if (Test-Path $repoEa)  { 'v' + (Get-MqlVersion $repoEa) }  else { 'MISSING' })"
Write-Host "  Script source in repo: $(if (Test-Path $repoOco) { 'v' + (Get-MqlVersion $repoOco) } else { 'MISSING  <-- this checkout predates v2.33' })"
Write-Host ""

# ---------- terminals ----------
$termRoot = Join-Path $env:APPDATA "MetaQuotes\Terminal"
Write-Host "MT5 TERMINALS UNDER: $termRoot"
if (-not (Test-Path $termRoot)) {
  Write-Host "  NONE FOUND. Desktop MT5 does not appear to be installed for this"
  Write-Host "  Windows user. If MT5 runs as a different user or is portable, use"
  Write-Host "  File -> Open Data Folder inside MT5 and pass that path as -RepoPath's"
  Write-Host "  sibling: Install-Break100-Box-Trading.ps1 -TerminalDataPath <path>"
  Write-Host ""
  exit 0
}

$dirs = Get-ChildItem $termRoot -Directory | Where-Object {
  Test-Path (Join-Path $_.FullName "MQL5")
}
if (-not $dirs) {
  Write-Host "  no folder here contains an MQL5\ subfolder."
  Write-Host ""
  exit 0
}

$n = 0
foreach ($d in $dirs) {
  $n++
  $mql5 = Join-Path $d.FullName "MQL5"
  Write-Host "  [$n] $($d.FullName)"
  $origin = Join-Path $d.FullName "origin.txt"
  if (Test-Path $origin) {
    $exeDir = (Get-Content $origin -TotalCount 1).Trim()
    $hasTerm = Test-Path (Join-Path $exeDir "terminal64.exe")
    $hasEdit = Test-Path (Join-Path $exeDir "metaeditor64.exe")
    Write-Host "      installed at: $exeDir"
    Write-Host "      terminal64.exe: $hasTerm   metaeditor64.exe: $hasEdit"
  } else {
    Write-Host "      (no origin.txt -- cannot map to an install dir)"
  }
  $inc = Join-Path $mql5 "Include\Break100"
  $incN = 0
  if (Test-Path $inc) { $incN = (Get-ChildItem $inc -Filter *.mqh -ErrorAction SilentlyContinue).Count }
  Write-Host "      Include\Break100: $incN .mqh files"

  $sEa  = Report-Pair "EA     " (Join-Path $mql5 "Experts\Break100 Box Trading.mq5")
  $sOco = Report-Pair "Script " (Join-Path $mql5 "Scripts\RES-SUP OCO.mq5")

  Write-Host "      VERDICT:"
  if ($sOco -eq "missing") {
    Write-Host "        RES-SUP OCO.mq5 was never copied into this terminal."
    Write-Host "        This is why Navigator shows no such script."
  }
  if ($sEa -eq "stale" -or $sOco -eq "stale" -or $sEa -eq "uncompiled" -or $sOco -eq "uncompiled") {
    Write-Host "        Something here is not compiled. MT5 will keep loading the"
    Write-Host "        old build until MetaEditor writes a fresh .ex5."
  }
  if ($sEa -eq "ok" -and $sOco -eq "ok") {
    Write-Host "        Looks correctly deployed. If MT5 still shows an old version,"
    Write-Host "        this is probably not the terminal you are running --"
    Write-Host "        check File -> Open Data Folder."
  }
  Write-Host ""
}

Write-Host "NEXT"
Write-Host "  1. In MT5: File -> Open Data Folder. Confirm that path is one of the"
Write-Host "     numbered folders above. If it is not, that is the whole problem."
Write-Host "  2. Deploy into exactly that folder:"
Write-Host "       .\Install-Break100-Box-Trading.ps1 -TerminalDataPath `"<that path>`""
Write-Host "  3. Then Navigator -> right-click Experts -> Refresh, and Scripts -> Refresh."
Write-Host ""
