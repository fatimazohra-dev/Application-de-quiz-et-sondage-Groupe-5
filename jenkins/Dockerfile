# Image Jenkins dédiée au projet Quiz Live
#   - client Docker + docker compose v2 (le daemon est celui de l'hôte via docker.sock)
#   - kubectl (déploiement sur Minikube)
#   - plugins du Jenkinsfile préinstallés
# Construction : docker build -t jenkins-quiz jenkins/
FROM jenkins/jenkins:lts

USER root
RUN apt-get update && apt-get install -y ca-certificates curl gnupg \
 && install -m 0755 -d /etc/apt/keyrings \
 && curl -fsSL https://download.docker.com/linux/debian/gpg -o /etc/apt/keyrings/docker.asc \
 && echo "deb [signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/debian $(. /etc/os-release && echo $VERSION_CODENAME) stable" \
      > /etc/apt/sources.list.d/docker.list \
 && apt-get update && apt-get install -y docker-ce-cli docker-compose-plugin \
 && rm -rf /var/lib/apt/lists/*

RUN curl -fsSL -o /usr/local/bin/kubectl \
      "https://dl.k8s.io/release/$(curl -fsSL https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl" \
 && chmod +x /usr/local/bin/kubectl

# Plugins nécessaires au Jenkinsfile (+ ceux de l'assistant "suggested plugins" utiles ici)
RUN jenkins-plugin-cli --plugins \
      workflow-aggregator git github credentials credentials-binding \
      plain-credentials timestamper docker-workflow

# root : accès au socket Docker de l'hôte sans gestion de groupe
USER root
