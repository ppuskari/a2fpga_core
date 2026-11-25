#requires -Version 5.1
<#
.SYNOPSIS
  One-command M3 BL616 Stage2 build / programming on Windows PowerShell.
.DESCRIPTION
  SDK and compiler paths are discovered beside the isolated M3 checkout; FPGA SRAM must be programmed separately.
  Only the BL616 Stage2 address (0x40000) can be programmed by this wrapper.
  Stage1, FPGA flash and saved A3 audio config are not modified.

  Flash intentionally bypasses the programmer's post-reboot USB enumeration
  check, which can report PARTIAL before signed Stage1 chains to Stage2.
  A confirmed flash write is NOT the same as byte-for-byte readback.
  Explicit VerifyReadback is separately available, and can fail on some
  Bouffalo tool configurations without establishing a failed flash write.
.EXAMPLE
  .\M3.ps1 Build
  .\M3.ps1 Flash
  .\M3.ps1 CheckRuntime
.EXAMPLE
  .\M3.ps1 BuildFlash -VerboseFlash
  .\M3.ps1 Build -DevRoot 'D:\AppleIIgsDev_02'
#>
[CmdletBinding()]
param(
    [Parameter(Position=0)]
    [ValidateSet('Help','SourceState','Build','Detect','Flash','BuildFlash','CheckRuntime','VerifyReadback')]
    [string] $Action='Help',
    [string] $DevRoot='',
    [string] $SdkRoot='',
    [string] $ToolchainBin='',
    [ValidateRange(1,32)][int] $Jobs=4,
    [ValidateRange(9600,2000000)][int] $BaudRate=500000,
    [string] $Port='',
    [switch] $VerboseFlash
)
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'

$requiredBranch='petar/m3-sd-sector-burst-20261123'
# Only this isolated experiment may also build/flash Stage2. Production M3
# keeps its original hard-fail guard and separate build manifest unchanged.
$experimentalBranch='petar/m3-mb-timing-prodos-suite-20261123'
# Post-release console-only experiment, intentionally isolated from the
# published M3 beta binaries and their SHA256 manifest.
$advancedConsoleBranch='petar/m3-advanced-console-80col-20261124'
# MCU-only post-release dual-catalog heap-efficiency build; isolated worktree.
$catalogCompactBranch='petar/m3-catalog-heap-compact-20261125'
$root=$PSScriptRoot
$board=Join-Path $root 'boards\a2n20v2-Enhanced\src\a2n20_bl616'
$hostDir=Join-Path $board 'firmware_host'
$programmer=Join-Path $board 'tools\a2n20-mcu-program'
$buildDir=Join-Path $hostDir 'build\build_out'
$firmware=Join-Path $buildDir 'a2n20_bl616_host_bl616.bin'
$manifest=Join-Path $buildDir 'm3-stage2-build.json'
# Some Gowin-generated FPGA files are tracked by legacy project history.
# Those files change during synthesis/P&R and must not invalidate a BL616
# Stage2 manifest: they are NOT inputs to the firmware_host compilation.
# Keep all actual tracked sources covered, including firmware_host/, shared
# firmware/, M3.ps1, and the rest of the repository.
# The Stage2 .bin itself is independently SHA256-checked at build/flash time.
$generatedBinaryPath='boards/a2n20v2-Enhanced/src/a2n20_bl616/firmware_host/build/build_out/a2n20_bl616_host_bl616.bin'
$firmwareSourcePathspecs=@(
    '.'
    ":(exclude)$generatedBinaryPath"
    ':(exclude)boards/a2n20v2-Enhanced/hdl/datetime.svh'
    ':(exclude)boards/a2n20v2-Enhanced/impl/pnr/**'
    ':(exclude)boards/a2n20v2-Enhanced/impl/project_process_config.json'
    ':(exclude)boards/a2n20v2-Enhanced/impl/a2n20v2_enhanced_process_config.json'
)

function Fail([string] $message) { throw $message }

function Show-Help {
    Write-Host ''
    Write-Host 'M3 BL616 - Windows PowerShell single-command helper' -ForegroundColor Cyan
    Write-Host '  .\M3.ps1 SourceState    Show tracked changes and source fingerprint'
    Write-Host '  .\M3.ps1 Build          Configure SDK/compiler and compile MCU Stage2'
    Write-Host '  .\M3.ps1 Detect         Show connected board, without programming'
    Write-Host '  .\M3.ps1 Flash          Write only Stage2 (0x40000), confirmation required'
    Write-Host '  .\M3.ps1 BuildFlash     Build and then explicitly confirm Stage2 write'
    Write-Host '  .\M3.ps1 CheckRuntime  Check USB enumeration after normal reboot'
    Write-Host '  .\M3.ps1 VerifyReadback  Optional byte-for-byte Stage2 readback'
    Write-Host ''
    Write-Host 'Defaults: SDK and compiler under checkout parent (AppleIIgsDev_02).'
    Write-Host 'Overrides: -DevRoot, -SdkRoot, -ToolchainBin, -Jobs, -Port, -BaudRate.'
    Write-Host ''
    Write-Warning 'Flash skips premature post-reboot USB check. No byte-readback claim.'
    Write-Warning 'CheckRuntime detects USB; only MOD OSD confirms M3 PCM512 + bytewise SDRAM + 2KiB windows.'
    Write-Host ''
}

function Require-Executable([string] $name) {
    if(-not (Get-Command $name -ErrorAction SilentlyContinue)) {
        Fail "Executable '$name' not found on PATH."
    }
}

function Assert-M3-Checkout {
    Require-Executable 'git'
    if(-not (Test-Path -LiteralPath $programmer -PathType Leaf)) {
        Fail "Cannot locate BL616 programmer: $programmer"
    }
    $current=(& git -C $root branch --show-current | Out-String).Trim()
    if($LASTEXITCODE -ne 0 -or
       ($current -ne $requiredBranch -and $current -ne $experimentalBranch -and
        $current -ne $advancedConsoleBranch -and
        $current -ne $catalogCompactBranch)) {
        Fail "Wrong repository branch '$current'. Only approved M3 branches may build."
    }
}

function Current-Commit {
    $sha=(& git -C $root rev-parse HEAD | Out-String).Trim()
    if($LASTEXITCODE -ne 0 -or $sha -notmatch '^[a-fA-F0-9]{40}$') {
        Fail 'Could not determine Git HEAD commit.'
    }
    return $sha
}

function Get-Tracked-Source-Fingerprint {
    # A modified checkout is allowed, but its actual source diff MUST be
    # identical at compile time and at flash time. Do not discard edits.
    # HEAD includes both staged and unstaged changes (unlike git diff alone).
    $lines=@(& git -C $root diff --no-ext-diff --no-color --binary HEAD -- @firmwareSourcePathspecs)
    if($LASTEXITCODE -ne 0) {
        Fail 'Could not compute tracked source diff against HEAD.'
    }
    $content=[string]::Join("`n",[string[]]$lines)
    $bytes=[Text.Encoding]::UTF8.GetBytes($content)
    $sha=[Security.Cryptography.SHA256]::Create()
    try {
        return ([BitConverter]::ToString($sha.ComputeHash($bytes))).Replace('-','')
    } finally {
        $sha.Dispose()
    }
}

function Show-Tracked-Source-State {
    Assert-M3-Checkout
    $changes=@(& git -C $root status --short --untracked-files=no -- @firmwareSourcePathspecs)
    if($LASTEXITCODE -ne 0) {
        Fail 'Unable to examine tracked Git changes.'
    }
    $changed=@($changes | Where-Object { $_ -and $_.Trim() })
    if($changed.Count -gt 0) {
        Write-Warning "Found $($changed.Count) locally modified tracked file(s)."
        foreach($change in $changed) {
            Write-Host "  $change"
        }
        Write-Warning 'Local changes will be included in the build; no edits will be discarded.'
    } else {
        Write-Host 'Git tracked files are clean.'
    }
    $fingerprint=Get-Tracked-Source-Fingerprint
    Write-Host "Source diff SHA256: $fingerprint"
    Write-Host 'Gowin-generated FPGA outputs are excluded; firmware binary SHA256 is independently checked.'
    return $fingerprint
}

function Configure-Toolchain {
    $parent=$DevRoot
    if(-not $parent) { $parent=Split-Path -Parent $root }
    $sdk=$SdkRoot
    if(-not $sdk) { $sdk=Join-Path $parent 'bouffalo_sdk' }
    $gcc=$ToolchainBin
    if(-not $gcc) {
        $gcc=Join-Path $parent 'bouffalo_tools\xuantie\xuantie-gcc-riscv-v2.10.2-windows-x86_64\bin'
    }
    if(-not (Test-Path -LiteralPath $sdk -PathType Container)) {
        Fail "Bouffalo SDK missing: $sdk. Use -SdkRoot PATH."
    }
    if(-not (Test-Path -LiteralPath $gcc -PathType Container)) {
        Fail "RISC-V toolchain missing: $gcc. Use -ToolchainBin PATH."
    }
    $env:BL_SDK_BASE=(Resolve-Path -LiteralPath $sdk).Path
    $env:PATH=(Join-Path $env:BL_SDK_BASE 'tools\make')+';'+
              (Join-Path $env:BL_SDK_BASE 'tools\cmake\bin')+';'+
              $gcc+';'+$env:PATH
    Require-Executable 'make'
    Require-Executable 'cmake'
    Require-Executable 'riscv64-unknown-elf-gcc'
    Write-Host "SDK: $env:BL_SDK_BASE"
    Write-Host "Toolchain: $gcc"
}

function Get-Verified-Binary-Hash {
    if(-not (Test-Path -LiteralPath $firmware -PathType Leaf)) {
        Fail "Stage2 binary not found: $firmware. Run .\M3.ps1 Build first."
    }
    $bytes=[IO.File]::ReadAllBytes($firmware)
    if($bytes.Length -lt 65536) {
        Fail "Stage2 binary is unexpectedly small: $($bytes.Length) bytes."
    }
    $txt=[Text.Encoding]::ASCII.GetString($bytes)
    foreach($marker in @('PCM RMAX=','MOD SMP CACHE=8x','MOD SMP WIN=4x2048B','MOD LOG=QUIET1HZ','MOD JUKE=STARTFILE','M2 FAT REPLY=YES','MOD MCU CACHE=','MOD SPI=PCM512 SDRAM=BYTE','M3 SD BURST FPGA=')) {
        if(-not $txt.Contains($marker)) {
            Fail "Expected M3 diagnostic '$marker' absent from Stage2 binary."
        }
    }
    # Detect a stale Stage2 binary when an incremental Bouffalo SDK build
    # erroneously reuses committed M3 artifacts in this isolated worktree.
    $currentBranch=(& git -C $root branch --show-current | Out-String).Trim()
    if($currentBranch -eq $catalogCompactBranch) {
        foreach($marker in @('M2 CAT: CHUNKS=', 'MCU JUKE: DIRS=%u DIRBYTES=%uB FALLBACK=%u')) {
            if(-not $txt.Contains($marker)) {
                Fail "Stale Stage2: compact dual-catalog firmware marker '$marker' absent. A clean MCU rebuild is required."
            }
        }
    }
    return (Get-FileHash -LiteralPath $firmware -Algorithm SHA256).Hash
}

function Assert-Built-Manifest {
    Assert-M3-Checkout
    $sourceHash=Show-Tracked-Source-State
    $hash=Get-Verified-Binary-Hash
    if(-not (Test-Path -LiteralPath $manifest -PathType Leaf)) {
        Fail 'Build manifest absent: run .\M3.ps1 Build before Flash.'
    }
    $record=Get-Content -LiteralPath $manifest -Raw | ConvertFrom-Json
    $head=Current-Commit
    $current=(& git -C $root branch --show-current | Out-String).Trim()
    if([string]$record.branch -ne $current -or
       [string]$record.commit -ne $head -or
       [string]$record.sha256 -ne $hash -or
       [string]$record.sourceDiffSha256 -ne $sourceHash -or
       [string]$record.binary -ne $firmware) {
        Fail 'Firmware or repository has changed since Build. Rebuild before Flash.'
    }
    Write-Host "Stage2: $firmware" -ForegroundColor Cyan
    Write-Host "SHA256: $hash"
    Write-Host "Commit: $head"
}

function Build-Stage2 {
    Assert-M3-Checkout
    $sourceBefore=Show-Tracked-Source-State
    Configure-Toolchain
    if(-not (Test-Path -LiteralPath $hostDir -PathType Container)) {
        Fail "firmware_host project missing: $hostDir"
    }
    # Never leave an old build manifest valid after a failed make.
    if(Test-Path -LiteralPath $manifest -PathType Leaf) {
        Remove-Item -LiteralPath $manifest -Force
    }
    Push-Location $hostDir
    try {
        & make "-j$Jobs" "CHIP=bl616" "BOARD=bl616dk"
        if($LASTEXITCODE -ne 0) {
            Fail "BL616 compiler returned $LASTEXITCODE - nothing flashed."
        }
    } finally {
        Pop-Location
    }
    $hash=Get-Verified-Binary-Hash
    $sourceAfter=Get-Tracked-Source-Fingerprint
    if($sourceBefore -ne $sourceAfter) {
        Fail 'Tracked source inputs changed DURING compilation; run SourceState to inspect changes before retrying.'
    }
    $record=[ordered]@{
        branch=(& git -C $root branch --show-current | Out-String).Trim()
        commit=(Current-Commit)
        sha256=$hash
        sourceDiffSha256=$sourceAfter
        binary=$firmware
        length=(Get-Item -LiteralPath $firmware).Length
        timestampUtc=(Get-Date).ToUniversalTime().ToString('o')
        readbackVerified=$false
    }
    $record | ConvertTo-Json | Set-Content -LiteralPath $manifest -Encoding UTF8
    Write-Host ''
    Write-Host 'BL616 Stage2 build succeeded. SHA256 manifest saved.' -ForegroundColor Green
    Write-Host "Firmware: $firmware"
    Write-Host 'Next: .\M3.ps1 Flash'
}

function Invoke-Programmer([string[]]$arguments) {
    Require-Executable 'py'
    & py -3 $programmer @arguments
    $status=$LASTEXITCODE
    if($status -ne 0) {
        Fail "MCU programmer returned exit code $status. Inspect its output."
    }
}

function Detect-Device {
    Assert-M3-Checkout
    Invoke-Programmer -arguments @('--detect')
    Write-Host 'Note: USB identification alone does not prove M3 Stage2 is running.'
}

function Flash-Stage2 {
    Assert-Built-Manifest
    Write-Warning 'This writes ONLY BL616 MCU Stage2 at 0x40000.'
    Write-Warning 'It does NOT touch signed Sipeed Stage1 (0x0) or FPGA flash.'
    Write-Warning 'Byte-for-byte flash readback is NOT performed automatically.'
    Write-Host 'If necessary, enter UPDATE/BootROM mode before continuing.'
    $answer=Read-Host 'To program Stage2, type FLASH M3'
    if($answer -cne 'FLASH M3') {
        Fail 'Programming cancelled; no write attempted.'
    }
    $flashArgs=@('--stage2', $firmware, '--baudrate', [string]$BaudRate,
                 '--skip-verify')
    if($Port) { $flashArgs+=@('--port',$Port) }
    if($VerboseFlash) { $flashArgs+='--verbose' }
    Invoke-Programmer -arguments $flashArgs
    Write-Host ''
    Write-Host 'Stage2 flash tool reported WRITE SUCCESS at 0x40000.' -ForegroundColor Green
    Write-Warning 'Flash readback was not performed; actual flash contents are unverified.'
    Write-Host 'Disconnect/reconnect without holding UPDATE, then run:'
    Write-Host '  .\M3.ps1 CheckRuntime'
    Write-Host 'On MOD OSD verify MOD SPI=PCM512 SDRAM=BYTE, MOD SMP CACHE=8x8192B and MOD SMP WIN=4x2048B and MOD LOG=QUIET1HZ.'
}

function Check-Runtime {
    Assert-M3-Checkout
    Write-Host 'Checking USB identity after normal power-on (no UPDATE)...'
    Invoke-Programmer -arguments @('--detect')
    Write-Host ''
    Write-Warning 'Stage1 may enumerate before Stage2 chain-loads. PARTIAL is not proof of bad flash.'
    Write-Host 'Wait until the normal MCU menu appears; verify M3 cache sizes on the MOD OSD.'
    Write-Host 'This does not byte-verify the flash contents.'
}

function Verify-Readback {
    Assert-Built-Manifest
    Write-Warning 'Optional diagnostic only. The Bouffalo readback path may fail even after a working Stage2 write.'
    Write-Host 'Place BL616 into UPDATE/BootROM mode for the readback.'
    $answer=Read-Host 'To read and compare Stage2 (without writing), type READBACK'
    if($answer -cne 'READBACK') {
        Fail 'Readback cancelled.'
    }
    $verifyArgs=@('--firmware',$firmware,'--addr','0x40000','--verify-flash',
                  '--baudrate',[string]$BaudRate)
    if($Port) { $verifyArgs+=@('--port',$Port) }
    if($VerboseFlash) { $verifyArgs+='--verbose' }
    try {
        Invoke-Programmer -arguments $verifyArgs
        Write-Host 'Stage2 bytes read back and matched the build image.' -ForegroundColor Green
    } catch {
        Write-Warning 'Byte readback NOT verified. This alone does not prove that Stage2 programming failed.'
        throw
    }
}

switch($Action) {
    'Help' { Show-Help }
    'SourceState' { $null=Show-Tracked-Source-State }
    'Build' { Build-Stage2 }
    'Detect' { Detect-Device }
    'Flash' { Flash-Stage2 }
    'BuildFlash' { Build-Stage2; Flash-Stage2 }
    'CheckRuntime' { Check-Runtime }
    'VerifyReadback' { Verify-Readback }
    default { Show-Help }
}
