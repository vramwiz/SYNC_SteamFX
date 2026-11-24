param(
    [string]$PluginPath = 'C:\ProgramData\aviutl2\Plugin\SYNC_SteamFX\SYNC_SteamFX.auf2',
    [string]$ImageDirectory
)

$ErrorActionPreference = 'Stop'
$projectDirectory = Split-Path -Parent $PSScriptRoot
$outputDirectory = Join-Path $projectDirectory 'Win64\Verification'
$dcuDirectory = Join-Path $outputDirectory 'DCU'
if (-not $ImageDirectory) { $ImageDirectory = Join-Path $outputDirectory 'Images' }
$ImageDirectory = [IO.Path]::GetFullPath($ImageDirectory)
New-Item -ItemType Directory -Path $dcuDirectory -Force | Out-Null
$installation = 'C:\Program Files (x86)\Embarcadero\Studio\37.0'
$libraryDirectory = Join-Path $installation 'lib\Win64\release'
Push-Location $PSScriptRoot
try {
    & (Join-Path $installation 'bin\dcc64.exe') '--no-config' '-B' '-Q' '-TX.exe' '-$R+' '-$Q+' `
        '-NSSystem;Winapi;Vcl' "-U$libraryDirectory;$libraryDirectory\JA" "-E$outputDirectory" `
        "-NU$dcuDirectory" 'SteamFX_RenderTests.dpr'
    if ($LASTEXITCODE -ne 0) { throw 'SteamFX verification build failed.' }
    & (Join-Path $outputDirectory 'SteamFX_RenderTests.exe') $PluginPath $ImageDirectory
    if ($LASTEXITCODE -ne 0) { throw 'Production AUF2 verification failed.' }
}
finally { Pop-Location }
