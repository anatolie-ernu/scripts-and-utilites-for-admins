#requires -RunAsAdministrator
[CmdletBinding()]
param(
    [string[]]$TargetGroups = @('Server-Pilot','Server-Production','SQL-Pilot','SQL-Production'),
    [int]$LookbackDays = 60,
    [switch]$WhatIf
)

$ErrorActionPreference = 'Stop'
Import-Module UpdateServices

$wsus = Get-WsusServer
$subscription = $wsus.GetSubscription()

if ($subscription.GetSynchronizationStatus().ToString() -eq 'Running') {
    Write-Host 'WSUS synchronization is running. Defender approval pass skipped to reduce contention.'
    exit 0
}

$groups = @{}
foreach ($name in $TargetGroups) {
    $group = $wsus.GetComputerTargetGroups() | Where-Object Name -eq $name
    if (-not $group) {
        Write-Warning "Target group does not exist: $name"
        continue
    }
    $groups[$name] = $group
}

if ($groups.Count -eq 0) {
    throw 'None of the configured Defender target groups exist.'
}

$allowed = @(
    @{ KB = '2267602'; Label = 'Defender Security Intelligence' },
    @{ KB = '4052623'; Label = 'Defender Platform Update' }
)

$approvedCount = 0
$alreadyCount = 0
$skippedCount = 0
$cutoffUtc = (Get-Date).ToUniversalTime().AddDays(-1 * [math]::Abs($LookbackDays))

foreach ($item in $allowed) {
    $kb = $item.KB
    $scope = New-Object Microsoft.UpdateServices.Administration.UpdateScope
    $scope.FromArrivalDate = $cutoffUtc
    $scope.TextIncludes = $kb

    $updates = @($wsus.GetUpdates($scope) | Where-Object {
        $normalizedKb = @($_.KnowledgebaseArticles | ForEach-Object { ($_ -replace '^KB','').Trim() })
        ($normalizedKb -contains $kb) -and
        ($_.Title -match 'Defender') -and
        (-not $_.IsDeclined) -and
        (-not $_.IsSuperseded)
    })

    Write-Host "`n$($item.Label) / KB$kb : $($updates.Count) active candidate(s)" -ForegroundColor Cyan

    foreach ($update in $updates) {
        Write-Host "  $($update.Title)"

        if ($update.RequiresLicenseAgreementAcceptance) {
            Write-Warning "  Skipped because a license agreement requires explicit acceptance: $($update.Title)"
            $skippedCount++
            continue
        }

        foreach ($groupName in $groups.Keys) {
            $group = $groups[$groupName]
            $existing = @($update.GetUpdateApprovals($group) | Where-Object {
                $_.Action -eq [Microsoft.UpdateServices.Administration.UpdateApprovalAction]::Install
            })

            if ($existing.Count -gt 0) {
                Write-Host "    Already approved -> $groupName" -ForegroundColor DarkGray
                $alreadyCount++
                continue
            }

            if ($WhatIf) {
                Write-Host "    WHATIF approve -> $groupName" -ForegroundColor Yellow
                continue
            }

            [void]$update.Approve([Microsoft.UpdateServices.Administration.UpdateApprovalAction]::Install,$group)
            Write-Host "    Approved -> $groupName" -ForegroundColor Green
            $approvedCount++
        }
    }
}

Write-Host "`nSummary: approved=$approvedCount already=$alreadyCount skipped=$skippedCount" -ForegroundColor Cyan
