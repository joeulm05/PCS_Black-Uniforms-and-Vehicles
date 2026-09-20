# Black Uniforms and Police Cars Installer v1.1.0 | Author: Joe "Gambit" Bradford
Set-StrictMode -Version Latest
$script:RcpDiscoveryLog = $null

function Join-RcpPath([string]$Base, [string]$Child) {
    $result = $Base
    foreach ($part in ($Child -split '[\\/]')) {
        if ($part) { $result = [IO.Path]::Combine($result, $part) }
    }
    return $result
}

function Write-RcpDiscovery([string]$Message) {
    if ($script:RcpDiscoveryLog) {
        Add-Content -LiteralPath $script:RcpDiscoveryLog -Value $Message -Encoding UTF8
    }
}

function ConvertTo-RcpPath([string]$Path) {
    if ([string]::IsNullOrWhiteSpace($Path)) { throw 'No game location was supplied.' }
    $clean = [Environment]::ExpandEnvironmentVariables($Path.Trim().Trim('"'))
    $clean = $clean.Replace([char]47, [IO.Path]::DirectorySeparatorChar)
    return [IO.Path]::GetFullPath($clean)
}

function Get-RcpGameFromExe([string]$Exe) {
    $exists = [IO.File]::Exists($Exe)
    Write-RcpDiscovery "EXE exists=$exists | $Exe"
    if (-not $exists) { return }
    $file = [IO.FileInfo]::new($Exe)
    if ($file.Name -ine 'PoliceChiefSimulator-Win64-Shipping.exe') { return }
    $bin = $file.Directory
    if ($null -eq $bin.Parent -or $null -eq $bin.Parent.Parent) { return }
    if ($bin.Name -ine 'Win64' -or $bin.Parent.Name -ine 'Binaries') { return }
    $project = $bin.Parent.Parent.FullName
    $paks = Join-RcpPath $project 'Content/Paks'
    Write-RcpDiscovery "PAKS exists=$([IO.Directory]::Exists($paks)) | $paks"
    return [pscustomobject]@{Project=$project; Bin=$bin.FullName; Exe=$file.FullName; Paks=$paks}
}

function Find-RcpGamesAt([string]$Directory) {
    foreach ($relative in @('Binaries/Win64/PoliceChiefSimulator-Win64-Shipping.exe', 'PoliceChiefSimulator/Binaries/Win64/PoliceChiefSimulator-Win64-Shipping.exe')) {
        Get-RcpGameFromExe (Join-RcpPath $Directory $relative)
    }
}

function Resolve-RcpGame([string]$Path) {
    $clean = ConvertTo-RcpPath $Path
    Write-RcpDiscovery "SELECTED | $clean"
    if (-not [IO.Directory]::Exists($clean) -and -not [IO.File]::Exists($clean)) {
        throw "The selected location does not exist or is inaccessible: $clean"
    }
    $found = @()
    $directory = $clean
    if ([IO.File]::Exists($clean)) {
        $found = @(Get-RcpGameFromExe $clean)
        $directory = [IO.Path]::GetDirectoryName($clean)
    }
    $candidate = $directory
    while ($found.Count -eq 0 -and $candidate) {
        $found = @(Find-RcpGamesAt $candidate | Sort-Object -Property Project -Unique)
        $parent = [IO.Directory]::GetParent($candidate)
        if ($null -eq $parent) { break }
        $candidate = $parent.FullName
    }
    if ($found.Count -eq 0) {
        $queue = [Collections.Generic.Queue[object]]::new()
        $queue.Enqueue([pscustomobject]@{Path=$directory; Depth=0})
        $visited = 0
        while ($queue.Count -gt 0 -and $visited -lt 512) {
            $entry = $queue.Dequeue()
            $visited++
            $here = @(Find-RcpGamesAt $entry.Path)
            $found += $here
            if ($here.Count -gt 0 -or $entry.Depth -ge 3) { continue }
            foreach ($child in @(Get-ChildItem -LiteralPath $entry.Path -Directory -Force -ErrorAction SilentlyContinue)) {
                if (($child.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) { continue }
                if ($child.Name -in @('Engine','Payload','Runtime','PCS_Black_Uniforms_Backups')) { continue }
                $queue.Enqueue([pscustomobject]@{Path=$child.FullName; Depth=($entry.Depth + 1)})
            }
        }
        $found = @($found | Sort-Object -Property Project -Unique)
    }
    if ($found.Count -gt 1) { throw "Multiple game installations exist below '$clean'. Select the intended PoliceChiefSimulator-Win64-Shipping.exe." }
    if ($found.Count -eq 0) {
        throw "No PoliceChiefSimulator-Win64-Shipping.exe was found at or near '$clean'. In Steam use Manage > Browse local files, then select PoliceChiefSimulator > Binaries > Win64 > PoliceChiefSimulator-Win64-Shipping.exe."
    }
    $game = $found[0]
    if (-not [IO.Directory]::Exists($game.Paks)) {
        throw "Found the game executable at '$($game.Exe)', but the original game folder '$($game.Paks)' is missing or inaccessible. Restore the original game files with Steam > Properties > Installed Files > Verify integrity, then run the installer again."
    }
    return $game
}

function Find-RcpLibraryGames([string[]]$Roots) {
    $libraries = [Collections.Generic.List[string]]::new()
    foreach ($root in @($Roots | Select-Object -Unique)) {
        if (-not $root -or -not [IO.Directory]::Exists($root)) { continue }
        $root = ConvertTo-RcpPath $root
        if ([IO.Path]::GetFileName($root.TrimEnd([IO.Path]::DirectorySeparatorChar)) -ieq 'steamapps') {
            $root = [IO.Directory]::GetParent($root).FullName
        }
        $libraries.Add($root)
        Write-RcpDiscovery "STEAM ROOT | $root"
        foreach ($relative in @('steamapps/libraryfolders.vdf','config/libraryfolders.vdf')) {
            $vdf = Join-RcpPath $root $relative
            if (-not [IO.File]::Exists($vdf)) { continue }
            try {
                $raw = [IO.File]::ReadAllText($vdf)
                foreach ($match in [regex]::Matches($raw, '"(?:path|[0-9]+)"\s+"([^"\r\n]+)"')) {
                    $location = $match.Groups[1].Value.Replace('\\','\')
                    if ([IO.Path]::IsPathRooted($location)) { $libraries.Add((ConvertTo-RcpPath $location)) }
                }
            } catch { Write-RcpDiscovery "STEAM LIST ERROR | $vdf | $($_.Exception.Message)" }
        }
    }
    foreach ($root in @($libraries | Select-Object -Unique)) {
        $apps = Join-RcpPath $root 'steamapps'
        if (-not [IO.Directory]::Exists($apps)) { continue }
        $common = Join-RcpPath $apps 'common'
        $candidates = [Collections.Generic.List[string]]::new()
        $candidates.Add((Join-RcpPath $common 'Police Chief Simulator'))
        foreach ($manifest in @(Get-ChildItem -LiteralPath $apps -Filter 'appmanifest_*.acf' -File -ErrorAction SilentlyContinue)) {
            try {
                $raw = [IO.File]::ReadAllText($manifest.FullName)
                if ($raw -match '(?i)"name"\s+"Police\s*Chief\s*Simulator[^"\r\n]*"' -and $raw -match '"installdir"\s+"([^"\r\n]+)"') {
                    $dir = $Matches[1]
                    if ($dir -notmatch '[\\/]' -and $dir -ne '..') { $candidates.Add((Join-RcpPath $common $dir)) }
                }
            } catch { Write-RcpDiscovery "MANIFEST ERROR | $($manifest.FullName) | $($_.Exception.Message)" }
        }
        if ([IO.Directory]::Exists($common)) {
            foreach ($dir in @(Get-ChildItem -LiteralPath $common -Directory -Force -ErrorAction SilentlyContinue)) { $candidates.Add($dir.FullName) }
        }
        foreach ($candidate in @($candidates | Select-Object -Unique)) {
            foreach ($game in @(Find-RcpGamesAt $candidate)) { $game.Project }
        }
    }
}

function Find-RcpSteamGames([string[]]$AdditionalRoots=@(), [string[]]$AdditionalLocations=@()) {
    $roots = [Collections.Generic.List[string]]::new()
    $direct = [Collections.Generic.List[string]]::new()
    foreach ($root in $AdditionalRoots) { if ($root) { $roots.Add($root) } }
    foreach ($location in $AdditionalLocations) { if ($location) { $direct.Add($location) } }
    if ([Environment]::OSVersion.Platform -eq [PlatformID]::Win32NT) {
        foreach ($hive in @([Microsoft.Win32.RegistryHive]::CurrentUser,[Microsoft.Win32.RegistryHive]::LocalMachine)) {
            foreach ($view in @([Microsoft.Win32.RegistryView]::Registry64,[Microsoft.Win32.RegistryView]::Registry32)) {
                $baseKey = $null
                try {
                    $baseKey = [Microsoft.Win32.RegistryKey]::OpenBaseKey($hive,$view)
                    $steamKey = $baseKey.OpenSubKey('Software\Valve\Steam')
                    if ($steamKey) {
                        try {
                            foreach ($name in @('SteamPath','InstallPath')) {
                                $value = [string]$steamKey.GetValue($name)
                                if ($value) { $roots.Add($value) }
                            }
                            $steamExe = [string]$steamKey.GetValue('SteamExe')
                            if ($steamExe) { $roots.Add([IO.Path]::GetDirectoryName($steamExe)) }
                        } finally { $steamKey.Dispose() }
                    }
                    $uninstall = $baseKey.OpenSubKey('Software\Microsoft\Windows\CurrentVersion\Uninstall')
                    if ($uninstall) {
                        try {
                            foreach ($subName in $uninstall.GetSubKeyNames()) {
                                $sub = $uninstall.OpenSubKey($subName)
                                if (-not $sub) { continue }
                                try {
                                    if ([string]$sub.GetValue('DisplayName') -match '^Police\s*Chief\s*Simulator') {
                                        $location = [string]$sub.GetValue('InstallLocation')
                                        if ($location) { $direct.Add($location) }
                                    }
                                } finally { $sub.Dispose() }
                            }
                        } finally { $uninstall.Dispose() }
                    }
                } catch { Write-RcpDiscovery "REGISTRY ERROR | $hive $view | $($_.Exception.Message)" }
                finally { if ($baseKey) { $baseKey.Dispose() } }
            }
        }
    }
    foreach ($process in @(Get-Process -Name steam -ErrorAction SilentlyContinue)) {
        try { if ($process.Path) { $roots.Add([IO.Path]::GetDirectoryName($process.Path)) } } catch { Write-RcpDiscovery $_.Exception.Message }
    }
    foreach ($base in @(${env:ProgramFiles(x86)},$env:ProgramFiles,$env:ProgramW6432)) {
        if ($base) { $roots.Add((Join-RcpPath $base 'Steam')) }
    }
    foreach ($drive in @(Get-PSDrive -PSProvider FileSystem)) {
        foreach ($relative in @('Steam','SteamLibrary','Games/Steam','Games/SteamLibrary','Program Files (x86)/Steam','Program Files/Steam')) {
            $roots.Add((Join-RcpPath $drive.Root $relative))
        }
        $direct.Add((Join-RcpPath $drive.Root 'Games/Police Chief Simulator'))
    }
    foreach ($location in @($direct | Select-Object -Unique)) {
        if (-not [IO.Directory]::Exists($location)) { continue }
        Write-RcpDiscovery "DIRECT LOCATION | $location"
        foreach ($game in @(Find-RcpGamesAt $location)) { $game.Project }
    }
    Find-RcpLibraryGames $roots.ToArray()
}
