# Quiz Live

Application de sondages en temps réel (mini-projet DevOps II).

## Lancer l'application (étape 1)

Prérequis : Docker Desktop installé.

```bash
docker compose up --build
```

Puis ouvre http://localhost:3000 dans ton navigateur.

## Tester

1. Clique sur « Créer un sondage », écris une question et des réponses.
2. Tu arrives sur l'écran des résultats, avec un **code à 4 chiffres**.
3. Ouvre un autre onglet (ou ton téléphone sur le même Wi-Fi : http://IP-DE-TON-PC:3000), clique sur « Rejoindre » et tape le code.
4. Vote : le graphique de l'écran bouge tout seul.

## Les fichiers

| Fichier | Rôle |
|---|---|
| `server.js` | Le serveur : crée les sondages, reçoit les votes, envoie les résultats en direct (WebSocket) |
| `public/index.html` | Page d'accueil (rejoindre ou créer) |
| `public/creer.html` | Création d'un sondage |
| `public/vote.html` | Page du participant |
| `public/ecran.html` | Écran commun avec le graphique |
| `public/style.css` | L'apparence |
| `Dockerfile` | Fabrique l'image Docker du serveur |
| `docker-compose.yml` | Lance le serveur et Redis ensemble |

## Pourquoi Redis ?

Redis stocke les sondages et les votes, et permet à plusieurs copies du serveur
(plusieurs Pods Kubernetes) de se transmettre les résultats. Sans lui, un vote reçu
par un Pod ne serait pas vu par les clients connectés à un autre Pod.

## Les étapes suivantes

1. Git : `git init`, `git add .`, `git commit -m "Première version"`, puis envoyer sur GitHub.
2. Kubernetes : fichiers Deployment (plusieurs réplicas), Service, Ingress avec affinité de session.
3. Jenkins : un `Jenkinsfile` (build, test, image Docker, déploiement).
4. Nagios : vérifier `/health` et le nombre de réplicas prêts.

Le serveur écrit le nom du Pod dans ses logs (`[nom-du-pod] ...`) : c'est ce qui servira à
prouver, pendant la démo, qu'un client reste connecté au même Pod.

## Qui voit les résultats ?

- L'écran commun `ecran.html?code=XXXX` affiche les résultats en direct (accessible avec le code).
- Chaque participant voit aussi les résultats en direct sur sa page, **une fois qu'il a voté**.
