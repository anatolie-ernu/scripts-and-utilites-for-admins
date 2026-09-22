#requires -RunAsAdministrator
[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)]
    [string]$SourceGpoName,

    [switch]$Apply,

    [string]$BackupRoot = 'C:\GPO-Backup\WSUS',

    [hashtable]$TargetMap = [ordered]@{
        'Computer Policy Deploy - WSUS Updates Server-Pilot'      = 'Server-Pilot'
        'Computer Policy Deploy - WSUS Updates Server-Production' = 'Server-Production'
        'Computer Policy Deploy - WSUS Updates SQL-Pilot'         = 'SQL-Pilot'
        'Computer Policy Deploy - WSUS Updates SQL-Production'    = 'SQL-Production'
    }
)

$ErrorActionPreference = 'Stop'
Import-Module GroupPolicy

$wuKey = 'HKLM\Software\Policies\Microsoft\Windows\WindowsUpdate'

Write-Host '=== WSUS Server GPO Baseline Import ===' -ForegroundColor Cyan
Write-Host "Source GPO: $SourceGpoName"
Write-Host "Mode: $(if ($Apply) { 'APPLY' } else { 'PREVIEW' })"

$source = Get-GPO -Name $SourceGpoName -ErrorAction SilentlyContinue
if (-not $source) {
    throw "Source GPO not found: $SourceGpoName"
}

$missingTargets = @()
$preview = foreach ($targetGpo in $TargetMap.Keys) {
    $target = Get-GPO -Name $targetGpo -ErrorAction SilentlyContinue
    if (-not $target) { $missingTargets += $targetGpo }

    [PSCustomObject]@{
        TargetGPO   = $targetGpo
        TargetGroup = $TargetMap[$targetGpo]
        Exists      = [bool]$target
        Action      = if ($target) { 'Import source settings into existing GPO, then restore WSUS targeting' } else { 'BLOCKED - target GPO does not exist' }
    }
}

$preview | Format-Table -Wrap -AutoSize

if (-not $Apply) {
    Write-Host ''
    Write-Host 'PREVIEW ONLY. No GPO was modified.' -ForegroundColor Yellow
    if ($missingTargets.Count -gt 0) { Write-Warning ('Missing target GPOs: ' + ($missingTargets -join ', ')) }
    Write-Host 'Run again with -Apply after reviewing the source and target mapping.' -ForegroundColor Yellow
    return
}

if ($missingTargets.Count -gt 0) {
    throw ('Cannot apply because target GPOs are missing: ' + ($missingTargets -join ', '))
}

$timestamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$runBackupRoot = Join-Path $BackupRoot "Server-GPO-Migration-$timestamp"
$sourceBackupPath = Join-Path $runBackupRoot 'Source'
$targetBackupPath = Join-Path $runBackupRoot 'Targets'

New-Item -ItemType Directory -Path $sourceBackupPath -Force | Out-Null
New-Item -ItemType Directory -Path $targetBackupPath -Force | Out-Null

Write-Host ''
Write-Host '=== Backup ===' -ForegroundColor Cyan
$sourceBackup = Backup-GPO -Name $SourceGpoName -Path $sourceBackupPath
Write-Host "Source backed up: $SourceGpoName" -ForegroundColor Green

foreach ($targetGpo in $TargetMap.Keys) {
    Backup-GPO -Name $targetGpo -Path $targetBackupPath | Out-Null
    Write-Host "Target backed up: $targetGpo" -ForegroundColor Green
}

Write-Host "Backup root: $runBackupRoot" -ForegroundColor Yellow

$results = foreach ($targetGpo in $TargetMap.Keys) {
    $targetGroup = $TargetMap[$targetGpo]

    Write-Host ''
    Write-Host "=== $targetGpo ===" -ForegroundColor Cyan

    Import-GPO -BackupId $sourceBackup.Id -Path $sourceBackupPath -TargetName $targetGpo | Out-Null

    Set-GPRegistryValue -Name $targetGpo -Key $wuKey -ValueName 'TargetGroup' -Type String -Value $targetGroup | Out-Null
    Set-GPRegistryValue -Name $targetGpo -Key $wuKey -ValueName 'TargetGroupEnabled' -Type DWord -Value 1 | Out-Null

    $values = Get-GPRegistryValue -Name $targetGpo -Key $wuKey -ErrorAction SilentlyContinue | Where-Object { $_.ValueName -in @('TargetGroup','TargetGroupEnabled','WUServer','WUStatusServer') }

    [PSCustomObject]@{
        GPO                = $targetGpo
        TargetGroup        = ($values | Where-Object ValueName -eq 'TargetGroup').Value
        TargetGroupEnabled = ($values | Where-Object ValueName -eq 'TargetGroupEnabled').Value
        WUServer           = ($values | Where-Object ValueName -eq 'WUServer').Value
        WUStatusServer     = ($values | Where-Object ValueName -eq 'WUStatusServer').Value
    }
}

Write-Host ''
Write-Host '=== Verification ===' -ForegroundColor Cyan
$results | Format-Table -Wrap -AutoSize

Write-Host ''
Write-Host 'Server GPO baseline import completed.' -ForegroundColor Green
Write-Host "Rollback backups: $runBackupRoot" -ForegroundColor Yellow
Write-Host 'Existing target GPO objects are reused; review OU links in Group Policy Management after import.' -ForegroundColor Yellow
