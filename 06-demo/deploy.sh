#!/bin/bash
set -e

echo "=== Notes App - Kubernetes Deployment ==="
echo ""

# Build the app image using minikube's docker
echo "[1/3] Building Docker image..."
eval $(minikube docker-env)
docker build -t notes-api:v1 ./app
echo "  ✓ Image built"

# Apply manifests
echo "[2/3] Deploying to Kubernetes..."
kubectl apply -f k8s/namespace.yaml
kubectl apply -f k8s/postgres-secret.yaml
kubectl apply -f k8s/postgres.yaml
kubectl apply -f k8s/app-config.yaml
kubectl apply -f k8s/app-deployment.yaml
kubectl apply -f k8s/ingress.yaml
echo "  ✓ Manifests applied"

# Wait for pods
echo "[3/3] Waiting for pods to be ready..."
kubectl wait --for=condition=ready pod -l app=postgres -n notes-app --timeout=60s
kubectl wait --for=condition=ready pod -l app=notes-api -n notes-app --timeout=60s
echo "  ✓ All pods running"

echo ""
echo "=== Deployment Complete ==="
echo ""
echo "Access the API:"
echo "  kubectl port-forward svc/notes-api -n notes-app 8080:80"
echo "  curl http://localhost:8080/api/notes"
