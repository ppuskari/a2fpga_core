#requires -Version 5.1
<#
.SYNOPSIS
  Stage and optionally publish one hardware-validated A2FPGA Enhanced M3
  GitHub Release, bundling the exact local FPGA .fs and BL616 Stage2 .bin.
.DESCRIPTION
  Run from your EXISTING, tested a2fpga-m3-hdmi-lab checkout; this script
  lives on a separate tools branch and MUST NOT require switching/pulling
  that checkout. It NEVER builds, flashes, resets or modifies the binaries.
  Release tag is attached to the exact local source commit; a matching MCU
  build manifest is REQUIRED. The .po image is optional.
.EXAMPLE
  .\Publish-M3-Release.ps1 -SourceRoot 'C:\AppleIIgsDev_02\a2fpga-m3-hdmi-lab'
.EXAMPLE
  .\Publish-M3-Release.ps1 -SourceRoot 'C:\AppleIIgsDev_02\a2fpga-m3-hdmi-lab' -Publish
.EXAMPLE
  .\Publish-M3-Release.ps1 -SourceRoot 'C:\AppleIIgsDev_02\a2fpga-m3-hdmi-lab' -A2MediaPo 'C:\AppleIIgsDev_02\a2media.system\disks\A2MEDIA-ProDOS243.po' -Publish
#>
[CmdletBinding()]
param(
    [string]$SourceRoot = (Get-Location).Path,
    [string]$Tag = 'm3-2026.11.24',
    [string]$A2MediaPo = '',
    [switch]$Publish,
    [switch]$ZipOnly
)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Require-File([string]$path,[long]$min) {
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        throw "Required release input missing: $path"
    }
    $f = Get-Item -LiteralPath $path
    if ($f.Length -lt $min) {
        throw "Release input looks too small ($($f.Length) bytes): $path"
    }
    return $f
}
function Get-Sha([string]$path) {
    return (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash.ToLowerInvariant()
}
function Add-Artifact([string]$src,[string]$name,[string]$role) {
    $dest = Join-Path $stage $name
    Copy-Item -LiteralPath $src -Destination $dest -ErrorAction Stop
    if ((Get-Sha $dest) -ne (Get-Sha $src)) {
        throw "SHA256 changed while staging: $src"
    }
    $artifactRecords.Add([ordered]@{
        filename=$name; role=$role
        bytes=(Get-Item -LiteralPath $dest).Length
        sha256=(Get-Sha $dest)
        source_path=$src
    }) | Out-Null
    return $dest
}

$root = (Resolve-Path -LiteralPath $SourceRoot).Path
$repo = 'ppuskari/a2fpga_core'
if ($Tag -notmatch '^[A-Za-z0-9][A-Za-z0-9._-]{2,63}$') {
    throw 'Tag may contain only letters, numbers, dots, underscores and hyphens.'
}
if (-not (Get-Command git -CommandType Application -ErrorAction SilentlyContinue)) {
    throw 'git.exe must be available on PATH.'
}
$branch = ((& git -C $root branch --show-current) | Out-String).Trim()
if ($LASTEXITCODE -ne 0 -or $branch -ne 'petar/m3-mb-timing-prodos-suite-20261123') {
    throw "Use the actually tested a2fpga-m3-hdmi-lab experiment checkout (found '$branch'). Do NOT switch branches just for packaging."
}
$head = ((& git -C $root rev-parse HEAD) | Out-String).Trim()
if ($LASTEXITCODE -ne 0 -or $head -notmatch '^[0-9a-f]{40}$') {
    throw 'Could not identify exact tested source commit.'
}

# Tracked implementation sources must match HEAD. Gowin emits tracked build
# artifacts and timestamp/process files; those are intentionally excluded.
$changed = @(& git -C $root diff --name-only HEAD -- .)
if ($LASTEXITCODE -ne 0) { throw 'Unable to inspect tracked source changes.' }
$sourceChanged = @($changed | Where-Object {
    $_ -and
    ($_ -notmatch '^boards/a2n20v2-Enhanced/impl/') -and
    ($_ -ne 'boards/a2n20v2-Enhanced/hdl/datetime.svh') -and
    ($_ -notmatch '^boards/a2n20v2-Enhanced/src/a2n20_bl616/firmware_host/build/')
})
if ($sourceChanged.Count -gt 0) {
    throw ("Local tracked source changes are not covered by a release tag. Commit/reconcile these first (without rebuilding your tested hardware): " + ($sourceChanged -join ', '))
}

$fpga = Join-Path $root 'boards\a2n20v2-Enhanced\impl\pnr\a2n20v2_enhanced.fs'
$mcuDir = Join-Path $root 'boards\a2n20v2-Enhanced\src\a2n20_bl616\firmware_host\build\build_out'
$mcu = Join-Path $mcuDir 'a2n20_bl616_host_bl616.bin'
$buildManifest = Join-Path $mcuDir 'm3-stage2-build.json'
$null=Require-File $fpga 100000
$null=Require-File $mcu 65536
$null=Require-File $buildManifest 100

$stage2Info = Get-Content -LiteralPath $buildManifest -Raw | ConvertFrom-Json
$mcuHash = Get-Sha $mcu
if ([string]$stage2Info.sha256 -ne $mcuHash -and
    ([string]$stage2Info.sha256).ToLowerInvariant() -ne $mcuHash) {
    throw 'MCU Stage2 binary SHA256 does not match its verified build manifest.'
}
if ([string]$stage2Info.commit -ne $head -or [string]$stage2Info.branch -ne $branch) {
    throw "MCU binary was built from a different source revision/branch ($($stage2Info.commit), $($stage2Info.branch)). Keep the proven binary; do not publish it under an unrelated source tag."
}
if ([long]$stage2Info.length -ne (Get-Item -LiteralPath $mcu).Length) {
    throw 'MCU binary size differs from its build manifest.'
}
# Avoid accidentally shipping an old, separately tracked MCU Stage2 image.
$firmwareAscii=[Text.Encoding]::ASCII.GetString([IO.File]::ReadAllBytes($mcu))
foreach ($marker in @('MOD JUKE=STARTFILE', 'M3 SD BURST FPGA=', 'HDMI CLIP=')) {
    if (-not $firmwareAscii.Contains($marker)) {
        throw "MCU Stage2 missing required M3 release signature: $marker"
    }
}

if (-not $A2MediaPo) {
    $candidate = Join-Path (Split-Path -Parent $root) 'a2media.system\disks\A2MEDIA-ProDOS243.po'
    if (Test-Path -LiteralPath $candidate -PathType Leaf) { $A2MediaPo=$candidate }
}
$includePo = -not [string]::IsNullOrWhiteSpace($A2MediaPo)
if ($includePo) {
    $null=Require-File $A2MediaPo 143360
    if ((Get-Item -LiteralPath $A2MediaPo).Length -ne 143360) {
        throw 'A2MEDIA ProDOS floppy .po must be a 143,360-byte 5.25-inch ProDOS image.'
    }
} else {
    Write-Warning 'No optional A2MEDIA .po file supplied/found. Package will contain FPGA+MCU only.'
}

# The release output is created separately from build products and never
# destroys an existing staged package.
$outDir=Join-Path $root ('release-out\' + $Tag)
if (Test-Path -LiteralPath $outDir) {
    throw "Output folder already exists: $outDir . Choose a new Tag or inspect/move the previous package; it was NOT overwritten."
}
$stage=Join-Path $outDir 'payload'
$null=New-Item -ItemType Directory -Path $stage -Force
$artifactRecords=New-Object 'System.Collections.Generic.List[object]'
$fpgaName='a2fpga-enhanced-m3-fpga.fs'
$mcuName='a2fpga-enhanced-m3-bl616-stage2.bin'
$fpgaAsset=Add-Artifact $fpga $fpgaName 'Tang Nano 20K Enhanced FPGA configuration'
$mcuAsset=Add-Artifact $mcu $mcuName 'BL616 Stage2 executable: address 0x40000 ONLY'
$poAsset=''
if ($includePo) {
    $poAsset=Add-Artifact $A2MediaPo 'A2MEDIA-ProDOS243.po' 'Optional ProDOS 2.4.3 boot floppy'
}

$manifestOut=Join-Path $stage 'MANIFEST.json'
$manifestData=[ordered]@{
    release_tag=$Tag
    project='a2fpga Enhanced M3'
    board='a2n20v2-Enhanced; Tang Nano 20K GW2AR-LV18QN88C8/I7; BL616 Stage2'
    git_repository=$repo
    source_branch=$branch
    source_commit=$head
    packaged_utc=(Get-Date).ToUniversalTime().ToString('o')
    validation='Hardware-tested latest HDMI-lab FPGA + MCU Stage2 per owner, November 2026'
    bl616_stage2_flash_address='0x40000'
    bl616_stage2_build_manifest_sha256=(Get-Sha $buildManifest)
    bl616_stage2_built_utc=[string]$stage2Info.timestampUtc
    fpga_built_last_write_utc=(Get-Item -LiteralPath $fpga).LastWriteTimeUtc.ToString('o')
    build_provenance='Exact on-disk .fs/.bin copies; SHA256 checksums. User hardware validation does not imply an automated FPGA flash readback.'
    files=@($artifactRecords)
}
$manifestData | ConvertTo-Json -Depth 7 | Set-Content -LiteralPath $manifestOut -Encoding UTF8

$readme=@"
A2FPGA Enhanced M3 — Stable Beta ($Tag)
=======================================
Hardware target: a2n20v2-Enhanced, Tang Nano 20K + BL616

FPGA:
  $fpgaName
  Gowin FPGA image; program through a compatible Tang Nano 20K FPGA
  programmer. Confirm the correct board BEFORE writing configuration flash.

MCU:
  $mcuName
  BL616 Stage2 firmware ONLY, at flash offset 0x40000.
  NEVER overwrite Sipeed's signed Stage1 firmware at 0x00000.
  Use the project's a2n20-mcu-program --stage2 tooling.

ProDOS:
  A2MEDIA-ProDOS243.po is optional, and is included only when the local
  file is explicitly present or provided to the packaging command.

After boot, HDMI defaults to native Apple II/IIgs video. TAB opens MCU
console; Y switches the MCU console/menu. MOD playback uses +8 dB MCU
gain with a linked -2 dBFS sample-peak ceiling. The combined HDMI mixer
also guards to -2 dBFS and reports clip history/one-second peak levels.
Supports MCU SD burst, ProTracker MOD jukebox, SSI263 and Ensoniq DOC.

Both firmware files are taken from the owner's locally tested HDMI-lab
checkout, not downloaded/reconstructed from older GitHub file history.

Verify all payload hashes with SHA256SUMS.txt / MANIFEST.json.
Source: https://github.com/$repo/tree/$head
"@
Set-Content -LiteralPath (Join-Path $stage 'README.txt') -Value $readme -Encoding UTF8
$sumLines=@()
foreach ($f in @(Get-ChildItem -LiteralPath $stage -File | Sort-Object Name)) {
    $sumLines += ("{0}  {1}" -f (Get-Sha $f.FullName),$f.Name)
}
$sumPath=Join-Path $stage 'SHA256SUMS.txt'
[IO.File]::WriteAllLines($sumPath,[string[]]$sumLines,[Text.Encoding]::ASCII)

$zip=Join-Path $outDir ("a2fpga-enhanced-" + $Tag + "-complete.zip")
Compress-Archive -Path (Join-Path $stage '*') -DestinationPath $zip -CompressionLevel Optimal -ErrorAction Stop
$null=Require-File $zip 100000
Add-Type -AssemblyName System.IO.Compression.FileSystem
$archive=[IO.Compression.ZipFile]::OpenRead($zip)
try {
    $archiveNames=@($archive.Entries | ForEach-Object { $_.FullName })
    foreach ($requiredName in @($fpgaName,$mcuName,'MANIFEST.json','README.txt','SHA256SUMS.txt')) {
        if ($archiveNames -notcontains $requiredName) {
            throw "ZIP integrity check: expected member not found: $requiredName"
        }
    }
    if ($includePo -and $archiveNames -notcontains 'A2MEDIA-ProDOS243.po') {
        throw 'ZIP integrity check: the selected .po was not included.'
    }
} finally { $archive.Dispose() }
$zipHash=Get-Sha $zip
$zipHashFile=$zip+'.sha256'
[IO.File]::WriteAllLines($zipHashFile,[string[]]@($zipHash+'  '+[IO.Path]::GetFileName($zip)),[Text.Encoding]::ASCII)

$notesFile=Join-Path $outDir 'RELEASE-NOTES.md'
$poNote=if ($includePo) {
    '- Optional A2MEDIA ProDOS 2.4.3 floppy image (single `.po`; no `.dsk`).'
} else { '- A2MEDIA `.po` not bundled; can be added in a later release.' }
$notes=@"
# A2FPGA Enhanced M3 — Stable Beta ($Tag)

Validated by the project owner on Tang Nano 20K/a2n20v2-Enhanced with
the most recent HDMI-lab FPGA and BL616 Stage2 firmware. An ~11-hour
playback/diagnostic session alongside SpectrumWall was successful.

- Native Apple II/IIgs HDMI video on startup; TAB to MCU console.
- Stereo MOD jukebox, fast file/folder loading, independent Mockingboard.
- Ensoniq DOC and SSI263 speech; SynthLAB piano instrument bank.
- HDMI CLIP=00 and approximately -2.0 dBFS L/R peak holds in measured playback.
- M3 512-byte autonomous SD bursts and responsive USB controls.
- Both exact local FPGA .fs and BL616 Stage2 .bin in one ZIP.
$poNote

Download $(Split-Path -Leaf $zip) for the COMPLETE set. Individual
flash assets are also attached unless ZipOnly was selected.

**BL616 flashing safety:** Stage2 .bin is for **0x40000 only**.
Do not overwrite Sipeed's encrypted/signed Stage1 at 0x00000.

Source commit: $head
FPGA SHA256: $(Get-Sha $fpgaAsset)
MCU SHA256: $(Get-Sha $mcuAsset)
ZIP SHA256: $zipHash
"@
Set-Content -LiteralPath $notesFile -Value $notes -Encoding UTF8

Write-Host ''
Write-Host 'M3 complete release package prepared and ZIP members verified:' -ForegroundColor Green
Write-Host "  $zip"
Write-Host "  $zipHashFile"
Write-Host "  Source commit: $head"
Write-Host "  FPGA SHA256: $(Get-Sha $fpgaAsset)"
Write-Host "  MCU SHA256: $(Get-Sha $mcuAsset)"
if ($includePo) { Write-Host "  PO   SHA256: $(Get-Sha $poAsset)" }
Write-Host "  ZIP  SHA256: $zipHash"

if (-not $Publish) {
    Write-Host ''
    Write-Host 'Package only; no GitHub release was created.' -ForegroundColor Yellow
    Write-Host 'To publish, run this script again with -Publish and a NEW output tag/folder.'
    return
}

$gh=Get-Command gh -CommandType Application -ErrorAction SilentlyContinue
if (-not $gh) {
    throw 'ZIP is ready but gh.exe (GitHub CLI) is not on PATH. Install/authenticate it to publish. Package was not lost.'
}
& $gh.Source auth status --hostname github.com
if ($LASTEXITCODE -ne 0) { throw 'gh is not authenticated to github.com. Release files were retained.' }
& $gh.Source release view $Tag --repo $repo *> $null
if ($LASTEXITCODE -eq 0) { throw "GitHub release tag '$Tag' already exists; refusing to overwrite assets." }

$assets=@($zip,$zipHashFile)
if (-not $ZipOnly) {
    $assets+=@($fpgaAsset,$mcuAsset)
    if ($includePo) { $assets+=$poAsset }
}
$ghArgs=@('release','create',$Tag)+$assets+
        @('--repo',$repo,'--target',$head,
          '--title',("A2FPGA Enhanced M3 Stable Beta " + $Tag),
          '--notes-file',$notesFile,'--prerelease')
& $gh.Source @ghArgs
if ($LASTEXITCODE -ne 0) {
    throw 'GitHub release creation or upload failed. Local package remains unchanged.'
}
Write-Host "Published release: https://github.com/$repo/releases/tag/$Tag" -ForegroundColor Green
