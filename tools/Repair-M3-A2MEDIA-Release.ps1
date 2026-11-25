#requires -Version 5.1
<#
.SYNOPSIS
  Correct M3 release by replacing P0 ProDOS floppy with tested-source M2 image.
.DESCRIPTION
  Validates SHA256 of exact unchanged original FPGA and Stage2, builds a new
  complete ZIP with M2 disk and fresh MANIFEST/README/checksums, then optionally
  uploads corrected assets to GitHub. Does not rebuild, flash, or touch the
  original release output folder.
#>
[CmdletBinding()]
param(
    [string]$SourceRoot='C:\AppleIIgsDev_02\a2fpga-m3-hdmi-lab',
    [string]$A2MediaPo = (Join-Path $env:TEMP 'A2MEDIA-M2-ProDOS243.po'),
    [switch]$Publish
)
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
$repo='ppuskari/a2fpga_core'
$tag='m3-2026.11.24'
$sourceCommit='565df1d1704b7fb4b5d7f5522297fc2ceebbd736'
$fpgaSha='dd34baaacbd80a4dabb2e5a94196ca59c4792f0392787aff9ba89a08ad62b6df'
$mcuSha='06819f74f90b95774a39256faaa518bab34239a31a78730089116763c020f741'
$m2PoSha='abf6c0d552534912c8bc1742510467b47e748165376924c6d6cbeda9fe051c32'
$m2Branch='petar/m2-80col-fat-picker-20261122'
$m2Commit='375bb6ee96ad129c1a0faee1e98d9fc83788d882'
$fpgaName='a2fpga-enhanced-m3-fpga.fs'
$mcuName='a2fpga-enhanced-m3-bl616-stage2.bin'
$oldPoName='A2MEDIA-ProDOS243.po'
$newPoName='A2MEDIA-M2-ProDOS243.po'
$zipName='a2fpga-enhanced-m3-2026.11.24-complete.zip'
$utf8 = [System.Text.UTF8Encoding]::new($false)
$root=(Resolve-Path -LiteralPath $SourceRoot).Path
$releaseDir=Join-Path $root ('release-out\'+$tag)
$original=Join-Path $releaseDir 'payload'
$output=Join-Path $releaseDir 'M2-corrected'
$payload=Join-Path $output 'payload'
$zip=Join-Path $output $zipName
$zipShaFile=$zip+'.sha256'

function Assert-Size([string]$file,[long]$size) {
    if(-not (Test-Path -LiteralPath $file -PathType Leaf)) {throw "Missing input: $file"}
    $length=(Get-Item -LiteralPath $file).Length
    if($length -ne $size){throw "Wrong size ($length, wanted $size): $file"}
}
function Hash([string]$file) {
    return (Get-FileHash -LiteralPath $file -Algorithm SHA256).Hash.ToLowerInvariant()
}
function Assert-Hash([string]$file,[string]$expected) {
    if(-not (Test-Path -LiteralPath $file -PathType Leaf)){throw "Missing input: $file"}
    $actual=Hash $file
    if($actual -ne $expected.ToLowerInvariant()){
        throw ("SHA256 mismatch for {0}: expected {1}, got {2}" -f $file,$expected,$actual)
    }
}
function Write-Utf8([string]$file,[string]$contents) {
    [IO.File]::WriteAllText($file,$contents,$utf8)
}
function Run-Gh([string[]]$ArgumentList) {
    & $gh.Source @ArgumentList
    if($LASTEXITCODE -ne 0){throw "GitHub CLI failed: gh $($ArgumentList -join ' ')"}
}
function New-Record([string]$file,[string]$role,[string]$source) {
    return [ordered]@{
        filename=[IO.Path]::GetFileName($file)
        role=$role
        bytes=[long](Get-Item -LiteralPath $file).Length
        sha256=(Hash $file)
        source_path=$source
    }
}

Assert-Size $A2MediaPo 143360
Assert-Hash $A2MediaPo $m2PoSha
Assert-Hash (Join-Path $original $fpgaName) $fpgaSha
Assert-Hash (Join-Path $original $mcuName) $mcuSha
$manifestPath=Join-Path $original 'MANIFEST.json'
if(-not (Test-Path -LiteralPath $manifestPath -PathType Leaf)){
    throw "Missing original release manifest: $manifestPath"
}
$previous=Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json
if([string]$previous.source_commit -ne $sourceCommit){throw 'Original release source commit changed.'}
if([string]$previous.release_tag -ne $tag){throw 'Original release tag changed.'}

# Keep the tested original binaries and prior release staging untouched.
if(Test-Path -LiteralPath $output){Remove-Item -LiteralPath $output -Force -Recurse}
$null=New-Item -ItemType Directory -Path $payload -Force
$fpgaFile=Join-Path $payload $fpgaName
$mcuFile=Join-Path $payload $mcuName
$newPoFile=Join-Path $payload $newPoName
Copy-Item -LiteralPath (Join-Path $original $fpgaName) -Destination $fpgaFile
Copy-Item -LiteralPath (Join-Path $original $mcuName) -Destination $mcuFile
Copy-Item -LiteralPath $A2MediaPo -Destination $newPoFile
Assert-Hash $fpgaFile $fpgaSha
Assert-Hash $mcuFile $mcuSha
Assert-Hash $newPoFile $m2PoSha

$manifest=[ordered]@{}
foreach($prop in $previous.PSObject.Properties){
    if($prop.Name -ne 'files'){$manifest[$prop.Name]=$prop.Value}
}
$manifest['files']=@(
    (New-Record $fpgaFile 'Tang Nano 20K Enhanced FPGA' 'Validated original M3 release')
    (New-Record $mcuFile 'BL616 Stage2 at offset 0x40000' 'Validated original M3 release')
    (New-Record $newPoFile 'M2 80-column ProDOS FAT browser' ('ppuskari/a2media.system@'+$m2Commit))
)
$manifest['a2media_source_repository']='ppuskari/a2media.system'
$manifest['a2media_source_branch']=$m2Branch
$manifest['a2media_source_commit']=$m2Commit
$manifest['a2media_floppy_version']='M2 80-column FAT directory browser'
$manifest['release_correction']='Replaced P0 with M2 ProDOS .po; FPGA and MCU hashes unchanged'
Write-Utf8 (Join-Path $payload 'MANIFEST.json') ($manifest | ConvertTo-Json -Depth 16)

$readme=@'
A2FPGA Enhanced M3 Stable Beta - Corrected M2 ProDOS image
=========================================================
a2fpga-enhanced-m3-fpga.fs       Tang Nano 20K Enhanced FPGA
a2fpga-enhanced-m3-bl616-stage2.bin   BL616 MCU Stage2
A2MEDIA-M2-ProDOS243.po          ProDOS 2.4.3 M2 FAT browser, 140 KB

This M2 80-column browser replaces the older P0 remote-control-only app.
It browses directories, navigates folders, pages 12 items, starts a MOD
or jukebox from a selected filename, handles slow 506-file directory
scans, and includes IIgs fast-mode mailbox sequence-handshake fixes.

FPGA and MCU binaries are unchanged from the hardware-tested M3 release.
The matching M2 mailbox features are already present in M3 source.
This corrected M2 Apple program still requires real-hardware validation.

Firmware safety: BL616 Stage2 must be programmed at 0x40000 ONLY.
Never overwrite the signed Sipeed Stage1 bootloader at 0x00000.
Refer to MANIFEST.json and SHA256SUMS.txt for provenance/checksums.
'@
Write-Utf8 (Join-Path $payload 'README.txt') $readme

$hashLines=@()
foreach($file in @(Get-ChildItem -LiteralPath $payload -File | Sort-Object Name)){
    $hashLines+=('{0}  {1}' -f (Hash $file.FullName),$file.Name)
}
[IO.File]::WriteAllLines((Join-Path $payload 'SHA256SUMS.txt'),[string[]]$hashLines,[Text.Encoding]::ASCII)
# ZIP stores filesystem timestamps. Fix these to stable release time so that
# repeated repair runs generate identical bytes and SHA256, not time-varying
# reuploads. No source or firmware bytes are changed by adjusting the COPIES.
$stableUtc=[DateTime]::SpecifyKind(([DateTime]'2026-11-24T12:00:00'),[DateTimeKind]::Utc)
foreach($entryFile in @(Get-ChildItem -LiteralPath $payload -File)){
    # Gowin-generated .fs files can be marked READONLY. Copy-Item inherits
    # that flag; clear it ONLY on the isolated release payload copy.
    # Never modify the actual tested FPGA/MCU outputs in the lab tree.
    if($entryFile.IsReadOnly){$entryFile.IsReadOnly=$false}
    $entryFile.LastWriteTimeUtc=$stableUtc
}
Compress-Archive -Path (Join-Path $payload '*') -DestinationPath $zip -CompressionLevel Optimal

# Verify every archived member byte-for-byte against the staged file.
Add-Type -AssemblyName System.IO.Compression.FileSystem
$archive=[IO.Compression.ZipFile]::OpenRead($zip)
try {
    $names=@($archive.Entries | ForEach-Object {$_.FullName})
    foreach($need in @($fpgaName,$mcuName,$newPoName,'README.txt','MANIFEST.json','SHA256SUMS.txt')){
        if($names -notcontains $need){throw "Corrected ZIP missing: $need"}
    }
    if($names -contains $oldPoName){throw 'Corrected ZIP still contains P0 floppy.'}
    foreach($entry in @($archive.Entries)){
        if($entry.FullName.EndsWith('/')){continue}
        $stream=$entry.Open()
        $sha=[Security.Cryptography.SHA256]::Create()
        try{
            $bytes=$sha.ComputeHash($stream)
            $entryHash=([BitConverter]::ToString($bytes)).Replace('-','').ToLowerInvariant()
        }finally{$sha.Dispose();$stream.Dispose()}
        $diskFile=Join-Path $payload $entry.FullName
        if($entryHash -ne (Hash $diskFile)){throw "ZIP entry hash mismatch: $($entry.FullName)"}
    }
}finally{$archive.Dispose()}
$zipHash=Hash $zip
[IO.File]::WriteAllLines($zipShaFile,[string[]]@("$zipHash  $zipName"),[Text.Encoding]::ASCII)

$notes=@"
# A2FPGA Enhanced M3 Stable Beta ($tag)

Hardware-validated combination of the Enhanced M3 FPGA and BL616 Stage2.
Includes native Apple II/IIgs-first HDMI boot, fast autonomous SD bursts,
MOD jukebox, Ensoniq DOC, SSI263 speech and Mockingboard. About 11 hours
of playback and SpectrumWall diagnostics were reported successful,
with peaks near -2 dBFS and HDMI CLIP=00.

## Corrected ProDOS player

Original release accidentally packaged the older P0, which does not
browse folders. Replaced it with A2MEDIA-M2-ProDOS243.po from the
latest M2 80-column FAT browser branch. Features: directory navigation,
12-item paging, 506-file async scan, M2 SEEK, now-playing indication,
and IIgs fast-mode mailbox handshake fixes. No .dsk is distributed.

The FPGA and Stage2 assets remain byte-for-byte UNCHANGED.

FPGA SHA256: $fpgaSha
MCU Stage2 SHA256: $mcuSha
M2 ProDOS PO SHA256: $m2PoSha
Complete ZIP SHA256: $zipHash

FPGA/MCU source commit: $sourceCommit
M2 ProDOS source commit: $m2Commit

Download $zipName for the complete matched set. Individual .fs, .bin
and M2 .po are also available.

IMPORTANT: MCU Stage2 .bin must only be flashed at BL616 offset 0x40000.
Never overwrite the signed Stage1 at offset 0x00000.

This is a prerelease beta; physical Apple IIe/IIgs directory browsing
with this M2 app should still be validated.
"@
$notesFile=Join-Path $output 'RELEASE-NOTES.md'
Write-Utf8 $notesFile $notes

Write-Host 'PASS: corrected ZIP and individual archived files verified' -ForegroundColor Green
Write-Host "New ZIP:         $zip"
Write-Host "FPGA UNCHANGED:  $fpgaSha"
Write-Host "MCU  UNCHANGED:  $mcuSha"
Write-Host "M2 PO SHA256:    $m2PoSha"
Write-Host "New ZIP SHA256:  $zipHash"

if(-not $Publish){
    Write-Host 'Package only. Release not changed. Re-run with -Publish.' -ForegroundColor Yellow
    return
}

$gh=Get-Command gh -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
if(-not $gh){throw 'GitHub CLI is not installed. Corrected package is preserved locally.'}
Run-Gh -ArgumentList @('release','view',$tag,'--repo',$repo,'--json','tagName','--jq','.tagName')
# Distinct filename for M2 eliminates ambiguity; always allow a retry.
Run-Gh -ArgumentList @('release','upload',$tag,$newPoFile,'--repo',$repo,'--clobber')
Run-Gh -ArgumentList @('release','upload',$tag,$zip,$zipShaFile,'--repo',$repo,'--clobber')
Run-Gh -ArgumentList @('release','edit',$tag,'--repo',$repo,'--notes-file',$notesFile)
# Delete obsolete standalone P0 only once corrected assets and notes exist.
Run-Gh -ArgumentList @('release','delete-asset',$tag,$oldPoName,'--repo',$repo,'--yes')

# Verify the remote GitHub digests, including firmware we never re-uploaded.
$json=(& $gh.Source api "repos/$repo/releases/tags/$tag" | Out-String)
if($LASTEXITCODE -ne 0){throw 'Cannot verify release after updating assets.'}
$release=$json | ConvertFrom-Json
if([string]$release.tag_name -ne $tag){throw 'Wrong remote release tag.'}
$required=@{
    $fpgaName=$fpgaSha
    $mcuName=$mcuSha
    $newPoName=$m2PoSha
    $zipName=$zipHash
}
foreach($name in $required.Keys){
    $found=@($release.assets | Where-Object {$_.name -eq $name})
    if($found.Count -ne 1){throw "Missing or duplicate GitHub release asset: $name"}
    if([string]$found[0].digest -ne ('sha256:'+$required[$name])){
        throw "Remote asset digest differs: $name"
    }
}
if(@($release.assets | Where-Object {$_.name -eq $oldPoName}).Count -gt 0){
    throw 'Old P0 standalone asset was not removed.'
}
Write-Host 'SUCCESS: GitHub release corrected, firmware hashes unchanged.' -ForegroundColor Green
Write-Host "https://github.com/$repo/releases/tag/$tag"
