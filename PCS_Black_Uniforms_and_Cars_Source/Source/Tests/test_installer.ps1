# Black Uniforms and Police Cars Installer Tests | Author: Joe "Gambit" Bradford
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$package = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../..'))
. (Join-Path $package 'Installer/Core.ps1')
$root = Join-RcpPath ([IO.Path]::GetTempPath()) ('Black_Test_' + [Guid]::NewGuid().ToString('N'))
function Assert-Check($ok,[string]$reason) { if (-not $ok) { throw $reason } }
try {
    $project = Join-RcpPath $root "Joe's ! [PCS]/PoliceChiefSimulator"
    [IO.Directory]::CreateDirectory((Join-RcpPath $project 'Binaries/Win64')) | Out-Null
    [IO.File]::WriteAllText((Join-RcpPath $project 'Binaries/Win64/PoliceChiefSimulator-Win64-Shipping.exe'),'fixture')
    [IO.Directory]::CreateDirectory((Join-RcpPath $project 'Content/Paks/~mods')) | Out-Null
    $game = Resolve-RcpGame $project
    $other = Join-RcpPath $game.Paks '~mods/RoboCop_Worker02_P.pak'
    [IO.File]::WriteAllText($other,'other mod preserved')
    $first = Install-BlackAssets $package $game
    Assert-Check ($first.Changed -eq 9) 'Fresh install must write all nine assets.'
    Assert-Check ((Install-BlackAssets $package $game).Changed -eq 0) 'Repeat installation must be idempotent.'
    Assert-Check ([IO.File]::ReadAllText($other) -eq 'other mod preserved') 'Other mod changed.'
    foreach ($ext in @('pak','utoc','ucas')) { Remove-Item -LiteralPath (Join-RcpPath $first.Destination ("zz_PCS_Chief_Uniform_P.$ext")) }
    Assert-Check ((Install-BlackAssets $package $game).Changed -eq 3) 'Upgrade from six-file package must add Chief assets.'
    $target = Join-RcpPath $first.Destination 'zz_PCS_Black_Uniforms_P.pak'
    [IO.File]::WriteAllText($target,'old texture mod')
    $upgrade = Install-BlackAssets $package $game
    Assert-Check ($upgrade.Changed -eq 1) 'Upgrade should replace only changed assets.'
    Assert-Check ([IO.File]::ReadAllText((Join-RcpPath $upgrade.Backup 'zz_PCS_Black_Uniforms_P.pak')) -eq 'old texture mod') 'Old asset backup missing.'
    $broken = Join-RcpPath $root 'BrokenPackage'
    [IO.Directory]::CreateDirectory((Join-RcpPath $broken 'Installer')) | Out-Null
    Copy-Item -LiteralPath (Join-RcpPath $package 'Installer/manifest.json') -Destination (Join-RcpPath $broken 'Installer/manifest.json')
    $rejected = $false
    try { Install-BlackAssets $broken $game | Out-Null } catch { $rejected=$true }
    Assert-Check $rejected 'Missing payload was accepted.'
    Assert-Check ((Install-BlackAssets $package $game).Changed -eq 0) 'Rejected package changed assets.'
    $targets = @(Get-ChildItem -LiteralPath $first.Destination -Filter 'zz_PCS_*' -File)
    foreach ($file in $targets) { [IO.File]::WriteAllText($file.FullName,('previous '+$file.Name)) }
    $script:failOnce = $true
    function Copy-Item {
        param([string]$LiteralPath,[string]$Destination,[switch]$Force)
        if ($script:failOnce -and $LiteralPath -match 'PCS_Black_Stage_' -and $Destination -like '*.ucas') {
            $script:failOnce = $false
            [IO.File]::WriteAllText($Destination,'partial write')
            throw 'Injected copy failure'
        }
        Microsoft.PowerShell.Management\Copy-Item -LiteralPath $LiteralPath -Destination $Destination -Force:$Force
    }
    $rejected = $false
    try { Install-BlackAssets $package $game | Out-Null } catch { $rejected=$true }
    Remove-Item Function:Copy-Item
    Assert-Check $rejected 'Injected write failure did not stop installation.'
    foreach ($file in $targets) {
        Assert-Check ([IO.File]::ReadAllText($file.FullName) -eq ('previous '+$file.Name)) 'Rollback failed.'
    }
    Assert-Check ([IO.File]::ReadAllText($other) -eq 'other mod preserved') 'Rollback changed unrelated mod.'
    Write-Host 'PASS: fresh install, rerun, upgrade, verified backup, missing payload rejection, partial-write rollback, unrelated mod preserved, special-character path.'
} finally {
    if (Test-Path Function:Copy-Item) { Remove-Item Function:Copy-Item }
    if ([IO.Directory]::Exists($root)) { Remove-Item -LiteralPath $root -Recurse -Force }
}
