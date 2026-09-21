#requires -RunAsAdministrator
[CmdletBinding(SupportsShouldProcess=$true, ConfirmImpact='High')]
param(
    [string]$BackupDirectory = 'C:\WSUS-BACKUP',
    [string]$OldContentPath = 'D:\WSUSUpdates',
    [switch]$PurgeOldContent
)

$ErrorActionPreference = 'Stop'
New-Item -ItemType Directory -Path $BackupDirectory -Force | Out-Null

$regRoot = 'HKLM\SOFTWARE\Microsoft\Update Services'
if (Test-Path 'HKLM:\SOFTWARE\Microsoft\Update Services') {
    & reg.exe export $regRoot (Join-Path $BackupDirectory 'Microsoft-Update-Services.reg') /y | Out-Null
}

Get-WindowsFeature *UpdateServices* | Out-File (Join-Path $BackupDirectory 'WSUS-Features.txt')
if (Test-Path 'HKLM:\SOFTWARE\Microsoft\Update Services\Server\Setup') {
    Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Update Services\Server\Setup' |
        Format-List * | Out-File (Join-Path $BackupDirectory 'WSUS-Setup.txt')
}

if ($PSCmdlet.ShouldProcess('Local WSUS installation','Remove WSUS role and residual configuration')) {
    Stop-Service WsusService -Force -ErrorAction SilentlyContinue
    iisreset /stop | Out-Null
    Uninstall-WindowsFeature -Name UpdateServices -IncludeManagementTools | Out-Host

    Import-Module WebAdministration -ErrorAction SilentlyContinue
    if (Get-Website -Name 'WSUS Administration' -ErrorAction SilentlyContinue) {
        Remove-Website -Name 'WSUS Administration'
    }

    if (Test-Path 'HKLM:\SOFTWARE\Microsoft\Update Services') {
        Remove-Item 'HKLM:\SOFTWARE\Microsoft\Update Services' -Recurse -Force
    }

    if (Test-Path 'C:\Program Files\Update Services') {
        Remove-Item 'C:\Program Files\Update Services' -Recurse -Force
    }

    if ($PurgeOldContent -and (Test-Path $OldContentPath)) {
        Remove-Item $OldContentPath -Recurse -Force
    }

    Write-Host 'Removal completed. A reboot before reinstall is recommended.' -ForegroundColor Green
}
