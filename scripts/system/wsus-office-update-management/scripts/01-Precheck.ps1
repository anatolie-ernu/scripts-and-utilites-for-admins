#requires -RunAsAdministrator
[CmdletBinding()]
param(
    [string]$DataDrive = 'D:'
)

$ErrorActionPreference = 'Stop'

Write-Host '=== WSUS pre-check ===' -ForegroundColor Cyan

$os = Get-CimInstance Win32_OperatingSystem
Write-Host "OS: $($os.Caption) $($os.Version)"

$driveLetter = $DataDrive.TrimEnd(':')
$volume = Get-Volume -DriveLetter $driveLetter
$volume | Select-Object DriveLetter, FileSystem, HealthStatus,
    @{N='SizeGB';E={[math]::Round($_.Size/1GB,2)}},
    @{N='FreeGB';E={[math]::Round($_.SizeRemaining/1GB,2)}} | Format-Table -AutoSize

if ($volume.FileSystem -ne 'NTFS') {
    Write-Warning 'The data volume is not NTFS. Validate the design before continuing.'
}
if ($volume.HealthStatus -ne 'Healthy') {
    throw 'Data volume is not healthy.'
}

Write-Host ""
Write-Host 'WSUS feature state:' -ForegroundColor Yellow
Get-WindowsFeature *UpdateServices* | Format-Table DisplayName,Name,InstallState -AutoSize

Write-Host ""
Write-Host 'Legacy WSUS registry:' -ForegroundColor Yellow
$reg = 'HKLM:\SOFTWARE\Microsoft\Update Services\Server\Setup'
if (Test-Path $reg) {
    Get-ItemProperty $reg | Select-Object ContentDir,SqlServerName,SqlDatabaseName,PortNumber | Format-List
} else {
    Write-Host 'No WSUS setup registry key found.'
}

Write-Host ""
Write-Host 'IIS sites:' -ForegroundColor Yellow
Import-Module WebAdministration -ErrorAction SilentlyContinue
if (Get-Command Get-WebSite -ErrorAction SilentlyContinue) {
    Get-WebSite | Select-Object Name,State,PhysicalPath | Format-Table -AutoSize
}

Write-Host ""
Write-Host 'WSUS service:' -ForegroundColor Yellow
Get-Service WsusService -ErrorAction SilentlyContinue | Select-Object Name,Status,StartType | Format-Table -AutoSize

Write-Host ""
Write-Host 'Pre-check complete.' -ForegroundColor Green
