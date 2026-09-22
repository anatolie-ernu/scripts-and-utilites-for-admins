#requires -RunAsAdministrator
[CmdletBinding(SupportsShouldProcess=$true)]
param(
    [switch]$Apply,
    [switch]$ApplyExisting,

    [string]$WindowsPilotGroup      = 'Windows-11-Pro-Pilot',
    [string]$WindowsProductionGroup = 'Windows-11-Pro-Production',
    [string]$ServerPilotGroup       = 'Server-Pilot',
    [string]$ServerProductionGroup  = 'Server-Production',

    [string[]]$PilotClassifications = @(
        'Critical Updates',
        'Security Updates',
        'Update Rollups',
        'Updates'
    ),

    [string[]]$ProductionClassifications = @(
        'Critical Updates',
        'Security Updates'
    )
)

$ErrorActionPreference = 'Stop'
Import-Module UpdateServices

$wsus = Get-WsusServer

$windowsProducts = @('Windows 11')
$serverProducts = @(
    'Microsoft Server operating system-21H2',
    'Microsoft Server Operating System-24H2'
)

$ruleDefinitions = @(
    [PSCustomObject]@{
        RuleName        = 'AutoApprove - Windows11 Pilot - Quality'
        Products        = $windowsProducts
        Classifications = $PilotClassifications
        TargetGroup     = $WindowsPilotGroup
    },
    [PSCustomObject]@{
        RuleName        = 'AutoApprove - Server Pilot - Quality'
        Products        = $serverProducts
        Classifications = $PilotClassifications
        TargetGroup     = $ServerPilotGroup
    },
    [PSCustomObject]@{
        RuleName        = 'AutoApprove - Windows11 Production - Critical Security'
        Products        = $windowsProducts
        Classifications = $ProductionClassifications
        TargetGroup     = $WindowsProductionGroup
    },
    [PSCustomObject]@{
        RuleName        = 'AutoApprove - Server Production - Critical Security'
        Products        = $serverProducts
        Classifications = $ProductionClassifications
        TargetGroup     = $ServerProductionGroup
    }
)

function Get-ExactClassification {
    param([string]$Title)

    $item = $wsus.GetUpdateClassifications() |
        Where-Object Title -eq $Title

    if (-not $item) {
        throw "Classification not found: $Title"
    }

    return $item
}

function Get-ExactProduct {
    param([string]$Title)

    $item = $wsus.GetUpdateCategories() |
        Where-Object {
            $_.Type -eq [Microsoft.UpdateServices.Administration.UpdateCategoryType]::Product -and
            $_.Title -eq $Title
        }

    if (-not $item) {
        throw "Product not found: $Title"
    }

    return $item
}

function Get-ExactTargetGroup {
    param([string]$Name)

    $group = $wsus.GetComputerTargetGroups() |
        Where-Object Name -eq $Name

    if (-not $group) {
        throw "WSUS target group not found: $Name"
    }

    return $group
}

function Resolve-Classifications {
    param([string[]]$Titles)

    return @(
        foreach ($title in $Titles) {
            Get-ExactClassification -Title $title
        }
    )
}

Write-Host '=== WSUS Automatic Approval Ring Policy ===' -ForegroundColor Cyan
Write-Host "Mode: $(if ($Apply) { 'APPLY' } else { 'PREVIEW' })"
Write-Host "Apply existing updates now: $ApplyExisting"
Write-Host ''
Write-Host 'Policy model:' -ForegroundColor Yellow
Write-Host '  Pilot      -> Critical + Security + Update Rollups + Updates'
Write-Host '  Production -> Critical + Security'
Write-Host '  Upgrades   -> manual'
Write-Host '  Drivers    -> manual / disabled by product-classification policy'
Write-Host '  SQL/SSMS/ODBC/OLE DB -> manual'
Write-Host ''
Write-Warning 'The WSUS Updates classification can contain non-security preview/optional quality updates. This is intentional for Pilot only. Production does not include the generic Updates classification.'
Write-Warning 'Critical/Security approvals to Production are immediate at synchronization time; Pilot is not a gate for those two classifications.'

$preview = foreach ($definition in $ruleDefinitions) {

    $resolvedProducts = @(
        foreach ($title in $definition.Products) {
            Get-ExactProduct -Title $title
        }
    )

    $resolvedClassifications = Resolve-Classifications -Titles $definition.Classifications
    $resolvedGroup = Get-ExactTargetGroup -Name $definition.TargetGroup

    $existingRule = $wsus.GetInstallApprovalRules() |
        Where-Object Name -eq $definition.RuleName

    [PSCustomObject]@{
        RuleName        = $definition.RuleName
        Products        = ($resolvedProducts.Title -join '; ')
        Classifications = ($resolvedClassifications.Title -join '; ')
        TargetGroup     = $resolvedGroup.Name
        Exists          = [bool]$existingRule
        Enabled         = if ($existingRule) { $existingRule.Enabled } else { $false }
        Action          = if ($existingRule) { 'Would update conditions and enable' } else { 'Would create and enable' }
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

    Write-Host ''
    Write-Host "=== $($definition.RuleName) ===" -ForegroundColor Cyan

    $rule = $wsus.GetInstallApprovalRules() |
        Where-Object Name -eq $definition.RuleName

    if (-not $rule) {
        if ($PSCmdlet.ShouldProcess($definition.RuleName, 'Create WSUS auto-approval rule')) {
            $rule = $wsus.CreateInstallApprovalRule($definition.RuleName)
            Write-Host "Created rule: $($definition.RuleName)" -ForegroundColor Green
        }
    }
    else {
        Write-Host "Rule already exists: $($definition.RuleName)" -ForegroundColor DarkGray
    }

    $classificationCollection = New-Object Microsoft.UpdateServices.Administration.UpdateClassificationCollection
    foreach ($classification in (Resolve-Classifications -Titles $definition.Classifications)) {
        [void]$classificationCollection.Add($classification)
    }

    $categoryCollection = New-Object Microsoft.UpdateServices.Administration.UpdateCategoryCollection
    foreach ($title in $definition.Products) {
        [void]$categoryCollection.Add((Get-ExactProduct -Title $title))
    }

    $groupCollection = New-Object Microsoft.UpdateServices.Administration.ComputerTargetGroupCollection
    [void]$groupCollection.Add((Get-ExactTargetGroup -Name $definition.TargetGroup))

    if ($PSCmdlet.ShouldProcess($definition.RuleName, 'Configure classifications, products and target group')) {
        $rule.SetUpdateClassifications($classificationCollection)
        $rule.SetCategories($categoryCollection)
        $rule.SetComputerTargetGroups($groupCollection)
        $rule.Enabled = $true
        $rule.Save()
        Write-Host "Enabled: $($definition.RuleName)" -ForegroundColor Green
    }

    if ($ApplyExisting) {
        if ($PSCmdlet.ShouldProcess($definition.RuleName, 'Apply rule to already-synchronized matching updates')) {
            $rule.ApplyRule()
            Write-Host 'Applied rule to existing updates.' -ForegroundColor Green
        }
    }
}

Write-Host ''
Write-Host '=== Final rule verification ===' -ForegroundColor Cyan

$expectedNames = $ruleDefinitions.RuleName
$wsus.GetInstallApprovalRules() |
    Where-Object { $expectedNames -contains $_.Name } |
    Sort-Object Name |
    ForEach-Object {
        $rule = $_

        Write-Host ''
        Write-Host $rule.Name -ForegroundColor Yellow
        Write-Host "Enabled: $($rule.Enabled)"

        Write-Host 'Classifications:'
        $rule.GetUpdateClassifications() |
            Select-Object Title |
            Format-Table -AutoSize

        Write-Host 'Products:'
        $rule.GetCategories() |
            Select-Object Title |
            Format-Table -AutoSize

        Write-Host 'Groups:'
        $rule.GetComputerTargetGroups() |
            Select-Object Name |
            Format-Table -AutoSize
    }

Write-Host ''
Write-Host 'Automatic approval ring policy configured.' -ForegroundColor Green
Write-Host 'Upgrades, Drivers, SQL CU/GDR and SQL tooling remain manual.' -ForegroundColor Yellow
