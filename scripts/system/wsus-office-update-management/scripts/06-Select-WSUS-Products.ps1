#requires -RunAsAdministrator
[CmdletBinding(SupportsShouldProcess=$true)]
param(
    [switch]$ListOnly
)

$ErrorActionPreference = 'Stop'
Import-Module UpdateServices
$wsus = Get-WsusServer

$targetPatterns = @(
    '^Windows 11$',
    '^Microsoft Server operating system-21H2$',
    '^Windows Server 2022$',
    'SQL Server 2017',
    'SQL Server 2019',
    'SQL Server 2022'
)

$allProducts = Get-WsusProduct
$candidates = $allProducts | Where-Object {
    $title = $_.Product.Title
    ($targetPatterns | Where-Object { $title -match $_ }).Count -gt 0
} | Sort-Object {$_.Product.Title}

$candidates | Select-Object @{N='Product';E={$_.Product.Title}},Enabled | Format-Table -AutoSize

if ($ListOnly) {
    Write-Host 'List-only mode: no product settings changed.' -ForegroundColor Yellow
    return
}

if (-not $candidates) { throw 'No target products were found. Complete the initial synchronization first.' }

Get-WsusProduct | Set-WsusProduct -Disable -Confirm:$false
foreach ($product in $candidates) {
    if ($PSCmdlet.ShouldProcess($product.Product.Title,'Enable WSUS product')) {
        $product | Set-WsusProduct -Confirm:$false
    }
}

$wantedClassifications = @('Critical Updates','Definition Updates','Security Updates','Update Rollups','Updates','Upgrades')
Get-WsusClassification | Set-WsusClassification -Disable -Confirm:$false
Get-WsusClassification |
    Where-Object { $wantedClassifications -contains $_.Classification.Title } |
    Set-WsusClassification -Confirm:$false

Write-Host 'Enabled products:' -ForegroundColor Cyan
Get-WsusProduct | Where-Object Enabled | Select-Object @{N='Product';E={$_.Product.Title}} | Sort-Object Product | Format-Table -AutoSize
Write-Host 'Enabled classifications:' -ForegroundColor Cyan
$wsus.GetSubscription().GetUpdateClassifications() | Sort-Object Title | Select-Object Title | Format-Table -AutoSize
