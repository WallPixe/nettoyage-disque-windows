<#
.SYNOPSIS
    Analyse le disque et propose de libérer de la place : caches, restes de jeux désinstallés,
    jeux plus joués, anciennes versions d'applications, dossiers de développement inactifs,
    fichiers temporaires abandonnés, gros fichiers oubliés, entrées de démarrage invalides.

.DESCRIPTION
    Le script commence par une analyse qui ne modifie rien. Il affiche ensuite une liste
    numérotée : rien n'est supprimé tant que l'utilisateur n'a pas choisi des numéros et tapé OUI.
      - Caches et fichiers régénérables : supprimés définitivement (ils se recréent seuls).
      - Contenu personnel (restes de jeux, gros fichiers, téléchargements) : envoyé à la Corbeille.
      - Jeux Steam : désinstallés par Steam lui-même (fenêtre de confirmation de Steam).

.PARAMETER SeulementAnalyse
    Affiche le rapport puis s'arrête, sans rien proposer de supprimer.

.PARAMETER JoursInactif
    Nombre de jours sans activité au-delà duquel un projet ou un jeu est considéré inutilisé (30 par défaut).

.PARAMETER TailleMinGo
    Taille à partir de laquelle un fichier personnel est signalé comme « gros » (2 Go par défaut).
#>
param(
    [switch]$SeulementAnalyse,
    [int]$JoursInactif = 30,
    [double]$TailleMinGo = 2
)

$ErrorActionPreference = 'SilentlyContinue'
$ProgressPreference = 'SilentlyContinue'
# Fichiers OneDrive « à la demande » : listés par Windows mais sans données sur le disque.
$SANS_DONNEES = 0x401000   # FILE_ATTRIBUTE_OFFLINE | FILE_ATTRIBUTE_RECALL_ON_DATA_ACCESS
$L = $env:LOCALAPPDATA
$maintenant = Get-Date
$limiteInactif = $maintenant.AddDays(-$JoursInactif)
$elements = New-Object System.Collections.Generic.List[object]

# ---------------------------------------------------------------- outils

function Format-Taille([double]$o) {
    if ($o -ge 1GB) { '{0:N1} Go' -f ($o / 1GB) }
    elseif ($o -ge 1MB) { '{0:N0} Mo' -f ($o / 1MB) }
    else { '{0:N0} Ko' -f ($o / 1KB) }
}

function Get-TailleDossier([string]$Chemin) {
    if (-not (Test-Path -LiteralPath $Chemin)) { return 0L }
    $total = 0L
    $pile = New-Object System.Collections.Generic.Stack[System.IO.DirectoryInfo]
    $pile.Push((New-Object System.IO.DirectoryInfo $Chemin))
    while ($pile.Count -gt 0) {
        $d = $pile.Pop()
        try { $entrees = $d.GetFileSystemInfos() } catch { continue }
        foreach ($e in $entrees) {
            if ($e -is [System.IO.DirectoryInfo]) {
                if (-not ($e.Attributes -band [IO.FileAttributes]::ReparsePoint)) { $pile.Push($e) }
            } elseif (-not ([int]$e.Attributes -band $SANS_DONNEES)) {
                $total += $e.Length
            }
        }
    }
    $total
}

function Get-TailleTotale([string[]]$Chemins) {
    $t = 0L
    foreach ($c in $Chemins) {
        if (Test-Path -LiteralPath $c -PathType Leaf) { $t += (Get-Item -LiteralPath $c -Force).Length }
        else { $t += Get-TailleDossier $c }
    }
    $t
}

# Modes : Contenu (vide le dossier), Supprimer, Corbeille, ViderCorbeille, Registre, Steam
function Ajouter {
    param($Categorie, $Libelle, [string[]]$Chemins, [long]$Taille, $Risque, $Mode, $Note = '', $Cle = '')
    if ($Taille -le 0 -and $Mode -notin 'Registre', 'Steam') { return }
    if ($Categorie -eq 'Caches' -and $Taille -lt 50MB) { return }
    $elements.Add([pscustomobject]@{
        Categorie = $Categorie; Libelle = $Libelle; Chemins = $Chemins; Taille = $Taille
        Risque = $Risque; Mode = $Mode; Note = $Note; Cle = $Cle
    })
}

function Etape([string]$Texte) { Write-Host "  - $Texte" -ForegroundColor DarkGray }

function Get-EspaceLibre {
    ((Get-PSDrive -PSProvider FileSystem | Where-Object { $_.Used -ne $null }) | Measure-Object Free -Sum).Sum
}

function Lire-Vdf([string]$Texte, [string]$Champ) {
    if ($Texte -match ('"' + $Champ + '"\s+"([^"]*)"')) { $Matches[1] -replace '\\\\', '\' } else { $null }
}

$estAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole(
    [Security.Principal.WindowsBuiltInRole]::Administrator)

Write-Host ''
Write-Host '=== Nettoyage du disque : analyse (rien n''est modifié) ===' -ForegroundColor Cyan
foreach ($dr in Get-PSDrive -PSProvider FileSystem | Where-Object { $_.Used -ne $null -and ($_.Used + $_.Free) -gt 0 }) {
    $pct = [math]::Round(100 * $dr.Free / ($dr.Used + $dr.Free))
    $couleur = if ($pct -lt 10) { 'Red' } elseif ($pct -lt 20) { 'Yellow' } else { 'Green' }
    Write-Host ("  Disque {0}: {1} libres sur {2} ({3} %)" -f $dr.Name, (Format-Taille $dr.Free), (Format-Taille ($dr.Used + $dr.Free)), $pct) -ForegroundColor $couleur
}
Write-Host ''

# ---------------------------------------------------------------- 1. caches

Etape 'Caches et fichiers temporaires'
$caches = @(
    @('Fichiers temporaires (utilisateur)', $env:TEMP, ''),
    @('Fichiers temporaires (Windows)', "$env:windir\Temp", $(if ($estAdmin) { '' } else { 'Lance le script en administrateur pour tout vider.' })),
    @('Cache des shaders NVIDIA', "$L\NVIDIA\DXCache", 'Se reconstruit : les jeux chargent un peu plus lentement la première fois.'),
    @('Cache des shaders NVIDIA (OpenGL)', "$L\NVIDIA\GLCache", ''),
    @('Cache des shaders AMD', "$L\AMD\DxCache", 'Se reconstruit : les jeux chargent un peu plus lentement la première fois.'),
    @('Cache des shaders AMD (DXC)', "$L\AMD\DxcCache", ''),
    @('Cache des shaders AMD (Vulkan)', "$L\AMD\VkCache", ''),
    @('Cache des shaders AMD (OpenGL)', "$L\AMD\GLCache", ''),
    @('Cache des shaders DirectX', "$L\D3DSCache", ''),
    @('Cache des shaders Intel', "$env:USERPROFILE\AppData\LocalLow\Intel\ShaderCache", ''),
    @('Rapports de plantage', "$L\CrashDumps", ''),
    @('Cache pip (Python)', "$L\pip\cache", 'Les paquets seront re-téléchargés si besoin.'),
    @('Cache uv (Python)', "$L\uv\cache", 'Les paquets seront re-téléchargés si besoin.'),
    @('Cache npm (Node.js)', "$L\npm-cache", 'Les paquets seront re-téléchargés si besoin.'),
    @('Cache Yarn (Node.js)', "$L\Yarn\Cache", 'Les paquets seront re-téléchargés si besoin.'),
    @('Cache Gradle (Android / Java)', "$env:USERPROFILE\.gradle\caches", 'Les dépendances seront re-téléchargées à la prochaine compilation.')
)
foreach ($c in $caches) {
    Ajouter 'Caches' $c[0] @($c[1]) (Get-TailleDossier $c[1]) 'Sûr' 'Contenu' $c[2]
}
# Python installé depuis le Microsoft Store : son cache pip est rangé ailleurs.
$pipStore = @(Get-ChildItem -LiteralPath "$L\Packages" -Directory -Filter 'PythonSoftwareFoundation.Python*' |
    ForEach-Object { Join-Path $_.FullName 'LocalCache\Local\pip\cache' } | Where-Object { Test-Path -LiteralPath $_ })
if ($pipStore.Count) { Ajouter 'Caches' 'Cache pip (Python du Microsoft Store)' $pipStore (Get-TailleTotale $pipStore) 'Sûr' 'Contenu' 'Les paquets seront re-téléchargés si besoin.' }

$navigateurs = [ordered]@{
    'Chrome' = "$L\Google\Chrome\User Data"
    'Edge'   = "$L\Microsoft\Edge\User Data"
    'Brave'  = "$L\BraveSoftware\Brave-Browser\User Data"
}
foreach ($nom in $navigateurs.Keys) {
    $profils = Get-ChildItem -LiteralPath $navigateurs[$nom] -Directory | Where-Object { $_.Name -eq 'Default' -or $_.Name -like 'Profile *' }
    $dossiers = @(foreach ($p in $profils) { foreach ($s in 'Cache', 'Code Cache', 'GPUCache') {
        $x = Join-Path $p.FullName $s; if (Test-Path -LiteralPath $x) { $x } } })
    if ($dossiers.Count) { Ajouter 'Caches' "Cache du navigateur $nom" $dossiers (Get-TailleTotale $dossiers) 'Sûr' 'Contenu' "Ferme $nom avant. Tes mots de passe, favoris et historique ne sont pas touchés." }
}
$ff = @(Get-ChildItem -LiteralPath "$L\Mozilla\Firefox\Profiles" -Directory | ForEach-Object { Join-Path $_.FullName 'cache2' } | Where-Object { Test-Path -LiteralPath $_ })
if ($ff.Count) { Ajouter 'Caches' 'Cache du navigateur Firefox' $ff (Get-TailleTotale $ff) 'Sûr' 'Contenu' 'Ferme Firefox avant. Tes mots de passe, favoris et historique ne sont pas touchés.' }

# ---------------------------------------------------------------- 2. Steam

$exclusParcours = New-Object System.Collections.Generic.List[string]
$steam = (Get-ItemProperty 'HKCU:\Software\Valve\Steam').SteamPath
if ($steam) {
    Etape 'Bibliothèques Steam'
    $steam = $steam -replace '/', '\'
    $biblios = @($steam)
    $vdf = Join-Path $steam 'steamapps\libraryfolders.vdf'
    if (Test-Path -LiteralPath $vdf) {
        $biblios += Select-String -LiteralPath $vdf -Pattern '"path"\s+"(.+)"' | ForEach-Object { $_.Matches[0].Groups[1].Value -replace '\\\\', '\' }
    }
    $biblios = $biblios | ForEach-Object { $_.TrimEnd('\') } | Sort-Object -Unique
    $jeuxInutilises = New-Object System.Collections.Generic.List[object]
    foreach ($b in $biblios) {
        $apps = Join-Path $b 'steamapps'
        if (-not (Test-Path -LiteralPath $apps)) { continue }
        $exclusParcours.Add($apps)
        $installes = @{}; $ids = @{}
        foreach ($m in Get-ChildItem -LiteralPath $apps -Filter 'appmanifest_*.acf') {
            $txt = Get-Content -LiteralPath $m.FullName -Raw
            $id = Lire-Vdf $txt 'appid'; $dir = Lire-Vdf $txt 'installdir'
            if ($id) { $ids[$id] = $true }
            if ($dir) { $installes[$dir] = $true }
            $joue = [long](Lire-Vdf $txt 'LastPlayed')
            $taille = [long](Lire-Vdf $txt 'SizeOnDisk')
            $dernier = if ($joue -gt 0) { [DateTimeOffset]::FromUnixTimeSeconds($joue).LocalDateTime } else { $null }
            if ($taille -ge 1GB -and ($dernier -eq $null -or $dernier -lt $limiteInactif)) {
                $quand = if ($dernier) { 'pas lancé depuis le ' + $dernier.ToString('dd/MM/yyyy') } else { 'jamais lancé' }
                $jeuxInutilises.Add([pscustomobject]@{ Id = $id; Nom = (Lire-Vdf $txt 'name'); Taille = $taille; Quand = $quand })
            }
        }
        # Dossiers de jeux encore présents alors que Steam ne les connaît plus.
        foreach ($d in Get-ChildItem -LiteralPath (Join-Path $apps 'common') -Directory) {
            if ($installes.ContainsKey($d.Name)) { continue }
            $t = Get-TailleDossier $d.FullName
            if ($t -ge 50MB) {
                Ajouter 'Restes de jeux désinstallés' "Steam : $($d.Name)" @($d.FullName) $t 'À vérifier' 'Corbeille' 'Plus installé selon Steam. Peut contenir des sauvegardes, captures ou mods.'
            }
        }
        $orphelins = @(Get-ChildItem -LiteralPath (Join-Path $apps 'shadercache') -Directory | Where-Object { -not $ids.ContainsKey($_.Name) } | ForEach-Object { $_.FullName })
        if ($orphelins.Count) { Ajouter 'Restes de jeux désinstallés' "Steam : caches de shaders de $($orphelins.Count) jeu(x) désinstallé(s)" $orphelins (Get-TailleTotale $orphelins) 'Sûr' 'Supprimer' '' }
        $workshop = @(Get-ChildItem -LiteralPath (Join-Path $apps 'workshop\content') -Directory | Where-Object { -not $ids.ContainsKey($_.Name) } | ForEach-Object { $_.FullName })
        if ($workshop.Count) { Ajouter 'Restes de jeux désinstallés' "Steam : mods Workshop de $($workshop.Count) jeu(x) désinstallé(s)" $workshop (Get-TailleTotale $workshop) 'À vérifier' 'Supprimer' 'Se re-téléchargent si tu réinstalles le jeu.' }
        $dl = Join-Path $apps 'downloading'
        $t = Get-TailleDossier $dl
        if ($t -ge 100MB) { Ajouter 'Restes de jeux désinstallés' 'Steam : téléchargements en attente ou interrompus' @($dl) $t 'À vérifier' 'Contenu' 'Ferme Steam avant. Une mise à jour en pause repartira de zéro.' }
    }
    foreach ($j in $jeuxInutilises | Sort-Object Taille -Descending) {
        Ajouter 'Jeux installés mais plus joués' "Steam : $($j.Nom) ($($j.Quand))" @($j.Id) $j.Taille 'À vérifier' 'Steam' 'Désinstallé par Steam (il demande confirmation). Les sauvegardes Steam Cloud sont gardées.'
    }
}

# ---------------------------------------------------------------- 3. Epic Games

$epicInstalles = @{}
foreach ($m in Get-ChildItem -LiteralPath "$env:ProgramData\Epic\EpicGamesLauncher\Data\Manifests" -Filter '*.item') {
    $j = Get-Content -LiteralPath $m.FullName -Raw | ConvertFrom-Json
    if ($j.InstallLocation) { $epicInstalles[$j.InstallLocation.TrimEnd('\')] = $true }
}
$dat = "$env:ProgramData\Epic\UnrealEngineLauncher\LauncherInstalled.dat"
if (Test-Path -LiteralPath $dat) {
    foreach ($i in (Get-Content -LiteralPath $dat -Raw | ConvertFrom-Json).InstallationList) {
        if ($i.InstallLocation) { $epicInstalles[$i.InstallLocation.TrimEnd('\')] = $true }
    }
}
# On ne regarde que les dossiers « Epic Games » : un jeu installé à la racine d'un disque
# ne doit pas faire passer tout le disque pour des restes.
$racinesEpic = @(@($epicInstalles.Keys | ForEach-Object { Split-Path $_ -Parent }) + "$env:ProgramFiles\Epic Games" |
    Where-Object { $_ -match 'Epic Games$' -and (Test-Path -LiteralPath $_) } | Sort-Object -Unique)
if ($racinesEpic.Count) { Etape 'Bibliothèques Epic Games' }
foreach ($r in $racinesEpic) {
    $exclusParcours.Add($r)
    foreach ($d in Get-ChildItem -LiteralPath $r -Directory) {
        if ($epicInstalles.ContainsKey($d.FullName) -or $d.Name -in 'Launcher', 'DirectXRedist', 'Epic Online Services') { continue }
        $t = Get-TailleDossier $d.FullName
        if ($t -ge 100MB) { Ajouter 'Restes de jeux désinstallés' "Epic Games : $($d.Name)" @($d.FullName) $t 'À vérifier' 'Corbeille' 'Plus installé selon le launcher Epic. Peut contenir des sauvegardes.' }
    }
}

# ---------------------------------------------------------------- 4. anciennes versions d'applications

Etape 'Anciennes versions d''applications'
$enCours = @(Get-Process | Where-Object { $_.Path } | ForEach-Object { $_.Path })
$regexVersion = '^(app-)?\d+(\.\d+){1,3}$'
$parents = @(Get-ChildItem -LiteralPath $L -Directory | Where-Object { $_.Name -notin 'Microsoft', 'Packages', 'Temp' }) +
           @(Get-ChildItem -LiteralPath "$L\Programs" -Directory)
$parents = @($parents | ForEach-Object { $_; $a = Join-Path $_.FullName 'Apps'; if (Test-Path -LiteralPath $a) { Get-Item -LiteralPath $a } })
foreach ($p in $parents) {
    $versions = @(Get-ChildItem -LiteralPath $p.FullName -Directory | Where-Object { $_.Name -match $regexVersion } |
        Sort-Object { [version]($_.Name -replace '^app-', '') })
    if ($versions.Count -lt 2) { continue }
    $garde = $versions[-1]
    $vieilles = @($versions[0..($versions.Count - 2)] | Where-Object {
        $dossier = $_.FullName + '\'; -not ($enCours | Where-Object { $_.StartsWith($dossier, 'OrdinalIgnoreCase') }) } |
        ForEach-Object { $_.FullName })
    if (-not $vieilles.Count) { continue }
    $t = Get-TailleTotale $vieilles
    $appli = if ($p.Name -eq 'Apps') { $p.Parent.Name } else { $p.Name }
    if ($t -ge 200MB) { Ajouter 'Anciennes versions d''applications' "$appli : $($vieilles.Count) ancienne(s) version(s)" $vieilles $t 'Sûr' 'Supprimer' "La version la plus récente ($($garde.Name)) est conservée." }
}
$ndk = @(Get-ChildItem -LiteralPath "$L\Android\Sdk\ndk" -Directory | Sort-Object { [version]$_.Name })
if ($ndk.Count -ge 2) {
    $vieux = @($ndk[0..($ndk.Count - 2)] | ForEach-Object { $_.FullName })
    Ajouter 'Anciennes versions d''applications' "Android SDK : $($vieux.Count) ancien(s) NDK" $vieux (Get-TailleTotale $vieux) 'À vérifier' 'Supprimer' "Garde le NDK $($ndk[-1].Name). Un vieux projet Android peut encore demander un NDK précis."
}

# ---------------------------------------------------------------- 5. dossier perso et dossiers à la racine du disque

$motifTemp = '\.(partial|part|crdownload|download|tmp)$|^\.kj-tmp'
$ilYa7Jours = $maintenant.AddDays(-7)
$devTrouves = New-Object System.Collections.Generic.List[object]
$grosFichiers = New-Object System.Collections.Generic.List[object]
$partiels = New-Object System.Collections.Generic.List[object]

function Parcourir([string[]]$Racines, [string[]]$Exclure) {
    $pile = New-Object System.Collections.Generic.Stack[System.IO.DirectoryInfo]
    foreach ($r in $Racines) { if (Test-Path -LiteralPath $r) { $pile.Push((New-Object System.IO.DirectoryInfo $r)) } }
    $n = 0
    while ($pile.Count -gt 0) {
        $d = $pile.Pop()
        if ($Exclure -contains $d.FullName.TrimEnd('\')) { continue }
        $n++; if ($n % 2000 -eq 0) { Write-Host ("`r    {0:N0} dossiers analysés..." -f $n) -NoNewline -ForegroundColor DarkGray }
        try { $entrees = $d.GetFileSystemInfos() } catch { continue }
        $unreal = [bool]($entrees | Where-Object { $_.Extension -eq '.uproject' })
        foreach ($e in $entrees) {
            if ($e -is [System.IO.DirectoryInfo]) {
                if ($e.Attributes -band [IO.FileAttributes]::ReparsePoint) { continue }
                if ($e.Name -eq 'node_modules') { $devTrouves.Add(@($e.FullName, 'node_modules', $d)); continue }
                if ($e.Name -in '.venv', 'venv', 'env' -and (Test-Path -LiteralPath (Join-Path $e.FullName 'pyvenv.cfg'))) { $devTrouves.Add(@($e.FullName, 'environnement Python', $d)); continue }
                if ($e.Name -eq 'build' -and (Test-Path -LiteralPath (Join-Path $e.FullName 'intermediates'))) { $devTrouves.Add(@($e.FullName, 'compilation Android', $d)); continue }
                if ($unreal -and $e.Name -in 'Intermediate', 'DerivedDataCache') { $devTrouves.Add(@($e.FullName, 'compilation Unreal', $d)); continue }
                # Dossiers cachés (.git, .cache, .android...) : données d'outils, pas des projets à nettoyer.
                if ($e.Name.StartsWith('.')) { continue }
                $pile.Push($e)
            } elseif (-not ([int]$e.Attributes -band $SANS_DONNEES)) {
                if ($e.Name -match $motifTemp -and $e.Length -ge 100MB -and $e.LastWriteTime -lt $ilYa7Jours) { $partiels.Add($e) }
                elseif ($e.Length -ge $TailleMinGo * 1GB) { $grosFichiers.Add($e) }
            }
        }
    }
    Write-Host ("`r    {0:N0} dossiers analysés.      " -f $n) -ForegroundColor DarkGray
}

Etape 'Dossier personnel et dossiers à la racine du disque (le plus long)'
$sys = $env:SystemDrive + '\'
$nomsSysteme = 'Windows', 'Program Files', 'Program Files (x86)', 'ProgramData', 'Users', '$Recycle.Bin', 'System Volume Information',
               'Recovery', '$WinREAgent', 'PerfLogs', 'Config.Msi', 'OneDriveTemp', 'Riot Games', 'XboxGames', 'SteamLibrary', 'Epic Games', 'GOG Games', 'EA Games', 'Ubisoft'
$racines = @($env:USERPROFILE) + @(Get-ChildItem -LiteralPath $sys -Directory -Force | Where-Object {
    $_.Name -notin $nomsSysteme -and -not ($_.Attributes -band [IO.FileAttributes]::ReparsePoint) } | ForEach-Object { $_.FullName })
$exclusParcours.Add("$env:USERPROFILE\AppData")
Parcourir $racines $exclusParcours.ToArray()

foreach ($dv in $devTrouves) {
    $chemin = $dv[0]; $type = $dv[1]; $projet = $dv[2]
    $recent = $projet.LastWriteTime
    foreach ($e in $projet.GetFileSystemInfos()) {
        if ($e.Name -in 'node_modules', 'build', '.venv', 'venv', 'env', 'Intermediate', 'DerivedDataCache', 'Saved', '.git') { continue }
        if ($e.LastWriteTime -gt $recent) { $recent = $e.LastWriteTime }
    }
    if ($recent -ge $limiteInactif) { continue }
    $t = Get-TailleDossier $chemin
    if ($t -lt 100MB) { continue }
    $jours = [int]($maintenant - $recent).TotalDays
    $comment = switch ($type) {
        'node_modules'         { 'Se réinstalle avec « npm install » dans le projet.' }
        'environnement Python' { 'Se recrée avec « python -m venv » puis « pip install -r requirements.txt » (si le projet a ce fichier).' }
        'compilation Android'  { 'Se régénère à la prochaine compilation.' }
        'compilation Unreal'   { 'Se régénère à la prochaine ouverture du projet (plus longue).' }
    }
    $risque = if ($type -eq 'environnement Python') { 'À vérifier' } else { 'Sûr' }
    Ajouter 'Dossiers de développement inactifs' "$type de « $($projet.Name) » (projet inactif depuis $jours jours)" @($chemin) $t $risque 'Supprimer' "$comment  [$chemin]"
}

foreach ($f in $partiels) {
    Ajouter 'Fichiers temporaires abandonnés' "$($f.Name) (du $($f.LastWriteTime.ToString('dd/MM/yyyy')))" @($f.FullName) $f.Length 'Sûr' 'Supprimer' "Copie ou téléchargement interrompu, inutilisable.  [$($f.DirectoryName)]"
}
foreach ($f in $grosFichiers | Sort-Object Length -Descending) {
    Ajouter 'Gros fichiers personnels' "$($f.Name) (modifié le $($f.LastWriteTime.ToString('dd/MM/yyyy')))" @($f.FullName) $f.Length 'À vérifier' 'Corbeille' "[$($f.DirectoryName)]"
}

# ---------------------------------------------------------------- 6. téléchargements, corbeille, démarrage

$dossierDl = (Get-ItemProperty 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\User Shell Folders').'{374DE290-123F-4565-9164-39C4925E467B}'
$dossierDl = if ($dossierDl) { [Environment]::ExpandEnvironmentVariables($dossierDl) } else { "$env:USERPROFILE\Downloads" }
$dejaListes = @{}; foreach ($f in $grosFichiers) { $dejaListes[$f.FullName] = $true }
$vieuxDl = @(Get-ChildItem -LiteralPath $dossierDl -Force | Where-Object {
    $_.LastWriteTime -lt $maintenant.AddDays(-90) -and -not $dejaListes.ContainsKey($_.FullName) -and $_.Name -ne 'desktop.ini' } | ForEach-Object { $_.FullName })
if ($vieuxDl.Count) {
    $t = Get-TailleTotale $vieuxDl
    if ($t -ge 100MB) { Ajouter 'Téléchargements' "$($vieuxDl.Count) éléments téléchargés il y a plus de 90 jours" $vieuxDl $t 'À vérifier' 'Corbeille' "Jette un œil au dossier avant : $dossierDl" }
}

$sid = [Security.Principal.WindowsIdentity]::GetCurrent().User.Value
$corbeilles = @(Get-PSDrive -PSProvider FileSystem | ForEach-Object { Join-Path $_.Root "`$Recycle.Bin\$sid" } | Where-Object { Test-Path -LiteralPath $_ })
$t = Get-TailleTotale $corbeilles
if ($t -ge 10MB) { Ajouter 'Corbeille' 'Vider la Corbeille' @() $t 'À vérifier' 'ViderCorbeille' 'Définitif : vérifie qu''il n''y a rien à récupérer dedans.' }

Etape 'Programmes lancés au démarrage'
$cleRun = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run'
$run = Get-ItemProperty -Path $cleRun
foreach ($prop in $run.PSObject.Properties | Where-Object { $_.Name -notlike 'PS*' }) {
    $cmd = [Environment]::ExpandEnvironmentVariables([string]$prop.Value).Trim()
    $exe = if ($cmd -match '^"([^"]+)"') { $Matches[1] }
           elseif ($cmd -match '^(.+?\.(exe|bat|cmd|com|lnk|vbs))(\s|$)') { $Matches[1] }
           else { ($cmd -split '\s+')[0] }
    # Le dossier WindowsApps (applis du Store) n'est pas lisible : on ne peut pas vérifier, on garde.
    $existe = if ($exe -match '\\WindowsApps\\') { $true }
              elseif ([IO.Path]::IsPathRooted($exe)) { Test-Path -LiteralPath $exe }
              else { [bool](Get-Command $exe -CommandType Application) }
    if (-not $existe) {
        Ajouter 'Démarrage' "Entrée de démarrage invalide : « $($prop.Name) » = « $cmd »" @($prop.Name) 0 'Sûr' 'Registre' 'Ne lance aucun programme existant. Une sauvegarde .reg est faite avant.' $cleRun
    }
}

# ---------------------------------------------------------------- rapport

$ordre = 'Caches', 'Fichiers temporaires abandonnés', 'Restes de jeux désinstallés', 'Anciennes versions d''applications',
         'Dossiers de développement inactifs', 'Jeux installés mais plus joués', 'Téléchargements', 'Gros fichiers personnels', 'Corbeille', 'Démarrage'
$liste = @($elements | Sort-Object @{ e = { [array]::IndexOf($ordre, $_.Categorie) } }, @{ e = { $_.Taille }; Descending = $true })

Write-Host ''
if (-not $liste.Count) { Write-Host 'Rien à nettoyer de notable. Ton disque est déjà propre !' -ForegroundColor Green; return }
$i = 0; $categorie = $null
foreach ($el in $liste) {
    $i++; $el | Add-Member -NotePropertyName Numero -NotePropertyValue $i -Force
    if ($el.Categorie -ne $categorie) { $categorie = $el.Categorie; Write-Host ''; Write-Host "  $categorie" -ForegroundColor Cyan }
    $couleur = if ($el.Risque -eq 'Sûr') { 'Green' } else { 'Yellow' }
    $taille = if ($el.Mode -eq 'Registre') { '' } else { Format-Taille $el.Taille }
    Write-Host ('  {0,3}. ' -f $i) -NoNewline
    Write-Host ('{0,9}  ' -f $taille) -NoNewline
    Write-Host ('{0,-11}' -f $el.Risque) -NoNewline -ForegroundColor $couleur
    Write-Host $el.Libelle
    if ($el.Note) { Write-Host ('                         ' + $el.Note) -ForegroundColor DarkGray }
}
$totalSur = ($liste | Where-Object Risque -eq 'Sûr' | Measure-Object Taille -Sum).Sum
$total = ($liste | Measure-Object Taille -Sum).Sum
Write-Host ''
Write-Host ("  Sans risque (« Sûr ») : {0}    Tout compris : {1}" -f (Format-Taille $totalSur), (Format-Taille $total)) -ForegroundColor Cyan

# Programmes installés : seulement un rappel, la désinstallation passe par Windows.
$progs = Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*', 'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*', 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*' |
    Where-Object { $_.DisplayName -and $_.EstimatedSize -ge 500000 -and -not $_.SystemComponent -and -not $_.ParentKeyName } |
    Sort-Object EstimatedSize -Descending | Select-Object -First 10
if ($progs) {
    Write-Host ''
    Write-Host '  Pour info, les programmes installés les plus lourds (à désinstaller dans Paramètres > Applications si tu ne t''en sers plus) :' -ForegroundColor Cyan
    foreach ($p in $progs) { Write-Host ('       {0,9}  {1}' -f (Format-Taille ($p.EstimatedSize * 1KB)), $p.DisplayName) }
}

if ($SeulementAnalyse) { return }

# ---------------------------------------------------------------- choix et nettoyage

Write-Host ''
Write-Host 'Que veux-tu nettoyer ?' -ForegroundColor Cyan
Write-Host '  - des numéros, par exemple : 1,3,7-9'
Write-Host '  - S pour tous les éléments marqués « Sûr »'
Write-Host '  - Entrée pour quitter sans rien toucher'
$reponse = (Read-Host 'Ton choix').Trim()
if (-not $reponse) { Write-Host 'Rien n''a été modifié.'; return }

$choix = @()
if ($reponse -ieq 'S') { $choix = @($liste | Where-Object Risque -eq 'Sûr') }
else {
    $nums = foreach ($morceau in $reponse -split '[,; ]+') {
        if ($morceau -match '^(\d+)-(\d+)$') { [int]$Matches[1]..[int]$Matches[2] } elseif ($morceau -match '^\d+$') { [int]$morceau }
    }
    $choix = @($liste | Where-Object { $nums -contains $_.Numero })
}
if (-not $choix.Count) { Write-Host 'Aucun numéro valide. Rien n''a été modifié.'; return }

Write-Host ''
foreach ($el in $choix) { Write-Host ('  {0,3}. {1,9}  {2}' -f $el.Numero, $(if ($el.Mode -eq 'Registre') { '' } else { Format-Taille $el.Taille }), $el.Libelle) }
Write-Host ("  Total : {0}" -f (Format-Taille (($choix | Measure-Object Taille -Sum).Sum))) -ForegroundColor Cyan
if ((Read-Host 'Tape OUI pour lancer le nettoyage') -cne 'OUI') { Write-Host 'Annulé. Rien n''a été modifié.'; return }

Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
public static class CorbeilleWindows {
    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
    struct SHFILEOPSTRUCT {
        public IntPtr hwnd; public uint wFunc; public string pFrom; public string pTo;
        public ushort fFlags; public bool fAnyOperationsAborted; public IntPtr hNameMappings; public string lpszProgressTitle;
    }
    [DllImport("shell32.dll", CharSet = CharSet.Unicode)]
    static extern int SHFileOperation(ref SHFILEOPSTRUCT op);
    // FO_DELETE avec FOF_ALLOWUNDO (Corbeille) | FOF_NOCONFIRMATION | FOF_WANTNUKEWARNING :
    // Windows prévient quand même si l'élément est trop gros pour la Corbeille.
    public static int Envoyer(string chemin) {
        var op = new SHFILEOPSTRUCT();
        op.wFunc = 3; op.pFrom = chemin + "\0\0"; op.fFlags = 0x0040 | 0x0010 | 0x4000;
        return SHFileOperation(ref op);
    }
}
'@

function Supprimer-Element([string]$Chemin) {
    if (Test-Path -LiteralPath $Chemin -PathType Container) {
        # rd ne suit pas les jonctions (contrairement à Remove-Item sous PowerShell 5) et gère les chemins longs.
        cmd.exe /c rd /s /q "\\?\$Chemin" 2>$null
    } else {
        Remove-Item -LiteralPath $Chemin -Force
    }
}

$avant = Get-EspaceLibre
Write-Host ''
foreach ($el in $choix | Sort-Object { $_.Mode -eq 'ViderCorbeille' }) {
    Write-Host ("  {0}..." -f $el.Libelle) -NoNewline
    switch ($el.Mode) {
        'Contenu'   { foreach ($c in $el.Chemins) { Get-ChildItem -LiteralPath $c -Force | ForEach-Object { Supprimer-Element $_.FullName } } }
        'Supprimer' { foreach ($c in $el.Chemins) { Supprimer-Element $c } }
        'Corbeille' { foreach ($c in $el.Chemins) { [void][CorbeilleWindows]::Envoyer($c) } }
        'ViderCorbeille' { Clear-RecycleBin -Force }
        'Steam'     { foreach ($id in $el.Chemins) { Start-Process "steam://uninstall/$id" } }
        'Registre'  {
            $sauvegarde = Join-Path ([Environment]::GetFolderPath('MyDocuments')) ('sauvegarde-demarrage-{0}.reg' -f $maintenant.ToString('yyyyMMdd-HHmmss'))
            if (-not (Test-Path -LiteralPath $sauvegarde)) { reg.exe export ($el.Cle -replace '^HKCU:', 'HKCU') $sauvegarde /y | Out-Null }
            foreach ($nom in $el.Chemins) {
                Remove-ItemProperty -Path $el.Cle -Name $nom
                Remove-ItemProperty -Path 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\StartupApproved\Run' -Name $nom
            }
            $el.Note = "Sauvegarde : $sauvegarde"
        }
    }
    $reste = @($el.Chemins | Where-Object { $el.Mode -in 'Supprimer', 'Corbeille' -and (Test-Path -LiteralPath $_) })
    if ($el.Mode -eq 'Steam') { Write-Host ' confirme dans la fenêtre de Steam' -ForegroundColor Yellow }
    elseif ($reste.Count) { Write-Host ' en partie (fichiers utilisés ou accès refusé)' -ForegroundColor Yellow }
    else { Write-Host ' ok' -ForegroundColor Green }
    if ($el.Mode -eq 'Registre') { Write-Host "       $($el.Note)" -ForegroundColor DarkGray }
}

$gagne = (Get-EspaceLibre) - $avant
Write-Host ''
Write-Host ("Terminé : {0} libérés." -f (Format-Taille ([math]::Max(0, $gagne)))) -ForegroundColor Green
if ($choix | Where-Object Mode -eq 'Corbeille') {
    Write-Host 'Les éléments envoyés à la Corbeille ne libèrent la place qu''une fois la Corbeille vidée.' -ForegroundColor Yellow
}
