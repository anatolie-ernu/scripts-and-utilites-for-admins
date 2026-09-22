#requires -RunAsAdministrator
[CmdletBinding(SupportsShouldProcess=$true)]
param(
    [switch]$Apply,
    [string]$GpoPrefix = 'Computer Policy Deploy - WSUS Updates',
    [string[]]$TargetGroups = @(
        'Windows-11-Pro-Pilot',
        'Windows-11-Pro-Production',
        'Server-Pilot',
        'Server-Production',
        'SQL-Pilot',
        'SQL-Production'
    )
)

$ErrorActionPreference = 'Stop'
Import-Module GroupPolicy

$wuKey = 'HKLM\Software\Policies\Microsoft\Windows\WindowsUpdate'

Write-Host '=== WSUS client-side targeting GPO configurator ===' -ForegroundColor Cyan
Write-Host "Mode: $(if ($Apply) { 'APPLY' } else { 'PREVIEW' })"

$results = foreach ($group in $TargetGroups) {
    $gpoName = "$GpoPrefix $group"
    $existing = Get-GPO -Name $gpoName -ErrorAction SilentlyContinue

    if (-not $Apply) {
        [PSCustomObject]@{
            GPO         = $gpoName
            TargetGroup = $group
            Exists      = [bool]$existing
            Action      = if ($existing) { 'Would update targeting values' } else { 'Would create thin targeting GPO' }
        }
        continue
    }

    if (-not $existing) {
        if ($PSCmdlet.ShouldProcess($gpoName, 'Create GPO')) {
            New-GPO -Name $gpoName | Out-Null
            Write-Host "Created GPO: $gpoName" -ForegroundColor Green
        }
    }
    else {
        Write-Host "GPO exists: $gpoName" -ForegroundColor DarkGray
    }

    if ($PSCmdlet.ShouldProcess($gpoName, "Set TargetGroup=$group")) {
        Set-GPRegistryValue `
            -Name $gpoName `
            -Key $wuKey `
            -ValueName 'TargetGroup' `
            -Type String `
            -Value $group | Out-Null

        Set-GPRegistryValue `
            -Name $gpoName `
            -Key $wuKey `
            -ValueName 'TargetGroupEnabled' `
            -Type DWord `
            -Value 1 | Out-Null
    }

    $values = Get-GPRegistryValue -Name $gpoName -Key $wuKey -ErrorAction SilentlyContinue |
        Where-Object { $_.ValueName -in @('TargetGroup','TargetGroupEnabled') }

    [PSCustomObject]@{
        GPO         = $gpoName
        TargetGroup = $group
        Exists      = $true
        Action      = (($values | ForEach-Object { "$($_.ValueName)=$($_.Value)" }) -join '; ')
    }
}

$results | Format-Table -Wrap -AutoSize

if (-not $Apply) {
    Write-Host ''
    Write-Host 'PREVIEW ONLY. No GPO was created or modified.' -ForegroundColor Yellow
    Write-Host 'Run again with -Apply after reviewing the mapping.' -ForegroundColor Yellow
    return
}

Write-Host ''
Write-Host 'Targeting GPOs configured.' -ForegroundColor Green
Write-Host 'Link each GPO only to the OU that should receive its matching WSUS target group.' -ForegroundColor Yellow
Write-Host 'Keep common WSUS settings in a separate baseline GPO; do not clone workstation-only settings to server OUs without review.' -ForegroundColor Yellow
