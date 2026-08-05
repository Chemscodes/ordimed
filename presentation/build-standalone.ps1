# =============================================================
#  Genere index.html (version autonome, hebergeable) a partir de
#  ordimed.html (version artifact, sans enveloppe HTML).
#
#  Usage :  .\build-standalone.ps1
#  A relancer apres chaque modification de ordimed.html.
# =============================================================

$src = Join-Path $PSScriptRoot 'ordimed.html'
$out = Join-Path $PSScriptRoot 'index.html'

if (-not (Test-Path $src)) {
    Write-Error "Fichier source introuvable : $src"
    exit 1
}

$body = Get-Content $src -Raw -Encoding UTF8

# Le <title> vit dans la source (l'artifact le lit la-bas). On l'extrait
# pour le replacer dans le <head>, ou il a sa place dans un vrai document.
$title = 'Ordimed - Logiciel de cabinet medical'
$m = [regex]::Match($body, '<title>(.*?)</title>', 'Singleline')
if ($m.Success) {
    $title = $m.Groups[1].Value.Trim()
    $body = $body.Remove($m.Index, $m.Length).TrimStart()
}

$head = @"
<!doctype html>
<html lang="fr">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>$title</title>
<meta name="description" content="Ordimed : logiciel de gestion de cabinet medical pour Windows. De l'accueil du patient a l'ordonnance imprimee. Concu et developpe par Zaouali Chems Eddine.">
<meta name="author" content="Zaouali Chems Eddine">
<meta name="theme-color" content="#04100E">

<link rel="canonical" href="https://ordimedev.netlify.app/">

<!-- Apercu lors du partage (LinkedIn, Facebook, WhatsApp, X). -->
<meta property="og:type" content="website">
<meta property="og:locale" content="fr_FR">
<meta property="og:site_name" content="Ordimed">
<meta property="og:title" content="$title">
<meta property="og:description" content="De l'accueil du patient a l'ordonnance imprimee : salle d'attente en temps reel, seances, reglements et caisse du jour.">
<meta property="og:url" content="https://ordimedev.netlify.app/">
<meta name="twitter:card" content="summary_large_image">

<!-- Vignette de partage : decommenter une fois apercu.jpg (1200x630)
     depose dans ce dossier et le site redeploye. -->
<!-- <meta property="og:image" content="https://ordimedev.netlify.app/apercu.jpg"> -->
<!-- <meta property="og:image:width" content="1200"> -->
<!-- <meta property="og:image:height" content="630"> -->

<link rel="icon" href="data:image/svg+xml,<svg xmlns='http://www.w3.org/2000/svg' viewBox='0 0 100 100'><text y='.9em' font-size='90'>%F0%9F%A9%BA</text></svg>">

<style>
  /* Reset minimal : l'artifact en fournit un, un document autonome non. */
  *, *::before, *::after { box-sizing: border-box; }
  body { margin: 0; }
  img, video { max-width: 100%; }
</style>
</head>
<body>
"@

$foot = "`n</body>`n</html>`n"

# UTF-8 sans BOM : certains serveurs statiques servent le BOM tel quel.
$utf8NoBom = New-Object System.Text.UTF8Encoding $false
[System.IO.File]::WriteAllText($out, $head + $body + $foot, $utf8NoBom)

$kb = [math]::Round((Get-Item $out).Length / 1KB, 1)
Write-Host "index.html genere ($kb Ko)" -ForegroundColor Green
