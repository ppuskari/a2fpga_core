# Enhanced M3 release publishing — actual tested Windows binaries

**First release:** `m3-2026.11.24` — A2FPGA Enhanced M3 Stable Beta.

GitHub repository `ppuskari/a2fpga_core` does not currently have a
published Release. A GitHub Release can refer to the exact source SHA from the
lab branch, without having to first merge the diverged A2Mega changes on
`main`. No force update or source-history rewrite is needed.

## What the package contains

```text
a2fpga-enhanced-m3-2026.11.24-complete.zip
    a2fpga-enhanced-m3-fpga.fs
    a2fpga-enhanced-m3-bl616-stage2.bin
    A2MEDIA-ProDOS243.po      (optional, only if verified/local file supplied)
    MANIFEST.json
    SHA256SUMS.txt
    README.txt
```

The release also attaches the ZIP's separate SHA256 file and
individual `.fs` / Stage2 `.bin` assets (plus `.po`, if included)
so end users may download either the pair or a specific file.

**CAUTION**: the `.bin` included in this release is BL616 **Stage2**
firmware at address `0x40000`. It is not Gowin FPGA `.binx`, not a
Stage1 bootloader, and must NEVER be flashed to BL616 offset `0x00000`.

## Never rebuild to package a tested configuration

The publisher's job is to copy the exact tested local
`impl/pnr/a2n20v2_enhanced.fs` and
`firmware_host/build/build_out/a2n20_bl616_host_bl616.bin` files.

It verifies the MCU Stage2 binary against its `m3-stage2-build.json`
SHA256, source commit, branch and length. The FPGA image is hashed
from its actual on-disk bytes; no incorrect Git-tracked/old bitstream
is silently substituted. Any local tracked source changes (other
than known Gowin-generated files) block release tagging.

The device was verified by its owner over an extended hardware run,
including MOD/HDMI levels, M3 SD burst, the MCU menu and IIgs-first boot.

## How to download the packager without modifying the tested checkout

The tooling script lives on **separate** branch
`petar/m3-release-packaging-20261124`.
It must not be merged or pulled into the working M3 checkout before
publishing; doing so would change Git HEAD and invalidate the
existing local build manifest.

In Windows PowerShell 5.1 with GitHub CLI (`gh`) installed/authenticated:

```powershell
$repoRoot='C:\AppleIIgsDev_02\a2fpga-m3-hdmi-lab'
$script=Join-Path $env:TEMP 'Publish-M3-Release.ps1'
$b64=gh api 'repos/ppuskari/a2fpga_core/contents/tools/Publish-M3-Release.ps1?ref=petar/m3-release-packaging-20261124' --jq .content
[IO.File]::WriteAllBytes($script,[Convert]::FromBase64String(($b64 -join '')))
```

If the A2MEDIA image is not already in a sibling clone:

```powershell
gh repo clone ppuskari/a2media.system 'C:\AppleIIgsDev_02\a2media.system'
```

The image is `disks/A2MEDIA-ProDOS243.po`. This package deliberately
includes **only `.po`**, never the alternate `.dsk`.

To package and **publish** in one guarded step:

```powershell
& $script -SourceRoot $repoRoot -Publish
```

Or explicitly specify the optional image:

```powershell
& $script -SourceRoot $repoRoot -A2MediaPo 'C:\AppleIIgsDev_02\a2media.system\disks\A2MEDIA-ProDOS243.po' -Publish
```

For an offline local ZIP only, omit `-Publish`. The script fails
closed if an output directory with the requested tag already exists:
it never overwrites the already-staged binary set. Use a new tag or
manually reconcile the existing folder before rerunning.

The publisher generates GitHub release notes with the **actual**
SHA256 of FPGA, MCU and full ZIP. The release tag is created from
the local checkout's exact Git commit via `gh release create --target`.

**No remote GitHub Release will exist until the user invokes
the publisher with `-Publish` from the machine holding the tested
binaries.** GitHub's existing connected repository tools cannot read
the on-disk Windows files or upload their bytes by themselves.

## Verify after upload

```powershell
gh release view m3-2026.11.24 -R ppuskari/a2fpga_core
gh release download m3-2026.11.24 -R ppuskari/a2fpga_core -p '*.zip' -D .\M3-release-check
```

Check the published ZIP and each included file against
`SHA256SUMS.txt` and `MANIFEST.json`. Keep the local tested binaries
and original MCU manifest as an immutable backup.
