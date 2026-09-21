# Ghid de instalare - WSUS + Microsoft Office Update Management

**ERNU.EU | IT & Security Solutions**  
Versiune 1.0 - Septembrie 2026

## 1. Scop

Implementare completă și depersonalizată pentru Windows Server 2022 cu WSUS + Windows Internal Database (WID), repository și SUSDB pe D:, plus repository local pentru Office Click-to-Run.

Acoperire:

- Windows 11: quality/security updates și feature upgrades;
- Windows Server 2022;
- SQL Server 2017, 2019 și 2022 pentru actualizările publicate prin Microsoft Update / WSUS;
- Office 2019, Office LTSC 2021 și Office LTSC 2024 prin Office Deployment Tool.

Office Click-to-Run nu este actualizat de WSUS. Fluxul Office este Office CDN -> ODT -> share intern -> clienți.

## 2. Arhitectura țintă

    Windows Server 2022
      WSUS :8530
      WID / SUSDB
        D:\WSUS\Database\SUSDB.mdf
        D:\WSUS\Database\SUSDB_log.ldf
      WSUS content
        D:\WSUS\Repository\WsusContent

    Office CDN
      -> ODT
      -> D:\OfficeUpdates
           Office2019
           Office2021
           Office2024
      -> \\officeupd.ernu.sec\OfficeUpdates
      -> clients

## 3. Pre-check

PowerShell ca Administrator:

    Get-WindowsFeature *UpdateServices*

    Get-ItemProperty "HKLM:\SOFTWARE\Microsoft\Update Services\Server\Setup" |
      Format-List *

    Get-WebSite | Select-Object Name,State,PhysicalPath

    Get-Volume D | Format-List DriveLetter,FileSystem,Size,SizeRemaining,HealthStatus

Volumul de date trebuie să fie sănătos și preferabil NTFS.

Automatizare:

    .\scripts\01-Precheck.ps1 -DataDrive D:

## 4. Backup minim înainte de rebuild

Salvați configurația existentă înainte de ștergere:

    New-Item -ItemType Directory -Path C:\WSUS-BACKUP -Force

    reg export "HKLM\SOFTWARE\Microsoft\Update Services" "C:\WSUS-BACKUP\Microsoft-Update-Services.reg" /y

    Get-WindowsFeature *UpdateServices* |
      Out-File C:\WSUS-BACKUP\WSUS-Features.txt

Dacă WSUS folosește un SQL extern, nu ștergeți SUSDB extern înainte ca noua instalare să fie validată.

## 5. Eliminarea WSUS existent

    Stop-Service WsusService -Force
    iisreset /stop
    Uninstall-WindowsFeature -Name UpdateServices -IncludeManagementTools

Verificare:

    Get-WindowsFeature *UpdateServices*

Componentele trebuie să fie Available.

Eliminați artefactele IIS/registry rămase numai după confirmarea dezinstalării:

    Remove-Website -Name "WSUS Administration"

    Remove-Item "HKLM:\SOFTWARE\Microsoft\Update Services" -Recurse -Force

    Remove-Item "C:\Program Files\Update Services" -Recurse -Force

Pentru reconstrucție completă, repository-ul vechi poate fi șters după backup/decizie de rollback.

Script:

    .\scripts\02-Remove-Existing-WSUS.ps1 -PurgeOldContent -OldContentPath 'D:\WSUSUpdates'

Reporniți serverul.

## 6. Structura nouă

    New-Item -ItemType Directory -Path "D:\WSUS\Repository" -Force
    New-Item -ItemType Directory -Path "D:\WSUS\Database" -Force

## 7. Instalarea WSUS cu WID

    Install-WindowsFeature UpdateServices-Services,UpdateServices-WidDB,UpdateServices-RSAT -IncludeManagementTools

Ținta:

    WID Connectivity        Installed
    WSUS Services           Installed
    SQL Server Connectivity Available
    WSUS Tools              Installed

Post-install:

    & "C:\Program Files\Update Services\Tools\WsusUtil.exe" postinstall CONTENT_DIR=D:\WSUS\Repository

Verificare:

    Get-ItemProperty "HKLM:\SOFTWARE\Microsoft\Update Services\Server\Setup" |
      Select-Object ContentDir,SqlServerName,SqlDatabaseName,PortNumber

Ținta:

    ContentDir      D:\WSUS\Repository
    SqlServerName   MICROSOFT##WID
    SqlDatabaseName SUSDB
    PortNumber      8530

Automatizare:

    .\scripts\03-Install-WSUS-WID.ps1 -WsusRoot 'D:\WSUS'

## 8. Relocarea SUSDB pe D:

Locația inițială WID este de regulă:

    C:\Windows\WID\Data\SUSDB.mdf
    C:\Windows\WID\Data\SUSDB_log.ldf

Verificați:

    Get-ChildItem "C:\Windows\WID\Data" -Filter "SUSDB*"

Acordați acces serviciului WID. Folosiți apostrofuri simple pentru contul cu semnul dolar:

    icacls "D:\WSUS\Database" /grant 'NT SERVICE\MSSQL$MICROSOFT##WID:(OI)(CI)F'

Schimbați metadata SQL/WID:

    ALTER DATABASE SUSDB
      MODIFY FILE (NAME = SUSDB, FILENAME = 'D:\WSUS\Database\SUSDB.mdf');

    ALTER DATABASE SUSDB
      MODIFY FILE (NAME = SUSDB_log, FILENAME = 'D:\WSUS\Database\SUSDB_log.ldf');

Oprire controlată:

    Stop-Service WsusService -Force
    iisreset /stop
    Stop-Service 'MSSQL$MICROSOFT##WID' -Force

Mutare:

    Move-Item "C:\Windows\WID\Data\SUSDB.mdf" "D:\WSUS\Database\SUSDB.mdf"
    Move-Item "C:\Windows\WID\Data\SUSDB_log.ldf" "D:\WSUS\Database\SUSDB_log.ldf"

Pornire:

    Start-Service 'MSSQL$MICROSOFT##WID'

Validați în sys.databases că SUSDB este ONLINE și în sys.master_files că ambele fișiere sunt pe D:. Apoi:

    iisreset /start
    Start-Service WsusService

Automatizare:

    .\scripts\04-Relocate-SUSDB.ps1 -Destination 'D:\WSUS\Database'

## 9. Verificarea API și portului

    Import-Module UpdateServices
    $wsus = Get-WsusServer
    $wsus | Select-Object Name,PortNumber

    Test-NetConnection localhost -Port 8530

TcpTestSucceeded trebuie să fie True.

## 10. Microsoft Update upstream

    Set-WsusServerSynchronization -SyncFromMU

    $config = $wsus.GetConfiguration()
    $config.MUUrl

Endpoint-ul modern este de forma https://sws.update.microsoft.com.

## 11. Comportamentul de download

Ținta:

    HostBinariesOnMicrosoftUpdate    False
    DownloadUpdateBinariesAsNeeded   True
    DownloadExpressPackages          False

Astfel serverul păstrează binarele local, dar nu descarcă întregul catalog de pachete. Binarele sunt descărcate la nevoie/după approval.

## 12. Limbile

Exemplul folosește:

    en
    ro
    ru

Automatizare:

    .\scripts\05-Configure-WSUS.ps1 -Languages en,ro,ru

## 13. Validarea TLS/.NET înainte de prima sincronizare

Pe Windows Server 2022, WSUS poate avea acces TCP 443 și handshake TLS 1.2 funcțional, dar sincronizarea să eșueze cu:

    Result    : Failed
    Error     : UssCommunicationError
    ErrorText : WebException: Unable to connect to the remote server

Simptomul poate apărea intermitent și către IP-uri Microsoft diferite, în timp ce:

    Test-NetConnection sws.update.microsoft.com -Port 443

returnează:

    TcpTestSucceeded : True

Acest lucru nu validează complet stack-ul .NET folosit de WSUS. Verificați și setările .NET Framework v4 pentru utilizarea criptografiei puternice și a versiunii TLS implicite a sistemului.

Verificare:

    $paths = @(
        'HKLM:\SOFTWARE\Microsoft\.NETFramework\v4.0.30319',
        'HKLM:\SOFTWARE\WOW6432Node\Microsoft\.NETFramework\v4.0.30319'
    )

    foreach ($p in $paths) {
        Write-Host "`n$p"
        Get-ItemProperty $p -ErrorAction SilentlyContinue |
            Select-Object SchUseStrongCrypto,SystemDefaultTlsVersions
    }

Ținta:

    SchUseStrongCrypto       = 1
    SystemDefaultTlsVersions = 1

Dacă valorile lipsesc sau sunt 0, setați-le în ambele ramuri .NET:

    foreach ($p in $paths) {
        New-ItemProperty -Path $p -Name SchUseStrongCrypto -Value 1 -PropertyType DWord -Force | Out-Null
        New-ItemProperty -Path $p -Name SystemDefaultTlsVersions -Value 1 -PropertyType DWord -Force | Out-Null
    }

Reîncărcați procesele WSUS/IIS:

    Restart-Service WsusService
    Restart-Service W3SVC

Verificare:

    Get-Service WsusService,W3SVC |
      Select-Object Name,Status,StartType

Ambele servicii trebuie să fie Running.

Pentru diagnostic suplimentar, verificați WinHTTP:

    netsh winhttp show proxy

Într-un scenariu fără proxy, rezultatul așteptat este:

    Direct access (no proxy server).

Verificați și endpoint-ul WSUS:

    $config = $wsus.GetConfiguration()
    $config.MUUrl

Exemplu:

    https://sws.update.microsoft.com

Dacă sincronizarea a eșuat către un IP Microsoft, testați doar ca diagnostic:

    Test-NetConnection <IP> -Port 443

Nu creați whitelist-uri permanente după IP. Endpoint-urile Microsoft Update pot folosi adrese diferite în timp; regulile de firewall trebuie proiectate după domeniile/serviciile Microsoft Update permise.

Test TLS 1.2 repetat, util pentru a diferenția un blocaj TCP/TLS simplu de o problemă specifică WSUS/.NET:

    $Targets = @('203.0.113.10','203.0.113.11')   # exemple RFC 5737

    foreach ($IP in $Targets) {
        1..20 | ForEach-Object {
            $tcp = New-Object System.Net.Sockets.TcpClient
            try {
                $async = $tcp.BeginConnect($IP,443,$null,$null)
                if (-not $async.AsyncWaitHandle.WaitOne(5000)) { throw 'TCP timeout' }
                $tcp.EndConnect($async)

                $ssl = New-Object System.Net.Security.SslStream($tcp.GetStream(),$false)
                $ssl.AuthenticateAsClient(
                    'sws.update.microsoft.com',
                    $null,
                    [System.Security.Authentication.SslProtocols]::Tls12,
                    $false
                )

                Write-Host "$_ OK TLS=$($ssl.SslProtocol)"
                $ssl.Dispose()
                $tcp.Dispose()
            }
            catch {
                Write-Host "$_ FAILED $($_.Exception.Message)"
                $tcp.Dispose()
            }
        }
    }

Dacă TCP/TLS este stabil, WinHTTP este direct, iar WSUS continuă să eșueze, capturați traficul pe server și firewall în timpul sincronizării înainte de alte modificări.
## 14. Prima sincronizare

Pe un WSUS nou trebuie întâi sincronizată metadata:

    $subscription = $wsus.GetSubscription()
    $subscription.StartSynchronization()

Status:

    $subscription.GetSynchronizationStatus()

Progres:

    $subscription.GetSynchronizationProgress() | Format-List *

Un număr mare în faza Updates reprezintă metadata/catalog, nu același număr de fișiere descărcate.

GetLastSynchronizationInfo poate raporta NeverRun cât timp prima sincronizare încă rulează.

După finalizare, statusul ajunge la NotProcessing și ultima sincronizare trebuie să fie reușită.

## 15. Produse WSUS țintă

După prima sincronizare listați toate produsele și verificați denumirile exacte:

    Get-WsusProduct |
      Select-Object @{N='Product';E={$_.Product.Title}},Enabled |
      Sort-Object Product

Ținta acestui proiect:

- Windows 11;
- Microsoft Server operating system-21H2 sau categoria reală din catalog pentru Windows Server 2022;
- SQL Server 2017;
- SQL Server 2019;
- SQL Server 2022.

Pentru Windows 11 nu confundați produsul principal cu categoriile Dynamic Update sau Drivers.

## 16. Classifications

Se activează:

- Critical Updates;
- Definition Updates;
- Security Updates;
- Update Rollups;
- Updates;
- Upgrades.

Upgrades este necesar pentru feature upgrade Windows 11.

Dezactivate implicit:

- Drivers;
- Driver Sets;
- Tools.

Feature Packs se activează doar dacă există nevoie reală.

Listare fără modificare:

    .\scripts\06-Select-WSUS-Products.ps1 -ListOnly

Aplicare:

    .\scripts\06-Select-WSUS-Products.ps1

După schimbarea selecției, sincronizați din nou.

## 17. SQL Server 2017-2022

SQL Server servicing este disponibil prin Microsoft Update / WSUS. Înainte de approval:

- identificați ramura CU/GDR;
- verificați backup;
- validați compatibilitatea aplicației;
- folosiți o fereastră de mentenanță;
- testați pe grup Pilot;
- documentați rollback.

Nu tratați SQL Server ca un workstation update generic.

## 18. Grupuri și rollout

Structură recomandată:

    All Computers
      Workstations
        W11-Pilot
        W11-Production
      Servers
        Server-Pilot
        Server-Production
      SQL
        SQL-Pilot
        SQL-Production

Flux:

    Microsoft Update
      -> WSUS metadata
      -> Pilot
      -> validare
      -> Production

## 19. GPO pentru Windows

Exemplu:

    http://wsus01.ernu.sec:8530

Configurați cel puțin:

- Specify intranet Microsoft update service location;
- Configure Automatic Updates;
- politici de restart;
- sursa pentru Feature Updates și Quality Updates.

Evitați politici conflictuale WSUS/WUfB. Dacă TargetReleaseVersion este setat la o versiune veche, feature upgrade-ul poate fi blocat intenționat.

## 20. Microsoft Office - modelul corect

Office Professional Plus 2019, Office LTSC 2021 și Office LTSC 2024 folosesc Click-to-Run. WSUS singur nu distribuie build-urile Office.

Flux:

    Office CDN
      -> Office Deployment Tool
      -> D:\OfficeUpdates
      -> SMB share
      -> Office clients

## 21. Starea suportului Office

- Office 2019 este legacy și a ieșit din suport normal. Repository-ul 2019 este păstrat pentru inventar existent și migrare.
- Office LTSC 2021 ajunge la finalul suportului în octombrie 2026; trebuie planificată migrarea.
- Office LTSC 2024 este ținta LTSC on-premises preferată în acest design.

## 22. Structura Office repository

    D:\OfficeUpdates\ODT
    D:\OfficeUpdates\Config
    D:\OfficeUpdates\Office2019
    D:\OfficeUpdates\Office2021
    D:\OfficeUpdates\Office2024

Copiați setup.exe din Office Deployment Tool în D:\OfficeUpdates\ODT și fișierele XML din office-configs în D:\OfficeUpdates\Config.

Canale:

    Office 2019       PerpetualVL2019
    Office LTSC 2021  PerpetualVL2021
    Office LTSC 2024  PerpetualVL2024

Actualizare repository:

    .\scripts\08-Update-Office-Repository.ps1 -Version 2019
    .\scripts\08-Update-Office-Repository.ps1 -Version 2021
    .\scripts\08-Update-Office-Repository.ps1 -Version 2024

ODT folosește setup.exe /download configuration.xml.

## 23. Share și GPO Office

Exemplu share:

    \\officeupd.ernu.sec\OfficeUpdates

Permisiuni:

- cont/serviciu administrativ: Modify;
- clienți: Read;
- fără acces anonim.

În ADMX Office, setarea Update Path este în zona:

    Computer Configuration
      Policies
        Administrative Templates
          Microsoft Office 2016 (Machine)
            Updates

Exemple Update Path:

    \\officeupd.ernu.sec\OfficeUpdates\Office2024
    \\officeupd.ernu.sec\OfficeUpdates\Office2021

Pe Office 2019 legacy păstrați sursa 2019 numai până la migrare.

## 24. Verificare Office client

Dintr-o aplicație Office:

    File -> Account -> Update Options -> Update Now

Verificați și task-ul Office Automatic Updates 2.0.

## 25. Validare finală

    .\scripts\07-Validate-WSUS.ps1

Criterii:

    WsusService                 Running
    MSSQL$MICROSOFT##WID        Running
    TCP 8530                    True
    ContentDir                  D:\WSUS\Repository
    SqlServerName               MICROSOFT##WID
    SUSDB MDF/LDF               D:\WSUS\Database
    HostBinariesOnMU            False
    DownloadAsNeeded            True
    Express                     False
    Languages                   en, ro, ru
    Sync source                 Microsoft Update

Produse:

    Windows 11
    Windows Server 2022 catalog category
    SQL Server 2017
    SQL Server 2019
    SQL Server 2022

Office:

    Office2019 repository - legacy
    Office2021 repository - migration planning
    Office2024 repository - LTSC target

## 26. Mentenanță

Planificați:

- sincronizare periodică;
- approval separat de synchronization;
- WSUS cleanup;
- SUSDB reindex/maintenance;
- verificare spațiu pe D:;
- monitorizarea erorilor de sync;
- IIS/WSUS app pool monitoring;
- actualizare periodică a repository-ului Office.

Nu ștergeți manual fișiere din WsusContent.

## 27. Surse oficiale

- Microsoft Learn - Deploy Windows Server Update Services: https://learn.microsoft.com/windows-server/administration/windows-server-update-services/deploy/deploy-windows-server-update-services
- Microsoft Learn - Install the WSUS server role: https://learn.microsoft.com/windows-server/administration/windows-server-update-services/deploy/1-install-the-wsus-server-role
- Microsoft Learn - Plan your WSUS deployment: https://learn.microsoft.com/windows-server/administration/windows-server-update-services/plan/plan-your-wsus-deployment
- Microsoft Learn - Set-WsusProduct: https://learn.microsoft.com/powershell/module/updateservices/set-wsusproduct
- Microsoft Learn - Set-WsusClassification: https://learn.microsoft.com/powershell/module/updateservices/set-wsusclassification
- Microsoft Learn - Update Office 2019: https://learn.microsoft.com/office/2019/update
- Microsoft Learn - Update Office LTSC 2021: https://learn.microsoft.com/office/ltsc/2021/update
- Microsoft Learn - Update Office LTSC 2024: https://learn.microsoft.com/office/ltsc/2024/update
- Microsoft Learn - Install SQL Server servicing updates: https://learn.microsoft.com/sql/database-engine/install-windows/install-sql-server-servicing-updates
- Microsoft Lifecycle - Office 2019: https://learn.microsoft.com/lifecycle/products/microsoft-office-2019
- Microsoft Lifecycle - Office LTSC 2021 end of support: https://learn.microsoft.com/lifecycle/announcements/office-ltsc-2021-end-of-support

- Microsoft Learn - .NET Framework TLS best practices: https://learn.microsoft.com/dotnet/framework/network-programming/tls
- Microsoft Learn - Troubleshoot WSUS import/sync issues: https://learn.microsoft.com/troubleshoot/mem/configmgr/update-management/troubleshoot-wsus-import-sync-issues
