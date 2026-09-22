#requires -RunAsAdministrator
[CmdletBinding()]
param(
    [string]$OutputDirectory = 'D:\WSUSReports\Operational',

    [ValidateRange(1,500)]
    [int]$ConsoleRows = 25,

    [switch]$SendEmail,
    [string]$SmtpServer,
    [ValidateRange(1,65535)]
    [int]$SmtpPort = 25,
    [switch]$UseSsl,
    [string]$MailFrom,
    [string]$MailTo,
    [string]$CredentialPath,
    [string]$MailSubjectPrefix = '[WSUS]'
)

$ErrorActionPreference = 'Stop'
Import-Module UpdateServices

$wsus = Get-WsusServer

Write-Host '=== WSUS Needed Operational Report ===' -ForegroundColor Cyan
Write-Host "Server          : $($wsus.Name)"
Write-Host "OutputDirectory : $OutputDirectory"
Write-Host "ConsoleRows     : $ConsoleRows"
Write-Host "SendEmail       : $SendEmail"

if ($SendEmail) {
    if ([string]::IsNullOrWhiteSpace($SmtpServer)) {
        throw 'SmtpServer is required when -SendEmail is used.'
    }

    if ([string]::IsNullOrWhiteSpace($MailFrom)) {
        throw 'MailFrom is required when -SendEmail is used.'
    }

    if ([string]::IsNullOrWhiteSpace($MailTo)) {
        throw 'At least one MailTo recipient is required when -SendEmail is used.'
    }

    $mailRecipients = @(
        $MailTo -split '[;,]' |
            ForEach-Object { $_.Trim() } |
            Where-Object { -not [string]::IsNullOrWhiteSpace($_) }
    )

    if ($mailRecipients.Count -eq 0) {
        throw 'MailTo did not contain a valid recipient.'
    }

    if ($CredentialPath -and -not (Test-Path -LiteralPath $CredentialPath)) {
        throw "CredentialPath not found: $CredentialPath"
    }
}

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
@(
    [PSCustomObject]@{
        Category = 'NEEDED-ACTIONABLE'
        Count    = $actionable.Count
    }
    [PSCustomObject]@{
        Category = 'NEEDED-SUPERSEDED'
        Count    = $superseded.Count
    }
    [PSCustomObject]@{
        Category = 'DECLINED-CLEANUP'
        Count    = $declined.Count
    }
) | Format-Table -AutoSize

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


if ($SendEmail) {
    Write-Host ''
    Write-Host '=== Sending email ===' -ForegroundColor Cyan

    $subject = "$MailSubjectPrefix WSUS Needed Report - $($wsus.Name) - $(Get-Date -Format 'yyyy-MM-dd')"

    function Convert-SectionToHtml {
        param(
            [object[]]$Rows,
            [string]$Title,
            [string]$HeaderColor,
            [int]$Top = 10
        )

        $selected = @(
            $Rows | Select-Object -First $Top NeededCount,IsApproved,Classification,KB,Title
        )

        if ($selected.Count -eq 0) {
            $table = '<p style="margin:8px 0 16px 0;">No entries.</p>'
        }
        else {
            $table = ($selected | ConvertTo-Html -Fragment -Property NeededCount,IsApproved,Classification,KB,Title) -join [Environment]::NewLine
            $table = $table -replace '<table>', '<table style="border-collapse:collapse;width:100%;font-family:Segoe UI,Arial,sans-serif;font-size:12px;">'
            $table = $table -replace '<th>', '<th style="border:1px solid #d0d0d0;padding:6px;text-align:left;background:#f3f3f3;">'
            $table = $table -replace '<td>', '<td style="border:1px solid #d0d0d0;padding:6px;vertical-align:top;">'
        }

        return @"
<div style="margin:18px 0;border:1px solid #d0d0d0;border-radius:6px;overflow:hidden;">
  <div style="background:$HeaderColor;color:#ffffff;padding:10px 12px;font-weight:600;font-size:15px;">
    $Title ($($Rows.Count))
  </div>
  <div style="padding:10px 12px;background:#ffffff;">
    $table
  </div>
</div>
"@
    }

    $actionableHtml = Convert-SectionToHtml -Rows $actionable -Title 'NEEDED-ACTIONABLE' -HeaderColor '#2e7d32'
    $supersededHtml = Convert-SectionToHtml -Rows $superseded -Title 'NEEDED-SUPERSEDED' -HeaderColor '#ef6c00'
    $declinedHtml = Convert-SectionToHtml -Rows $declined -Title 'DECLINED-CLEANUP' -HeaderColor '#616161'

    $body = @"
<html>
<body style="font-family:Segoe UI,Arial,sans-serif;background:#f7f7f7;color:#202020;padding:18px;">
<div style="max-width:1100px;margin:0 auto;background:#ffffff;border:1px solid #dddddd;border-radius:8px;padding:20px;">
  <h2 style="margin-top:0;">WSUS Needed Operational Report</h2>

  <p>
    <b>Server:</b> $($wsus.Name)<br/>
    <b>Generated:</b> $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')
  </p>

  <table style="border-collapse:collapse;margin:14px 0 20px 0;">
    <tr>
      <td style="padding:8px 14px;background:#e8f5e9;border:1px solid #c8e6c9;"><b>NEEDED-ACTIONABLE</b></td>
      <td style="padding:8px 14px;background:#e8f5e9;border:1px solid #c8e6c9;">$($actionable.Count)</td>
    </tr>
    <tr>
      <td style="padding:8px 14px;background:#fff3e0;border:1px solid #ffe0b2;"><b>NEEDED-SUPERSEDED</b></td>
      <td style="padding:8px 14px;background:#fff3e0;border:1px solid #ffe0b2;">$($superseded.Count)</td>
    </tr>
    <tr>
      <td style="padding:8px 14px;background:#eeeeee;border:1px solid #dddddd;"><b>DECLINED-CLEANUP</b></td>
      <td style="padding:8px 14px;background:#eeeeee;border:1px solid #dddddd;">$($declined.Count)</td>
    </tr>
  </table>

  $actionableHtml
  $supersededHtml
  $declinedHtml

  <p style="font-size:11px;color:#666666;margin-top:20px;">
    Full CSV reports are attached. This report is read-only and does not approve, decline, delete, or otherwise modify WSUS updates.
  </p>
</div>
</body>
</html>
"@

    $mail = New-Object System.Net.Mail.MailMessage
    $smtp = $null

    try {
        $mail.From = New-Object System.Net.Mail.MailAddress($MailFrom)

        foreach ($recipient in $mailRecipients) {
            if (-not [string]::IsNullOrWhiteSpace($recipient)) {
                [void]$mail.To.Add($recipient.Trim())
            }
        }

        $mail.Subject = $subject
        $mail.Body = $body
        $mail.IsBodyHtml = $true

        foreach ($attachmentPath in @($summaryTxt,$actionableCsv,$supersededCsv,$declinedCsv)) {
            [void]$mail.Attachments.Add((New-Object System.Net.Mail.Attachment($attachmentPath)))
        }

        $smtp = New-Object System.Net.Mail.SmtpClient($SmtpServer,$SmtpPort)
        $smtp.EnableSsl = [bool]$UseSsl

        if ($CredentialPath) {
            $credential = Import-Clixml -LiteralPath $CredentialPath
            if (-not ($credential -is [System.Management.Automation.PSCredential])) {
                throw "CredentialPath does not contain a PSCredential: $CredentialPath"
            }

            $smtp.UseDefaultCredentials = $false
            $smtp.Credentials = $credential.GetNetworkCredential()
        }
        else {
            $smtp.UseDefaultCredentials = $false
        }

        $smtp.Send($mail)
        Write-Host "Email sent to: $($mailRecipients -join ', ')" -ForegroundColor Green
    }
    finally {
        if ($mail) { $mail.Dispose() }
        if ($smtp) { $smtp.Dispose() }
    }
}

Write-Host ''
Write-Host 'Read-only report completed.' -ForegroundColor Green
