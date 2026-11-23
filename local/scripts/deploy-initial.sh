#!/bin/sh
# Premier démarrage : remet Redis + quiz-live (3 réplicas) dans le cluster k3s.
# Ensuite c'est Jenkins qui déploie les nouvelles versions.
set -e
export KUBECONFIG=/tmp/kubeconfig

echo "[deploy] attente du cluster k3s..."
until [ -s /output/kubeconfig.yaml ]; do sleep 2; done
sed 's#https://127.0.0.1:6443#https://k3s:6443#' /output/kubeconfig.yaml > "$KUBECONFIG"
# Attendre que le nœud soit enregistré (sinon "kubectl wait" ne trouve rien), puis prêt
until [ -n "$(kubectl get nodes -o name 2>/dev/null)" ]; do sleep 3; done
kubectl wait --for=condition=Ready node --all --timeout=300s
# Attendre que le compte de service "default" existe (requis pour créer des Pods)
until kubectl get serviceaccount default >/dev/null 2>&1; do sleep 2; done

if kubectl get deployment quiz-live >/dev/null 2>&1; then
  echo "[deploy] quiz-live déjà présent : rien à faire"
  kubectl get pods -o wide
  exit 0
fi

echo "[deploy] déploiement de Redis et de $QUIZ_IMAGE"
kubectl apply -f /k8s/redis.yaml
sed "s|image: .*quiz-live:.*|image: $QUIZ_IMAGE|" /k8s/app.yaml | kubectl apply -f -
kubectl rollout status deployment/quiz-live --timeout=300s
kubectl get pods -o wide
echo "[deploy] OK : application sur http://localhost:30080"
