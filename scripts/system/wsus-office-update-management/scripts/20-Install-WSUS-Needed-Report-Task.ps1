
#requires -RunAsAdministrator
[CmdletBinding()]
param(
    [switch]$Apply,

    [string]$TaskName = 'WSUS - Needed Operational Report',
    [string]$ReportScriptPath = 'D:\Scripts\19-WSUS-Needed-Operational-Report.ps1',
    [string]$OutputDirectory = 'D:\WSUSReports\Operational',

    [ValidatePattern('^(?:[01]\d|2[0-3]):[0-5]\d$')]
    [string]$DailyAt = '08:00',

    [Parameter(Mandatory)]
    [string]$SmtpServer,

    [ValidateRange(1,65535)]
    [int]$SmtpPort = 25,

    [switch]$UseSsl,

    [Parameter(Mandatory)]
    [string]$MailFrom,

    [Parameter(Mandatory)]
    [string]$MailTo,

    [string]$MailSubjectPrefix = '[WSUS]'
)

$ErrorActionPreference = 'Stop'

if (-not (Test-Path -LiteralPath $ReportScriptPath)) {
    throw "Report script not found: $ReportScriptPath"
}

function Quote-Argument {
    param([string]$Value)

    if ($null -eq $Value) {
        return '""'
    }

    return '"' + ($Value -replace '"','\"') + '"'
}

$arguments = @(
    '-NoLogo',
    '-NoProfile',
    '-NonInteractive',
    '-ExecutionPolicy',
    'RemoteSigned',
    '-File',
    (Quote-Argument $ReportScriptPath),
    '-OutputDirectory',
    (Quote-Argument $OutputDirectory),
    '-SendEmail',
    '-SmtpServer',
    (Quote-Argument $SmtpServer),
    '-SmtpPort',
    $SmtpPort,
    '-MailFrom',
    (Quote-Argument $MailFrom),
    '-MailTo',
    (Quote-Argument $MailTo),
    '-MailSubjectPrefix',
    (Quote-Argument $MailSubjectPrefix)
)

if ($UseSsl) {
    $arguments += '-UseSsl'
}

$argumentString = $arguments -join ' '

$timeParts = $DailyAt.Split(':')
$triggerTime = Get-Date -Hour ([int]$timeParts[0]) -Minute ([int]$timeParts[1]) -Second 0

$action = New-ScheduledTaskAction -Execute 'PowerShell.exe' -Argument $argumentString
$trigger = New-ScheduledTaskTrigger -Daily -At $triggerTime

$settingsParams = @{
    StartWhenAvailable  = $true
    MultipleInstances   = 'IgnoreNew'
    ExecutionTimeLimit  = (New-TimeSpan -Hours 2)
}
$settings = New-ScheduledTaskSettingsSet @settingsParams

$principalParams = @{
    UserId    = 'SYSTEM'
    LogonType = 'ServiceAccount'
    RunLevel  = 'Highest'
}
$principal = New-ScheduledTaskPrincipal @principalParams

Write-Host '=== WSUS Needed Report Scheduled Task ===' -ForegroundColor Cyan
Write-Host "Mode            : $(if ($Apply) { 'APPLY' } else { 'PREVIEW' })"
Write-Host "TaskName        : $TaskName"
Write-Host "Schedule        : Daily at $DailyAt"
Write-Host "RunAs           : SYSTEM"
Write-Host "ReportScript    : $ReportScriptPath"
Write-Host "OutputDirectory : $OutputDirectory"
Write-Host "SMTP            : $SmtpServer:$SmtpPort"
Write-Host "UseSsl          : $UseSsl"
Write-Host "MailFrom        : $MailFrom"
Write-Host "MailTo          : $MailTo"
Write-Host ''
Write-Host 'Attachments:' -ForegroundColor Yellow
Write-Host '  00-Summary.txt'
Write-Host '  01-Needed-Actionable.csv'
Write-Host '  02-Needed-Superseded.csv'
Write-Host '  03-Declined-Cleanup.csv'
Write-Host ''
Write-Host 'Email body: HTML with color-coded Actionable, Superseded and Declined/Cleanup sections.' -ForegroundColor Yellow

if (-not $Apply) {
    Write-Host ''
    Write-Host 'PREVIEW ONLY. Scheduled Task was not created or changed.' -ForegroundColor Yellow
    Write-Host 'Run again with -Apply after reviewing the SMTP and schedule settings.' -ForegroundColor Yellow
    return
}

$existing = Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue

if ($existing) {
    Write-Host "Replacing existing task: $TaskName" -ForegroundColor Yellow
    Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false
}

$registerParams = @{
    TaskName    = $TaskName
    Action      = $action
    Trigger     = $trigger
    Settings    = $settings
    Principal   = $principal
    Description = 'Generates the read-only WSUS Needed operational report and sends an HTML email with CSV attachments.'
}
Register-ScheduledTask @registerParams | Out-Null

$task = Get-ScheduledTask -TaskName $TaskName
$taskInfo = Get-ScheduledTaskInfo -TaskName $TaskName

Write-Host ''
Write-Host '=== Installed task ===' -ForegroundColor Cyan
[PSCustomObject]@{
    TaskName       = $task.TaskName
    State          = $task.State
    NextRunTime    = $taskInfo.NextRunTime
    LastRunTime    = $taskInfo.LastRunTime
    LastTaskResult = $taskInfo.LastTaskResult
    RunAs          = $task.Principal.UserId
} | Format-List

Write-Host ''
Write-Host 'Scheduled Task installed.' -ForegroundColor Green
Write-Warning 'This default SYSTEM task assumes the SMTP server accepts relay from the WSUS server without interactive authentication. Do not store SMTP passwords in this public script.'
