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
    $runtimeTest=Join-Path $scratch 'runtime'
    $pythonDir=Join-Path $runtimeTest 'python'
    $realPython=Join-Path $pythonDir 'cpython-3.13.15-windows-x86_64-none'
    $pythonAlias=Join-Path $pythonDir 'cpython-3.13-windows-x86_64-none'
    New-Item -ItemType Directory -Path $realPython -Force | Out-Null
    Assert-RuntimeLinks $runtimeTest
    Check $true 'Runtime without links accepted'
    New-Item -ItemType Junction -Path $pythonAlias -Target $realPython | Out-Null
    try {
        Assert-RuntimeLinks $runtimeTest
        Check $true 'Exact Python alias accepted'
        $nested=Join-Path $realPython 'unexpected'
        New-Item -ItemType Junction -Path $nested -Target $existing | Out-Null
        try {
            $failed=$false
            try { Assert-RuntimeLinks $runtimeTest } catch { $failed=$true }
            Check $failed 'Link inside Python target accepted'
        } finally { [IO.Directory]::Delete($nested) }
    } finally { [IO.Directory]::Delete($pythonAlias) }
    foreach ($badTarget in @($existing, (Join-Path $pythonDir 'cpython-3.13.14-windows-x86_64-none'))) {
        if (!(Test-Path -LiteralPath $badTarget)) { New-Item -ItemType Directory -Path $badTarget | Out-Null }
        New-Item -ItemType Junction -Path $pythonAlias -Target $badTarget | Out-Null
        try {
            $failed=$false
            try { Assert-RuntimeLinks $runtimeTest } catch { $failed=$true }
            Check $failed 'External or wrong-version Python target accepted'
        } finally { [IO.Directory]::Delete($pythonAlias) }
    }
    $wrongAlias=Join-Path $runtimeTest 'other-python'
    New-Item -ItemType Junction -Path $wrongAlias -Target $realPython | Out-Null
    try {
        $failed=$false
        try { Assert-RuntimeLinks $runtimeTest } catch { $failed=$true }
        Check $failed 'Unexpected alias location accepted'
    } finally { [IO.Directory]::Delete($wrongAlias) }
    # An approved-looking target must itself be a real directory, not a second link.
    [IO.Directory]::Delete($realPython)
    New-Item -ItemType Junction -Path $realPython -Target $existing | Out-Null
    New-Item -ItemType Junction -Path $pythonAlias -Target $realPython | Out-Null
    try {
        $failed=$false
        try { Assert-RuntimeLinks $runtimeTest } catch { $failed=$true }
        Check $failed 'Chained Python junction accepted'
    } finally {
        [IO.Directory]::Delete($pythonAlias)
        [IO.Directory]::Delete($realPython)
    }
    # Exercise each model destination with relative/absolute symlinks and junctions.
    $profileTest=Join-Path $scratch 'profile'
    foreach ($pair in @(@('Stable-diffusion','checkpoints'),@('Stable-diffusion','diffusion_models'),@('Stable-diffusion','unet'),@('Lora','loras'),@('text_encoder','text_encoders'),@('text_encoder','clip'),@('VAE','vae'),@('ControlNet','controlnet'),@('upscale_models','upscale_models'),@('custom\nested','custom\nested'))) {
        $target=Join-Path $profileTest ('Documents\ComfyUI\models\' + $pair[1])
        $folder=Join-Path $runtimeTest ('forge-neo\models\' + $pair[0])
        New-Item -ItemType Directory -Path $target -Force | Out-Null
        foreach ($placement in @('root','child')) {
            $share=$folder
            if ($placement -eq 'child') {
                New-Item -ItemType Directory -Path $folder -Force | Out-Null
                $share=Join-Path $folder 'shared'
            }
            foreach ($mode in @('relative','absolute','junction')) {
                if ($mode -eq 'junction') {
                    New-Item -ItemType Junction -Path $share -Target $target | Out-Null
                } else {
                    $relative=if ($mode -eq 'relative') {'1'} else {'0'}
                    New-Item -ItemType Directory -Path ([IO.Path]::GetDirectoryName($share)) -Force | Out-Null
                    & python -c 'import os,sys; t,p,r=sys.argv[1:]; os.symlink(os.path.relpath(t,os.path.dirname(p)) if int(r) else t,p,target_is_directory=True)' $target $share $relative
                    if ($LASTEXITCODE -ne 0) { throw 'Could not create model test symlink' }
                }
                try { Assert-RuntimeLinks $runtimeTest $profileTest; Check $true "Model share accepted: $pair $placement $mode" }
                finally { [IO.Directory]::Delete($share) }
            }
            if ($placement -eq 'child') { [IO.Directory]::Delete($folder) }
        }
    }
    $wholeRuntime=Join-Path $scratch 'whole-runtime'
    $wholeLink=Join-Path $wholeRuntime 'forge-neo\models'
    $wholeTarget=Join-Path $profileTest 'Documents\ComfyUI\models'
    New-Item -ItemType Directory -Path ([IO.Path]::GetDirectoryName($wholeLink)) -Force | Out-Null
    New-Item -ItemType Junction -Path $wholeLink -Target $wholeTarget | Out-Null
    try { Assert-RuntimeLinks $wholeRuntime $profileTest; Check $true 'Whole models directory accepted' }
    finally { [IO.Directory]::Delete($wholeLink) }
    # Reject code aliases and prefix-lookalike destinations.
    foreach ($badShare in @('forge-neo\extensions\wrong','forge-neo\models\text_encoder\nested\wrong')) {
        $share=Join-Path $runtimeTest $badShare
        New-Item -ItemType Directory -Path ([IO.Path]::GetDirectoryName($share)) -Force | Out-Null
        $target=Join-Path $profileTest 'Documents\ComfyUI\models-unsafe\text_encoders'
        New-Item -ItemType Directory -Path $target -Force | Out-Null
        New-Item -ItemType Junction -Path $share -Target $target | Out-Null
        try {
            $failed=$false
            try { Assert-RuntimeLinks $runtimeTest $profileTest } catch { $failed=$true }
            Check $failed 'Code alias or outside model root accepted'
        } finally { [IO.Directory]::Delete($share) }
    }
    $profileTest=Join-Path $scratch 'profile'
    $sharedVae=Join-Path $profileTest 'Documents\ComfyUI\models\vae'
    $vaeAlias=Join-Path $runtimeTest 'forge-neo\models\VAE\vae'
    New-Item -ItemType Directory -Path $sharedVae -Force | Out-Null
    New-Item -ItemType Directory -Path ([IO.Path]::GetDirectoryName($vaeAlias)) -Force | Out-Null
    'preserve model' | Set-Content (Join-Path $sharedVae 'sentinel.txt')
    foreach ($relative in @('1','0')) {
        # Python uses Windows' unprivileged symlink API when Developer Mode is enabled.
        & python -c 'import os,sys; t,p,r=sys.argv[1:]; os.symlink(os.path.relpath(t,os.path.dirname(p)) if int(r) else t,p,target_is_directory=True)' $sharedVae $vaeAlias $relative
        if ($LASTEXITCODE -ne 0) { throw 'Could not create test symlink' }
        try {
            Assert-RuntimeLinks $runtimeTest $profileTest
            Check $true 'Approved VAE symbolic link accepted'
            Check ((Get-Content (Join-Path $sharedVae 'sentinel.txt')) -eq 'preserve model') 'Shared model changed'
        } finally { [IO.Directory]::Delete($vaeAlias) }
    }
    & python -c 'import os,sys; os.symlink(sys.argv[1],sys.argv[2],target_is_directory=True)' $existing $vaeAlias
    if ($LASTEXITCODE -ne 0) { throw 'Could not create test symlink' }
    try {
        $failed=$false
        try { Assert-RuntimeLinks $runtimeTest $profileTest } catch { $failed=$true }
        Check $failed 'VAE link to an unapproved destination accepted'
    } finally { [IO.Directory]::Delete($vaeAlias) }
    $codeAlias=Join-Path $runtimeTest 'forge-neo\extensions\vae'
    New-Item -ItemType Directory -Path ([IO.Path]::GetDirectoryName($codeAlias)) -Force | Out-Null
    & python -c 'import os,sys; os.symlink(sys.argv[1],sys.argv[2],target_is_directory=True)' $sharedVae $codeAlias
    if ($LASTEXITCODE -ne 0) { throw 'Could not create test symlink' }
    try {
        $failed=$false
        try { Assert-RuntimeLinks $runtimeTest $profileTest } catch { $failed=$true }
        Check $failed 'Code location symlink accepted'
    } finally { [IO.Directory]::Delete($codeAlias) }
    # A matching but missing model directory is not an approved share.
    $missingProfile=Join-Path $scratch 'missing-profile'
    $missingTarget=Join-Path $missingProfile 'Documents\ComfyUI\models\vae'
    & python -c 'import os,sys; os.symlink(sys.argv[1],sys.argv[2],target_is_directory=True)' $missingTarget $vaeAlias
    if ($LASTEXITCODE -ne 0) { throw 'Could not create test symlink' }
    try {
        $failed=$false
        try { Assert-RuntimeLinks $runtimeTest $missingProfile } catch { $failed=$true }
        Check $failed 'Missing VAE target accepted'
    } finally { [IO.Directory]::Delete($vaeAlias) }
    New-Item -ItemType Directory -Path ([IO.Path]::GetDirectoryName($missingTarget)) -Force | Out-Null
    New-Item -ItemType Junction -Path $missingTarget -Target $sharedVae | Out-Null
    & python -c 'import os,sys; os.symlink(sys.argv[1],sys.argv[2],target_is_directory=True)' $missingTarget $vaeAlias
    if ($LASTEXITCODE -ne 0) { throw 'Could not create test symlink' }
    try {
        $failed=$false
        try { Assert-RuntimeLinks $runtimeTest $missingProfile } catch { $failed=$true }
        Check $failed 'Chained VAE target accepted'
    } finally {
        [IO.Directory]::Delete($vaeAlias)
        [IO.Directory]::Delete($missingTarget)
    }
} finally {
    $resolved=[IO.Path]::GetFullPath($scratch)
    $tempPrefix=[IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd('\') + '\amd-safety-'
    if ($resolved.StartsWith($tempPrefix,[StringComparison]::OrdinalIgnoreCase)) {
        Remove-Item -LiteralPath $resolved -Recurse -Force
    }
}
Write-Host "PASS: $count safety assertions"

