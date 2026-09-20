# Black Uniforms and Police Cars v1.1.0 | Author: Joe "Gambit" Bradford
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'Discovery.ps1')

function Get-BlackHash([string]$Path) {
    return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()
}

function Install-BlackAssets([string]$Package, $Game) {
    if (@(Get-Process -Name 'PoliceChiefSimulator-Win64-Shipping','PoliceChiefSimulator' -ErrorAction SilentlyContinue).Count) {
        throw 'Close Police Chief Simulator before installing.'
    }
    $manifest = Get-Content -LiteralPath (Join-RcpPath $Package 'Installer/manifest.json') -Raw | ConvertFrom-Json
    $expected = @()
    foreach ($stem in @('zz_PCS_Black_Uniforms_P','zz_PCS_Black_PoliceCar_P','zz_PCS_Chief_Uniform_P')) {
        foreach ($ext in @('pak','utoc','ucas')) { $expected += "$stem.$ext" }
    }
    $files = @($manifest.files)
    if ($files.Count -ne 9 -or @($files.name | Sort-Object -Unique).Count -ne 9) { throw 'Invalid package manifest.' }
    $destination = Join-RcpPath $Game.Paks '~mods'
    foreach ($entry in $files) {
        if ($expected -cnotcontains $entry.name) { throw 'Unexpected package filename.' }
        $source = Join-RcpPath $Package ("Payload/~mods/" + $entry.name)
        if (-not [IO.File]::Exists($source)) { throw "Missing $($entry.name). Extract the entire player ZIP first." }
        if ((Get-Item -LiteralPath $source).Length -ne $entry.size -or (Get-BlackHash $source) -ne $entry.sha256) { throw "Package integrity check failed: $($entry.name)" }
        $target = Join-RcpPath $destination $entry.name
        if (Test-Path -LiteralPath $target) {
            $item = Get-Item -LiteralPath $target -Force
            if ($item.PSIsContainer -or ($item.Attributes -band [IO.FileAttributes]::ReparsePoint)) { throw "Unexpected destination item: $target" }
        }
    }
    $stage = Join-RcpPath ([IO.Path]::GetTempPath()) ('PCS_Black_Stage_' + [Guid]::NewGuid().ToString('N'))
    $backup = Join-RcpPath $Game.Project ('PCS_Black_Uniforms_Backups/' + (Get-Date -Format 'yyyyMMdd_HHmmss_fff') + '_' + [Guid]::NewGuid().ToString('N'))
    $changes = [Collections.Generic.List[object]]::new()
    $committed = [Collections.Generic.List[object]]::new()
    try {
        [IO.Directory]::CreateDirectory($stage) | Out-Null
        foreach ($entry in $files) {
            $target = Join-RcpPath $destination $entry.name
            if ([IO.File]::Exists($target) -and (Get-BlackHash $target) -eq $entry.sha256) { continue }
            $source = Join-RcpPath $Package ("Payload/~mods/" + $entry.name)
            $staged = Join-RcpPath $stage $entry.name
            Copy-Item -LiteralPath $source -Destination $staged
            if ((Get-BlackHash $staged) -ne $entry.sha256) { throw 'Staged file verification failed.' }
            $existed = [IO.File]::Exists($target)
            $saved = Join-RcpPath $backup $entry.name
            if ($existed) {
                [IO.Directory]::CreateDirectory($backup) | Out-Null
                Copy-Item -LiteralPath $target -Destination $saved
                if ((Get-BlackHash $saved) -ne (Get-BlackHash $target)) { throw 'Backup verification failed.' }
            }
            $changes.Add([pscustomobject]@{Target=$target; Staged=$staged; Saved=$saved; Existed=$existed; Hash=$entry.sha256})
        }
        [IO.Directory]::CreateDirectory($destination) | Out-Null
        foreach ($change in $changes) {
            $committed.Add($change)
            Copy-Item -LiteralPath $change.Staged -Destination $change.Target -Force
            if ((Get-BlackHash $change.Target) -ne $change.Hash) { throw 'Installed file verification failed.' }
        }
        return [pscustomobject]@{Destination=$destination; Changed=$changes.Count; Backup=$(if ([IO.Directory]::Exists($backup)) {$backup} else {'No existing files needed replacement.'})}
    } catch {
        $reason = $_.Exception.Message
        $restoreErrors = [Collections.Generic.List[string]]::new()
        for ($i=$committed.Count-1; $i -ge 0; $i--) {
            $change = $committed[$i]
            try {
                if ($change.Existed) {
                    Copy-Item -LiteralPath $change.Saved -Destination $change.Target -Force
                    if ((Get-BlackHash $change.Target) -ne (Get-BlackHash $change.Saved)) { throw 'Restored file differs from backup.' }
                } elseif ([IO.File]::Exists($change.Target)) { Remove-Item -LiteralPath $change.Target -Force }
            } catch { $restoreErrors.Add($_.Exception.Message) }
        }
        if ($restoreErrors.Count) { throw "$reason. Automatic restoration could not finish. Backups: $backup. $($restoreErrors -join '; ')" }
        throw "$reason. Any changed mod files were restored."
    } finally {
        if ([IO.Directory]::Exists($stage)) { Remove-Item -LiteralPath $stage -Recurse -Force -ErrorAction SilentlyContinue }
    }
}
