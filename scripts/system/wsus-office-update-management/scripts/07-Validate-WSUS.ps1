#requires -RunAsAdministrator
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
Import-Module UpdateServices
$wsus = Get-WsusServer
$config = $wsus.GetConfiguration()
$sub = $wsus.GetSubscription()

Write-Host '=== WSUS service ===' -ForegroundColor Cyan
Get-Service WsusService,'MSSQL$MICROSOFT##WID' | Select-Object Name,Status,StartType | Format-Table -AutoSize

Write-Host '=== Connectivity ===' -ForegroundColor Cyan
Test-NetConnection localhost -Port $wsus.PortNumber | Select-Object ComputerName,RemotePort,TcpTestSucceeded | Format-Table -AutoSize

Write-Host '=== Setup ===' -ForegroundColor Cyan
Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Update Services\Server\Setup' |
    Select-Object ContentDir,SqlServerName,SqlDatabaseName,PortNumber | Format-List

Write-Host '=== Download behavior ===' -ForegroundColor Cyan
$config | Select-Object MUUrl,HostBinariesOnMicrosoftUpdate,DownloadUpdateBinariesAsNeeded,DownloadExpressPackages,AllUpdateLanguagesEnabled | Format-List
Write-Host 'Languages:'
$config.GetEnabledUpdateLanguages()

Write-Host '=== Synchronization ===' -ForegroundColor Cyan
$sub.GetSynchronizationStatus()
$sub.GetLastSynchronizationInfo() | Format-List Id,StartTime,EndTime,StartedManually,Result,Error,ErrorText

Write-Host '=== Enabled products ===' -ForegroundColor Cyan
Get-WsusProduct | Where-Object Enabled | Select-Object @{N='Product';E={$_.Product.Title}} | Sort-Object Product | Format-Table -AutoSize

Write-Host '=== Enabled classifications ===' -ForegroundColor Cyan
$sub.GetUpdateClassifications() | Sort-Object Title | Select-Object Title | Format-Table -AutoSize

Write-Host '=== SUSDB physical files ===' -ForegroundColor Cyan
$conn = New-Object System.Data.SqlClient.SqlConnection
$conn.ConnectionString = 'Data Source=np:\\.\pipe\MICROSOFT##WID\tsql\query;Initial Catalog=master;Integrated Security=SSPI;'
$conn.Open()
$cmd = $conn.CreateCommand()
$cmd.CommandText = "SELECT name,physical_name FROM sys.master_files WHERE database_id=DB_ID('SUSDB');"
$dt = New-Object System.Data.DataTable
$dt.Load($cmd.ExecuteReader())
$conn.Close()
$dt | Format-Table -AutoSize
