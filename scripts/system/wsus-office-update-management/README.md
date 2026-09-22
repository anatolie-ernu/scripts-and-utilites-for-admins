# WSUS + Office Update Management

Public, depersonalized implementation guide and PowerShell toolkit for rebuilding and operating Windows Server Update Services (WSUS) with Windows Internal Database (WID), relocating WSUS content and SUSDB to a data volume, and maintaining local Microsoft Office Click-to-Run repositories.

**ERNU.EU | IT & Security Solutions**

## Scope

The subproject covers:

- Windows 11 quality, security and feature updates;
- Windows Server 2022 servicing;
- Windows Server 2025 servicing;
- Microsoft SQL Server 2017, 2019 and 2022 servicing delivered through Microsoft Update / WSUS;
- Microsoft Office 2019, Office LTSC 2021 and Office LTSC 2024 local update repositories.

Office 2019/2021/2024 Click-to-Run is intentionally handled outside WSUS. Office uses Office CDN or an internal repository populated with Office Deployment Tool (ODT).

## Target architecture

    Windows Server 2022
    |
    +-- WSUS :8530
    |   +-- Windows Internal Database (WID)
    |   |   +-- D:\WSUS\Database\SUSDB.mdf
    |   |   +-- D:\WSUS\Database\SUSDB_log.ldf
    |   +-- D:\WSUS\Repository\WsusContent
    |
    +-- Office local update repository
        +-- D:\OfficeUpdates\Office2019
        +-- D:\OfficeUpdates\Office2021
        +-- D:\OfficeUpdates\Office2024

Example public hostnames use the ernu.sec documentation namespace.

## Design choices

- WID instead of an external SQL Server for WSUS.
- WSUS content on D:.
- SUSDB MDF/LDF relocated to D:.
- Update binaries downloaded on demand/after approval.
- Express packages disabled.
- Languages limited to en, ro and ru in the example.
- Drivers and Driver Sets disabled by default.
- Target products deliberately constrained.
- Pilot and Production approval separated.
- Office Click-to-Run maintained by ODT + internal share/GPO.

## Files

    README.md
    docs/
      INSTALLATION-GUIDE-RO.md
      TROUBLESHOOTING.md
      ERNU_EU_Ghid_WSUS_Office_Update_Management_RO.pdf
    scripts/
      01-Precheck.ps1
      02-Remove-Existing-WSUS.ps1
      03-Install-WSUS-WID.ps1
      04-Relocate-SUSDB.ps1
      05-Configure-WSUS.ps1
      06-Select-WSUS-Products.ps1
      07-Validate-WSUS.ps1
      08-Update-Office-Repository.ps1
      09-Configure-WSUS-Production.ps1
      10-Approve-DefenderUpdates.ps1
      11-Configure-WSUS-Targeting-GPOs.ps1
      12-Import-WSUS-Server-GPO-Baseline.ps1
      13-New-WSUS-Server-BaselineV2.ps1
      14-Install-Defender-Client-AutoUpdateTask.ps1
      15-Configure-WSUS-Pilot-AutoApproval.ps1
      16-Configure-WSUS-Accelerated-AutoApproval.ps1
      17-Switch-WSUS-AutoApproval-Mode.ps1
      18-Configure-Defender-Definition-AutoApproval.ps1
    office-configs/
      office2019.xml
      office2021.xml
      office2024.xml

## Recommended execution order

1. Run 01-Precheck.ps1.
2. Back up the existing WSUS configuration/database if rollback is required.
3. Run 02-Remove-Existing-WSUS.ps1 only for an intentional clean rebuild.
4. Run 03-Install-WSUS-WID.ps1.
5. Run 04-Relocate-SUSDB.ps1.
6. Run 05-Configure-WSUS.ps1.
7. Complete the first metadata synchronization.
8. Run 06-Select-WSUS-Products.ps1 -ListOnly and review exact product titles.
9. Run 06-Select-WSUS-Products.ps1.
10. Synchronize again and approve updates to Pilot groups first.
11. Run 07-Validate-WSUS.ps1.
12. Run 09-Configure-WSUS-Production.ps1 in preview mode and review the exact products.
13. Apply the production policy with `09-Configure-WSUS-Production.ps1 -Apply`.
14. Validate the Defender worker with `10-Approve-DefenderUpdates.ps1 -WhatIf`.
15. After reviewing the exact Defender candidates, run `09-Configure-WSUS-Production.ps1 -Apply -InstallDefenderTask` to install the hourly task.
16. Install ODT and use 08-Update-Office-Repository.ps1 for the Office repositories.

## Target products and classifications

Products:

- Windows 11
- Microsoft Server operating system-21H2 / the catalog title applicable to Windows Server 2022
- SQL Server 2017
- SQL Server 2019
- SQL Server 2022
- SQL Server Management Studio v17, v18, v19, v20
- Microsoft ODBC Driver 17 and 18 for SQL Server
- Microsoft OLE DB Driver 18 and 19 for SQL Server
- Microsoft Defender Antivirus

Classifications:

- Critical Updates
- Definition Updates
- Security Updates
- Update Rollups
- Updates
- Upgrades

Drivers, Driver Sets and Tools are not enabled by default.

## Office channels

- Office 2019: PerpetualVL2019
- Office LTSC 2021: PerpetualVL2021
- Office LTSC 2024: PerpetualVL2024

Office 2019 is legacy/out of normal support. Office LTSC 2021 reaches end of support in October 2026. Office LTSC 2024 is the preferred LTSC on-premises target in this guide.

## Client-side targeting GPOs

The recommended WSUS targeting model uses one thin GPO per WSUS target group while keeping common WSUS settings in a separate baseline GPO.

Target groups:

- Windows-11-Pro-Pilot
- Windows-11-Pro-Production
- Server-Pilot
- Server-Production
- SQL-Pilot
- SQL-Production

Recommended GPO names:

- Computer Policy Deploy - WSUS Updates Windows-11-Pro-Pilot
- Computer Policy Deploy - WSUS Updates Windows-11-Pro-Production
- Computer Policy Deploy - WSUS Updates Server-Pilot
- Computer Policy Deploy - WSUS Updates Server-Production
- Computer Policy Deploy - WSUS Updates SQL-Pilot
- Computer Policy Deploy - WSUS Updates SQL-Production

Each targeting GPO sets only:

- `HKLM\Software\Policies\Microsoft\Windows\WindowsUpdate\TargetGroup`
- `HKLM\Software\Policies\Microsoft\Windows\WindowsUpdate\TargetGroupEnabled = 1`

Use the helper in preview mode first:

    .\scripts\11-Configure-WSUS-Targeting-GPOs.ps1

Apply after reviewing the mapping:

    .\scripts\11-Configure-WSUS-Targeting-GPOs.ps1 -Apply

The helper creates thin targeting GPOs only; it does not link them to OUs. Link each GPO manually to the intended Pilot/Production OU. Do not clone workstation-only settings into server or SQL OUs without review.

## Reusing an existing server WSUS GPO baseline

When an organization already has a validated server-side WSUS GPO and the new Pilot/Production targeting GPOs already exist, do **not** use `Copy-GPO` over those existing targets.

Use a backup/import workflow instead:

1. Back up the source server WSUS GPO.
2. Back up every existing target GPO.
3. Import the source policy settings into each existing target GPO with `Import-GPO`.
4. Reapply the target-specific `TargetGroup` and `TargetGroupEnabled=1` values.
5. Verify `WUServer`, `WUStatusServer`, `TargetGroup`, and `TargetGroupEnabled`.
6. Review OU links in Group Policy Management before rollout.

Preview:

    .\scripts\12-Import-WSUS-Server-GPO-Baseline.ps1 -SourceGpoName "WSUS Server Baseline"

Apply:

    .\scripts\12-Import-WSUS-Server-GPO-Baseline.ps1 -SourceGpoName "WSUS Server Baseline" -Apply

Default target mapping:

- Computer Policy Deploy - WSUS Updates Server-Pilot -> Server-Pilot
- Computer Policy Deploy - WSUS Updates Server-Production -> Server-Production
- Computer Policy Deploy - WSUS Updates SQL-Pilot -> SQL-Pilot
- Computer Policy Deploy - WSUS Updates SQL-Production -> SQL-Production

The helper refuses to apply if a target GPO is missing, creates timestamped rollback backups, imports settings into the existing target GPO objects, and restores the target-specific WSUS group values after import.

## Server Baseline v2: ordinary updates manual, Defender automatic

For Windows Server, use a separate server baseline rather than the workstation update policy.

Desired behavior:

- ordinary Windows Server, .NET, SQL, SSMS/ODBC/OLE DB and feature updates: notify/manual installation;
- `AUOptions=2` and `NoAutoUpdate=0`;
- all Feature/Quality/Driver/Other scan sources explicitly point to WSUS;
- no client-side `TargetGroup` value in the common baseline;
- Defender security intelligence checks hourly from `InternalDefinitionUpdateServer`;
- Defender platform/security-intelligence WSUS approvals remain restricted to Broad channel;
- automatic client installation of approved KB2267602/KB4052623 is handled by a dedicated SYSTEM scheduled task, not by changing the global Windows Update mode.

Create/refresh the v2 baseline from an existing validated server GPO:

    .\scripts\13-New-WSUS-Server-BaselineV2.ps1 \
      -SourceGpoName "WSUS Server Baseline" \
      -WsusUrl "http://wsus01.ernu.sec:8530"

Apply after preview:

    .\scripts\13-New-WSUS-Server-BaselineV2.ps1 \
      -SourceGpoName "WSUS Server Baseline" \
      -WsusUrl "http://wsus01.ernu.sec:8530" \
      -Apply

The script creates a timestamped backup, clones/imports the source policy into `Computer Policy Deploy - WSUS Server Baseline v2`, normalizes WSUS settings, removes legacy scheduled-install/noise values, removes baseline targeting, and configures Defender Security Intelligence to use WSUS hourly.

On a pilot server, install the client Defender-only task:

    .\scripts\14-Install-Defender-Client-AutoUpdateTask.ps1

Apply:

    .\scripts\14-Install-Defender-Client-AutoUpdateTask.ps1 -Apply

The client worker installs only applicable, WSUS-approved, Broad-channel:

- KB2267602 - Defender Security Intelligence
- KB4052623 - Defender Platform

It never installs general cumulative, .NET, SQL, driver, or feature updates and never forces a reboot.

## Selectable WSUS auto-approval modes

Two supported automatic-approval models are available.

### Option 1 - Conservative

Use `15-Configure-WSUS-Pilot-AutoApproval.ps1`.

Policy:

- Pilot: Critical Updates + Security Updates;
- Production: manual approval;
- Upgrades, Drivers, SQL CU/GDR, SSMS/ODBC/OLE DB: manual.

Preview:

    .\scripts\15-Configure-WSUS-Pilot-AutoApproval.ps1

Apply:

    .\scripts\15-Configure-WSUS-Pilot-AutoApproval.ps1 -Apply

### Option 2 - Accelerated

Use `16-Configure-WSUS-Accelerated-AutoApproval.ps1`.

Policy:

- Pilot: Critical Updates + Security Updates + Update Rollups + Updates;
- Production: Critical Updates + Security Updates;
- Upgrades: manual;
- Drivers: manual/disabled;
- SQL CU/GDR and SQL tooling: manual.

Preview:

    .\scripts\16-Configure-WSUS-Accelerated-AutoApproval.ps1

Apply:

    .\scripts\16-Configure-WSUS-Accelerated-AutoApproval.ps1 -Apply

The generic `Updates` classification may contain preview/optional quality updates. It is intentionally enabled only for Pilot in Accelerated mode.

### Switching modes

Use `17-Switch-WSUS-AutoApproval-Mode.ps1` to disable the managed rules from the other mode and activate the selected mode.

Preview:

    .\scripts\17-Switch-WSUS-AutoApproval-Mode.ps1 -Mode Conservative

    .\scripts\17-Switch-WSUS-AutoApproval-Mode.ps1 -Mode Accelerated

Apply:

    .\scripts\17-Switch-WSUS-AutoApproval-Mode.ps1 -Mode Conservative -Apply

    .\scripts\17-Switch-WSUS-AutoApproval-Mode.ps1 -Mode Accelerated -Apply

Add `-ApplyExisting` only after reviewing already-synchronized updates. Switching modes changes future automatic approvals; it does not revoke approvals already granted under the previous mode.

## Defender Definition Updates auto-approval

Use `18-Configure-Defender-Definition-AutoApproval.ps1` to create a dedicated WSUS rule for the `Microsoft Defender Antivirus` product and `Definition Updates` classification across all managed workstation/server rings:

- Windows-11-Pro-Pilot
- Windows-11-Pro-Production
- Server-Pilot
- Server-Production
- SQL-Pilot
- SQL-Production

Preview:

    .\scripts\18-Configure-Defender-Definition-AutoApproval.ps1

Create/update and enable the rule:

    .\scripts\18-Configure-Defender-Definition-AutoApproval.ps1 -Apply

Apply the rule to already-synchronized matching Defender definition updates as well:

    .\scripts\18-Configure-Defender-Definition-AutoApproval.ps1 -Apply -ApplyExisting

The rule is intentionally constrained by both product and classification. It does not approve generic Windows quality updates, upgrades, drivers, SQL CU/GDR, SSMS, ODBC or OLE DB updates.

## Public-data policy

All examples are sanitized:

- documentation hostnames use *.ernu.sec;
- no production IP addresses;
- no passwords, API tokens, product keys, internal DNS names or organization identifiers.

## Documentation

- Romanian guide: docs/INSTALLATION-GUIDE-RO.md
- Troubleshooting: docs/TROUBLESHOOTING.md
- PDF guide: docs/ERNU_EU_Ghid_WSUS_Office_Update_Management_RO.pdf

Copyright © 2026 ERNU.EU. All rights reserved.


## Production policy automation

After the initial metadata synchronization finishes successfully, use the production configurator.

Preview only:

    .\scripts\09-Configure-WSUS-Production.ps1

Apply the strict product/classification set, create Pilot/Production groups, and configure six synchronizations per day:

    .\scripts\09-Configure-WSUS-Production.ps1 -Apply

Preview the exact Defender approvals:

    .\scripts\10-Approve-DefenderUpdates.ps1 -WhatIf

Only after the preview is correct, install the hourly Defender approval task:

    .\scripts\09-Configure-WSUS-Production.ps1 -Apply -InstallDefenderTask

The script refuses to apply if the last WSUS synchronization is not `Succeeded`.

Target groups created:

- Windows-11-Pro-Pilot
- Windows-11-Pro-Production
- Server-Pilot
- Server-Production
- SQL-Pilot
- SQL-Production

The Defender worker targets only the server/SQL groups and approves only:

- KB2267602 — Microsoft Defender Antivirus security intelligence;
- KB4052623 — Microsoft Defender Antivirus platform update.

It does **not** automatically approve Windows cumulative updates, .NET updates, SQL Server CU/GDR updates, Windows 11 quality updates, or Windows 11 feature upgrades.

Manual preview of Defender approvals:

    .\scripts\10-Approve-DefenderUpdates.ps1 -WhatIf

The production worker uses a 60-day arrival window, ignores declined and superseded updates, and requires the update title to contain Defender in addition to the exact KB match.

Official references:

- Microsoft Defender Antivirus updates: https://learn.microsoft.com/defender-endpoint/microsoft-defender-antivirus-updates
- Approve-WsusUpdate: https://learn.microsoft.com/powershell/module/updateservices/approve-wsusupdate


### SQL tools and driver products

The production policy also enables the following exact Microsoft Update catalog products when they are present:

- Microsoft SQL Server Management Studio v17
- Microsoft SQL Server Management Studio v18
- Microsoft SQL Server Management Studio v19
- Microsoft SQL Server Management Studio v20
- Microsoft ODBC Driver 17 for SQL Server
- Microsoft ODBC Driver 18 for SQL Server
- Microsoft OLE DB Driver 18 for SQL Server
- Microsoft OLE DB Driver 19 for SQL Server

SQL tools and drivers are matched by exact catalog title. The script does not enable generic SQL Server, SQL Feature Pack, older SQL Server releases, SQL Server 2025, or unrelated setup-product categories.

Windows Server 2025 is selected in WSUS through the exact catalog product `Microsoft Server operating system-24H2`. Windows Server 2022 remains `Microsoft Server operating system-21H2`.
