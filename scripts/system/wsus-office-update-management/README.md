# WSUS + Office Update Management

Public, depersonalized implementation guide and PowerShell toolkit for rebuilding and operating Windows Server Update Services (WSUS) with Windows Internal Database (WID), relocating WSUS content and SUSDB to a data volume, and maintaining local Microsoft Office Click-to-Run repositories.

**ERNU.EU | IT & Security Solutions**

## Scope

The subproject covers:

- Windows 11 quality, security and feature updates;
- Windows Server 2022 servicing;
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
12. Install ODT and use 08-Update-Office-Repository.ps1 for the Office repositories.

## Target products and classifications

Products:

- Windows 11
- Microsoft Server operating system-21H2 / the catalog title applicable to Windows Server 2022
- SQL Server 2017
- SQL Server 2019
- SQL Server 2022

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
