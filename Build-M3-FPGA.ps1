#requires -Version 5.1
<#
.SYNOPSIS
  Clean/reproducible M3 Enhanced Tang Nano 20K build with automatic
  SSI263 and Apple SynthLAB piano ROM preparation.
.DESCRIPTION
  The SSI263 original/derived ROMs are committed. Exact Apple SynthLAB
  PCM is verified/locally extracted from pinned synthLAB.po at build time.
  No zero-filled or substitute instrument ROM is ever silently used.
.EXAMPLE
  .\Build-M3-FPGA.ps1 Prepare
  .\Build-M3-FPGA.ps1 Build -GowinCli 'C:\Gowin\Gowin_V1.9.10.03\IDE\bin\gw_sh.exe'
  .\Build-M3-FPGA.ps1 Prepare -Offline -SynthLABDisk 'D:\Archive\synthLAB.po'
#>
[CmdletBinding()]
param(
    [Parameter(Position=0)]
    [ValidateSet('Prepare','Check','Synthesize','Build')]
    [string] $Action='Prepare',
    [string] $GowinCli='',
    [string] $SynthLABDisk='',
    [switch] $Offline
)
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
$root=$PSScriptRoot
# Never produce an experimental FPGA bitstream from the golden M2 branch.
$branch=(& git -C $root branch --show-current | Out-String).Trim()
if($LASTEXITCODE -ne 0 -or $branch -ne 'petar/m3-sd-sector-burst-20261123') {
    throw "M3 FPGA must be built from petar/m3-sd-sector-burst-20261123, not '$branch'."
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

if(-not $GowinCli) {
    foreach($name in @('gw_sh.exe','gw_sh')) {
        $candidate=Get-Command $name -ErrorAction SilentlyContinue
        if($candidate){$GowinCli=$candidate.Source;break}
    }
}
if(-not $GowinCli -or -not (Test-Path -LiteralPath $GowinCli -PathType Leaf)) {
    throw "Gowin gw_sh not found; supply -GowinCli with its full path."
}
$run=if($Action -eq 'Synthesize'){'run syn'}else{'run all'}
$cmds="open_project $project`n$run`nexit`n"
Write-Host "Gowin ${Action}: $GowinCli" -ForegroundColor Cyan
Push-Location $board
try {
    $cmds | & $GowinCli
    if($LASTEXITCODE -ne 0){throw "Gowin returned exit code $LASTEXITCODE"}
} finally {
    Pop-Location
}
if($Action -eq 'Build') {
    $bitstream=Join-Path $board 'impl\pnr\a2n20v2_enhanced.fs'
    if(-not (Test-Path -LiteralPath $bitstream -PathType Leaf)) {
        throw "Gowin reported success, but no FPGA .fs was produced: $bitstream"
    }
    $report=Join-Path $board 'impl\pnr\a2n20v2_enhanced_tr_content.html'
    if(-not (Test-Path -LiteralPath $report -PathType Leaf)) {
        throw "Missing Gowin timing report. Inspect synthesis and place-and-route."
    }
    $text=Get-Content -LiteralPath $report -Raw
    if($text -notmatch 'Setup Violated Endpoints' -or
       $text -notmatch 'Hold Violated Endpoints') {
        throw "Could not verify Gowin timing report format. Inspect manually."
    }
    Write-Host "FPGA bitstream produced: $bitstream" -ForegroundColor Green
    Write-Warning "Read timing violation counts in $report before programming hardware."
    Write-Warning 'Program volatile SRAM first. Leave J2R11 golden FPGA flash intact.'
}
