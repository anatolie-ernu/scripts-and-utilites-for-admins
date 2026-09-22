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
    Windows Server 2025
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
- Microsoft Server operating system-21H2 pentru Windows Server 2022;
- Microsoft Server operating system-24H2 pentru Windows Server 2025;
- SQL Server 2017;
- SQL Server 2019;
- SQL Server 2022;
- Microsoft SQL Server Management Studio v17;
- Microsoft SQL Server Management Studio v18;
- Microsoft SQL Server Management Studio v19;
- Microsoft SQL Server Management Studio v20;
- Microsoft ODBC Driver 17 for SQL Server;
- Microsoft ODBC Driver 18 for SQL Server;
- Microsoft OLE DB Driver 18 for SQL Server;
- Microsoft OLE DB Driver 19 for SQL Server.

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

## 18. SQL tools și drivere de conectivitate

Dacă aceste componente există în infrastructură, politica strictă WSUS le include explicit după denumirea exactă din catalog:

    Microsoft SQL Server Management Studio v17
    Microsoft SQL Server Management Studio v18
    Microsoft SQL Server Management Studio v19
    Microsoft SQL Server Management Studio v20
    Microsoft ODBC Driver 17 for SQL Server
    Microsoft ODBC Driver 18 for SQL Server
    Microsoft OLE DB Driver 18 for SQL Server
    Microsoft OLE DB Driver 19 for SQL Server

Nu se folosește wildcard generic SQL. Astfel rămân dezactivate automat produse precum SQL Server 2012/2014/2016/2025, SQL Server Feature Pack, drivere neutilizate și categoriile Setup Product Updates.

ODBC Driver 17 și 18 pot exista în paralel și au cicluri de suport separate. Microsoft recomandă menținerea pe cel mai recent build disponibil din ramura majoră folosită. OLE DB Driver 19 este generația curentă pentru dezvoltări noi, iar OLE DB Driver 18 poate rămâne instalat pentru compatibilitate cu aplicații existente.

SSMS are propriul ciclu Modern Lifecycle. Dacă există mai multe versiuni majore în infrastructură, WSUS poate păstra produsele lor în catalog, dar trebuie planificată standardizarea treptată pe o versiune SSMS curentă.

## 19. Grupuri și rollout

Structură recomandată:

    All Computers
      Workstations
        Windows-11-Pro-Pilot
        Windows-11-Pro-Production
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

## 20. GPO pentru Windows și client-side targeting

Exemplu server WSUS:

    http://wsus01.ernu.sec:8530

Configurați într-un GPO comun de bază cel puțin:

- Specify intranet Microsoft update service location;
- Configure Automatic Updates;
- politici de restart;
- sursa pentru Feature Updates, Quality Updates, Driver Updates și Other Updates;
- scan source explicit pe WSUS atunci când mediul folosește Windows 11 și WSUS.

Pentru targeting se recomandă GPO-uri subțiri, separate de baseline-ul WSUS. Numele grupului din GPO trebuie să coincidă cu numele grupului existent în WSUS.

Mapping recomandat:

    WSUS Group                    GPO
    ---------------------------  --------------------------------------------------------------
    Windows-11-Pro-Pilot         Computer Policy Deploy - WSUS Updates Windows-11-Pro-Pilot
    Windows-11-Pro-Production    Computer Policy Deploy - WSUS Updates Windows-11-Pro-Production
    Server-Pilot                 Computer Policy Deploy - WSUS Updates Server-Pilot
    Server-Production            Computer Policy Deploy - WSUS Updates Server-Production
    SQL-Pilot                    Computer Policy Deploy - WSUS Updates SQL-Pilot
    SQL-Production               Computer Policy Deploy - WSUS Updates SQL-Production

Fiecare GPO de targeting setează numai:

    HKLM\Software\Policies\Microsoft\Windows\WindowsUpdate
      TargetGroup        = <numele exact al grupului WSUS>
      TargetGroupEnabled = 1

Pentru creare/actualizare controlată:

    .\scripts\11-Configure-WSUS-Targeting-GPOs.ps1

Preview-ul nu modifică Active Directory. După validare:

    .\scripts\11-Configure-WSUS-Targeting-GPOs.ps1 -Apply

Scriptul creează GPO-urile, dar nu le leagă automat la OU-uri. Link-ul către OU trebuie făcut explicit de administrator, astfel încât un OU Pilot să primească doar GPO-ul Pilot, iar OU-urile Production să primească GPO-ul Production corespunzător.

Pentru validare pe client:

    gpupdate /force
    reg query "HKLM\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate" /v TargetGroup
    reg query "HKLM\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate" /v TargetGroupEnabled

Exemplu rezultat Pilot:

    TargetGroup          REG_SZ      Windows-11-Pro-Pilot
    TargetGroupEnabled   REG_DWORD   0x1

Evitați politici conflictuale WSUS/WUfB. Dacă TargetReleaseVersion este setat la o versiune veche, feature upgrade-ul poate fi blocat intenționat. Nu copiați automat un GPO de workstation către Server/SQL dacă acesta conține setări specifice stațiilor; păstrați baseline-ul comun separat de targeting.

### 20.1. Reutilizarea unui GPO server WSUS existent

Dacă există deja un GPO server-side validat, acesta poate fi folosit drept baseline pentru noile GPO-uri Pilot/Production. Dacă GPO-urile țintă există deja, nu se recomandă `Copy-GPO` peste ele.

Flux recomandat:

    GPO server existent
      -> Backup source
      -> Backup GPO-uri țintă
      -> Import-GPO în obiectele țintă existente
      -> Reaplicare TargetGroup / TargetGroupEnabled
      -> Verificare
      -> Review link-uri OU

Avantajul este că GPO-urile țintă existente sunt reutilizate, iar procedura păstrează separarea dintre identitatea GPO-ului țintă și setările importate.

Script:

    .\scripts\12-Import-WSUS-Server-GPO-Baseline.ps1

Preview:

    .\scripts\12-Import-WSUS-Server-GPO-Baseline.ps1 -SourceGpoName "WSUS Server Baseline"

Aplicare:

    .\scripts\12-Import-WSUS-Server-GPO-Baseline.ps1 -SourceGpoName "WSUS Server Baseline" -Apply

Mapping implicit:

    GPO țintă                                                     TargetGroup
    ------------------------------------------------------------  -----------------
    Computer Policy Deploy - WSUS Updates Server-Pilot            Server-Pilot
    Computer Policy Deploy - WSUS Updates Server-Production       Server-Production
    Computer Policy Deploy - WSUS Updates SQL-Pilot               SQL-Pilot
    Computer Policy Deploy - WSUS Updates SQL-Production          SQL-Production

Scriptul:

- verifică existența GPO-ului sursă;
- verifică existența tuturor GPO-urilor țintă;
- în modul Preview nu modifică nimic;
- în modul Apply creează backup cu timestamp pentru sursă și toate țintele;
- importă setările sursei în fiecare GPO țintă existent;
- reaplică `TargetGroup` specific fiecărui GPO;
- reaplică `TargetGroupEnabled=1`;
- afișează la final `TargetGroup`, `TargetGroupEnabled`, `WUServer` și `WUStatusServer`;
- nu creează link-uri OU și nu mută automat GPO-urile între OU-uri.

Directorul implicit pentru backup este:

    C:\GPO-Backup\WSUS\Server-GPO-Migration-YYYYMMDD-HHMMSS

După import, verificați în Group Policy Management:

- link-ul GPO-ului către OU-ul corect;
- Security Filtering;
- WMI Filtering;
- Enforced / Block Inheritance;
- ordinea link-urilor dacă există mai multe GPO-uri care setează Windows Update.

Verificare PowerShell:

    Get-GPRegistryValue -Name "<GPO>" -Key "HKLM\Software\Policies\Microsoft\Windows\WindowsUpdate" |
      Where-Object { $_.ValueName -in @("WUServer","WUStatusServer","TargetGroup","TargetGroupEnabled") } |
      Select-Object ValueName,Value

Pentru Server și SQL, baseline-ul server-side trebuie revizuit separat de cel pentru Windows 11 workstation. Nu importați setări specifice workstation într-un GPO server fără validare.

### 20.2. Server Baseline v2: notify/manual pentru update-uri obișnuite

Cerința operațională recomandată pentru servere este:

    Update-uri Windows Server / .NET / SQL / Feature
        -> WSUS
        -> notificare
        -> instalare manuală

    Defender Security Intelligence / Platform
        -> WSUS
        -> auto-approval Broad
        -> instalare automată prin worker Defender dedicat

Nu modificați `AUOptions` pentru a automatiza Defender, deoarece această setare afectează toate update-urile aprobate. Baseline v2 păstrează:

    AUOptions = 2
    NoAutoUpdate = 0
    UseWUServer = 1
    UseUpdateClassPolicySource = 1

și setează explicit sursa WSUS pentru:

    Feature Updates = WSUS
    Quality Updates = WSUS
    Driver Updates  = WSUS
    Other Updates   = WSUS

Script de creare/curățare:

    .\scripts\13-New-WSUS-Server-BaselineV2.ps1 \
      -SourceGpoName "WSUS Server Baseline" \
      -WsusUrl "http://wsus01.ernu.sec:8530"

Preview-ul nu modifică GPO-ul. Aplicare:

    .\scripts\13-New-WSUS-Server-BaselineV2.ps1 \
      -SourceGpoName "WSUS Server Baseline" \
      -WsusUrl "http://wsus01.ernu.sec:8530" \
      -Apply

Scriptul:

- face backup cu timestamp pentru GPO-ul sursă și pentru baseline v2 dacă există;
- creează baseline v2 prin `Copy-GPO` dacă nu există;
- dacă există deja, îl reîmprospătează prin `Import-GPO`;
- setează `WUServer` și `WUStatusServer`;
- setează `AUOptions=2`;
- setează scan source WSUS pentru toate clasele de update;
- elimină `TargetGroup` și `TargetGroupEnabled` din baseline;
- elimină setările legacy de scheduled install/reboot care nu sunt necesare în modul notify/manual;
- elimină `ElevateNonAdmins`;
- configurează Defender Security Intelligence cu `FallbackOrder=InternalDefinitionUpdateServer`;
- configurează verificarea security intelligence la fiecare oră;
- nu creează link-uri OU.

Opțional, pentru medii strict izolate puteți utiliza `-BlockWindowsUpdateInternetLocations`, dar această opțiune trebuie evaluată deoarece poate afecta scenarii Features on Demand / language packs.

### 20.3. Instalare automată Defender fără automatizarea celorlalte update-uri

Auto-approval-ul pe WSUS nu înseamnă automat și auto-install pe client dacă serverele folosesc `AUOptions=2`.

Pentru a automatiza numai Defender, utilizați:

    .\scripts\14-Install-Defender-Client-AutoUpdateTask.ps1

Preview:

    .\scripts\14-Install-Defender-Client-AutoUpdateTask.ps1

Aplicare pe un server pilot:

    .\scripts\14-Install-Defender-Client-AutoUpdateTask.ps1 -Apply

Scriptul creează:

    C:\Scripts\WSUS\Install-Approved-DefenderUpdates.ps1

și task-ul:

    WSUS - Install Approved Defender Updates

Task-ul rulează orar ca SYSTEM și caută exclusiv update-uri aplicabile, aprobate/oferite de WSUS, cu titlul Defender și canalul `Current Channel (Broad)` pentru:

    KB2267602
    KB4052623

Nu instalează update-uri cumulative Windows, .NET, SQL, drivere sau feature upgrades. Worker-ul nu forțează restartul; dacă WUA raportează `RebootRequired=True`, situația este doar înregistrată în log.

Log:

    C:\ProgramData\WSUS-Defender-AutoUpdate\DefenderAutoUpdate.log

Validare manuală pe server pilot:

    PowerShell.exe -NoLogo -NoProfile -ExecutionPolicy RemoteSigned -File \
      "C:\Scripts\WSUS\Install-Approved-DefenderUpdates.ps1" -WhatIf


### 20.4. Două moduri de auto-approval și comutare controlată

Sunt suportate două modele operaționale.

#### Opțiunea 1 - Conservative

Script:

    .\scripts\15-Configure-WSUS-Pilot-AutoApproval.ps1

Politică:

    Pilot:
      Critical Updates
      Security Updates

    Production:
      Manual approval

    Upgrades:
      Manual

    Drivers:
      Manual / disabled

    SQL CU/GDR / SSMS / ODBC / OLE DB:
      Manual

Preview:

    .\scripts\15-Configure-WSUS-Pilot-AutoApproval.ps1

Aplicare:

    .\scripts\15-Configure-WSUS-Pilot-AutoApproval.ps1 -Apply

#### Opțiunea 2 - Accelerated

Script:

    .\scripts\16-Configure-WSUS-Accelerated-AutoApproval.ps1

Politică:

    Pilot:
      Critical Updates
      Security Updates
      Update Rollups
      Updates

    Production:
      Critical Updates
      Security Updates

    Upgrades:
      Manual

    Drivers:
      Manual / disabled

    SQL CU/GDR / SSMS / ODBC / OLE DB:
      Manual

Clasificarea generică `Updates` poate include update-uri quality preview/opționale. Din acest motiv este permisă automat numai pe Pilot în modul Accelerated.

Preview:

    .\scripts\16-Configure-WSUS-Accelerated-AutoApproval.ps1

Aplicare:

    .\scripts\16-Configure-WSUS-Accelerated-AutoApproval.ps1 -Apply

#### Comutare între cele două opțiuni

Script:

    .\scripts\17-Switch-WSUS-AutoApproval-Mode.ps1

Preview Conservative:

    .\scripts\17-Switch-WSUS-AutoApproval-Mode.ps1 -Mode Conservative

Preview Accelerated:

    .\scripts\17-Switch-WSUS-AutoApproval-Mode.ps1 -Mode Accelerated

Aplicare Conservative:

    .\scripts\17-Switch-WSUS-AutoApproval-Mode.ps1 -Mode Conservative -Apply

Aplicare Accelerated:

    .\scripts\17-Switch-WSUS-AutoApproval-Mode.ps1 -Mode Accelerated -Apply

Scriptul de switch:

- dezactivează toate regulile administrate de cele două moduri;
- activează numai regulile modului selectat;
- poate aplica regulile și peste backlog-ul existent doar cu `-ApplyExisting`;
- nu revocă aprobările deja acordate anterior.

Important: trecerea din Accelerated în Conservative modifică auto-approval-urile viitoare. Update-urile Production aprobate deja de modul Accelerated rămân aprobate până când administratorul le revocă explicit după review.



### 20.5. Auto-approval Defender Definition Updates pe stații și servere

Pentru actualizările de definiții Microsoft Defender se poate utiliza o regulă WSUS separată, limitată strict la:

    Product:
      Microsoft Defender Antivirus

    Classification:
      Definition Updates

    Groups:
      Windows-11-Pro-Pilot
      Windows-11-Pro-Production
      Server-Pilot
      Server-Production
      SQL-Pilot
      SQL-Production

Script:

    .\scripts\18-Configure-Defender-Definition-AutoApproval.ps1

Preview:

    .\scripts\18-Configure-Defender-Definition-AutoApproval.ps1

Aplicare:

    .\scripts\18-Configure-Defender-Definition-AutoApproval.ps1 -Apply

Aplicare inclusiv pentru update-urile Defender deja sincronizate:

    .\scripts\18-Configure-Defender-Definition-AutoApproval.ps1 -Apply -ApplyExisting

Regula verifică simultan produsul `Microsoft Defender Antivirus` și clasificarea `Definition Updates`. Nu aprobă generic toate update-urile Windows și nu afectează `Critical Updates`, `Security Updates`, `Updates`, `Update Rollups`, `Upgrades`, Drivers, SQL CU/GDR, SSMS, ODBC sau OLE DB.



## 21. Microsoft Office - modelul corect

Office Professional Plus 2019, Office LTSC 2021 și Office LTSC 2024 folosesc Click-to-Run. WSUS singur nu distribuie build-urile Office.

Flux:

    Office CDN
      -> Office Deployment Tool
      -> D:\OfficeUpdates
      -> SMB share
      -> Office clients

## 22. Starea suportului Office

- Office 2019 este legacy și a ieșit din suport normal. Repository-ul 2019 este păstrat pentru inventar existent și migrare.
- Office LTSC 2021 ajunge la finalul suportului în octombrie 2026; trebuie planificată migrarea.
- Office LTSC 2024 este ținta LTSC on-premises preferată în acest design.

## 23. Structura Office repository

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

## 24. Share și GPO Office

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

## 25. Verificare Office client

Dintr-o aplicație Office:

    File -> Account -> Update Options -> Update Now

Verificați și task-ul Office Automatic Updates 2.0.

## 26. Automatizarea politicii WSUS de producție

După ce sincronizarea inițială se termină cu:

    Result : Succeeded

rulați întâi configuratorul în mod Preview:

    .\scripts\09-Configure-WSUS-Production.ps1

În acest mod nu se schimbă nimic. Scriptul afișează produsele pe care le-a identificat pentru:

- Windows 11;
- Windows Server 2022;
- Windows Server 2025;
- SQL Server 2017;
- SQL Server 2019;
- SQL Server 2022;
- Microsoft Defender Antivirus.

Dacă lista este corectă, aplicați mai întâi politica fără task-ul Defender:

    .\scripts\09-Configure-WSUS-Production.ps1 -Apply

Scriptul:

- dezactivează produsele WSUS care nu sunt în setul țintă;
- activează numai produsele identificate și validate;
- păstrează clasificările Critical Updates, Definition Updates, Security Updates, Update Rollups, Updates și Upgrades;
- creează grupurile Windows-11-Pro-Pilot, Windows-11-Pro-Production, Server-Pilot, Server-Production, SQL-Pilot și SQL-Production;
- configurează implicit șase sincronizări WSUS pe zi;
- instalează worker-ul Defender în C:\Scripts\WSUS;
- creează task-ul orar WSUS - Auto Approve Defender Updates.

Auto-approval Defender este intenționat mai strict decât regula standard WSUS bazată doar pe Product + Classification. Worker-ul aprobă numai KB-urile:

    KB2267602   Security Intelligence / baza antivirus
    KB4052623   Microsoft Defender Antivirus Platform Update

și numai pentru grupurile:

    Server-Pilot
    Server-Production
    SQL-Pilot
    SQL-Production

Preview pentru worker:

    .\scripts\10-Approve-DefenderUpdates.ps1 -WhatIf

Dacă sunt afișate exclusiv update-urile Defender așteptate, instalați task-ul orar prin rerularea configuratorului:

    .\scripts\09-Configure-WSUS-Production.ps1 -Apply -InstallDefenderTask

Worker-ul verifică exact KB-ul, cere ca titlul update-ului să conțină Defender, ignoră update-urile Declined și Superseded și caută implicit doar update-urile sosite în ultimele 60 de zile.

Nu se aprobă automat:

- Windows Server cumulative updates;
- .NET updates;
- SQL Server CU/GDR;
- Windows 11 quality updates;
- Windows 11 feature upgrades.

Acestea rămân în flux Pilot -> validare -> Production.

Microsoft Defender publică security intelligence sub KB2267602 și platform updates sub KB4052623. Platform updates pot apărea în mai multe pachete în WSUS din cauza rollout-ului gradual.

Pentru auto-approval, worker-ul acceptă strict numai titlurile `Current Channel (Broad)` pentru KB2267602 și KB4052623. Scheduled Task rulează fără `-ExecutionPolicy Bypass`; scriptul copiat este deblocat explicit și se execută sub politica PowerShell configurată pe server (`RemoteSigned` în exemplul recomandat). Sunt excluse automat canalele Preview, Staged, Beta/Prerelease, Internal Only și Packaging Only. `Critical: Time Delay` rămâne exclus din regula automată implicită și poate fi gestionat separat pentru sisteme de tip datacenter care necesită întârziere controlată.

## 27. Validare finală

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
    Windows Server 2025 catalog category
    SQL Server 2017
    SQL Server 2019
    SQL Server 2022

Office:

    Office2019 repository - legacy
    Office2021 repository - migration planning
    Office2024 repository - LTSC target

## 28. Mentenanță

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

## 29. Surse oficiale

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

- Microsoft Learn - Microsoft Defender Antivirus security intelligence and product updates: https://learn.microsoft.com/defender-endpoint/microsoft-defender-antivirus-updates

- Microsoft Learn - ODBC Driver for SQL Server release notes: https://learn.microsoft.com/sql/connect/odbc/windows/release-notes-odbc-sql-server-windows
- Microsoft Learn - ODBC Driver support lifecycle: https://learn.microsoft.com/sql/connect/odbc/support-lifecycle
- Microsoft Learn - OLE DB Driver for SQL Server: https://learn.microsoft.com/sql/connect/oledb/oledb-driver-for-sql-server
- Microsoft Learn - SSMS support policy: https://learn.microsoft.com/ssms/support-policy

- Microsoft Learn / WSUS catalog note - Windows Server 2025 uses Microsoft Server operating system-24H2 in WSUS.
