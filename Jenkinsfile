// Pipeline CI/CD Quiz Live : build -> tests -> push Docker Hub -> déploiement Kubernetes
// Credentials requises (créées par jenkins/setup-jenkins.sh) :
//   dockerhub-creds (Username/Password)   kubeconfig (Secret file)
pipeline {
  agent any

  environment {
    TAG = "${env.BUILD_NUMBER}"                       // une version unique par build
    COMPOSE_PROJECT = "quiz-ci-${env.BUILD_NUMBER}"   // stack de test isolée
  }

  options {
    timestamps()
    timeout(time: 20, unit: 'MINUTES')
    disableConcurrentBuilds()
  }

  stages {

    stage('Checkout') {
      steps { checkout scm }
    }

    stage('Init') {
      steps {
        // Le nom de l'image vient du compte Docker Hub stocké dans Jenkins
        withCredentials([usernamePassword(credentialsId: 'dockerhub-creds',
                          usernameVariable: 'DH_USER', passwordVariable: 'DH_PASS')]) {
          script { env.IMAGE = "${DH_USER}/quiz-live" }
        }
        echo "Image : ${env.IMAGE}:${env.TAG}"
      }
    }

    stage('Build image') {
      steps {
        sh 'docker build -t $IMAGE:$TAG -t $IMAGE:latest .'
      }
    }

    stage('Tests') {
      steps {
        // App + Redis dans un réseau isolé (pas de port publié sur l'hôte)
        sh 'docker compose -p $COMPOSE_PROJECT -f docker-compose.yml -f docker-compose.ci.yml up -d'
        // Tests exécutés avec l'image qu'on vient de construire (elle contient test/).
        // Pas de montage de volume : fonctionne aussi quand Jenkins tourne dans Docker.
        sh '''
          docker run --rm --network ${COMPOSE_PROJECT}_default \
            -e BASE_URL=http://app:3000 $IMAGE:$TAG npm test
        '''
      }
      post {
        failure { sh 'docker compose -p $COMPOSE_PROJECT logs app || true' }
        always  { sh 'docker compose -p $COMPOSE_PROJECT down -v || true' }
      }
    }

    stage('Push image') {
      steps {
        withCredentials([usernamePassword(credentialsId: 'dockerhub-creds',
                          usernameVariable: 'DH_USER', passwordVariable: 'DH_PASS')]) {
          sh '''
            echo "$DH_PASS" | docker login -u "$DH_USER" --password-stdin
            docker push $IMAGE:$TAG
            docker push $IMAGE:latest
          '''
        }
      }
    }

    stage('Deploy Kubernetes') {
      steps {
        script { env.DEPLOY_STARTED = 'true' }   // utilisé par le rollback
        withCredentials([file(credentialsId: 'kubeconfig', variable: 'KUBECONFIG')]) {
          sh '''
            kubectl apply -f k8s/redis.yaml
            # Remplace l'image du manifest par la version de ce build
            sed "s|image: .*quiz-live:.*|image: $IMAGE:$TAG|" k8s/app.yaml | kubectl apply -f -
            kubectl rollout status deployment/quiz-live --timeout=180s
          '''
        }
      }
    }

    stage('Smoke test') {
      steps {
        withCredentials([file(credentialsId: 'kubeconfig', variable: 'KUBECONFIG')]) {
          sh '''
            kubectl get pods -l app=quiz-live -o wide
            WANT=$(kubectl get deployment quiz-live -o jsonpath='{.spec.replicas}')
            READY=$(kubectl get deployment quiz-live -o jsonpath='{.status.readyReplicas}')
            echo "Réplicas prêts : ${READY:-0} / $WANT"
            test "${READY:-0}" = "$WANT"
          '''
        }
      }
    }
  }

  post {
    failure {
      script {
        // Rollback seulement si l'échec a eu lieu pendant/après le déploiement
        if (env.DEPLOY_STARTED == 'true') {
          withCredentials([file(credentialsId: 'kubeconfig', variable: 'KUBECONFIG')]) {
            sh 'kubectl rollout undo deployment/quiz-live || true'
          }
          echo 'Échec du déploiement : retour à la version précédente'
        }
      }
    }
    always { sh 'docker logout || true' }
  }
}
