#requires -RunAsAdministrator
[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)]
    [ValidateSet('2019','2021','2024')]
    [string]$Version,

    [string]$OdtDirectory = 'D:\OfficeUpdates\ODT',
    [string]$ConfigDirectory = 'D:\OfficeUpdates\Config'
)

$ErrorActionPreference = 'Stop'
$setup = Join-Path $OdtDirectory 'setup.exe'
if (-not (Test-Path $setup)) {
    throw "Office Deployment Tool setup.exe not found at $setup"
}

$configName = switch ($Version) {
    '2019' { 'office2019.xml' }
    '2021' { 'office2021.xml' }
    '2024' { 'office2024.xml' }
}
$config = Join-Path $ConfigDirectory $configName
if (-not (Test-Path $config)) { throw "Configuration file not found: $config" }

Write-Host "Downloading/updating Office $Version repository using $config" -ForegroundColor Cyan
$quotedConfig = '"' + $config + '"'
$proc = Start-Process -FilePath $setup -ArgumentList @('/download',$quotedConfig) -Wait -PassThru
if ($proc.ExitCode -ne 0) { throw "ODT download failed with exit code $($proc.ExitCode)" }
Write-Host 'Office repository update completed.' -ForegroundColor Green
