#requires -RunAsAdministrator
[CmdletBinding(SupportsShouldProcess=$true, ConfirmImpact='High')]
param(
    [Parameter(Mandatory=$true)]
    [string]$SourceGpoName,

    [string]$TargetGpoName = 'Computer Policy Deploy - WSUS Server Baseline v2',

    [Parameter(Mandatory=$true)]
    [ValidatePattern('^https?://')]
    [string]$WsusUrl,

    [ValidateRange(1,22)]
    [int]$DetectionFrequencyHours = 3,

    [ValidateRange(1,24)]
    [int]$DefenderSignatureIntervalHours = 1,

    [switch]$BlockWindowsUpdateInternetLocations,

    [switch]$KeepTrustedPublisherCertificatePolicy,

    [switch]$Apply,

    [string]$BackupRoot = 'C:\GPO-Backup\WSUS'
)

$ErrorActionPreference = 'Stop'
Import-Module GroupPolicy

$wuKey  = 'HKLM\Software\Policies\Microsoft\Windows\WindowsUpdate'
$auKey  = 'HKLM\Software\Policies\Microsoft\Windows\WindowsUpdate\AU'
$defKey = 'HKLM\Software\Policies\Microsoft\Windows Defender\Signature Updates'

function Remove-GpoValueSafe {
    param(
        [Parameter(Mandatory=$true)][string]$Gpo,
        [Parameter(Mandatory=$true)][string]$Key,
        [Parameter(Mandatory=$true)][string]$Name
    )

    try {
        Remove-GPRegistryValue -Name $Gpo -Key $Key -ValueName $Name -ErrorAction Stop | Out-Null
        Write-Host "Removed legacy value: $Key\$Name" -ForegroundColor DarkGray
    }
    catch {
        # Missing values are acceptable and keep the script idempotent.
    }
}

function Set-GpoDword {
    param([string]$Gpo,[string]$Key,[string]$Name,[int]$Value)
    Set-GPRegistryValue -Name $Gpo -Key $Key -ValueName $Name -Type DWord -Value $Value | Out-Null
}

function Set-GpoString {
    param([string]$Gpo,[string]$Key,[string]$Name,[string]$Value)
    Set-GPRegistryValue -Name $Gpo -Key $Key -ValueName $Name -Type String -Value $Value | Out-Null
}

$source = Get-GPO -Name $SourceGpoName -ErrorAction SilentlyContinue
if (-not $source) {
    throw "Source GPO not found: $SourceGpoName"
}

$target = Get-GPO -Name $TargetGpoName -ErrorAction SilentlyContinue

Write-Host '=== WSUS Server Baseline v2 ===' -ForegroundColor Cyan
Write-Host "Source GPO : $SourceGpoName"
Write-Host "Target GPO : $TargetGpoName"
Write-Host "WSUS URL   : $WsusUrl"
Write-Host "Mode       : $(if ($Apply) { 'APPLY' } else { 'PREVIEW' })"

Write-Host ''
Write-Host 'Desired Windows Update behavior:' -ForegroundColor Yellow
Write-Host '  AUOptions=2 -> notify before download/install for ordinary updates'
Write-Host '  UseWUServer=1'
Write-Host '  Feature/Quality/Driver/Other scan sources -> WSUS'
Write-Host '  Client-side TargetGroup values -> removed from baseline'
Write-Host '  Defender Security Intelligence source -> InternalDefinitionUpdateServer'
Write-Host "  Defender Security Intelligence interval -> $DefenderSignatureIntervalHours hour(s)"
Write-Host '  Defender platform KB4052623 still requires the dedicated Defender client update worker for automatic installation.'

if (-not $Apply) {
    Write-Host ''
    Write-Host 'PREVIEW ONLY. No GPO was created or modified.' -ForegroundColor Yellow
    Write-Host 'Run again with -Apply after reviewing the source and desired state.' -ForegroundColor Yellow
    return
}

$timestamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$runBackupRoot = Join-Path $BackupRoot "Server-Baseline-v2-$timestamp"
$sourceBackupPath = Join-Path $runBackupRoot 'Source'
$targetBackupPath = Join-Path $runBackupRoot 'Target'

New-Item -ItemType Directory -Path $sourceBackupPath -Force | Out-Null
New-Item -ItemType Directory -Path $targetBackupPath -Force | Out-Null

Write-Host ''
Write-Host '=== Backup ===' -ForegroundColor Cyan
$sourceBackup = Backup-GPO -Name $SourceGpoName -Path $sourceBackupPath
Write-Host "Backed up source: $SourceGpoName" -ForegroundColor Green

if ($target) {
    Backup-GPO -Name $TargetGpoName -Path $targetBackupPath | Out-Null
    Write-Host "Backed up existing target: $TargetGpoName" -ForegroundColor Green
}

if (-not $target) {
    if ($PSCmdlet.ShouldProcess($TargetGpoName, "Create from source GPO '$SourceGpoName'")) {
        Copy-GPO -SourceName $SourceGpoName -TargetName $TargetGpoName -CopyAcl | Out-Null
        Write-Host "Created target GPO from source: $TargetGpoName" -ForegroundColor Green
    }
}
else {
    if ($PSCmdlet.ShouldProcess($TargetGpoName, "Refresh settings from source GPO '$SourceGpoName'")) {
        Import-GPO -BackupId $sourceBackup.Id -Path $sourceBackupPath -TargetName $TargetGpoName | Out-Null
        Write-Host "Imported source settings into existing target: $TargetGpoName" -ForegroundColor Green
    }
}

if ($PSCmdlet.ShouldProcess($TargetGpoName, 'Apply Server Baseline v2 desired state')) {

    # WSUS service location.
    Set-GpoString -Gpo $TargetGpoName -Key $wuKey -Name 'WUServer'       -Value $WsusUrl
    Set-GpoString -Gpo $TargetGpoName -Key $wuKey -Name 'WUStatusServer' -Value $WsusUrl

    # Explicit scan-source policy: all update classes come from WSUS.
    foreach ($name in @(
        'SetPolicyDrivenUpdateSourceForFeatureUpdates',
        'SetPolicyDrivenUpdateSourceForQualityUpdates',
        'SetPolicyDrivenUpdateSourceForDriverUpdates',
        'SetPolicyDrivenUpdateSourceForOtherUpdates'
    )) {
        Set-GpoDword -Gpo $TargetGpoName -Key $wuKey -Name $name -Value 1
    }

    # Automatic Updates: notify/manual for ordinary updates.
    Set-GpoDword -Gpo $TargetGpoName -Key $auKey -Name 'NoAutoUpdate'                 -Value 0
    Set-GpoDword -Gpo $TargetGpoName -Key $auKey -Name 'AUOptions'                    -Value 2
    Set-GpoDword -Gpo $TargetGpoName -Key $auKey -Name 'UseWUServer'                  -Value 1
    Set-GpoDword -Gpo $TargetGpoName -Key $auKey -Name 'UseUpdateClassPolicySource'   -Value 1
    Set-GpoDword -Gpo $TargetGpoName -Key $auKey -Name 'DetectionFrequencyEnabled'    -Value 1
    Set-GpoDword -Gpo $TargetGpoName -Key $auKey -Name 'DetectionFrequency'           -Value $DetectionFrequencyHours
    Set-GpoDword -Gpo $TargetGpoName -Key $auKey -Name 'NoAutoRebootWithLoggedOnUsers' -Value 1

    # Keep targeting out of the common baseline. Pilot/Production GPOs own these values.
    Remove-GpoValueSafe -Gpo $TargetGpoName -Key $wuKey -Name 'TargetGroup'
    Remove-GpoValueSafe -Gpo $TargetGpoName -Key $wuKey -Name 'TargetGroupEnabled'

    # Remove policies that would weaken admin control or duplicate scheduled-install behavior.
    foreach ($name in @(
        'ElevateNonAdmins',
        'ScheduledInstallDay',
        'ScheduledInstallTime',
        'ScheduledInstallEveryWeek',
        'RebootWarningTimeoutEnabled',
        'RebootWarningTimeout',
        'RebootRelaunchTimeoutEnabled',
        'RebootRelaunchTimeout',
        'RescheduleWaitTimeEnabled',
        'RescheduleWaitTime',
        'AutoInstallMinorUpdates',
        'IncludeRecommendedUpdates'
    )) {
        Remove-GpoValueSafe -Gpo $TargetGpoName -Key $auKey -Name $name
    }

    foreach ($name in @(
        'AllowMUUpdateService',
        'EnableFeaturedSoftware',
        'DisableDualScan',
        'UpdateServiceUrlAlternate'
    )) {
        Remove-GpoValueSafe -Gpo $TargetGpoName -Key $wuKey -Name $name
        Remove-GpoValueSafe -Gpo $TargetGpoName -Key $auKey -Name $name
    }

    if (-not $KeepTrustedPublisherCertificatePolicy) {
        Remove-GpoValueSafe -Gpo $TargetGpoName -Key $wuKey -Name 'AcceptTrustedPublisherCert'
    }

    if ($BlockWindowsUpdateInternetLocations) {
        Set-GpoDword -Gpo $TargetGpoName -Key $wuKey -Name 'DoNotConnectToWindowsUpdateInternetLocations' -Value 1
    }

    # Defender Security Intelligence: automatic, WSUS/internal definition update server only.
    # Windows Defender ADMX uses FallbackOrder under the Signature Updates policy key.
    Set-GpoString -Gpo $TargetGpoName -Key $defKey -Name 'FallbackOrder' -Value 'InternalDefinitionUpdateServer'
    Set-GpoDword  -Gpo $TargetGpoName -Key $defKey -Name 'SignatureUpdateInterval' -Value $DefenderSignatureIntervalHours
}

Write-Host ''
Write-Host '=== Verification ===' -ForegroundColor Cyan

$verifyKeys = @($wuKey,$auKey,$defKey)
foreach ($key in $verifyKeys) {
    Write-Host ''
    Write-Host $key -ForegroundColor Yellow
    try {
        Get-GPRegistryValue -Name $TargetGpoName -Key $key -ErrorAction Stop |
            Sort-Object ValueName |
            Select-Object ValueName,Value,Type,PolicyState |
            Format-Table -Wrap -AutoSize
    }
    catch {
        Write-Host 'No configured registry values found.' -ForegroundColor DarkGray
    }
}

Write-Host ''
Write-Host "Baseline v2 configured: $TargetGpoName" -ForegroundColor Green
Write-Host "Rollback backup: $runBackupRoot" -ForegroundColor Yellow
Write-Host 'Review Security Filtering, WMI Filtering and OU links in Group Policy Management before deployment.' -ForegroundColor Yellow
