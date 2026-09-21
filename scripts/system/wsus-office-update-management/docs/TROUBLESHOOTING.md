# Troubleshooting - WSUS + Office Update Management

## WSUS post-install fails

Check feature state and the WSUS post-install log. The intended design is WID Connectivity installed and SQL Server Connectivity not installed.

    Get-WindowsFeature *UpdateServices*

## WSUS still references an external SQL Server

    Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Update Services\Server\Setup' |
      Select-Object SqlServerName,SqlDatabaseName,ContentDir

For this design, SqlServerName must be MICROSOFT##WID.

## Residual IIS site after uninstall

    Get-WebSite | Format-List Name,ID,State,PhysicalPath,Bindings

Confirm a stale site has no bindings or applications before removing it.

## WID ACL error - account mapping fails

In PowerShell, the dollar sign in the WID service account can be expanded when double quotes are used. Use a literal/single-quoted account string:

    icacls "D:\WSUS\Database" /grant 'NT SERVICE\MSSQL$MICROSOFT##WID:(OI)(CI)F'

## SUSDB remains on C:

Validate SQL metadata:

    SELECT name,physical_name
    FROM sys.master_files
    WHERE database_id=DB_ID('SUSDB');

Never move MDF/LDF manually while WID is running.

## Initial synchronization is slow

    $subscription.GetSynchronizationStatus()
    $subscription.GetSynchronizationProgress() | Format-List *

A large Updates item count is metadata processing. It does not mean every update binary is downloaded when DownloadUpdateBinariesAsNeeded=True.

## GetLastSynchronizationInfo returns NeverRun

This is normal while the first synchronization is still in progress. It reports the last completed synchronization.

## Windows 11 feature upgrade does not appear

Verify:

- product Windows 11 enabled;
- classification Upgrades enabled;
- initial and post-selection synchronization completed;
- target device is applicable;
- GPO does not pin the device to an older TargetReleaseVersion;
- modern Windows update scan-source policies are not conflicting.

## Windows Server 2022 product not obvious

Search the catalog:

    Get-WsusProduct |
      Where-Object {$_.Product.Title -match 'Server operating system|Server 2022'} |
      Select-Object @{N='Product';E={$_.Product.Title}},Enabled

Windows Server 2022 is commonly represented by Microsoft Server operating system-21H2.

## SQL Server updates do not appear

Confirm Microsoft Update is upstream and list exact SQL Server product titles after the metadata synchronization. Apply only the CU/GDR branch appropriate for the environment.

## Office updates do not appear in WSUS

Expected for Office 2019, Office LTSC 2021 and Office LTSC 2024 Click-to-Run. Use Office CDN or an internal ODT repository.

## Office client cannot update from the local share

Validate:

- SMB/DNS reachability;
- Read permission on the share;
- correct Update Path;
- correct channel: PerpetualVL2019, PerpetualVL2021 or PerpetualVL2024;
- repository contains a complete build;
- Office Automatic Updates 2.0 task is healthy;
- Office, Project and Visio channel compatibility.
