param(
    [string]$ReleaseDirectory,
    [string]$XxhsumPath
)

# SYNC_WeatherFX/setup を継承。SteamFX の本番 AUF2 を梱包し、末尾バージョンのハッシュを更新する。
# ビルド・ホスト起動・ネットワークへの公開は行わない。
# Copyright (c) 2026 VRAMの魔術師 / SPDX-License-Identifier: GPL-3.0-only
$ErrorActionPreference = 'Stop'
$packageName = 'SYNC_SteamFX'
$projectDir = Split-Path -Parent $PSScriptRoot
if (-not $ReleaseDirectory) { $ReleaseDirectory = Join-Path $env:ProgramData "aviutl2\Plugin\$packageName" }
$pluginName = "$packageName.auf2"
$pluginPath = Join-Path $ReleaseDirectory $pluginName
if (-not (Test-Path -LiteralPath $pluginPath -PathType Leaf)) {
    throw "Release plugin not found: $pluginPath. Build the Win64 Release configuration first."
}

if (-not $XxhsumPath) {
    $XxhsumPath = Join-Path $projectDir 'Win64\Dependencies\xxHash-0.8.4\xxhsum.exe'
    if (-not (Test-Path -LiteralPath $XxhsumPath -PathType Leaf)) {
        $xxhsum = Get-Command xxhsum.exe -CommandType Application -ErrorAction SilentlyContinue
        if (-not $xxhsum) { throw 'xxhsum.exe is required. See setup\README.md.' }
        $XxhsumPath = $xxhsum.Source
    }
}
$XxhsumPath = (Resolve-Path -LiteralPath $XxhsumPath).ProviderPath

$catalogPath = Join-Path $PSScriptRoot "$packageName.catalog.json"
$zipPath = Join-Path $PSScriptRoot "$packageName.zip"
$tempBase = Join-Path $PSScriptRoot ('.release-' + [guid]::NewGuid().ToString('N'))
$tempPlugin = "$tempBase-plugin.tmp"
$tempZip = "$tempBase-zip.tmp"
$tempCatalog = "$tempBase-catalog.tmp"
$catalogBackup = "$tempBase-previous-catalog.tmp"

Add-Type -AssemblyName System.IO.Compression, System.IO.Compression.FileSystem
$lock = [Threading.Mutex]::new($false, 'Local\VRAMWIZ.SYNC_SteamFX.ReleaseZip')
$ownsLock = $false
try {
    try { $ownsLock = $lock.WaitOne(0) }
    catch [Threading.AbandonedMutexException] { $ownsLock = $true }
    if (-not $ownsLock) { throw 'Another release ZIP is being created. Run the batch again.' }

    $catalogSource = [IO.File]::ReadAllText($catalogPath)
    if ($catalogSource -notmatch '^\s*\[') { throw 'The catalog root must be a JSON array.' }
    $catalog = [object[]]($catalogSource | ConvertFrom-Json)
    if ($catalog.Count -ne 1 -or $catalog[0].id -cne "VRAMWIZ.$packageName") {
        throw "The catalog must contain only VRAMWIZ.$packageName."
    }
    $entry = $catalog[0]
    $github = $entry.installer.source.github
    if ($github.owner -cne 'vramwiz' -or $github.repo -cne $packageName -or
        [string]::IsNullOrWhiteSpace($github.pattern) -or
        "$packageName.zip" -cnotmatch $github.pattern) {
        throw 'The catalog GitHub source must match this repository and ZIP name.'
    }
    $install = @($entry.installer.install)
    $pluginDirectory = "{pluginsDir}/$packageName"
    if ($install.Count -ne 3 -or $install[0].action -cne 'download' -or
        $install[1].action -cne 'extract' -or $install[2].action -cne 'copy' -or
        $install[2].from -cne "{tmp}/$packageName" -or $install[2].to -cne $pluginDirectory) {
        throw 'The catalog must download and extract the ZIP, then copy the plugin directory.'
    }
    $uninstall = @($entry.installer.uninstall)
    $packagedFiles = @("$packageName.auf2", 'README.md', 'LICENSE', 'THIRD_PARTY_NOTICES.md', 'ThirdParty/LICENSE.AviUtl2-SDK.txt')
    $expectedPaths = @($packagedFiles | ForEach-Object { "{pluginsDir}/$packageName/$_" })
    $deletePaths = @($uninstall | Where-Object action -ceq 'delete' | ForEach-Object path)
    if ($uninstall.Count -ne $expectedPaths.Count -or $deletePaths.Count -ne $expectedPaths.Count -or
        @(Compare-Object $expectedPaths $deletePaths -CaseSensitive).Count -ne 0) {
        throw 'The catalog uninstall paths must list every installed file exactly once.'
    }
    if (@($entry.version).Count -eq 0) { throw 'The catalog must contain a release version.' }
    if ($entry.version[0].version -cne 'v1.0.0') {
        throw 'The first public SteamFX version must be v1.0.0.'
    }
    $version = $catalog[0].version[-1]
    $releaseDate = [datetime]::MinValue
    if ([string]::IsNullOrWhiteSpace($version.version) -or
        @($entry.version | Where-Object version -ceq $version.version).Count -ne 1 -or
        -not [datetime]::TryParseExact($version.release_date, 'yyyy-MM-dd',
            [Globalization.CultureInfo]::InvariantCulture,
            [Globalization.DateTimeStyles]::None, [ref]$releaseDate)) {
        throw 'The last catalog version must have a unique name and a valid yyyy-MM-dd release date.'
    }
    $pluginEntry = @($version.file | Where-Object path -ceq "{pluginsDir}/$packageName/$pluginName")
    if (@($version.file).Count -ne 1 -or $pluginEntry.Count -ne 1) {
        throw 'The last catalog version must list only the production AUF2 once.'
    }
    if (-not $pluginEntry[0].PSObject.Properties['XXH3_128'] -or
        ($pluginEntry[0].XXH3_128 -ne '' -and $pluginEntry[0].XXH3_128 -cnotmatch '^[0-9a-fA-F]{32}$')) {
        throw 'The AUF2 XXH3_128 must be empty or contain exactly 32 hexadecimal digits.'
    }

    # Hash the same AUF2 bytes that will go into the ZIP.
    Copy-Item -LiteralPath $pluginPath -Destination $tempPlugin
    $hashOutput = & $XxhsumPath -H128 --tag $tempPlugin
    if ($LASTEXITCODE -ne 0 -or ($hashOutput -join "`n") -notmatch ' = ([0-9a-f]{32})\s*\z') {
        throw 'Could not calculate the AUF2 XXH3-128 hash.'
    }
    $hash = $Matches[1].ToLowerInvariant()

    $packageFiles = [ordered]@{
        $pluginName = $tempPlugin
        'README.md' = Join-Path $projectDir 'README.md'
        'LICENSE' = Join-Path $projectDir 'LICENSE'
        'THIRD_PARTY_NOTICES.md' = Join-Path $projectDir 'THIRD_PARTY_NOTICES.md'
        'ThirdParty/LICENSE.AviUtl2-SDK.txt' = Join-Path $projectDir 'ThirdParty\LICENSE.AviUtl2-SDK.txt'
    }
    foreach ($file in $packageFiles.Values) {
        if (-not (Test-Path -LiteralPath $file -PathType Leaf)) { throw "Package file not found: $file" }
    }
    $zip = [IO.Compression.ZipFile]::Open($tempZip, [IO.Compression.ZipArchiveMode]::Create)
    try {
        foreach ($file in $packageFiles.GetEnumerator()) {
            [IO.Compression.ZipFileExtensions]::CreateEntryFromFile(
                $zip, $file.Value, "$packageName/$($file.Key)", [IO.Compression.CompressionLevel]::Optimal
            ) | Out-Null
        }
    }
    finally { $zip.Dispose() }

    if ([IO.File]::ReadAllText($catalogPath) -cne $catalogSource) {
        throw 'Catalog changed during packaging. Run the batch again.'
    }
    if ($pluginEntry[0].XXH3_128 -cne $hash) {
        $pluginEntry[0].XXH3_128 = $hash
        $json = ConvertTo-Json -InputObject $catalog -Depth 12
        [IO.File]::WriteAllText($tempCatalog, $json + [Environment]::NewLine, [Text.UTF8Encoding]::new($false))
        [IO.File]::Replace($tempCatalog, $catalogPath, $catalogBackup)
    }
    try {
        if ([IO.File]::Exists($zipPath)) { [IO.File]::Replace($tempZip, $zipPath, [NullString]::Value) }
        else { [IO.File]::Move($tempZip, $zipPath) }
    }
    catch {
        if ([IO.File]::Exists($catalogBackup)) {
            [IO.File]::Replace($catalogBackup, $catalogPath, [NullString]::Value)
        }
        throw
    }
    if ([IO.File]::Exists($catalogBackup)) { [IO.File]::Delete($catalogBackup) }
}
finally {
    if ($ownsLock) { $lock.ReleaseMutex() }
    $lock.Dispose()
    foreach ($tempPath in @($tempPlugin, $tempZip, $tempCatalog)) {
        [IO.File]::Delete($tempPath)
    }
}

Write-Output "Created $zipPath"
Write-Output "Catalog $catalogPath ($($version.version), XXH3_128=$hash)"
