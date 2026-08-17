# Demarre la pile Ordimed sans Docker.
#
#   .\demarrer-pile.ps1          # lance MongoDB puis le backend
#   .\demarrer-pile.ps1 -Arreter # les arrete
#   .\demarrer-pile.ps1 -Etat    # dit ce qui tourne
#
# Pourquoi pas Docker : Docker Desktop exige des droits administrateur, WSL2
# ou Hyper-V, et la virtualisation materielle activee dans le BIOS. Aucun des
# trois n'est disponible sur ce poste. Or Docker n'etait qu'un moyen de lancer
# mongod et node : on les lance directement.
#
# Le mongod utilise est celui que mongodb-memory-server a telecharge pour les
# tests. C'est un binaire officiel MongoDB 8.2.6, pas un substitut.
#
# Difference avec docker-compose : les donnees vont dans D:\ordimed_data\db au
# lieu d'un volume Docker, et rien ne redemarre tout seul apres un
# redemarrage de Windows. Pour un vrai cabinet, il faudra des services
# Windows ; pour eprouver le code, ceci suffit.

param(
    [switch]$Arreter,
    [switch]$Etat
)

$Mongod = 'D:\ordimed\backend\node_modules\.cache\mongodb-memory-server\mongod-x64-win32-8.2.6.exe'
$Donnees = 'D:\ordimed_data\db'
$Journaux = 'D:\ordimed_data\log'
$Backend = 'D:\ordimed\backend'

function Tourne($nom) { [bool](Get-Process -Name $nom -ErrorAction SilentlyContinue) }

function AfficherEtat {
    Write-Host ''
    Write-Host "  MongoDB : $(if (Tourne 'mongod-x64-win32-8.2.6') { 'en marche' } else { 'arrete' })"
    try {
        $r = Invoke-RestMethod -Uri 'http://localhost:4000/health' -TimeoutSec 3
        Write-Host "  Backend : en marche (mongo : $($r.mongo))"
    } catch {
        Write-Host '  Backend : arrete'
    }
    Write-Host ''
}

if ($Etat) { AfficherEtat; exit 0 }

if ($Arreter) {
    Write-Host ''
    Write-Host '  Arret...' -ForegroundColor Cyan
    # Le backend d'abord : il tient une connexion a la base.
    Get-Process -Name node -ErrorAction SilentlyContinue |
        Where-Object { $_.Path -and $_.Path -notlike '*flutter*' } |
        Stop-Process -Force -ErrorAction SilentlyContinue
    Get-Process -Name 'mongod*' -ErrorAction SilentlyContinue | Stop-Process -Force
    Start-Sleep -Seconds 2
    AfficherEtat
    exit 0
}

if (-not (Test-Path $Mongod)) {
    Write-Host ''
    Write-Host '  mongod introuvable. Depuis backend\ : npm install' -ForegroundColor Red
    Write-Host '  (mongodb-memory-server le telecharge a l installation)' -ForegroundColor DarkGray
    Write-Host ''
    exit 1
}

New-Item -ItemType Directory -Force $Donnees | Out-Null
New-Item -ItemType Directory -Force $Journaux | Out-Null

# ---- MongoDB ----
if (Tourne 'mongod-x64-win32-8.2.6') {
    Write-Host '  MongoDB tourne deja.'
} else {
    Write-Host '  Demarrage de MongoDB...' -ForegroundColor Cyan
    # --replSet : sans replica set, MongoDB refuse les transactions, et l app
    # en fait 21. L echec surviendrait a l execution, a moitie ecrit.
    # --bind_ip 127.0.0.1 : la base tourne sans authentification, elle ne doit
    # pas etre joignable depuis le reseau du cabinet.
    Start-Process -FilePath $Mongod -WindowStyle Hidden -ArgumentList @(
        '--replSet', 'rs0',
        '--dbpath', $Donnees,
        '--port', '27017',
        '--bind_ip', '127.0.0.1',
        '--logpath', "$Journaux\mongod.log",
        '--logappend'
    )
    Start-Sleep -Seconds 6
    if (-not (Tourne 'mongod-x64-win32-8.2.6')) {
        Write-Host "  MongoDB n a pas demarre. Voir $Journaux\mongod.log" -ForegroundColor Red
        exit 1
    }
}

# ---- Replica set ----
Write-Host '  Verification du replica set...'
Push-Location $Backend
try {
    $init = @'
const { MongoClient } = require('mongodb');
(async () => {
  const c = new MongoClient('mongodb://127.0.0.1:27017/?directConnection=true');
  await c.connect();
  const a = c.db('admin');
  try {
    const s = await a.command({ replSetGetStatus: 1 });
    console.log('  replica set : ' + s.members[0].stateStr);
  } catch (e) {
    // Un rs.initiate sur un set deja initie leve une erreur : ce n est pas
    // un echec, c est la reponse.
    await a.command({ replSetInitiate: { _id: 'rs0', members: [{ _id: 0, host: '127.0.0.1:27017' }] } });
    for (let i = 0; i < 20; i++) {
      await new Promise((r) => setTimeout(r, 500));
      const s = await a.command({ replSetGetStatus: 1 });
      if (s.members[0].stateStr === 'PRIMARY') { console.log('  replica set : PRIMARY (initie)'); break; }
    }
  }
  await c.close();
})().catch((e) => { console.error('  echec replica set : ' + e.message); process.exit(1); });
'@
    Set-Content -Path "$Backend\.rs-init.js" -Value $init -Encoding utf8
    node "$Backend\.rs-init.js"
    $codeRs = $LASTEXITCODE
    Remove-Item "$Backend\.rs-init.js" -ErrorAction SilentlyContinue
    if ($codeRs -ne 0) { exit 1 }
} finally { Pop-Location }

# ---- Backend ----
try {
    Invoke-RestMethod -Uri 'http://localhost:4000/health' -TimeoutSec 3 | Out-Null
    Write-Host '  Backend tourne deja.'
} catch {
    Write-Host '  Demarrage du backend...' -ForegroundColor Cyan

    # Le secret est tire une fois et conserve : le regenerer a chaque
    # demarrage invaliderait les sessions ouvertes sur chaque poste.
    $fichierSecret = 'D:\ordimed_data\jwt-secret.txt'
    if (-not (Test-Path $fichierSecret)) {
        $octets = New-Object byte[] 32
        [Security.Cryptography.RandomNumberGenerator]::Create().GetBytes($octets)
        Set-Content -Path $fichierSecret -Value ([Convert]::ToBase64String($octets)) -Encoding ascii
    }
    $env:JWT_SECRET = (Get-Content $fichierSecret -Raw).Trim()
    $env:MONGO_URL = 'mongodb://127.0.0.1:27017/ordimed?replicaSet=rs0&w=majority&journal=true'
    $env:PORT = '4000'

    Start-Process -FilePath 'node' -WindowStyle Hidden -WorkingDirectory $Backend `
        -ArgumentList 'server.js' `
        -RedirectStandardOutput "$Journaux\backend.log" `
        -RedirectStandardError "$Journaux\backend-erreurs.log"
    Start-Sleep -Seconds 5
}

AfficherEtat
Write-Host '  L app se regle sur http://localhost:4000 depuis son ecran de connexion.' -ForegroundColor DarkGray
Write-Host ''
