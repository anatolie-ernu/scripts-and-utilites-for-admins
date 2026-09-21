#requires -RunAsAdministrator
[CmdletBinding()]
param(
    [string[]]$Languages = @('en','ro','ru')
)

$ErrorActionPreference = 'Stop'
Import-Module UpdateServices
$wsus = Get-WsusServer
Set-WsusServerSynchronization -SyncFromMU | Out-Host
$config = $wsus.GetConfiguration()

$config.HostBinariesOnMicrosoftUpdate = $false
$config.DownloadUpdateBinariesAsNeeded = $true
$config.DownloadExpressPackages = $false
$config.AllUpdateLanguagesEnabled = $false

$langs = New-Object System.Collections.Specialized.StringCollection
foreach ($lang in $Languages) {
    if ($config.SupportedUpdateLanguages -notcontains $lang) {
        throw "Unsupported WSUS language code: $lang"
    }
    [void]$langs.Add($lang)
}
$config.SetEnabledUpdateLanguages($langs)
$config.Save()

Write-Host 'Base WSUS configuration:' -ForegroundColor Cyan
$config = $wsus.GetConfiguration()
$config | Select-Object MUUrl,HostBinariesOnMicrosoftUpdate,DownloadUpdateBinariesAsNeeded,DownloadExpressPackages,AllUpdateLanguagesEnabled | Format-List
Write-Host 'Enabled languages:'
$config.GetEnabledUpdateLanguages()

Write-Host 'Start the initial synchronization before selecting products on a new WSUS server.' -ForegroundColor Yellow
