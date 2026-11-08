[CmdletBinding()]
param(
    [ValidateSet('Detect','Install','Launch','Verify','Generate','Extensions')][string]$Action='Detect',
    [ValidateSet('Auto','ROCm','DirectML','ZLUDA')][string]$Backend='Auto',
    [int]$GpuIndex=-1,
    [switch]$Experimental,
    [switch]$SafeMode,
    [switch]$NonInteractive,
    [ValidateRange(1024,65535)][int]$Port=7865
)
. "$PSScriptRoot\Common.ps1"
$root = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$runtime = Join-Path $root 'runtime'
$logStarted=$false; $lock=$null; $exitCode=0
try {
    Assert-NoLinks $root
    # Reject links anywhere under managed runtime, including venv and model junctions.
    Assert-NoLinks $runtime
    if (Test-Path -LiteralPath $runtime) {
        $links = @(Get-ChildItem -LiteralPath $runtime -Force -Recurse -Attributes ReparsePoint -ErrorAction Stop)
        if ($links.Count) { throw 'runtime contains a junction/symlink. Use a separate fresh directory.' }
    }
    $manifest = Get-Content -LiteralPath "$root\manifest.json" -Raw | ConvertFrom-Json
    if (!(Test-Path -LiteralPath "$root\logs")) { New-Item -ItemType Directory "$root\logs" | Out-Null }
    Assert-NoLinks "$root\logs"
    $log = Join-Path $root ('logs\' + $Action + '-' + (Get-Date -Format 'yyyyMMdd-HHmmss-fff') + '.log')
    Start-Transcript -LiteralPath $log | Out-Null; $logStarted=$true
    $lockName = if ($Action -eq 'Generate') { '.generation.lock' } else { '.operation.lock' }
    Assert-NoLinks (Join-Path $root $lockName)
    $lock = [IO.File]::Open((Join-Path $root $lockName), 'OpenOrCreate', 'ReadWrite', 'None')
    Write-Host "EasyForgeNeo AMD companion / $Action / recipe $($manifest.recipe)"
    if (![Environment]::Is64BitOperatingSystem -or $env:PROCESSOR_ARCHITECTURE -ne 'AMD64') { throw 'Windows x64 is required.' }
    $os = Get-CimInstance Win32_OperatingSystem
    $gpus = @(Get-CimInstance Win32_VideoController)
    $inventory = for ($i=0; $i -lt $gpus.Count; $i++) {
        $plan=Get-GpuPlan $gpus[$i] $manifest
        [pscustomobject]@{ index=$i; name=$gpus[$i].Name; pnp=$gpus[$i].PNPDeviceID;
            driver=$gpus[$i].DriverVersion; backend=$plan.backend; arch=$plan.arch; tier=$plan.tier; reason=$plan.reason }
    }
    $inventory | Format-Table index,name,driver,arch,tier -AutoSize | Out-Host
    $inventory | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath "$root\logs\gpu-inventory.json" -Encoding UTF8
    if ($Action -eq 'Detect') {
        Write-Host 'ROCm: supported profiles below. DirectML/ZLUDA: blocked for this Neo recipe; see README.'
        $inventory | Format-List | Out-Host
        return
    }
    if ($Backend -in @('DirectML','ZLUDA')) {
        throw "$Backend is not a compatible automatic install route for this pinned Forge Neo. See README > backend comparison. Nothing installed."
    }
    if ([int]$os.BuildNumber -lt 26200) { throw 'ROCm 10.1 recipe requires Windows 11 25H2 (build 26200+) per AMD matrix.' }
    $marker=Join-Path $runtime 'owner.json'
    $stateFile=Join-Path $runtime 'state.json'
    $python=Join-Path $runtime 'venv\Scripts\python.exe'
    $neo=Join-Path $runtime 'forge-neo'
    if ($Action -eq 'Install') {
        $admin=([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
        if ($admin) { throw 'Run as a normal user, not Administrator.' }
        if ($root -notmatch '^[A-Za-z]:\\[A-Za-z0-9_\\.-]+$' -or $root.Length -gt 100) {
            throw 'Extract to a short ASCII path, e.g. D:\EasyForgeNeo-AMD (no spaces).'
        }
        if (Test-Path -LiteralPath $runtime) {
            throw 'runtime already exists. No overwrite/resume is performed. Use Launch/Verify, or extract a new copy to another folder after a failed install.'
        }
        $eligible=@($inventory | Where-Object backend -eq 'rocm')
        if (!$eligible.Count) { throw 'No mapped AMD GPU. See README compatibility table. No automatic fallback or architecture guessing.' }
        if ($GpuIndex -lt 0) {
            if ($eligible.Count -eq 1) { $GpuIndex=$eligible[0].index }
            elseif ($NonInteractive) { throw 'Multiple AMD GPUs: pass -GpuIndex from Detect output.' }
            else { $GpuIndex=[int](Read-Host 'Select AMD GPU index from the table') }
        }
        $selected=@($eligible | Where-Object index -eq $GpuIndex)
        if ($selected.Count -ne 1) { throw 'Selected GPU is not eligible.' }
        $selected=$selected[0]
        if ($selected.tier -eq 'experimental' -and !$Experimental) {
            if ($NonInteractive -or (Read-Host 'This GPU is a TheRock development-qualified target, not a verified Neo configuration. Type EXPERIMENTAL to continue') -cne 'EXPERIMENTAL') {
                throw 'Experimental GPU requires explicit opt-in (-Experimental).'
            }
        }
        Write-Host 'AMD prerequisite: Windows 11 25H2 + Adrenalin 26.10.41.05 (or matching CDE CPR 26.10.48).'
        Write-Host 'WMI driver numbers use another format. Check the AMD Software version yourself; GPU kernel verification follows.'
        Write-Host "Install ROCm $($manifest.rocm), $($selected.name) / $($selected.arch) in $runtime"
        Write-Host 'Download size: several GB; allow at least 30 GB free plus models. Existing installations will not be imported.'
        if (!$NonInteractive -and (Read-Host 'Start download and setup? [Y/N]') -notmatch '^(?i)y(es)?$') { return }
        $drive=Get-PSDrive -Name $root.Substring(0,1)
        if ($drive.Free -lt 30GB) { throw 'At least 30 GB free required before model download.' }
        New-Item -ItemType Directory $runtime | Out-Null
        @{ product='easyforgeneo-amd-companion'; recipe=$manifest.recipe; root=$root } | ConvertTo-Json | Set-Content $marker -Encoding UTF8
        $cache=Join-Path $runtime 'downloads'; New-Item -ItemType Directory $cache | Out-Null
        [Net.ServicePointManager]::SecurityProtocol=[Net.SecurityProtocolType]::Tls12
        Get-VerifiedZip $manifest.uv "$runtime\uv" $cache
        Get-VerifiedZip $manifest.git "$runtime\git" $cache
        Set-LocalEnvironment $runtime
        $uv=Join-Path $runtime 'uv\uv.exe'
        $git=$env:GIT_PYTHON_GIT_EXECUTABLE
        Invoke-Checked $uv @('python','install',$manifest.python,'--no-progress','--no-bin','--no-registry')
        Invoke-Checked $uv @('venv','--python',$manifest.python,'--managed-python','--seed','--link-mode','copy',"$runtime\venv")
        Invoke-Checked $git @('init',$neo)
        Invoke-Checked $git @('-C',$neo,'remote','add','origin',$manifest.forge.url)
        Invoke-Checked $git @('-C',$neo,'fetch','--depth','1','origin',$manifest.forge.commit)
        Invoke-Checked $git @('-C',$neo,'checkout','--detach','FETCH_HEAD')
        $commit=(& $git -C $neo rev-parse HEAD).Trim()
        if ($LASTEXITCODE -ne 0 -or $commit -ne $manifest.forge.commit) { throw 'Forge commit verification failed.' }
        $extra="device-$($selected.arch)"
        Invoke-Checked $python @('-m','pip','install','--index-url',$manifest.amdIndex,
            "torch[$extra]==$($manifest.torch)","torchvision[$extra]==$($manifest.torchvision)")
        $constraints=Join-Path $runtime 'constraints.txt'
        @("torch==$($manifest.torch)","torchvision==$($manifest.torchvision)") | Set-Content $constraints -Encoding ASCII
        Invoke-Checked $python @('-m','pip','install','--index-url','https://pypi.org/simple','-c',$constraints,
            '-r',"$root\requirements-amd.txt")
        Invoke-Checked $python @('-m','pip','check')
        $state=@{ recipe=$manifest.recipe; backend='rocm'; arch=$selected.arch; gpuName=$selected.name;
            pnp=$selected.pnp; forgeCommit=$commit; installed=(Get-Date -Format o); port=$Port }
        $state | ConvertTo-Json | Set-Content $stateFile -Encoding UTF8
        Invoke-Checked $python @("$PSScriptRoot\runtime.py",'verify','--root',$runtime)
        & $python -m pip freeze | Set-Content "$runtime\installed-packages.txt" -Encoding UTF8
        if ($LASTEXITCODE -ne 0) { throw 'pip freeze failed' }
        'complete' | Set-Content "$runtime\setup-complete.txt" -Encoding ASCII
        Write-Host 'Setup and GPU math checks passed. Run 03_Launch.bat. Actual image generation is a separate validation.'
    } else {
        if (!(Test-Path $marker) -or !(Test-Path "$runtime\setup-complete.txt")) { throw 'No completed owned installation. Read README recovery instructions.' }
        $owner=Get-Content $marker -Raw | ConvertFrom-Json
        if ($owner.product -ne 'easyforgeneo-amd-companion' -or $owner.root -ne $root -or $owner.recipe -ne $manifest.recipe) { throw 'Ownership/path/recipe mismatch. Do not move an installed environment.' }
        Set-LocalEnvironment $runtime
        $state=Get-Content $stateFile -Raw | ConvertFrom-Json
        if (!@($inventory | Where-Object pnp -eq $state.pnp).Count) { throw 'Configured AMD GPU is no longer present.' }
        $head=(& $env:GIT_PYTHON_GIT_EXECUTABLE -C $neo rev-parse HEAD).Trim()
        if ($LASTEXITCODE -ne 0 -or $head -ne $manifest.forge.commit) { throw 'Forge revision changed. Use a separate fresh install.' }
        if ($Action -eq 'Launch') {
            $launchArgs=@("$PSScriptRoot\runtime.py",'launch','--root',$runtime,'--port',"$Port")
            if ($SafeMode) { $launchArgs += '--safe-mode' }
            Invoke-Checked $python $launchArgs
        }
        elseif ($Action -eq 'Extensions') {
            if (!$NonInteractive -and (Read-Host 'Install the 14 EasyForgeNeo extensions (experimental on AMD)? [Y/N]') -notmatch '^(?i)y(es)?$') { return }
            Invoke-Checked $python @("$PSScriptRoot\extensions.py",'--root',$runtime)
        }
        elseif ($Action -eq 'Verify') {
            Invoke-Checked $python @('-m','pip','check')
            Invoke-Checked $python @("$PSScriptRoot\runtime.py",'verify','--root',$runtime)
        } else { Invoke-Checked $python @("$PSScriptRoot\runtime.py",'generate','--root',$runtime,'--port',"$Port") }
    }
} catch {
    $exitCode=1
    Write-Host "`n[FAILED] $($_.Exception.Message)" -ForegroundColor Red
    Write-Host 'See README troubleshooting. Do not replace system DLLs or run the NVIDIA installer in this directory.'
    if ($logStarted) { Write-Host "Log: $log" }
} finally {
    if ($null -ne $lock) { $lock.Dispose() }
    if ($logStarted) { Stop-Transcript | Out-Null }
}
exit $exitCode
