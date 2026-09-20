# Black Uniforms and Police Cars Discovery Tests | Author: Joe "Gambit" Bradford
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$package = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../..'))
. (Join-Path $package 'Installer/Core.ps1')
$root = Join-Path ([IO.Path]::GetTempPath()) ('RcpDiscovery_' + [guid]::NewGuid().ToString('N'))
function Write-TestFile([string]$p,[string]$s) {
    [IO.Directory]::CreateDirectory((Split-Path -Parent $p)) | Out-Null
    [IO.File]::WriteAllText($p,$s)
}
function New-TestGame([string]$base,[string]$name) {
    $p = Join-Path $base ("steamapps/common/$name/PoliceChiefSimulator")
    Write-TestFile (Join-Path $p 'Binaries/Win64/PoliceChiefSimulator-Win64-Shipping.exe') 'test'
    [IO.Directory]::CreateDirectory((Join-Path $p 'Content/Paks')) | Out-Null
    return $p
}
try {
    $steam = Join-Path $root 'Steam'
    $extra = Join-Path $root "Drive D/Steam Library [games] & Joe's !"
    $expected = New-TestGame $extra 'PoliceChiefSimulator'
    Write-TestFile (Join-Path $steam 'steamapps/libraryfolders.vdf') ('"libraryfolders" { "0" { "path" "' + $extra.Replace('\','\\') + '" } }')
    Write-TestFile (Join-Path $extra 'steamapps/appmanifest_123.acf') '"AppState" { "name" "Police Chief Simulator" "installdir" "PoliceChiefSimulator" }'
    $found = @(Find-RcpLibraryGames @($steam) | Select-Object -Unique)
    if ($found.Count -ne 1 -or $found[0] -ne $expected) { throw 'Secondary library/manifest detection failed.' }
    Remove-Item -LiteralPath (Join-Path $extra 'steamapps/appmanifest_123.acf')
    $found = @(Find-RcpLibraryGames @($steam) | Select-Object -Unique)
    if ($found.Count -ne 1 -or $found[0] -ne $expected) { throw 'Common-folder fallback failed.' }
    Remove-Item -LiteralPath (Join-Path $steam 'steamapps/libraryfolders.vdf')
    Write-TestFile (Join-Path $steam 'config/libraryfolders.vdf') ('"LibraryFolders" { "1" "' + $extra.Replace('\','\\') + '" }')
    $found = @(Find-RcpLibraryGames @($steam) | Select-Object -Unique)
    if ($found.Count -ne 1 -or $found[0] -ne $expected) { throw 'Legacy library detection failed.' }
    $other = New-TestGame $steam 'Police Chief Simulator'
    $found = @(Find-RcpLibraryGames @($steam,$extra,$steam) | Select-Object -Unique)
    if ($found.Count -ne 2) { throw 'Multiple installs/deduplication failed.' }
    if (@(Find-RcpLibraryGames @((Join-Path $root 'missing'))).Count -ne 0) { throw 'Missing library handling failed.' }
    $launcher = Join-Path (Split-Path -Parent $expected) 'PoliceChiefSimulator.exe'
    Write-TestFile $launcher 'launcher'
    $exe = Join-Path $expected 'Binaries/Win64/PoliceChiefSimulator-Win64-Shipping.exe'
    $deep = Join-Path $expected 'Binaries/Win64/ue4ss/Mods/RoboCopGameplay/Scripts'
    [IO.Directory]::CreateDirectory($deep) | Out-Null
    $variants = @($expected,(Split-Path -Parent $expected),$launcher,$exe,(Split-Path -Parent $exe),$deep,
        (Join-Path $expected 'Content/Paks'),('"' + $expected + '"'),($expected + [IO.Path]::DirectorySeparatorChar),
        (Join-Path $extra 'steamapps/common'),$extra)
    foreach ($variant in $variants) {
        if ((Resolve-RcpGame $variant).Project -ne $expected) { throw "Selected-path resolution failed: $variant" }
    }
    $expanded = @(Find-RcpLibraryGames @((Join-Path $extra 'steamapps')) | Select-Object -Unique)
    if ($expanded.Count -ne 1 -or $expanded[0] -ne $expected) { throw 'steamapps root detection failed.' }
    $env:RCP_TEST_GAME_LOCATION = $expected
    if ((Resolve-RcpGame '%RCP_TEST_GAME_LOCATION%').Project -ne $expected) { throw 'Environment path expansion failed.' }
    $flatLibrary = Join-Path $root 'Flat library'
    $flatProject = Join-Path $flatLibrary 'steamapps/common/PoliceChiefSimulator'
    Write-TestFile (Join-Path $flatProject 'Binaries/Win64/PoliceChiefSimulator-Win64-Shipping.exe') 'test'
    [IO.Directory]::CreateDirectory((Join-Path $flatProject 'Content/Paks')) | Out-Null
    $flat = @(Find-RcpLibraryGames @($flatLibrary))
    if ($flat.Count -ne 1 -or $flat[0] -ne $flatProject) { throw 'Flat game layout discovery failed.' }
    Remove-Item -LiteralPath (Join-Path $flatProject 'Content/Paks') -Recurse
    $incomplete = @(Find-RcpLibraryGames @($flatLibrary))
    if ($incomplete.Count -ne 1) { throw 'An incomplete game was hidden during discovery.' }
    try { Resolve-RcpGame $flatProject | Out-Null; throw 'Missing Paks was accepted.' }
    catch { if ($_.Exception.Message -notmatch 'original game folder.*missing or inaccessible') { throw } }
    $log = Join-Path $root 'discovery.log'
    $script:RcpDiscoveryLog = $log
    Resolve-RcpGame $exe | Out-Null
    $logged = [IO.File]::ReadAllText($log)
    if (-not $logged.Contains($exe) -or -not $logged.Contains('EXE exists=True') -or -not $logged.Contains('PAKS exists=True')) { throw 'Path diagnostics are incomplete.' }
    $script:RcpDiscoveryLog = $null
    $scriptText = [IO.File]::ReadAllText((Join-Path $package 'Installer/Install.ps1'))
    if ($scriptText.Contains('Read-Host')) { throw 'A typing/confirmation prompt remains.' }
    foreach ($file in @(Get-ChildItem -LiteralPath (Join-Path $package 'Installer') -Filter '*.ps1')) {
        $tokens=$null; $errors=$null
        [Management.Automation.Language.Parser]::ParseFile($file.FullName,[ref]$tokens,[ref]$errors) | Out-Null
        if ($errors.Count) { throw $errors[0] }
    }
    Write-Host 'PASS: Steam libraries, manifests, missing manifests, flat/nested game layouts, selected EXE/launcher/folder/deep mod folder, quoted and expanded paths, missing Paks diagnosis, trace logging, no console prompt, syntax.'
} finally { if (Test-Path -LiteralPath $root) { Remove-Item -LiteralPath $root -Recurse -Force } }
