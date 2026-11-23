#!/usr/bin/env bash
# Lance toute la stack Quiz Live sur ce PC (Mac / Linux, Docker Desktop ou Docker Engine).
#   bash local/start.sh
# Prérequis : Docker démarré + jenkins-home.tar.gz copié dans le dossier local/
set -euo pipefail
cd "$(dirname "$0")"

docker info >/dev/null 2>&1 || { echo "Docker n'est pas démarré."; exit 1; }

VOL=quiz-live-jenkins-data
if ! docker volume inspect "$VOL" >/dev/null 2>&1; then
  [ -f jenkins-home.tar.gz ] || { echo "jenkins-home.tar.gz manquant dans $(pwd) (demandez-le à Anass)."; exit 1; }
  echo "==> Restauration de l'état Jenkins (première fois)"
  docker volume create "$VOL" >/dev/null
  docker run --rm -v "$VOL:/data" -v "$(pwd):/backup" alpine:3.20 tar xzf /backup/jenkins-home.tar.gz -C /data \
    || { docker volume rm "$VOL" >/dev/null; echo "Échec de la restauration"; exit 1; }
else
  echo "==> État Jenkins déjà présent (volume $VOL)"
fi

echo "==> Démarrage de k3s + Jenkins (la 1re fois : ~5-10 min)"
docker compose up -d --build

echo "==> Déploiement de l'application dans le cluster"
docker compose logs -f deploy
if [ "$(docker inspect -f '{{.State.ExitCode}}' quiz-live-local-deploy-1)" != "0" ]; then
  echo "Le déploiement initial a échoué. Relancez : docker compose -f local/docker-compose.yml up deploy"
  exit 1
fi

echo "==> Attente de Jenkins"
until curl -fs -o /dev/null http://localhost:8082/login 2>/dev/null; do sleep 3; done

echo
echo "Jenkins     : http://localhost:8082"
echo "Application : http://localhost:30080"
echo "Arrêter     : docker compose -f local/docker-compose.yml stop"
