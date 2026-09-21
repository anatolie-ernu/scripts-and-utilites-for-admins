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

## Synchronization fails with UssCommunicationError although TCP 443 works

Typical symptom:

    Result : Failed
    Error  : UssCommunicationError

with an ErrorText similar to:

    WebException: Unable to connect to the remote server
    ... <Microsoft-IP>:443
    ... ServerSyncProxy.GetUpdateData(...)

Do not assume that WSUS/WID/SUSDB is broken if post-install succeeded and SUSDB is ONLINE.

Validate in this order:

1. Microsoft Update endpoint:

       $config = $wsus.GetConfiguration()
       $config.MUUrl

2. Direct TCP connectivity:

       Test-NetConnection sws.update.microsoft.com -Port 443

3. WSUS proxy configuration:

       $config | Select-Object UseProxy,ProxyName,ProxyServerPort,AnonymousProxyAccess

4. WinHTTP:

       netsh winhttp show proxy

5. TLS 1.2 in SCHANNEL/WSUS log:

       Select-String -Path "C:\Program Files\Update Services\LogFiles\SoftwareDistribution.log" -Pattern "TLS 1.2|SCHANNEL Protocol" |
         Select-Object -Last 20

6. .NET Framework v4 strong crypto/system-default TLS:

       $paths = @(
           'HKLM:\SOFTWARE\Microsoft\.NETFramework\v4.0.30319',
           'HKLM:\SOFTWARE\WOW6432Node\Microsoft\.NETFramework\v4.0.30319'
       )

       foreach ($p in $paths) {
           Get-ItemProperty $p -ErrorAction SilentlyContinue |
             Select-Object SchUseStrongCrypto,SystemDefaultTlsVersions
       }

Expected:

    SchUseStrongCrypto       = 1
    SystemDefaultTlsVersions = 1

If missing:

    foreach ($p in $paths) {
        New-ItemProperty -Path $p -Name SchUseStrongCrypto -Value 1 -PropertyType DWord -Force | Out-Null
        New-ItemProperty -Path $p -Name SystemDefaultTlsVersions -Value 1 -PropertyType DWord -Force | Out-Null
    }

Then restart:

    Restart-Service WsusService
    Restart-Service W3SVC

A successful Test-NetConnection proves only that a TCP connection could be opened at that moment. It does not prove that the .NET Framework process used by WSUS is selecting the correct TLS defaults for long-running synchronization.

If multiple synchronization attempts fail against different Microsoft IP addresses while later TCP/TLS tests to those addresses succeed, investigate .NET TLS defaults and intermittent network/security inspection before changing SUSDB or reinstalling WSUS again.

Do not permanently whitelist individual Microsoft Update IP addresses. Use Microsoft Update/WSUS service domains according to current Microsoft guidance.
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
