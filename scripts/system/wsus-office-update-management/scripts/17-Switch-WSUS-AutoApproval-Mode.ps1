#requires -RunAsAdministrator
[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)]
    [ValidateSet('Conservative','Accelerated')]
    [string]$Mode,

    [switch]$Apply,
    [switch]$ApplyExisting
)

$ErrorActionPreference = 'Stop'
Import-Module UpdateServices

$wsus = Get-WsusServer
$scriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path

$conservativeRules = @(
    'AutoApprove - Windows11 Pilot - Critical Security',
    'AutoApprove - Server Pilot - Critical Security'
)

$acceleratedRules = @(
    'AutoApprove - Windows11 Pilot - Quality',
    'AutoApprove - Server Pilot - Quality',
    'AutoApprove - Windows11 Production - Critical Security',
    'AutoApprove - Server Production - Critical Security'
)

$managedRules = @($conservativeRules + $acceleratedRules)

Write-Host '=== WSUS Auto-Approval Mode Switcher ===' -ForegroundColor Cyan
Write-Host "Requested mode : $Mode"
Write-Host "Mode           : $(if ($Apply) { 'APPLY' } else { 'PREVIEW' })"
Write-Host "ApplyExisting  : $ApplyExisting"

Write-Host ''
Write-Host 'Current managed rules:' -ForegroundColor Yellow
$wsus.GetInstallApprovalRules() |
    Where-Object { $managedRules -contains $_.Name } |
    Sort-Object Name |
    Select-Object Name,Enabled |
    Format-Table -AutoSize

Write-Host ''
if ($Mode -eq 'Conservative') {
    Write-Host 'Target policy:' -ForegroundColor Yellow
    Write-Host '  Pilot      -> Critical + Security'
    Write-Host '  Production -> manual'
}
else {
    Write-Host 'Target policy:' -ForegroundColor Yellow
    Write-Host '  Pilot      -> Critical + Security + Update Rollups + Updates'
    Write-Host '  Production -> Critical + Security'
}

Write-Warning 'Switching modes changes future automatic approvals only. Existing update approvals are NOT revoked automatically.'

if ($Mode -eq 'Conservative') {
    $targetScript = Join-Path $scriptRoot '15-Configure-WSUS-Pilot-AutoApproval.ps1'
}
else {
    $targetScript = Join-Path $scriptRoot '16-Configure-WSUS-Accelerated-AutoApproval.ps1'
}

if (-not (Test-Path $targetScript)) {
    throw "Required mode script not found: $targetScript. No existing auto-approval rules were changed."
}

if (-not $Apply) {
    Write-Host ''
    Write-Host 'PREVIEW ONLY. No rules were enabled or disabled.' -ForegroundColor Yellow
    Write-Host "Run again with -Mode $Mode -Apply after review." -ForegroundColor Yellow
    return
}

Write-Host ''
Write-Host 'Disabling all managed auto-approval rules...' -ForegroundColor Cyan
foreach ($ruleName in $managedRules) {
    $rule = $wsus.GetInstallApprovalRules() | Where-Object Name -eq $ruleName
    if ($rule -and $rule.Enabled) {
        $rule.Enabled = $false
        $rule.Save()
        Write-Host "Disabled: $ruleName" -ForegroundColor DarkGray
    }
}

$args = @{
    Apply = $true
}

if ($ApplyExisting) {
    $args.ApplyExisting = $true
}

Write-Host ''
Write-Host "Activating $Mode mode..." -ForegroundColor Cyan
& $targetScript @args

Write-Host ''
Write-Host '=== Final managed rules ===' -ForegroundColor Cyan
$wsus = Get-WsusServer
$wsus.GetInstallApprovalRules() |
    Where-Object { $managedRules -contains $_.Name } |
    Sort-Object Name |
    Select-Object Name,Enabled |
    Format-Table -AutoSize

Write-Host ''
Write-Host "Active auto-approval mode: $Mode" -ForegroundColor Green
Write-Warning 'Review existing approvals separately if you switched from Accelerated to Conservative; previously approved Production updates remain approved.'
