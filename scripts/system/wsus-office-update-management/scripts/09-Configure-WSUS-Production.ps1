#requires -RunAsAdministrator
[CmdletBinding(SupportsShouldProcess=$true, ConfirmImpact='High')]
param(
    [switch]$Apply,
    [int]$SynchronizationsPerDay = 6,
    [TimeSpan]$FirstSyncLocalTime = ([TimeSpan]::FromHours(2)),
    [switch]$InstallDefenderTask,
    [string]$TaskRoot = 'C:\Scripts\WSUS'
)

$ErrorActionPreference = 'Stop'
Import-Module UpdateServices

$wsus = Get-WsusServer
$subscription = $wsus.GetSubscription()

Write-Host '=== WSUS Production Policy ===' -ForegroundColor Cyan
Write-Host "Server: $($wsus.Name):$($wsus.PortNumber)"

$lastSync = $subscription.GetLastSynchronizationInfo()
Write-Host "Last sync result: $($lastSync.Result)"
if ($Apply -and $lastSync.Result -ne 'Succeeded') {
    throw 'The last WSUS synchronization is not Succeeded. Complete a successful metadata synchronization before applying the production policy.'
}

$productRules = [ordered]@{
    Windows11    = @('^Windows 11$')
    Server2022   = @('^Microsoft Server operating system-21H2$', '^Windows Server 2022$')
    Server2025   = @('^Microsoft Server operating system-24H2$', '^Windows Server 2025$')
    SQL2017      = @('^Microsoft SQL Server 2017$')
    SQL2019      = @('^Microsoft SQL Server 2019$')
    SQL2022      = @('^Microsoft SQL Server 2022$')
    SSMS17       = @('^Microsoft SQL Server Management Studio v17$')
    SSMS18       = @('^Microsoft SQL Server Management Studio v18$')
    SSMS19       = @('^Microsoft SQL Server Management Studio v19$')
    SSMS20       = @('^Microsoft SQL Server Management Studio v20$')
    ODBC17       = @('^Microsoft ODBC Driver 17 for SQL Server$')
    ODBC18       = @('^Microsoft ODBC Driver 18 for SQL Server$')
    OLEDB18      = @('^Microsoft OLE DB Driver 18 for SQL Server$')
    OLEDB19      = @('^Microsoft OLE DB Driver 19 for SQL Server$')
    Defender     = @('^Microsoft Defender Antivirus$', '^Windows Defender$')
}

$allProducts = @(Get-WsusProduct)
$selectedProducts = @()
$missingFamilies = @()

foreach ($family in $productRules.Keys) {
    $patterns = $productRules[$family]
    $matches = @($allProducts | Where-Object {
        $title = $_.Product.Title
        ($patterns | Where-Object { $title -match $_ }).Count -gt 0
    })

    if ($matches.Count -eq 0) {
        $missingFamilies += $family
        Write-Warning "No product match found for required family: $family"
        continue
    }

    Write-Host "`n[$family]" -ForegroundColor Yellow
    $matches | Select-Object @{N='Product';E={$_.Product.Title}} | Sort-Object Product | Format-Table -AutoSize
    $selectedProducts += $matches
}

$selectedProducts = @($selectedProducts | Sort-Object {$_.Product.Title} -Unique)

$wantedClassifications = @(
    'Critical Updates',
    'Definition Updates',
    'Security Updates',
    'Update Rollups',
    'Updates',
    'Upgrades'
)

$availableClassifications = @(Get-WsusClassification)
$missingClassifications = @($wantedClassifications | Where-Object {
    $wanted = $_
    -not ($availableClassifications | Where-Object {$_.Classification.Title -eq $wanted})
})

Write-Host "`nTarget classifications:" -ForegroundColor Cyan
$wantedClassifications | ForEach-Object { Write-Host "  $_" }

$groupNames = @(
    'Windows-11-Pro-Pilot',
    'Windows-11-Pro-Production',
    'Server-Pilot',
    'Server-Production',
    'SQL-Pilot',
    'SQL-Production'
)

Write-Host "`nTarget WSUS groups:" -ForegroundColor Cyan
$groupNames | ForEach-Object { Write-Host "  $_" }

if (-not $Apply) {
    Write-Host "`nPREVIEW ONLY. No WSUS settings were changed." -ForegroundColor Yellow
    if ($missingFamilies.Count -gt 0) {
        Write-Warning ('Missing required product families: ' + ($missingFamilies -join ', '))
    }
    if ($missingClassifications.Count -gt 0) {
        Write-Warning ('Missing classifications: ' + ($missingClassifications -join ', '))
    }
    Write-Host 'Run again with -Apply after reviewing the exact product list.' -ForegroundColor Yellow
    Write-Host 'Add -InstallDefenderTask to install the hourly Defender-only approval task.' -ForegroundColor Yellow
    return
}

if ($missingFamilies.Count -gt 0) {
    throw ('Cannot apply: missing required product families: ' + ($missingFamilies -join ', '))
}
if ($missingClassifications.Count -gt 0) {
    throw ('Cannot apply: missing required classifications: ' + ($missingClassifications -join ', '))
}

if ($PSCmdlet.ShouldProcess('WSUS Products','Disable all products and enable only the approved production set')) {
    Get-WsusProduct | Set-WsusProduct -Disable -Confirm:$false
    $selectedProducts | Set-WsusProduct -Confirm:$false
}

if ($PSCmdlet.ShouldProcess('WSUS Classifications','Disable all classifications and enable only the approved production set')) {
    Get-WsusClassification | Set-WsusClassification -Disable -Confirm:$false
    Get-WsusClassification |
        Where-Object { $wantedClassifications -contains $_.Classification.Title } |
        Set-WsusClassification -Confirm:$false
}

$existingGroups = @($wsus.GetComputerTargetGroups())
foreach ($groupName in $groupNames) {
    $existing = $existingGroups | Where-Object Name -eq $groupName
    if (-not $existing) {
        if ($PSCmdlet.ShouldProcess($groupName,'Create WSUS computer target group')) {
            [void]$wsus.CreateComputerTargetGroup($groupName)
            Write-Host "Created group: $groupName" -ForegroundColor Green
        }
    } else {
        Write-Host "Group exists: $groupName" -ForegroundColor DarkGray
    }
}

if ($SynchronizationsPerDay -lt 1 -or $SynchronizationsPerDay -gt 24) {
    throw 'SynchronizationsPerDay must be between 1 and 24.'
}

$localStart = [DateTime]::Today.Add($FirstSyncLocalTime)
$utcTimeOfDay = $localStart.ToUniversalTime().TimeOfDay
$subscription.SynchronizeAutomatically = $true
$subscription.NumberOfSynchronizationsPerDay = $SynchronizationsPerDay
$subscription.SynchronizeAutomaticallyTimeOfDay = $utcTimeOfDay
$subscription.Save()

Write-Host "Automatic synchronization enabled: $SynchronizationsPerDay time(s)/day; first local time $FirstSyncLocalTime" -ForegroundColor Green

if ($InstallDefenderTask) {
    $workerSource = Join-Path $PSScriptRoot '10-Approve-DefenderUpdates.ps1'
    if (-not (Test-Path $workerSource)) {
        throw "Defender worker script not found: $workerSource"
    }

    New-Item -ItemType Directory -Path $TaskRoot -Force | Out-Null
    $workerDest = Join-Path $TaskRoot 'Approve-DefenderUpdates.ps1'
    Copy-Item $workerSource $workerDest -Force
    Unblock-File -Path $workerDest -ErrorAction SilentlyContinue

    $taskName = 'WSUS - Auto Approve Defender Updates'
    $taskCommand = 'PowerShell.exe -NoLogo -NoProfile -NonInteractive -File "' + $workerDest + '"'
    $taskStart = (Get-Date).AddMinutes(2).ToString('HH:mm')
    & schtasks.exe /Create /TN $taskName /SC HOURLY /MO 1 /ST $taskStart /TR $taskCommand /RU SYSTEM /RL HIGHEST /F | Out-Host
    if ($LASTEXITCODE -ne 0) { throw "Failed to create scheduled task: $taskName" }

    Write-Host "Installed scheduled task: $taskName" -ForegroundColor Green
    Write-Host "Worker: $workerDest" -ForegroundColor Green
}

Write-Host "`n=== Products selected for synchronization ===" -ForegroundColor Cyan
$subscription = $wsus.GetSubscription()
$subscription.GetUpdateCategories() |
    Where-Object { $_.Type -eq [Microsoft.UpdateServices.Administration.UpdateCategoryType]::Product } |
    Sort-Object Title |
    Select-Object Title |
    Format-Table -AutoSize

Write-Host '=== Enabled classifications ===' -ForegroundColor Cyan
$subscription.GetUpdateClassifications() | Sort-Object Title | Select-Object Title | Format-Table -AutoSize

Write-Host '=== WSUS groups ===' -ForegroundColor Cyan
$wsus.GetComputerTargetGroups() | Where-Object {$groupNames -contains $_.Name} | Sort-Object Name | Select-Object Name | Format-Table -AutoSize

Write-Host 'Production policy configured.' -ForegroundColor Green
