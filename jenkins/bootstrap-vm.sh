#!/usr/bin/env bash
# =============================================================================
#  bootstrap-vm.sh : installe tout l'environnement Quiz Live sur une VM Ubuntu
#    1. Docker Engine + docker compose
#    2. kubectl + Minikube (driver docker)
#    3. Cluster Minikube (+ addon ingress)
#    4. Image et conteneur Jenkins dédiés (port 8082), branchés sur le réseau minikube
#    5. kubeconfig pour Jenkins
#
#  À lancer avec votre utilisateur normal (PAS root), qui doit avoir sudo :
#    git clone -b ci/jenkins-pipeline https://github.com/fatimazohra-dev/Application-de-quiz-et-sondage-Groupe-5
#    bash Application-de-quiz-et-sondage-Groupe-5/jenkins/bootstrap-vm.sh
#
#  Le script peut être relancé : ce qui est déjà installé est ignoré.
# =============================================================================
set -euo pipefail

MINIKUBE_CPUS="${MINIKUBE_CPUS:-2}"
MINIKUBE_MEMORY="${MINIKUBE_MEMORY:-4g}"
JENKINS_PORT="${JENKINS_PORT:-8082}"
JENKINS_NAME="jenkins-quiz"
JENKINS_VOLUME="jenkins-quiz-data"

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
KUBECONFIG_JENKINS="$HOME/kubeconfig-jenkins"

info() { echo -e "\n\e[34m==> $*\e[0m"; }
ok()   { echo -e "\e[32m[ OK ]\e[0m $*"; }
warn() { echo -e "\e[33m[WARN]\e[0m $*"; }
die()  { echo -e "\e[31m[ERREUR]\e[0m $*" >&2; exit 1; }

# Docker via sudo : le groupe "docker" n'est actif qu'après une reconnexion
dk() { sudo docker "$@"; }
# Minikube refuse root : on le lance en tant qu'utilisateur, avec le groupe docker
mk() { sg docker -c "minikube $*"; }

[ "$(id -u)" -ne 0 ] || die "Ne lancez pas ce script en root (Minikube le refuse). Utilisez votre utilisateur normal."
command -v sudo >/dev/null || die "sudo est requis"
[ -f "$REPO_DIR/jenkins/Dockerfile" ] || die "jenkins/Dockerfile introuvable dans $REPO_DIR (bonne branche ?)"

# ---------------------------------------------------------------------------
info "1/6 Paquets de base"
sudo apt-get update -y
sudo apt-get install -y ca-certificates curl gnupg git conntrack

# ---------------------------------------------------------------------------
info "2/6 Docker Engine"
if command -v docker >/dev/null && docker compose version >/dev/null 2>&1; then
  ok "Docker déjà installé : $(docker --version)"
else
  sudo install -m 0755 -d /etc/apt/keyrings
  sudo curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
  sudo chmod a+r /etc/apt/keyrings/docker.asc
  echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu $(. /etc/os-release && echo "$VERSION_CODENAME") stable" \
    | sudo tee /etc/apt/sources.list.d/docker.list >/dev/null
  sudo apt-get update -y
  sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
  sudo systemctl enable --now docker
  ok "Docker installé : $(docker --version)"
fi
if id -nG "$USER" | grep -qw docker; then
  ok "$USER est dans le groupe docker"
else
  sudo usermod -aG docker "$USER"
  ok "$USER ajouté au groupe docker (actif à la prochaine connexion SSH)"
fi

# ---------------------------------------------------------------------------
info "3/6 kubectl et Minikube"
if command -v kubectl >/dev/null; then
  ok "kubectl déjà installé"
else
  KVER="$(curl -fsSL https://dl.k8s.io/release/stable.txt)"
  curl -fsSLo /tmp/kubectl "https://dl.k8s.io/release/${KVER}/bin/linux/amd64/kubectl"
  sudo install -m 0755 /tmp/kubectl /usr/local/bin/kubectl && rm -f /tmp/kubectl
  ok "kubectl ${KVER} installé"
fi
if command -v minikube >/dev/null; then
  ok "minikube déjà installé"
else
  curl -fsSLo /tmp/minikube https://storage.googleapis.com/minikube/releases/latest/minikube-linux-amd64
  sudo install -m 0755 /tmp/minikube /usr/local/bin/minikube && rm -f /tmp/minikube
  ok "minikube installé : $(minikube version --short)"
fi

# ---------------------------------------------------------------------------
info "4/6 Cluster Minikube (driver docker, ${MINIKUBE_CPUS} CPU, ${MINIKUBE_MEMORY})"
if mk status >/dev/null 2>&1; then
  ok "Minikube déjà démarré"
else
  mk start --driver=docker --cpus="$MINIKUBE_CPUS" --memory="$MINIKUBE_MEMORY"
fi
mk addons enable ingress >/dev/null && ok "addon ingress activé"
# Redémarrage automatique du cluster au boot de la VM (le conteneur minikube n'a pas de restart policy)
sudo tee /etc/systemd/system/minikube.service >/dev/null <<UNIT
[Unit]
Description=Minikube (cluster Quiz Live)
After=docker.service network-online.target
Requires=docker.service

[Service]
Type=oneshot
RemainAfterExit=yes
User=$USER
ExecStart=/usr/local/bin/minikube start
ExecStop=/usr/local/bin/minikube stop
TimeoutStartSec=600

[Install]
WantedBy=multi-user.target
UNIT
sudo systemctl daemon-reload
sudo systemctl enable minikube.service >/dev/null 2>&1 && ok "Minikube démarrera au boot de la VM"
kubectl get nodes
MINIKUBE_IP="$(mk ip)"
ok "API Kubernetes : https://${MINIKUBE_IP}:8443"

# ---------------------------------------------------------------------------
info "5/6 Jenkins dédié (${JENKINS_NAME}, port ${JENKINS_PORT})"
dk build -t jenkins-quiz "$REPO_DIR/jenkins"
if dk ps -a --format '{{.Names}}' | grep -qx "$JENKINS_NAME"; then
  ok "Conteneur $JENKINS_NAME existe déjà"
  dk start "$JENKINS_NAME" >/dev/null
else
  dk run -d --name "$JENKINS_NAME" \
    -p "${JENKINS_PORT}:8080" \
    -v "${JENKINS_VOLUME}:/var/jenkins_home" \
    -v /var/run/docker.sock:/var/run/docker.sock \
    --restart unless-stopped \
    jenkins-quiz >/dev/null
  ok "Conteneur $JENKINS_NAME lancé"
fi
# Réseau minikube : Jenkins peut joindre l'API du cluster
if dk inspect "$JENKINS_NAME" --format '{{json .NetworkSettings.Networks}}' | grep -q '"minikube"'; then
  ok "$JENKINS_NAME déjà sur le réseau minikube"
else
  dk network connect minikube "$JENKINS_NAME"
  ok "$JENKINS_NAME branché sur le réseau minikube"
fi

# ---------------------------------------------------------------------------
info "6/6 kubeconfig pour Jenkins"
# --flatten : certificats inclus ; serveur = IP interne de minikube (joignable depuis Jenkins)
kubectl config view --raw --flatten --minify --context minikube \
  | sed "s#server: https://.*#server: https://${MINIKUBE_IP}:8443#" > "$KUBECONFIG_JENKINS"
chmod 600 "$KUBECONFIG_JENKINS"
dk cp "$KUBECONFIG_JENKINS" "$JENKINS_NAME:/tmp/kubeconfig-jenkins"
dk cp "$REPO_DIR/jenkins/setup-jenkins.sh" "$JENKINS_NAME:/tmp/setup-jenkins.sh"
if dk exec "$JENKINS_NAME" kubectl --kubeconfig /tmp/kubeconfig-jenkins get nodes >/dev/null; then
  ok "Jenkins accède au cluster Minikube"
else
  warn "Jenkins n'accède pas au cluster : vérifiez le réseau minikube"
fi

# ---------------------------------------------------------------------------
info "Attente du mot de passe initial de Jenkins"
PASS=""
for _ in $(seq 1 60); do
  PASS="$(dk exec "$JENKINS_NAME" cat /var/jenkins_home/secrets/initialAdminPassword 2>/dev/null || true)"
  [ -n "$PASS" ] && break
  sleep 3
done

cat <<EOF

=============================================================================
 Installation terminée
=============================================================================
 Jenkins : port ${JENKINS_PORT} de la VM
   Depuis votre PC (tunnel SSH, recommandé) :
     ssh -L ${JENKINS_PORT}:localhost:${JENKINS_PORT} quiz-vm      (alias défini dans ~/.ssh/config)
     ou, dans PowerShell : gcloud compute ssh quiz-vm --zone=europe-west1-b '--' -L ${JENKINS_PORT}:localhost:${JENKINS_PORT}
     puis ouvrez http://localhost:${JENKINS_PORT}

 Mot de passe initial : ${PASS:-"(pas encore prêt : sudo docker exec ${JENKINS_NAME} cat /var/jenkins_home/secrets/initialAdminPassword)"}
   (si l'assistant n'apparaît pas, Jenkins était déjà configuré)

 Étapes suivantes :
   1. Assistant Jenkins : "Install suggested plugins", créer le compte admin
   2. Créer un API Token Jenkins + un token Docker Hub
   3. Credentials :
      sudo docker exec -it -e JENKINS_URL=http://localhost:8080 -e JENKINS_USER=admin \\
        -e DOCKERHUB_USER=votre_user -e KUBECONFIG_FILE=/tmp/kubeconfig-jenkins \\
        ${JENKINS_NAME} bash /tmp/setup-jenkins.sh credentials
   4. Créer le job Pipeline (SCM Git, branche ci/jenkins-pipeline, Jenkinsfile)

 Déconnectez-vous puis reconnectez-vous en SSH pour utiliser "docker" sans sudo.
=============================================================================
EOF
