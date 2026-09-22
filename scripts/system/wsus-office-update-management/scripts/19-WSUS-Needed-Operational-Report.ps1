#requires -RunAsAdministrator
[CmdletBinding()]
param(
    [string]$OutputDirectory = 'D:\WSUSReports\Operational',
    [ValidateRange(1,500)]
    [int]$ConsoleRows = 25
)

$ErrorActionPreference = 'Stop'
Import-Module UpdateServices

$wsus = Get-WsusServer

Write-Host '=== WSUS Needed Operational Report ===' -ForegroundColor Cyan
Write-Host "Server          : $($wsus.Name)"
Write-Host "OutputDirectory : $OutputDirectory"
Write-Host "ConsoleRows     : $ConsoleRows"

$updateScope = New-Object Microsoft.UpdateServices.Administration.UpdateScope
$computerScope = New-Object Microsoft.UpdateServices.Administration.ComputerTargetScope

Write-Host ''
Write-Host 'Collecting WSUS per-update summaries...' -ForegroundColor Yellow
$summaries = $wsus.GetSummariesPerUpdate($updateScope, $computerScope)

$summaryByUpdateId = @{}
foreach ($summary in $summaries) {
    $summaryByUpdateId[$summary.UpdateId.ToString()] = $summary
}

Write-Host "Summary rows    : $($summaries.Count)"

Write-Host ''
Write-Host 'Collecting update metadata...' -ForegroundColor Yellow
$updates = $wsus.GetUpdates()
Write-Host "Update rows     : $($updates.Count)"

$rows = foreach ($update in $updates) {

    if (-not $update.IsLatestRevision) {
        continue
    }

    $key = $update.Id.UpdateId.ToString()
    $summary = $summaryByUpdateId[$key]

    $notInstalled = 0
    $downloaded = 0
    $failed = 0
    $pendingReboot = 0
    $unknown = 0

    if ($summary) {
        $notInstalled = [int]$summary.NotInstalledCount
        $downloaded = [int]$summary.DownloadedCount
        $failed = [int]$summary.FailedCount
        $pendingReboot = [int]$summary.InstalledPendingRebootCount
        $unknown = [int]$summary.UnknownCount
    }

    # Operational "Needed" means a client still requires action:
    # not installed yet, downloaded but not installed, or failed.
    $needed = $notInstalled + $downloaded + $failed

    $bucket = $null

    if ($update.IsDeclined) {
        $bucket = 'DECLINED-CLEANUP'
    }
    elseif ($needed -gt 0 -and $update.IsSuperseded) {
        $bucket = 'NEEDED-SUPERSEDED'
    }
    elseif ($needed -gt 0 -and -not $update.IsSuperseded) {
        $bucket = 'NEEDED-ACTIONABLE'
    }

    if (-not $bucket) {
        continue
    }

    [PSCustomObject]@{
        Bucket            = $bucket
        NeededCount       = $needed
        NotInstalledCount = $notInstalled
        DownloadedCount   = $downloaded
        FailedCount       = $failed
        PendingReboot     = $pendingReboot
        UnknownCount      = $unknown
        IsApproved        = [bool]$update.IsApproved
        IsSuperseded      = [bool]$update.IsSuperseded
        IsDeclined        = [bool]$update.IsDeclined
        Classification    = $update.UpdateClassificationTitle
        Products          = ($update.ProductTitles -join '; ')
        KB                = ($update.KnowledgebaseArticles -join ',')
        Title             = $update.Title
        ArrivalDate       = $update.ArrivalDate
        CreationDate      = $update.CreationDate
        UpdateId          = $update.Id.UpdateId
        Revision          = $update.Id.RevisionNumber
    }
}

$actionable = @(
    $rows |
        Where-Object Bucket -eq 'NEEDED-ACTIONABLE' |
        Sort-Object @{Expression='NeededCount';Descending=$true},
                    @{Expression='ArrivalDate';Descending=$true}
)

$superseded = @(
    $rows |
        Where-Object Bucket -eq 'NEEDED-SUPERSEDED' |
        Sort-Object @{Expression='NeededCount';Descending=$true},
                    @{Expression='ArrivalDate';Descending=$true}
)

$declined = @(
    $rows |
        Where-Object Bucket -eq 'DECLINED-CLEANUP' |
        Sort-Object @{Expression='NeededCount';Descending=$true},
                    @{Expression='ArrivalDate';Descending=$true}
)

$timestamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$reportDir = Join-Path $OutputDirectory $timestamp
New-Item -ItemType Directory -Path $reportDir -Force | Out-Null

$actionableCsv = Join-Path $reportDir '01-Needed-Actionable.csv'
$supersededCsv = Join-Path $reportDir '02-Needed-Superseded.csv'
$declinedCsv = Join-Path $reportDir '03-Declined-Cleanup.csv'
$summaryTxt = Join-Path $reportDir '00-Summary.txt'

$actionable | Export-Csv -Path $actionableCsv -NoTypeInformation -Encoding UTF8
$superseded | Export-Csv -Path $supersededCsv -NoTypeInformation -Encoding UTF8
$declined | Export-Csv -Path $declinedCsv -NoTypeInformation -Encoding UTF8

$summaryText = @"
WSUS Needed Operational Report
Generated: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')
Server: $($wsus.Name)

NEEDED-ACTIONABLE : $($actionable.Count)
NEEDED-SUPERSEDED : $($superseded.Count)
DECLINED-CLEANUP  : $($declined.Count)

NeededCount is calculated as:
  NotInstalledCount + DownloadedCount + FailedCount

NEEDED-ACTIONABLE:
  NeededCount > 0
  IsSuperseded = False
  IsDeclined = False

NEEDED-SUPERSEDED:
  NeededCount > 0
  IsSuperseded = True
  IsDeclined = False

DECLINED-CLEANUP:
  IsDeclined = True
  NeededCount is retained for visibility, including zero.

This report is read-only. It does not approve, decline, delete, or modify updates.
"@

Set-Content -Path $summaryTxt -Value $summaryText -Encoding UTF8

Write-Host ''
Write-Host '=== Summary ===' -ForegroundColor Cyan
[PSCustomObject]@{
    Category = 'NEEDED-ACTIONABLE'
    Count    = $actionable.Count
},
[PSCustomObject]@{
    Category = 'NEEDED-SUPERSEDED'
    Count    = $superseded.Count
},
[PSCustomObject]@{
    Category = 'DECLINED-CLEANUP'
    Count    = $declined.Count
} | Format-Table -AutoSize

Write-Host ''
Write-Host "=== NEEDED-ACTIONABLE - Top $ConsoleRows ===" -ForegroundColor Green
$actionable |
    Select-Object -First $ConsoleRows NeededCount,IsApproved,Classification,KB,Title |
    Format-Table -Wrap -AutoSize

Write-Host ''
Write-Host "=== NEEDED-SUPERSEDED - Top $ConsoleRows ===" -ForegroundColor Yellow
$superseded |
    Select-Object -First $ConsoleRows NeededCount,IsApproved,Classification,KB,Title |
    Format-Table -Wrap -AutoSize

Write-Host ''
Write-Host "=== DECLINED-CLEANUP - Top $ConsoleRows ===" -ForegroundColor DarkYellow
$declined |
    Select-Object -First $ConsoleRows NeededCount,IsSuperseded,Classification,KB,Title |
    Format-Table -Wrap -AutoSize

Write-Host ''
Write-Host '=== Report files ===' -ForegroundColor Cyan
Write-Host $summaryTxt
Write-Host $actionableCsv
Write-Host $supersededCsv
Write-Host $declinedCsv

Write-Host ''
Write-Host 'Read-only report completed.' -ForegroundColor Green
