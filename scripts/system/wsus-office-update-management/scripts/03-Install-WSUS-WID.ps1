#requires -RunAsAdministrator
[CmdletBinding()]
param(
    [string]$WsusRoot = 'D:\WSUS'
)

$ErrorActionPreference = 'Stop'
$repo = Join-Path $WsusRoot 'Repository'
$db   = Join-Path $WsusRoot 'Database'

New-Item -ItemType Directory -Path $repo -Force | Out-Null
New-Item -ItemType Directory -Path $db -Force | Out-Null

Install-WindowsFeature UpdateServices-Services,UpdateServices-WidDB,UpdateServices-RSAT -IncludeManagementTools | Out-Host

$features = Get-WindowsFeature *UpdateServices*
$wid = $features | Where-Object Name -eq 'UpdateServices-WidDB'
$sql = $features | Where-Object Name -eq 'UpdateServices-DB'
if ($wid.InstallState -ne 'Installed') { throw 'WID Connectivity was not installed.' }
if ($sql.InstallState -eq 'Installed') { throw 'SQL Server Connectivity is installed; expected WID-only configuration.' }

$wsusUtil = 'C:\Program Files\Update Services\Tools\WsusUtil.exe'
& $wsusUtil postinstall "CONTENT_DIR=$repo"
if ($LASTEXITCODE -ne 0) { throw "WSUS postinstall failed with exit code $LASTEXITCODE" }

Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Update Services\Server\Setup' |
    Select-Object ContentDir,SqlServerName,SqlDatabaseName,PortNumber | Format-List
