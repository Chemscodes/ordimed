# Bascule Ordimed entre ses deux versions.
#
#   .\basculer.ps1 firebase    # Firebase Auth + Firestore
#   .\basculer.ps1 mongo       # backend Node + MongoDB
#   .\basculer.ps1             # dit seulement ou on en est
#
# Les donnees ne suivent pas : les deux versions lisent des bases
# differentes. Chacune retrouve la sienne telle qu'elle etait, et ce qui a
# ete saisi dans l'autre entre-temps n'y sera pas. C'est assume — voir
# backend/README.md pour transporter les donnees d'un monde a l'autre.

param(
    [ValidateSet('firebase', 'mongo', 'etat')]
    [string]$Version = 'etat',

    # Ne relance pas l'app apres la construction.
    [switch]$SansLancer
)

$ErrorActionPreference = 'Stop'

$Depot = 'D:\ordimed'
# La construction se fait dans une copie : le dossier build du depot est
# inaccessible en ecriture (droits NTFS qu'un takeown administrateur seul
# pourrait reprendre), et CMake echoue a y recreer pkgRedirects.
$Chantier = 'D:\ordimed_run'
$Exe = "$Chantier\build\windows\x64\runner\Debug\ordimed.exe"

$Branches = @{ firebase = 'firebase'; mongo = 'main' }

function Etat {
    $b = git -C $Depot branch --show-current
    $nom = if ($b -eq 'firebase') { 'FIREBASE (Auth + Firestore)' }
           elseif ($b -eq 'main') { 'MONGO (backend Node + MongoDB)' }
           else { "branche « $b »" }

    Write-Host ''
    Write-Host "  Version active : $nom" -ForegroundColor Cyan
    Write-Host "  Branche        : $b"

    if (Test-Path $Exe) {
        $d = (Get-Item $Exe).LastWriteTime
        Write-Host "  Binaire        : construit le $d"
    } else {
        Write-Host "  Binaire        : aucun" -ForegroundColor Yellow
    }
    Write-Host ''
}

if ($Version -eq 'etat') {
    Etat
    Write-Host "  .\basculer.ps1 firebase   |   .\basculer.ps1 mongo" -ForegroundColor DarkGray
    Write-Host ''
    exit 0
}

$cible = $Branches[$Version]

# Un travail non commite serait perdu par le changement de branche : mieux
# vaut refuser que d'effacer sans le dire.
$sale = git -C $Depot status --porcelain
if ($sale) {
    Write-Host ''
    Write-Host '  Des modifications ne sont pas enregistrees :' -ForegroundColor Yellow
    $sale -split "`n" | Select-Object -First 10 | ForEach-Object { Write-Host "    $_" }
    Write-Host ''
    Write-Host '  Fais un commit, ou « git stash », puis relance.' -ForegroundColor Yellow
    Write-Host ''
    exit 1
}

Write-Host ''
Write-Host "  Bascule vers $($Version.ToUpper())…" -ForegroundColor Cyan

# L'app en cours tient le binaire ouvert : la reconstruction echouerait.
Get-Process -Name ordimed -ErrorAction SilentlyContinue | Stop-Process -Force

git -C $Depot switch $cible
if ($LASTEXITCODE -ne 0) { throw "Impossible de passer sur la branche $cible" }

Write-Host '  Dependances…'
Push-Location $Depot
try { flutter pub get | Out-Null } finally { Pop-Location }

Write-Host '  Copie vers le chantier…'
# /MIR efface dans la copie ce qui a disparu de la source : sans lui, les
# fichiers d'une version resteraient dans la construction de l'autre —
# api_service.dart survivrait cote Firebase, et l'analyse echouerait sur
# des imports introuvables.
robocopy "$Depot\lib" "$Chantier\lib" /MIR /NFL /NDL /NJH /NJS /NP | Out-Null
robocopy $Depot $Chantier /XD build .dart_tool tools presentation ephemeral .git backend import /XF *.log /NFL /NDL /NJH /NJS /NP | Out-Null
if ($LASTEXITCODE -ge 8) { throw "Echec de la copie (code $LASTEXITCODE)" }

Write-Host '  Construction…'
Push-Location $Chantier
try {
    flutter pub get | Out-Null
    flutter build windows --debug 2>&1 | Select-String -Pattern '^√|error:' | ForEach-Object { Write-Host "    $_" }
} finally { Pop-Location }

if (-not (Test-Path $Exe)) { throw 'La construction n’a pas produit d’executable.' }

Etat

if (-not $SansLancer) {
    Write-Host '  Lancement…' -ForegroundColor DarkGray
    Start-Process $Exe -WorkingDirectory (Split-Path $Exe)
}

if ($Version -eq 'mongo') {
    Write-Host '  Rappel : le backend doit tourner (docker compose up) et' -ForegroundColor DarkGray
    Write-Host '  l’adresse du serveur se regle depuis l’ecran de connexion.' -ForegroundColor DarkGray
    Write-Host ''
}
