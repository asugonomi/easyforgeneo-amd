Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Assert-NoLinks([string]$Path) {
    $p = [IO.Path]::GetFullPath($Path)
    while ($p) {
        if (Test-Path -LiteralPath $p) {
            if ((Get-Item -LiteralPath $p -Force).Attributes -band [IO.FileAttributes]::ReparsePoint) {
                throw "Junction/symlink is not allowed: $p"
            }
        }
        $parent = [IO.Directory]::GetParent($p)
        if ($null -eq $parent) { break }
        $p = $parent.FullName
    }
}

function Get-GpuPlan($Gpu, $Manifest) {
    if ($Gpu.PNPDeviceID -notmatch '^PCI\\VEN_1002&') {
        return [pscustomobject]@{ backend='blocked'; arch=''; tier='not-amd'; reason='AMD PCI GPU not detected' }
    }
    $name = ($Gpu.Name -replace '(?i)\(TM\)|\(R\)', '' -replace '\s+', ' ').Trim()
    foreach ($rule in $Manifest.gpus) {
        if ($name -match $rule.pattern) {
            return [pscustomobject]@{ backend='rocm'; arch=$rule.arch; tier=$rule.tier; reason=$rule.note }
        }
    }
    return [pscustomobject]@{ backend='blocked'; arch=''; tier='unknown'; reason='GPU model unknown or outside this release: see README' }
}

function Invoke-Checked([string]$Exe, [string[]]$Arguments) {
    Write-Host ('> ' + $Exe + ' ' + ($Arguments -join ' '))
    # PS 5.1 treats native stderr as ErrorRecord. Preserve output and check the actual exit code.
    $saved = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try { & $Exe @Arguments 2>&1 | ForEach-Object { Write-Host "$_" }; $code = $LASTEXITCODE }
    finally { $ErrorActionPreference = $saved }
    if ($code -ne 0) { throw "Command failed (exit=$code): $Exe" }
}

function Get-VerifiedZip($Spec, [string]$Destination, [string]$Cache) {
    Assert-NoLinks $Destination
    if (Test-Path -LiteralPath $Destination) { throw "Destination already exists: $Destination" }
    $archive = Join-Path $Cache ($Spec.sha256 + '.zip')
    if (!(Test-Path -LiteralPath $archive)) {
        Invoke-WebRequest -UseBasicParsing -Uri $Spec.url -OutFile ($archive + '.part')
        Move-Item -LiteralPath ($archive + '.part') -Destination $archive
    }
    if ((Get-FileHash -LiteralPath $archive -Algorithm SHA256).Hash -ne $Spec.sha256) {
        throw "SHA256 mismatch. Do not run this download. Remove only this archive and retry: $archive"
    }
    # Reject traversal entries before extraction.
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $zip = [IO.Compression.ZipFile]::OpenRead($archive)
    try {
        $prefix = [IO.Path]::GetFullPath($Destination).TrimEnd('\') + '\'
        foreach ($entry in $zip.Entries) {
            $target = [IO.Path]::GetFullPath((Join-Path $Destination $entry.FullName))
            if (!$target.StartsWith($prefix, [StringComparison]::OrdinalIgnoreCase)) { throw 'Unsafe ZIP entry' }
        }
    } finally { $zip.Dispose() }
    Expand-Archive -LiteralPath $archive -DestinationPath $Destination
}

function Set-LocalEnvironment([string]$Runtime) {
    # Only the current PowerShell process and its children are affected.
    foreach ($item in @(Get-ChildItem Env: | Where-Object Name -Match '^(UV_|PIP_|GIT_)')) {
        [Environment]::SetEnvironmentVariable($item.Name, $null, 'Process')
    }
    foreach ($key in @('PYTHONHOME','PYTHONPATH','VIRTUAL_ENV','CONDA_PREFIX','COMMANDLINE_ARGS',
        'TORCH_COMMAND','TORCH_INDEX_URL','REQS_FILE','CUDA_VISIBLE_DEVICES','HIP_VISIBLE_DEVICES',
        'ROCR_VISIBLE_DEVICES','HSA_OVERRIDE_GFX_VERSION','HIP_PATH','ROCM_PATH','ZLUDA_PATH',
        'PIP_INDEX_URL','PIP_EXTRA_INDEX_URL','PIP_TARGET','PIP_PREFIX','PIP_USER','PIP_CONSTRAINT',
        'UV_INDEX','UV_DEFAULT_INDEX','UV_EXTRA_INDEX_URL','UV_INDEX_URL')) {
        [Environment]::SetEnvironmentVariable($key, $null, 'Process')
    }
    $env:PYTHONNOUSERSITE='1'; $env:PYTHONUTF8='1'; $env:PYTHONUNBUFFERED='1'
    $env:PIP_CONFIG_FILE='NUL'; $env:UV_NO_CONFIG='1'
    $env:UV_CACHE_DIR=Join-Path $Runtime 'cache\uv'
    $env:UV_PYTHON_INSTALL_DIR=Join-Path $Runtime 'python'
    $env:UV_PYTHON_BIN_DIR=Join-Path $Runtime 'python-bin'
    $env:PIP_CACHE_DIR=Join-Path $Runtime 'cache\pip'
    $env:HF_HOME=Join-Path $Runtime 'cache\huggingface'
    $env:TORCH_HOME=Join-Path $Runtime 'cache\torch'
    $env:TEMP=Join-Path $Runtime 'temp'; $env:TMP=$env:TEMP
    New-Item -ItemType Directory -Force $env:TEMP | Out-Null
    $env:PATH="$(Join-Path $Runtime 'git\cmd');$env:SystemRoot\System32;$env:SystemRoot;$env:SystemRoot\System32\Wbem"
    $env:GIT_PYTHON_GIT_EXECUTABLE=Join-Path $Runtime 'git\cmd\git.exe'
    $env:GIT_CONFIG_GLOBAL='NUL'; $env:GIT_CONFIG_NOSYSTEM='1'; $env:GIT_TERMINAL_PROMPT='0'
    $env:GRADIO_ANALYTICS_ENABLED='False'
}
