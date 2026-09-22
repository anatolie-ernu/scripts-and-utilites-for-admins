#requires -RunAsAdministrator
[CmdletBinding(SupportsShouldProcess=$true)]
param(
    [switch]$Apply,
    [switch]$ApplyExisting,

    [string]$RuleName = 'AutoApprove - Defender Definition Updates - All Managed Computers',

    [string[]]$TargetGroups = @(
        'Windows-11-Pro-Pilot',
        'Windows-11-Pro-Production',
        'Server-Pilot',
        'Server-Production',
        'SQL-Pilot',
        'SQL-Production'
    ),

    [string]$ProductName = 'Microsoft Defender Antivirus',
    [string]$ClassificationName = 'Definition Updates'
)

$ErrorActionPreference = 'Stop'
Import-Module UpdateServices

$wsus = Get-WsusServer

function Get-ExactProduct {
    param([string]$Title)

    $item = $wsus.GetUpdateCategories() |
        Where-Object {
            $_.Type -eq [Microsoft.UpdateServices.Administration.UpdateCategoryType]::Product -and
            $_.Title -eq $Title
        }

    if (-not $item) {
        throw "WSUS product not found: $Title"
    }

    return $item
}

function Get-ExactClassification {
    param([string]$Title)

    $item = $wsus.GetUpdateClassifications() |
        Where-Object Title -eq $Title

    if (-not $item) {
        throw "WSUS classification not found: $Title"
    }

    return $item
}

function Get-ExactTargetGroup {
    param([string]$Name)

    $group = $wsus.GetComputerTargetGroups() |
        Where-Object Name -eq $Name

    if (-not $group) {
        throw "WSUS computer group not found: $Name"
    }

    return $group
}

Write-Host '=== WSUS Defender Definition Auto-Approval ===' -ForegroundColor Cyan
Write-Host "Mode          : $(if ($Apply) { 'APPLY' } else { 'PREVIEW' })"
Write-Host "ApplyExisting : $ApplyExisting"
Write-Host "Rule          : $RuleName"

$product = Get-ExactProduct -Title $ProductName
$classification = Get-ExactClassification -Title $ClassificationName

$groups = @(
    foreach ($groupName in $TargetGroups) {
        Get-ExactTargetGroup -Name $groupName
    }
)

$existingRule = $wsus.GetInstallApprovalRules() |
    Where-Object Name -eq $RuleName

Write-Host ''
Write-Host 'Product:' -ForegroundColor Yellow
$product | Select-Object Title | Format-Table -AutoSize

Write-Host 'Classification:' -ForegroundColor Yellow
$classification | Select-Object Title | Format-Table -AutoSize

Write-Host 'Target groups:' -ForegroundColor Yellow
$groups | Sort-Object Name | Select-Object Name | Format-Table -AutoSize

Write-Host "Rule exists   : $([bool]$existingRule)"
Write-Host "Rule enabled  : $(if ($existingRule) { $existingRule.Enabled } else { $false })"

Write-Warning 'This rule approves Definition Updates only when they are categorized under the Microsoft Defender Antivirus product.'
Write-Warning 'It does not approve Critical, Security, Updates, Update Rollups, Upgrades, Drivers, SQL CU/GDR, SSMS, ODBC or OLE DB updates.'

if (-not $Apply) {
    Write-Host ''
    Write-Host 'PREVIEW ONLY. No WSUS rule was created or modified.' -ForegroundColor Yellow
    Write-Host 'Run again with -Apply after reviewing the product, classification and groups.' -ForegroundColor Yellow
    Write-Host 'Add -ApplyExisting only if already-synchronized matching Defender Definition Updates should be approved immediately.' -ForegroundColor Yellow
    return
}

$rule = $existingRule
if (-not $rule) {
    if ($PSCmdlet.ShouldProcess($RuleName, 'Create WSUS auto-approval rule')) {
        $rule = $wsus.CreateInstallApprovalRule($RuleName)
        Write-Host "Created rule: $RuleName" -ForegroundColor Green
    }
}

$classCollection = New-Object Microsoft.UpdateServices.Administration.UpdateClassificationCollection
[void]$classCollection.Add($classification)

$productCollection = New-Object Microsoft.UpdateServices.Administration.UpdateCategoryCollection
[void]$productCollection.Add($product)

$groupCollection = New-Object Microsoft.UpdateServices.Administration.ComputerTargetGroupCollection
foreach ($group in $groups) {
    [void]$groupCollection.Add($group)
}

if ($PSCmdlet.ShouldProcess($RuleName, 'Configure Defender Definition Updates auto-approval')) {
    $rule.SetUpdateClassifications($classCollection)
    $rule.SetCategories($productCollection)
    $rule.SetComputerTargetGroups($groupCollection)
    $rule.Enabled = $true
    $rule.Save()

    Write-Host "Enabled: $RuleName" -ForegroundColor Green
}

if ($ApplyExisting) {
    if ($PSCmdlet.ShouldProcess($RuleName, 'Apply rule to already-synchronized matching updates')) {
        $rule.ApplyRule()
        Write-Host 'Applied rule to existing matching updates.' -ForegroundColor Green
    }
}

Write-Host ''
Write-Host '=== Verification ===' -ForegroundColor Cyan
Write-Host "Rule: $($rule.Name)"
Write-Host "Enabled: $($rule.Enabled)"

Write-Host ''
Write-Host 'Classification:'
$rule.GetUpdateClassifications() |
    Select-Object Title |
    Format-Table -AutoSize

Write-Host 'Product:'
$rule.GetCategories() |
    Select-Object Title |
    Format-Table -AutoSize

Write-Host 'Groups:'
$rule.GetComputerTargetGroups() |
    Sort-Object Name |
    Select-Object Name |
    Format-Table -AutoSize

Write-Host ''
Write-Host 'Defender Definition Updates auto-approval configured.' -ForegroundColor Green
