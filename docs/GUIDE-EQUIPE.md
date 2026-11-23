# Guide de l'équipe : travailler sur Quiz Live

Tout l'environnement (Jenkins + cluster Minikube) tourne **déjà** sur une VM Google Cloud
partagée. Vous n'avez **rien à installer côté serveur** : vous vous connectez depuis votre PC
par un tunnel SSH, et tout le monde voit le même Jenkins et le même cluster.

```
 Votre PC ──(tunnel SSH)──► VM quiz-vm (Google Cloud, projet quiz-live-g5-2026)
                             ├── Jenkins (port 8082)  ── job quiz-live
                             └── Minikube ── 3 Pods quiz-live + Redis
 GitHub (push) ──(vérifié toutes les 2 min)──► Jenkins ──► Docker Hub ──► Minikube
```

---

## 1. Une seule fois : préparer votre PC (≈ 10 min)

1. Installer **Git** et le **Google Cloud SDK** (gcloud) :
   https://cloud.google.com/sdk/docs/install
2. Envoyer à Anass l'**adresse Gmail** de votre compte Google : il vous donne l'accès au projet.
3. Une fois l'accès donné :
   ```bash
   gcloud auth login
   gcloud config set project quiz-live-g5-2026
   gcloud config set compute/zone europe-west1-b
   ```
4. Cloner le dépôt :
   ```bash
   git clone https://github.com/fatimazohra-dev/Application-de-quiz-et-sondage-Groupe-5
   ```
5. Demander à Anass votre **compte Jenkins** (identifiant + mot de passe personnel).

---

## 2. Chaque séance de travail : ouvrir le tunnel

Dans un terminal (PowerShell, Terminal Mac/Linux) — **gardez-le ouvert** :

```bash
gcloud compute ssh quiz-vm '--' -L 8082:localhost:8082 -L 3000:192.168.49.2:31829
```

| Dans votre navigateur | Ce que c'est |
|---|---|
| http://localhost:8082 | Jenkins (job `quiz-live`, builds, logs) |
| http://localhost:3000 | L'application Quiz Live déployée sur Kubernetes |

- `'--'` entre guillemets : obligatoire dans PowerShell (sinon PowerShell le supprime).
- La première connexion crée une clé SSH : répondez `y` à la question *Store key in cache?*.
- Si l'application ne répond pas sur 3000, le port NodePort a peut-être changé :
  `kubectl get svc quiz-live` (sur la VM) et remplacez `31829`.

**La VM est arrêtée ?** (`gcloud compute instances list` → `TERMINATED`)
```bash
gcloud compute instances start quiz-vm
```
Jenkins et Minikube redémarrent tout seuls (≈ 2 min). Prévenez le groupe avant de l'arrêter.

---

## 3. Travailler sur le code (le pipeline fait le reste)

```bash
git checkout ci/jenkins-pipeline      # ou main, une fois la branche fusionnée
git pull
# ... modifier le code ...
git add -A
git commit -m "Ma modification"
git push
```

Dans les **2 minutes**, Jenkins détecte le commit et lance automatiquement :
Checkout → Build image → Tests → Push Docker Hub → Deploy Kubernetes → Smoke test.
Suivez-le sur http://localhost:8082/job/quiz-live/. Si les tests échouent, rien n'est déployé.

---

## 4. Tester en local AVANT de pousser (facultatif, Docker Desktop)

Pas besoin de la VM pour développer :
```bash
docker compose up --build          # application sur http://localhost:3000
```
(fermez le tunnel ou changez son port 3000 si vous faites les deux en même temps)

Lancer les tests (Node.js 20+ installé, application démarrée) :
```bash
npm test
```

---

## 5. Commandes utiles sur la VM

```bash
gcloud compute ssh quiz-vm
sudo -iu pc                        # passer sur l'utilisateur qui gère le cluster
kubectl get pods -l app=quiz-live -o wide      # les 3 réplicas
kubectl logs -l app=quiz-live --prefix -f      # logs de tous les Pods (démo affinité)
kubectl get pods -l app=quiz-live -w           # suivre un rolling update
sudo docker logs -f jenkins-quiz               # logs de Jenkins
```

---

## 6. Règles du groupe

- Ne **supprimez** jamais la VM, les conteneurs `minikube` / `jenkins-quiz` ou le volume
  `jenkins-quiz-data`.
- Ne partagez **aucun token** (Docker Hub, Jenkins) dans le code, les commits ou les messages.
- Chacun utilise **son propre compte Jenkins** (pas `admin`).
- Arrêter la VM (`gcloud compute instances stop quiz-vm`) seulement si tout le monde a fini :
  elle coûte des crédits quand elle tourne.

---

## 7. Fichiers du pipeline (référence)

| Fichier | Rôle |
|---|---|
| `Jenkinsfile` | Les étapes du pipeline CI/CD |
| `test/api.test.js` | Tests d'intégration (`npm test`) |
| `docker-compose.ci.yml` | Stack de test isolée utilisée par Jenkins |
| `jenkins/Dockerfile` | Image Jenkins (Docker, compose, kubectl, plugins) |
| `jenkins/bootstrap-vm.sh` | Recrée toute la VM depuis zéro (si besoin) |
| `jenkins/setup-jenkins.sh` | Crée les credentials Jenkins via Jenkins CLI |
