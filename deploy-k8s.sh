#!/bin/bash
set -e
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

kubectl get nodes || { echo "ERROR: kubectl not configured."; exit 1; }

# Helm repos
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts 2>/dev/null || true
helm repo add grafana https://grafana.github.io/helm-charts 2>/dev/null || true
helm repo add grafana-community https://grafana-community.github.io/helm-charts 2>/dev/null || true
helm repo update

# Namespaces
kubectl create namespace observability --dry-run=client -o yaml | kubectl apply -f -
kubectl create namespace boutique --dry-run=client -o yaml | kubectl apply -f -

# Boutique dashboard
kubectl create configmap grafana-boutique-dashboard \
  --from-file=boutique-dashboard.json="$SCRIPT_DIR/kubernetes/boutique-dashboard.json" \
  -n observability \
  --dry-run=client -o yaml | kubectl apply -f -

# Prometheus
NODE_IP=$(kubectl get nodes -o jsonpath='{.items[0].status.addresses[?(@.type=="InternalIP")].address}')
echo "Deploying Prometheus (node: $NODE_IP)..."
helm upgrade --install kps prometheus-community/kube-prometheus-stack \
  -n observability \
  -f "$SCRIPT_DIR/kubernetes/prometheus-values.yaml" \
  --set "kubeControllerManager.endpoints={$NODE_IP}" \
  --set "kubeScheduler.endpoints={$NODE_IP}" \
  --set "kubeProxy.endpoints={$NODE_IP}" \
  --wait --timeout 8m

# Loki
echo "Deploying Loki..."
helm upgrade --install loki grafana-community/loki \
  -n observability \
  -f "$SCRIPT_DIR/kubernetes/loki-values.yaml" \
  --wait --timeout 5m

# Tempo
echo "Deploying Tempo..."
helm upgrade --install tempo grafana-community/tempo \
  -n observability \
  -f "$SCRIPT_DIR/kubernetes/tempo-values.yaml" \
  --wait --timeout 5m

# Alloy
echo "Deploying Grafana Alloy..."
helm upgrade --install alloy grafana/alloy \
  -n observability \
  -f "$SCRIPT_DIR/kubernetes/alloy-values.yaml" \
  --wait --timeout 5m

# Grafana
echo "Deploying Grafana..."
kubectl delete pvc grafana -n observability --ignore-not-found
kubectl delete pvc grafana -n observability --ignore-not-found
kubectl delete secret grafana -n observability --ignore-not-found
kubectl delete pv $(kubectl get pv | grep grafana | awk '{print $1}') 2>/dev/null || true
sleep 10
helm upgrade --install grafana grafana-community/grafana \
  -n observability \
  -f "$SCRIPT_DIR/kubernetes/grafana-values.yaml" \
  --force \
  --wait --timeout 8m

# Online Boutique
echo "Deploying Online Boutique..."
kubectl apply -f https://raw.githubusercontent.com/GoogleCloudPlatform/microservices-demo/main/release/kubernetes-manifests.yaml -n boutique
kubectl apply -f "$SCRIPT_DIR/kubernetes/online-boutique.yaml" -n boutique

# Disabled loadgenerator (too much cpu usage)
kubectl delete deployment loadgenerator -n boutique --ignore-not-found

# Disabled adservice (too much ram usage)
kubectl scale deployment adservice -n boutique --replicas=0

echo "Waiting for pods..."
kubectl wait --for=condition=available deployment --all -n boutique --timeout=300s 2>/dev/null || true

echo "Enabling tracing..."
for svc in frontend checkoutservice productcatalogservice shippingservice cartservice \
           paymentservice emailservice recommendationservice currencyservice; do
  kubectl set env deployment/$svc -n boutique \
    ENABLE_TRACING=1 \
    COLLECTOR_SERVICE_ADDR=alloy.observability.svc.cluster.local:4317 \
    2>/dev/null || true
done

echo ""
echo "Done. Grafana: :30300 (admin/admin) | Boutique: :30080"
