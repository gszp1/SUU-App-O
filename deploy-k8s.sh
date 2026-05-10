#!/bin/bash
set -e
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

echo "=============================="
echo " Deploying Observability Stack"
echo "=============================="

echo "[0/8] Verifying cluster access..."
kubectl get nodes || { echo "ERROR: kubectl not configured."; exit 1; }

echo "[1/8] Adding Helm repos..."
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts 2>/dev/null || true
helm repo add grafana https://grafana.github.io/helm-charts 2>/dev/null || true
helm repo add grafana-community https://grafana-community.github.io/helm-charts 2>/dev/null || true
helm repo update

echo "[2/8] Creating namespaces..."
kubectl create namespace observability --dry-run=client -o yaml | kubectl apply -f -
kubectl create namespace boutique --dry-run=client -o yaml | kubectl apply -f -

echo "[3/8] Deploying Prometheus..."
NODE_IP=$(kubectl get nodes -o jsonpath='{.items[0].status.addresses[?(@.type=="InternalIP")].address}')
echo "  Node IP: $NODE_IP"
helm upgrade --install kps prometheus-community/kube-prometheus-stack \
  -n observability \
  -f "$SCRIPT_DIR/kubernetes/prometheus-values.yaml" \
  --set "kubeControllerManager.endpoints={$NODE_IP}" \
  --set "kubeScheduler.endpoints={$NODE_IP}" \
  --set "kubeProxy.endpoints={$NODE_IP}" \
  --wait --timeout 8m

echo "[4/8] Deploying Loki..."
helm upgrade --install loki grafana-community/loki \
  -n observability \
  -f "$SCRIPT_DIR/kubernetes/loki-values.yaml" \
  --wait --timeout 5m

echo "[5/8] Deploying Tempo..."
helm upgrade --install tempo grafana-community/tempo \
  -n observability \
  -f "$SCRIPT_DIR/kubernetes/tempo-values.yaml" \
  --wait --timeout 5m

echo "[6/8] Deploying Grafana Alloy..."
helm upgrade --install alloy grafana/alloy \
  -n observability \
  -f "$SCRIPT_DIR/kubernetes/alloy-values.yaml" \
  --wait --timeout 5m

echo "[7/8] Deploying Grafana..."
helm upgrade --install grafana grafana-community/grafana \
  -n observability \
  -f "$SCRIPT_DIR/kubernetes/grafana-values.yaml" \
  --wait --timeout 5m

echo " Observability stack deployed!"

echo "[8/8] Deploying Online Boutique..."
kubectl apply -f https://raw.githubusercontent.com/GoogleCloudPlatform/microservices-demo/main/release/kubernetes-manifests.yaml \
  -n boutique
kubectl apply -f "$SCRIPT_DIR/kubernetes/online-boutique.yaml" -n boutique

echo "  Waiting for pods..."
kubectl wait --for=condition=available deployment --all -n boutique --timeout=300s 2>/dev/null || true

echo "  Enabling tracing..."
for svc in frontend checkoutservice productcatalogservice shippingservice cartservice \
           paymentservice emailservice recommendationservice adservice currencyservice; do
  kubectl set env deployment/$svc -n boutique \
    ENABLE_TRACING=1 \
    COLLECTOR_SERVICE_ADDR=alloy.observability.svc.cluster.local:4317 \
    2>/dev/null || true
done

echo ""
echo "=============================="
echo " ALL DEPLOYED!"
echo " Grafana:         http://<PUBLIC_IP>:30300  (admin/admin)"
echo " Online Boutique: http://<PUBLIC_IP>:30080"
echo " Run: terraform -chdir=terraform output instance_public_ip"
echo "=============================="
