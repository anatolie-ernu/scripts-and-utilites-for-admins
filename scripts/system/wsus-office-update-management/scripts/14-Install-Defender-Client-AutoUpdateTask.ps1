#requires -RunAsAdministrator
[CmdletBinding(SupportsShouldProcess=$true)]
param(
    [string]$InstallRoot = 'C:\Scripts\WSUS',
    [string]$TaskName = 'WSUS - Install Approved Defender Updates',
    [switch]$Apply
)

$ErrorActionPreference = 'Stop'

$workerPath = Join-Path $InstallRoot 'Install-Approved-DefenderUpdates.ps1'
$logRoot = 'C:\ProgramData\WSUS-Defender-AutoUpdate'

$worker = @'
[CmdletBinding()]
param(
    [switch]$WhatIf
)

$ErrorActionPreference = 'Stop'
$logRoot = 'C:\ProgramData\WSUS-Defender-AutoUpdate'
$logFile = Join-Path $logRoot 'DefenderAutoUpdate.log'
New-Item -ItemType Directory -Path $logRoot -Force | Out-Null

function Write-Log {
    param([string]$Message)
    $line = "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') $Message"
    Add-Content -Path $logFile -Value $line
    Write-Host $line
}

$allowedKbs = @('2267602','4052623')

try {
    $session = New-Object -ComObject Microsoft.Update.Session
    $searcher = $session.CreateUpdateSearcher()
    $result = $searcher.Search("IsInstalled=0 and Type='Software' and IsHidden=0")

    $candidates = @(
        foreach ($update in $result.Updates) {
            $normalizedKb = @($update.KBArticleIDs | ForEach-Object { ($_ -replace '^KB','').Trim() })
            $kb = $allowedKbs | Where-Object { $normalizedKb -contains $_ }

            if (
                $kb -and
                $update.Title -match 'Defender' -and
                $update.Title -match 'Current Channel \(Broad\)'
            ) {
                [PSCustomObject]@{
                    KB     = $kb | Select-Object -First 1
                    Update = $update
                }
            }
        }
    )

    if ($candidates.Count -eq 0) {
        Write-Log 'No approved Broad-channel Defender updates are currently applicable.'
        exit 0
    }

    foreach ($candidate in $candidates) {
        $update = $candidate.Update
        $kb = $candidate.KB

        Write-Log "Candidate KB$kb: $($update.Title)"

        if ($WhatIf) {
            Write-Log "WHATIF: would download/install KB$kb"
            continue
        }

        if (-not $update.EulaAccepted) {
            try { $update.AcceptEula() } catch {}
        }

        $collection = New-Object -ComObject Microsoft.Update.UpdateColl
        [void]$collection.Add($update)

        if (-not $update.IsDownloaded) {
            $downloader = $session.CreateUpdateDownloader()
            $downloader.Updates = $collection
            $downloadResult = $downloader.Download()
            Write-Log "KB$kb download result: $($downloadResult.ResultCode)"
        }

        $installer = $session.CreateUpdateInstaller()
        $installer.Updates = $collection
        $installer.ForceQuiet = $true

        $installResult = $installer.Install()
        Write-Log "KB$kb install result: $($installResult.ResultCode); rebootRequired=$($installResult.RebootRequired)"
    }

    exit 0
}
catch {
    Write-Log "ERROR: $($_.Exception.Message)"
    exit 1
}
'@

Write-Host '=== Defender client auto-update task installer ===' -ForegroundColor Cyan
Write-Host "Install root : $InstallRoot"
Write-Host "Worker       : $workerPath"
Write-Host "Task         : $TaskName"
Write-Host "Mode         : $(if ($Apply) { 'APPLY' } else { 'PREVIEW' })"
Write-Host ''
Write-Host 'The worker installs only applicable WSUS-approved Broad-channel Defender updates:' -ForegroundColor Yellow
Write-Host '  KB2267602 - Security Intelligence'
Write-Host '  KB4052623 - Defender Platform'
Write-Host 'It does not install Windows cumulative, .NET, SQL, driver, or feature updates.'

if (-not $Apply) {
    Write-Host ''
    Write-Host 'PREVIEW ONLY. No files or scheduled tasks were created.' -ForegroundColor Yellow
    Write-Host 'Run again with -Apply on a pilot server after validating the baseline GPO.' -ForegroundColor Yellow
    return
}

if ($PSCmdlet.ShouldProcess($InstallRoot, 'Create Defender worker and scheduled task')) {
    New-Item -ItemType Directory -Path $InstallRoot -Force | Out-Null
    New-Item -ItemType Directory -Path $logRoot -Force | Out-Null

    Set-Content -Path $workerPath -Value $worker -Encoding UTF8
    Unblock-File -Path $workerPath -ErrorAction SilentlyContinue

    $taskCommand = 'PowerShell.exe -NoLogo -NoProfile -NonInteractive -ExecutionPolicy RemoteSigned -File "' + $workerPath + '"'
    $taskStart = (Get-Date).AddMinutes(2).ToString('HH:mm')

    & schtasks.exe /Create /TN $TaskName /SC HOURLY /MO 1 /ST $taskStart /TR $taskCommand /RU SYSTEM /RL HIGHEST /F | Out-Host
    if ($LASTEXITCODE -ne 0) {
        throw "Failed to create scheduled task: $TaskName"
    }

    Write-Host "Installed worker: $workerPath" -ForegroundColor Green
    Write-Host "Installed task  : $TaskName" -ForegroundColor Green
    Write-Host "Log directory   : $logRoot" -ForegroundColor Green
}

Write-Host ''
Write-Host 'Pilot validation command:' -ForegroundColor Cyan
Write-Host "  PowerShell.exe -NoLogo -NoProfile -ExecutionPolicy RemoteSigned -File \"$workerPath\" -WhatIf"
