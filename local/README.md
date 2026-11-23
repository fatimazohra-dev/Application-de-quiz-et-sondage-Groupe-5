# Quiz Live en local : même état, zéro configuration

Tout l'environnement tourne dans des conteneurs sur **votre PC**, sans VM :

| Conteneur | Rôle |
|---|---|
| `k3s` | Cluster Kubernetes 1.37 (remplace Minikube) |
| `jenkins` | **Le même Jenkins** que celui d'Anass : job `quiz-live`, historique des builds, comptes, credentials Docker Hub, plugins |
| `deploy` | Au premier démarrage, remet l'application (Redis + 3 réplicas) dans le cluster, puis s'arrête |

La credential `kubeconfig` de Jenkins est reconfigurée **automatiquement** vers le cluster local
à chaque démarrage (`init.groovy.d/kubeconfig-credential.groovy`).

## Démarrer (3 étapes)

1. Installer **Docker Desktop** et **Git**, démarrer Docker Desktop
   (Paramètres → Resources : au moins **4 Go de RAM**).
2. Cloner le dépôt, puis copier dans le dossier `local/` le fichier **`jenkins-home.tar.gz`**
   reçu d'Anass (partagé en privé : il contient les credentials).
   ```bash
   git clone -b ci/jenkins-pipeline https://github.com/fatimazohra-dev/Application-de-quiz-et-sondage-Groupe-5
   ```
3. Lancer :
   - Windows (PowerShell) :
     ```bash
     powershell -ExecutionPolicy Bypass -File local\start.ps1
     ```
   - Mac / Linux :
     ```bash
     bash local/start.sh
     ```

Première fois : 5 à 10 minutes (téléchargement des images). Ensuite :

| Adresse | Quoi |
|---|---|
| http://localhost:8082 | Jenkins (mêmes identifiants que sur le Jenkins d'Anass) |
| http://localhost:30080 | L'application Quiz Live (servie par Kubernetes) |

## Au quotidien

```bash
docker compose -f local/docker-compose.yml stop     # arrêter (tout est conservé)
docker compose -f local/docker-compose.yml start    # relancer
docker compose -f local/docker-compose.yml ps       # état des conteneurs
```

Commandes Kubernetes (sans rien installer) :
```bash
docker compose -f local/docker-compose.yml exec k3s kubectl get pods -o wide
docker compose -f local/docker-compose.yml exec k3s kubectl logs -l app=quiz-live --prefix -f
```

Un `git push` déclenche un build dans les 2 minutes (Poll SCM) : build → tests → push Docker Hub
→ déploiement dans **votre** cluster local.

## Repartir de zéro

```bash
docker compose -f local/docker-compose.yml down -v   # supprime conteneurs ET volumes (état perdu)
```
Puis relancer `start` : l'état est restauré depuis `jenkins-home.tar.gz`.

## Important

- `jenkins-home.tar.gz` contient le token Docker Hub : **ne jamais le committer**
  (il est dans `.gitignore`) ni le publier.
- Ports utilisés : 8082, 30080, 6443. S'ils sont occupés, arrêtez l'autre programme.
