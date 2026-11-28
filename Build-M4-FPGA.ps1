#requires -Version 5.1
<#
.SYNOPSIS
  Clean/reproducible M4 Enhanced Tang Nano 20K build with automatic
  SSI263 and Apple SynthLAB piano ROM preparation.
.DESCRIPTION
  The SSI263 original/derived ROMs are committed. Exact Apple SynthLAB
  PCM is verified/locally extracted from pinned synthLAB.po at build time.
  No zero-filled or substitute instrument ROM is ever silently used.
.EXAMPLE
  .\Build-M4-FPGA.ps1 Prepare
  .\Build-M4-FPGA.ps1 Build -GowinCli 'C:\Gowin\Gowin_V1.9.10.03\IDE\bin\gw_sh.exe'
  .\Build-M4-FPGA.ps1 Prepare -Offline -SynthLABDisk 'D:\Archive\synthLAB.po'
#>
[CmdletBinding()]
param(
    [Parameter(Position=0)]
    [ValidateSet('Prepare','Check','Script','Synthesize','Build')]
    [string] $Action='Prepare',
    [string] $GowinCli='',
    [string] $SynthLABDisk='',
    [switch] $Offline
)
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
$root=$PSScriptRoot
# M3 production and its explicit isolated audio experiment may build FPGA.
# All other branches fail closed. This exception exists ONLY on the
# experimental branch; the production M3 helper is not modified.
$branch=(& git -C $root branch --show-current | Out-String).Trim()
$allowedFpgaBranches=@('petar/m4-upstream-enhanced-integration-20261125')
if($LASTEXITCODE -ne 0 -or $branch -notin $allowedFpgaBranches) {
    throw "M3 FPGA build requires an approved M4 branch; current '$branch'."
}
$board=Join-Path $root 'boards\a2n20v2-Enhanced'
$project='a2n20v2_enhanced.gprj'
$assetTool=Join-Path $root 'tools\prepare_enhanced_assets.py'
if(-not (Test-Path -LiteralPath $assetTool -PathType Leaf)) {
    throw "Missing Enhanced FPGA asset preparation script: $assetTool"
}
$python=''
$pyArgs=@()
if(Get-Command 'py' -ErrorAction SilentlyContinue) {
    $python='py';$pyArgs=@('-3')
} elseif(Get-Command 'python3' -ErrorAction SilentlyContinue) {
    $python='python3'
} elseif(Get-Command 'python' -ErrorAction SilentlyContinue) {
    $python='python'
} else {
    throw "Python 3 not found. Required to verify the ROMs prior to Gowin."
}
$assetArgs=@($assetTool)
if($Action -eq 'Check'){$assetArgs+='--check'}
if($Offline){$assetArgs+='--offline'}
if($SynthLABDisk){$assetArgs+=@('--disk',$SynthLABDisk)}
Write-Host "Preparing SSI263 and SynthLAB piano for $project" -ForegroundColor Cyan
& $python @pyArgs @assetArgs
if($LASTEXITCODE -ne 0){throw "Required ROM preparation failed. FPGA build NOT started."}
if($Action -eq 'Check') {
    Write-Host "SSI263 and SynthLAB piano ROM integrity verified" -ForegroundColor Green
    return
}
& $python @pyArgs $assetTool --check
if($LASTEXITCODE -ne 0){throw "ROM integrity check failed. FPGA build NOT started."}
if($Action -eq 'Prepare'){
    Write-Host 'All Enhanced audio ROM assets are ready. You may now use Gowin GUI.' -ForegroundColor Green
    return
}

# Gowin 1.9.9 Beta/Education gw_sh DOES NOT implement open_project.
# Generate a Tcl script from the authoritative .gprj to avoid divergence.
$generator=Join-Path $root 'tools\generate_m3_gowin_tcl.py'
$tclScript=Join-Path $board 'impl\m4-headless-build.tcl'
if(-not (Test-Path -LiteralPath $generator -PathType Leaf)) {
    throw "Missing Gowin 1.9.9 Tcl generator: $generator"
}
$flow=if($Action -eq 'Synthesize'){'syn'}else{'all'}
& $python @pyArgs $generator --project (Join-Path $board $project) --out $tclScript --flow $flow
if($LASTEXITCODE -ne 0) {
    throw 'Cannot generate complete headless Tcl: inspect missing project files.'
}
if($Action -eq 'Script') {
    Write-Host "Generated Gowin 1.9.9 compatible Tcl: $tclScript" -ForegroundColor Green
    Write-Host "Run manually from the board directory: gw_sh.exe `"$tclScript`""
    return
}

if(-not $GowinCli) {
    foreach($name in @('gw_sh.exe','gw_sh')) {
        $candidate=Get-Command $name -ErrorAction SilentlyContinue
        if($candidate){$GowinCli=$candidate.Source;break}
    }
}
if(-not $GowinCli -or -not (Test-Path -LiteralPath $GowinCli -PathType Leaf)) {
    throw "Gowin gw_sh not found; supply -GowinCli with its full path."
}

# Never allow a prior M2/M3 GUI artifact to impersonate a new headless build.
# Archive rather than destroy the previous bitstream/timing report.
$pnrDir=Join-Path $board 'impl\pnr'
$bitstream=Join-Path $pnrDir 'a2n20v2_enhanced.fs'
$report=Join-Path $pnrDir 'a2n20v2_enhanced_tr_content.html'
$backupDir=Join-Path $board ('impl\m4-previous-artifacts\'+
                             (Get-Date -Format 'yyyyMMdd-HHmmss-fff'))
$archived=0
foreach($outputFile in @($bitstream,$report)) {
    if(Test-Path -LiteralPath $outputFile -PathType Leaf) {
        if(-not (Test-Path -LiteralPath $backupDir -PathType Container)) {
            $null=New-Item -ItemType Directory -Path $backupDir -Force
        }
        Move-Item -LiteralPath $outputFile -Destination $backupDir -Force
        $archived++
    }
}
if($archived -gt 0) {
    Write-Warning "Archived $archived previous FPGA artifact(s) in $backupDir. They are NOT a new M4 build."
}

$stdoutPath=Join-Path $board 'impl\m4-gowin-stdout.log'
$stderrPath=Join-Path $board 'impl\m4-gowin-stderr.log'
foreach($file in @($stdoutPath,$stderrPath)) {
    if(Test-Path -LiteralPath $file) {
        Remove-Item -LiteralPath $file -Force
    }
}
Write-Host "Gowin $Action (legacy 1.9.9 Tcl): $GowinCli" -ForegroundColor Cyan
Write-Host "Generated source list: $tclScript"
Write-Host "Build stdout: $stdoutPath"

# Give gw_sh a real SCRIPT FILE as its argument, not piped console input.
# Some Gowin versions return process exit code 0 even when Tcl reports an
# invalid command. We require a Tcl completion marker, a clean log AND
# newly produced artifacts. Output remains available for postmortem.
$started=Get-Date
$quotedScript='"'+$tclScript+'"'
$process=Start-Process -FilePath $GowinCli -ArgumentList $quotedScript `
          -WorkingDirectory $board `
          -RedirectStandardOutput $stdoutPath `
          -RedirectStandardError $stderrPath `
          -PassThru -Wait -NoNewWindow
# Get-Content -Raw returns $null for an EXISTING but zero-byte file.
# Gowin often writes stdout only. Never call .Trim() on that null.
# Cast each result explicitly to string before validating the output.
[string]$stdOut=if(Test-Path -LiteralPath $stdoutPath) {
    [string](Get-Content -LiteralPath $stdoutPath -Raw)
} else {''}
[string]$stdErr=if(Test-Path -LiteralPath $stderrPath) {
    [string](Get-Content -LiteralPath $stderrPath -Raw)
} else {''}
Write-Host '--- Gowin stdout (last 100 lines) ---'
$stdOut -split '\r?\n' | Select-Object -Last 100 | ForEach-Object {
    if($_){Write-Host $_}
}
if(-not [string]::IsNullOrWhiteSpace($stdErr)) {
    Write-Warning 'Gowin stderr (last 60 lines):'
    $stdErr -split '\r?\n' | Select-Object -Last 60 | ForEach-Object {
        if($_){Write-Warning $_}
    }
}
$allLog=$stdOut+"`n"+$stdErr
if($process.ExitCode -ne 0) {
    throw "Gowin process exited $($process.ExitCode). Inspect $stdoutPath and $stderrPath; previous bitstream archived."
}
if($allLog -match '(?im)^\s*(?:ERROR\b|FATAL\b|invalid command name\b|M3_GOWIN_TCL_FAILED\b)' -or
   $allLog -match '(?i)No available design files found in this project') {
    throw "Gowin logged a synthesis/project/Tcl error despite exit code 0. Inspect $stdoutPath and $stderrPath; DO NOT program an FPGA."
}
if($allLog -notmatch 'M3_GOWIN_TCL_COMPLETED') {
    throw "Gowin never confirmed completion of run $flow. Inspect $stdoutPath; DO NOT program an FPGA."
}

if($Action -eq 'Build') {
    if(-not (Test-Path -LiteralPath $bitstream -PathType Leaf)) {
        throw "Fresh Gowin run produced no FPGA .fs: $bitstream. DO NOT use an older bitstream."
    }
    if(-not (Test-Path -LiteralPath $report -PathType Leaf)) {
        throw "Fresh Gowin run produced no timing report: $report. DO NOT use an older bitstream."
    }
    foreach($file in @($bitstream,$report)) {
        $item=Get-Item -LiteralPath $file
        if($item.Length -le 1000 -or $item.LastWriteTime -lt $started.AddSeconds(-2)) {
            throw "FPGA output missing, empty or stale: $file. DO NOT program an FPGA."
        }
    }
    $timingText=Get-Content -LiteralPath $report -Raw
    if($timingText -notmatch 'Setup Violated Endpoints' -or
       $timingText -notmatch 'Hold Violated Endpoints') {
        throw "Timing report not verified: $report. DO NOT program until inspected."
    }
    Write-Host "Fresh FPGA bitstream built: $bitstream" -ForegroundColor Green
    Write-Host "SHA256: $((Get-FileHash -LiteralPath $bitstream -Algorithm SHA256).Hash)"
    Write-Host "Timing report: $report" -ForegroundColor Green
    Write-Warning 'Review actual Setup/Hold Violated Endpoints before FPGA SRAM programming.'
    Write-Warning 'PROGRAM VOLATILE FPGA SRAM ONLY: leave the M2 golden FPGA flash untouched.'
} else {
    Write-Host 'Gowin synthesis completed; no bitstream is implied.' -ForegroundColor Green
}
