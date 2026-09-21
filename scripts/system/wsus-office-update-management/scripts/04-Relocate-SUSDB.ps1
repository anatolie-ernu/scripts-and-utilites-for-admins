#requires -RunAsAdministrator
[CmdletBinding()]
param(
    [string]$Destination = 'D:\WSUS\Database'
)

$ErrorActionPreference = 'Stop'
$widPipe = 'np:\\.\pipe\MICROSOFT##WID\tsql\query'
$widService = 'MSSQL$MICROSOFT##WID'
$widAccount = 'NT SERVICE\MSSQL$MICROSOFT##WID'
$sourceMdf = 'C:\Windows\WID\Data\SUSDB.mdf'
$sourceLdf = 'C:\Windows\WID\Data\SUSDB_log.ldf'
$destMdf = Join-Path $Destination 'SUSDB.mdf'
$destLdf = Join-Path $Destination 'SUSDB_log.ldf'

New-Item -ItemType Directory -Path $Destination -Force | Out-Null
$acl = $widAccount + ':(OI)(CI)F'
& icacls.exe $Destination /grant $acl | Out-Host

$conn = New-Object System.Data.SqlClient.SqlConnection
$conn.ConnectionString = "Data Source=$widPipe;Initial Catalog=master;Integrated Security=SSPI;"
$conn.Open()
$cmd = $conn.CreateCommand()
$cmd.CommandText = @"
ALTER DATABASE SUSDB MODIFY FILE (NAME = SUSDB, FILENAME = '$destMdf');
ALTER DATABASE SUSDB MODIFY FILE (NAME = SUSDB_log, FILENAME = '$destLdf');
"@
[void]$cmd.ExecuteNonQuery()
$conn.Close()

Stop-Service WsusService -Force -ErrorAction SilentlyContinue
iisreset /stop | Out-Null
Stop-Service $widService -Force

if (Test-Path $sourceMdf) { Move-Item $sourceMdf $destMdf -Force }
if (Test-Path $sourceLdf) { Move-Item $sourceLdf $destLdf -Force }

Start-Service $widService

$conn = New-Object System.Data.SqlClient.SqlConnection
$conn.ConnectionString = "Data Source=$widPipe;Initial Catalog=master;Integrated Security=SSPI;"
$conn.Open()
$cmd = $conn.CreateCommand()
$cmd.CommandText = "SELECT name,state_desc FROM sys.databases WHERE name='SUSDB';"
$dt = New-Object System.Data.DataTable
$dt.Load($cmd.ExecuteReader())
$conn.Close()
$dt | Format-Table -AutoSize
if (($dt | Where-Object name -eq 'SUSDB').state_desc -ne 'ONLINE') { throw 'SUSDB is not ONLINE after relocation.' }

iisreset /start | Out-Null
Start-Service WsusService

Write-Host "SUSDB relocated to $Destination" -ForegroundColor Green
