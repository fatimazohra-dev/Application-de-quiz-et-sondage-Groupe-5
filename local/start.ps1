# Lance toute la stack Quiz Live sur ce PC (Windows, Docker Desktop).
#   powershell -ExecutionPolicy Bypass -File local\start.ps1
# Prérequis : Docker Desktop démarré + jenkins-home.tar.gz copié dans le dossier local\
Set-Location $PSScriptRoot

docker info *> $null
if ($LASTEXITCODE -ne 0) { Write-Host "Docker Desktop n'est pas demarre." -ForegroundColor Red; exit 1 }

$vol = "quiz-live-jenkins-data"
docker volume inspect $vol *> $null
if ($LASTEXITCODE -ne 0) {
    if (-not (Test-Path "jenkins-home.tar.gz")) {
        Write-Host "jenkins-home.tar.gz manquant dans $PSScriptRoot (demandez-le a Anass)." -ForegroundColor Red
        exit 1
    }
    Write-Host "==> Restauration de l'etat Jenkins (premiere fois)" -ForegroundColor Cyan
    docker volume create $vol | Out-Null
    docker run --rm -v "${vol}:/data" -v "${PSScriptRoot}:/backup" alpine:3.20 tar xzf /backup/jenkins-home.tar.gz -C /data
    if ($LASTEXITCODE -ne 0) { Write-Host "Echec de la restauration" -ForegroundColor Red; docker volume rm $vol | Out-Null; exit 1 }
} else {
    Write-Host "==> Etat Jenkins deja present (volume $vol)" -ForegroundColor Green
}

Write-Host "==> Demarrage de k3s + Jenkins (la 1re fois : ~5-10 min)" -ForegroundColor Cyan
docker compose up -d --build
if ($LASTEXITCODE -ne 0) { exit 1 }

Write-Host "==> Deploiement de l'application dans le cluster" -ForegroundColor Cyan
docker compose logs -f deploy
$code = docker inspect -f "{{.State.ExitCode}}" quiz-live-local-deploy-1
if ($code -ne "0") {
    Write-Host "Le deploiement initial a echoue. Relancez : docker compose -f local\docker-compose.yml up deploy" -ForegroundColor Red
    exit 1
}

Write-Host "==> Attente de Jenkins" -ForegroundColor Cyan
do {
    Start-Sleep -Seconds 3
    try { $ok = (Invoke-WebRequest -UseBasicParsing -Uri "http://localhost:8082/login" -TimeoutSec 5).StatusCode -eq 200 } catch { $ok = $false }
} until ($ok)

Write-Host ""
Write-Host "Jenkins     : http://localhost:8082" -ForegroundColor Green
Write-Host "Application : http://localhost:30080" -ForegroundColor Green
Write-Host "Arreter     : docker compose -f local\docker-compose.yml stop"
