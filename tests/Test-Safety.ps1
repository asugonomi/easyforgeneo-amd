$ErrorActionPreference='Stop'
. "$PSScriptRoot\..\scripts\Common.ps1"
$manifest=Get-Content "$PSScriptRoot\..\manifest.json" -Raw | ConvertFrom-Json
$count=0
function Check($Condition, $Message) {
    if (!$Condition) { throw $Message }
    $script:count++
}
foreach ($file in Get-ChildItem "$PSScriptRoot\..\scripts\*.ps1") {
    $tokens=$null; $errors=$null
    [Management.Automation.Language.Parser]::ParseFile($file.FullName,[ref]$tokens,[ref]$errors) | Out-Null
    Check ($errors.Count -eq 0) "Syntax error: $file $errors"
}
foreach ($case in @(
    @('AMD Radeon RX 9070 XT','PCI\VEN_1002&DEV_7550','gfx1201','candidate'),
    @('AMD Radeon RX 9060 XT','PCI\VEN_1002&DEV_0000','gfx1200','candidate'),
    @('AMD Radeon RX 7900 XTX','PCI\VEN_1002&DEV_0000','gfx1100','candidate'),
    @('AMD Radeon RX 7800 XT','PCI\VEN_1002&DEV_0000','gfx1101','candidate'),
    @('AMD Radeon RX 6600','PCI\VEN_1002&DEV_0000','gfx1032','experimental'),
    @('NVIDIA GeForce RTX 4070','PCI\VEN_10DE&DEV_0000','','not-amd'),
    @('AMD Radeon RX 9070 XT','ROOT\DISPLAY\0000','','not-amd'),
    @('AMD Radeon Graphics','PCI\VEN_1002&DEV_0000','','unknown'),
    @('AMD Radeon RX 9070 XTX','PCI\VEN_1002&DEV_0000','','unknown'),
    @('AMD Radeon RX 580','PCI\VEN_1002&DEV_0000','','unknown')
)) {
    $plan=Get-GpuPlan ([pscustomobject]@{Name=$case[0];PNPDeviceID=$case[1]}) $manifest
    Check ($plan.arch -eq $case[2] -and $plan.tier -eq $case[3]) "Unexpected GPU classification: $($case[0])"
}
$scratch=Join-Path ([IO.Path]::GetTempPath()) ('amd-safety-' + [guid]::NewGuid())
New-Item -ItemType Directory $scratch | Out-Null
try {
    $existing=Join-Path $scratch 'existing'
    New-Item -ItemType Directory $existing | Out-Null
    'preserve' | Set-Content (Join-Path $existing 'sentinel.txt')
    $failed=$false
    try { Get-VerifiedZip ([pscustomobject]@{sha256='invalid';url='https://invalid.invalid/'}) $existing $scratch }
    catch { $failed=$true }
    Check $failed 'Existing directory was not refused'
    Check ((Get-Content (Join-Path $existing 'sentinel.txt')) -eq 'preserve') 'Existing data changed'
    $archive=Join-Path $scratch (('0' * 64) + '.zip')
    'not a trusted archive' | Set-Content $archive
    $failed=$false
    try { Get-VerifiedZip ([pscustomobject]@{sha256=('0' * 64);url='https://invalid.invalid/'}) (Join-Path $scratch 'new') $scratch }
    catch { $failed=$true }
    Check $failed 'Bad hash accepted'
    Check (!(Test-Path (Join-Path $scratch 'new'))) 'Bad hash extracted'
    $link=Join-Path $scratch 'link'
    New-Item -ItemType Junction -Path $link -Target $existing | Out-Null
    $failed=$false
    try { Assert-NoLinks (Join-Path $link 'nested') } catch { $failed=$true }
    Check $failed 'Junction ancestor accepted'
    # Delete the junction itself, never recurse through its target.
    [IO.Directory]::Delete($link)
} finally {
    $resolved=[IO.Path]::GetFullPath($scratch)
    $tempPrefix=[IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd('\') + '\amd-safety-'
    if ($resolved.StartsWith($tempPrefix,[StringComparison]::OrdinalIgnoreCase)) {
        Remove-Item -LiteralPath $resolved -Recurse -Force
    }
}
Write-Host "PASS: $count safety assertions"
