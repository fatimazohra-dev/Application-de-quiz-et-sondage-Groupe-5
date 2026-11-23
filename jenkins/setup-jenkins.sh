#!/usr/bin/env bash
# =============================================================================
#  setup-jenkins.sh : automatise les étapes 1 et 2 du pipeline Quiz Live
#    Étape 1 : préparer la machine (docker, kubectl, git, accès de l'utilisateur jenkins)
#              + installer les plugins avec Jenkins CLI
#    Étape 2 : créer les credentials "dockerhub-creds" et "kubeconfig"
#
#  À lancer SUR LA MACHINE JENKINS (Linux / WSL), avec Java installé.
#
#  Utilisation :
#    export JENKINS_URL=http://localhost:8080
#    export JENKINS_USER=admin
#    export JENKINS_TOKEN=xxxxxxxx          # Jenkins > (votre nom) > Security > API Token
#    export DOCKERHUB_USER=monuser
#    export DOCKERHUB_TOKEN=dckr_pat_xxxx    # Docker Hub > Account settings > Personal access tokens
#    bash setup-jenkins.sh                   # tout faire
#    bash setup-jenkins.sh plugins           # seulement les plugins
#    bash setup-jenkins.sh credentials       # seulement les credentials
#    bash setup-jenkins.sh host              # seulement la préparation de la machine
#
#  Les secrets non définis sont demandés au clavier (sans affichage).
# =============================================================================
set -euo pipefail

JENKINS_URL="${JENKINS_URL:-http://localhost:8080}"
JENKINS_URL="${JENKINS_URL%/}"
JENKINS_SYSTEM_USER="${JENKINS_SYSTEM_USER:-jenkins}"   # utilisateur Linux qui fait tourner Jenkins
CLI_JAR="${CLI_JAR:-./jenkins-cli.jar}"

# Plugins nécessaires au Jenkinsfile
PLUGINS=(
  workflow-aggregator   # Pipeline (Jenkinsfile)
  git                   # checkout scm
  github                # webhook GitHub (GitHub hook trigger)
  credentials           # gestion des credentials
  credentials-binding   # withCredentials(...)
  plain-credentials     # credential de type "Secret file" (kubeconfig)
  timestamper           # options { timestamps() }
  docker-workflow       # Docker Pipeline (optionnel mais utile)
)

# ---------- utilitaires ------------------------------------------------------
info() { echo -e "\e[34m[INFO]\e[0m $*"; }
ok()   { echo -e "\e[32m[ OK ]\e[0m $*"; }
warn() { echo -e "\e[33m[WARN]\e[0m $*"; }
die()  { echo -e "\e[31m[ERREUR]\e[0m $*" >&2; exit 1; }

ask_secret() {   # ask_secret NOM_VARIABLE "Question"
  local var="$1" question="$2"
  if [ -z "${!var:-}" ]; then
    read -r -s -p "$question : " "$var"; echo
    [ -n "${!var}" ] || die "$var est vide"
  fi
}

ask_value() {    # ask_value NOM_VARIABLE "Question"
  local var="$1" question="$2"
  if [ -z "${!var:-}" ]; then
    read -r -p "$question : " "$var"
    [ -n "${!var}" ] || die "$var est vide"
  fi
}

# Échappe & < > pour l'insertion dans du XML
xml_escape() { sed -e 's/&/\&amp;/g' -e 's/</\&lt;/g' -e 's/>/\&gt;/g' <<<"$1"; }

cli() {
  # -http (et non -webSocket) : le mode WebSocket refuse la connexion quand l'URL
  # utilisée (ex. localhost:8080 dans le conteneur) diffère de l'URL racine de
  # Jenkins (ex. localhost:8082 via le tunnel) -> "Unexpected request origin"
  java -jar "$CLI_JAR" -s "$JENKINS_URL" -http -auth "$JENKINS_USER:$JENKINS_TOKEN" "$@"
}

wait_jenkins() {
  info "Attente de Jenkins sur $JENKINS_URL ..."
  for _ in $(seq 1 60); do
    code=$(curl -s -o /dev/null -w '%{http_code}' "$JENKINS_URL/login" || true)
    [ "$code" = "200" ] && { ok "Jenkins est disponible"; return 0; }
    sleep 5
  done
  die "Jenkins ne répond pas après 5 minutes"
}

# ---------- Étape 1a : préparer la machine ----------------------------------
prepare_host() {
  info "=== Étape 1a : préparation de la machine ==="
  for cmd in git docker kubectl java curl; do
    if command -v "$cmd" >/dev/null; then ok "$cmd présent"; else warn "$cmd ABSENT : installez-le"; fi
  done

  if ! docker compose version >/dev/null 2>&1; then
    warn "docker compose (v2) introuvable : installez le plugin docker-compose-plugin"
  fi

  if id "$JENKINS_SYSTEM_USER" >/dev/null 2>&1; then
    # L'utilisateur jenkins doit pouvoir utiliser Docker
    if id -nG "$JENKINS_SYSTEM_USER" | grep -qw docker; then
      ok "$JENKINS_SYSTEM_USER est déjà dans le groupe docker"
    else
      info "Ajout de $JENKINS_SYSTEM_USER au groupe docker (sudo)"
      sudo usermod -aG docker "$JENKINS_SYSTEM_USER"
      warn "Redémarrage du service Jenkins pour appliquer le groupe"
      sudo systemctl restart jenkins || warn "Redémarrez Jenkins manuellement"
      wait_jenkins
    fi
    sudo -u "$JENKINS_SYSTEM_USER" docker ps >/dev/null 2>&1 \
      && ok "$JENKINS_SYSTEM_USER peut utiliser Docker" \
      || warn "$JENKINS_SYSTEM_USER ne peut pas encore utiliser Docker"
  else
    warn "Utilisateur système '$JENKINS_SYSTEM_USER' introuvable (Jenkins dans Docker ?), étape ignorée"
  fi

  kubectl get nodes >/dev/null 2>&1 \
    && ok "kubectl accède au cluster" \
    || warn "kubectl n'accède pas au cluster (minikube start ?)"
}

# ---------- Jenkins CLI ------------------------------------------------------
get_cli() {
  ask_value  JENKINS_USER  "Utilisateur admin Jenkins"
  ask_secret JENKINS_TOKEN "API Token Jenkins"
  command -v java >/dev/null || die "Java est requis pour jenkins-cli.jar"
  wait_jenkins
  if [ ! -s "$CLI_JAR" ]; then
    info "Téléchargement de jenkins-cli.jar depuis $JENKINS_URL"
    curl -fsSL "$JENKINS_URL/jnlpJars/jenkins-cli.jar" -o "$CLI_JAR"
  fi
  cli who-am-i | grep -q "Authenticated as: $JENKINS_USER" \
    || die "Authentification CLI échouée (vérifiez JENKINS_USER / JENKINS_TOKEN)"
  ok "Jenkins CLI authentifié en tant que $JENKINS_USER"
}

# ---------- Étape 1b : plugins ----------------------------------------------
install_plugins() {
  info "=== Étape 1b : installation des plugins ==="
  local installed missing=()
  installed=$(cli list-plugins | awk '{print $1}')
  for p in "${PLUGINS[@]}"; do
    if grep -qx "$p" <<<"$installed"; then ok "plugin $p déjà installé"; else missing+=("$p"); fi
  done
  if [ ${#missing[@]} -eq 0 ]; then
    ok "Tous les plugins sont déjà installés"
    return
  fi
  info "Installation : ${missing[*]}"
  cli install-plugin "${missing[@]}" -deploy
  info "Redémarrage sécurisé de Jenkins"
  cli safe-restart || true
  sleep 10
  wait_jenkins
  ok "Plugins installés"
}

# ---------- Étape 2 : credentials -------------------------------------------
# upsert_credential ID < xml  : crée la credential, ou la met à jour si elle existe
upsert_credential() {
  local id="$1" xml
  xml=$(cat)
  if cli get-credentials-as-xml system::system::jenkins _ "$id" >/dev/null 2>&1; then
    printf '%s' "$xml" | cli update-credentials-by-xml system::system::jenkins _ "$id"
    ok "credential '$id' mise à jour"
  else
    printf '%s' "$xml" | cli create-credentials-by-xml system::system::jenkins _
    ok "credential '$id' créée"
  fi
}

create_credentials() {
  info "=== Étape 2 : credentials ==="

  # 2a. Docker Hub (Username with password)
  ask_value  DOCKERHUB_USER  "Utilisateur Docker Hub"
  ask_secret DOCKERHUB_TOKEN "Access token Docker Hub"
  upsert_credential dockerhub-creds <<EOF
<com.cloudbees.plugins.credentials.impl.UsernamePasswordCredentialsImpl>
  <scope>GLOBAL</scope>
  <id>dockerhub-creds</id>
  <description>Docker Hub - push des images quiz-live</description>
  <username>$(xml_escape "$DOCKERHUB_USER")</username>
  <password>$(xml_escape "$DOCKERHUB_TOKEN")</password>
</com.cloudbees.plugins.credentials.impl.UsernamePasswordCredentialsImpl>
EOF

  # 2b. kubeconfig (Secret file)
  # --flatten : intègre les certificats dans le fichier (Minikube pointe sinon
  # vers des fichiers .crt locaux que Jenkins ne pourrait pas lire)
  local kubeconfig_b64
  if [ -n "${KUBECONFIG_FILE:-}" ]; then
    [ -f "$KUBECONFIG_FILE" ] || die "Fichier introuvable : $KUBECONFIG_FILE"
    kubeconfig_b64=$(base64 -w0 "$KUBECONFIG_FILE")
  else
    command -v kubectl >/dev/null || die "kubectl requis (ou définissez KUBECONFIG_FILE)"
    kubeconfig_b64=$(kubectl config view --raw --flatten --minify | base64 -w0)
  fi
  [ -n "$kubeconfig_b64" ] || die "kubeconfig vide"

  upsert_credential kubeconfig <<EOF
<org.jenkinsci.plugins.plaincredentials.impl.FileCredentialsImpl>
  <scope>GLOBAL</scope>
  <id>kubeconfig</id>
  <description>Accès au cluster Kubernetes (Minikube)</description>
  <fileName>kubeconfig</fileName>
  <secretBytes>$kubeconfig_b64</secretBytes>
</org.jenkinsci.plugins.plaincredentials.impl.FileCredentialsImpl>
EOF

  info "Credentials présentes :"
  cli list-credentials system::system::jenkins | grep -E 'dockerhub-creds|kubeconfig' || true
}

# ---------- main -------------------------------------------------------------
case "${1:-all}" in
  host)        prepare_host ;;
  plugins)     get_cli; install_plugins ;;
  credentials) get_cli; create_credentials ;;
  all)         prepare_host; get_cli; install_plugins; create_credentials ;;
  *)           die "Usage : $0 [all|host|plugins|credentials]" ;;
esac

ok "Terminé."
