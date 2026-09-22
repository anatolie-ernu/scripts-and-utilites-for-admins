#requires -RunAsAdministrator
[CmdletBinding(SupportsShouldProcess=$true)]
param(
    [switch]$Apply,
    [switch]$ApplyExisting,

    [string]$WindowsPilotGroup = 'Windows-11-Pro-Pilot',
    [string]$ServerPilotGroup  = 'Server-Pilot',

    [string[]]$Classifications = @(
        'Critical Updates',
        'Security Updates'
    )
)

$ErrorActionPreference = 'Stop'
Import-Module UpdateServices

$wsus = Get-WsusServer

$ruleDefinitions = @(
    [PSCustomObject]@{
        RuleName    = 'AutoApprove - Windows11 Pilot - Critical Security'
        Products    = @('Windows 11')
        TargetGroup = $WindowsPilotGroup
    },
    [PSCustomObject]@{
        RuleName    = 'AutoApprove - Server Pilot - Critical Security'
        Products    = @(
            'Microsoft Server operating system-21H2',
            'Microsoft Server Operating System-24H2'
        )
        TargetGroup = $ServerPilotGroup
    }
)

function Get-ExactClassification {
    param([string]$Title)

    $item = $wsus.GetUpdateClassifications() | Where-Object Title -eq $Title
    if (-not $item) { throw "Classification not found: $Title" }
    return $item
}

function Get-ExactProduct {
    param([string]$Title)

    $item = $wsus.GetUpdateCategories() |
        Where-Object {
            $_.Type -eq [Microsoft.UpdateServices.Administration.UpdateCategoryType]::Product -and
            $_.Title -eq $Title
        }

    if (-not $item) { throw "Product not found: $Title" }
    return $item
}

function Get-ExactTargetGroup {
    param([string]$Name)

    $group = $wsus.GetComputerTargetGroups() | Where-Object Name -eq $Name
    if (-not $group) { throw "WSUS target group not found: $Name" }
    return $group
}

Write-Host '=== WSUS Pilot Auto-Approval - CONSERVATIVE ===' -ForegroundColor Cyan
Write-Host "Mode: $(if ($Apply) { 'APPLY' } else { 'PREVIEW' })"
Write-Host "Apply existing updates now: $ApplyExisting"
Write-Host 'Policy: Critical + Security are auto-approved only to Pilot; Production remains manual.' -ForegroundColor Yellow

$resolvedClassifications = @(
    foreach ($title in $Classifications) {
        Get-ExactClassification -Title $title
    }
)

$preview = foreach ($definition in $ruleDefinitions) {
    $resolvedProducts = @(
        foreach ($title in $definition.Products) {
            Get-ExactProduct -Title $title
        }
    )

    $resolvedGroup = Get-ExactTargetGroup -Name $definition.TargetGroup
    $existingRule = $wsus.GetInstallApprovalRules() | Where-Object Name -eq $definition.RuleName

    [PSCustomObject]@{
        RuleName        = $definition.RuleName
        Products        = ($resolvedProducts.Title -join '; ')
        Classifications = ($resolvedClassifications.Title -join '; ')
        TargetGroup     = $resolvedGroup.Name
        Exists          = [bool]$existingRule
        Enabled         = if ($existingRule) { $existingRule.Enabled } else { $false }
    }
}

$preview | Format-Table -Wrap -AutoSize

if (-not $Apply) {
    Write-Host ''
    Write-Host 'PREVIEW ONLY. No WSUS rule was created or modified.' -ForegroundColor Yellow
    Write-Host 'Run again with -Apply after reviewing the mapping.' -ForegroundColor Yellow
    Write-Host 'Add -ApplyExisting only if already-synchronized matching updates should be approved immediately.' -ForegroundColor Yellow
    return
}

foreach ($definition in $ruleDefinitions) {
    $rule = $wsus.GetInstallApprovalRules() | Where-Object Name -eq $definition.RuleName

    if (-not $rule) {
        $rule = $wsus.CreateInstallApprovalRule($definition.RuleName)
        Write-Host "Created rule: $($definition.RuleName)" -ForegroundColor Green
    }

    $classificationCollection = New-Object Microsoft.UpdateServices.Administration.UpdateClassificationCollection
    foreach ($classification in $resolvedClassifications) {
        [void]$classificationCollection.Add($classification)
    }

    $categoryCollection = New-Object Microsoft.UpdateServices.Administration.UpdateCategoryCollection
    foreach ($title in $definition.Products) {
        [void]$categoryCollection.Add((Get-ExactProduct -Title $title))
    }

    $groupCollection = New-Object Microsoft.UpdateServices.Administration.ComputerTargetGroupCollection
    [void]$groupCollection.Add((Get-ExactTargetGroup -Name $definition.TargetGroup))

    $rule.SetUpdateClassifications($classificationCollection)
    $rule.SetCategories($categoryCollection)
    $rule.SetComputerTargetGroups($groupCollection)
    $rule.Enabled = $true
    $rule.Save()

    Write-Host "Enabled: $($definition.RuleName)" -ForegroundColor Green

    if ($ApplyExisting) {
        $rule.ApplyRule()
        Write-Host 'Applied rule to existing updates.' -ForegroundColor Green
    }
}

Write-Host ''
Write-Host 'Conservative Pilot auto-approval configured.' -ForegroundColor Green
Write-Host 'Production approvals remain manual.' -ForegroundColor Yellow
