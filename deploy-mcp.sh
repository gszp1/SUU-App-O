#!/bin/bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

NAMESPACE="observability"
MANIFEST="$SCRIPT_DIR/kubernetes/grafana-mcp-server/mcp-grafana.yaml"
SECRET_NAME="mcp-grafana-credentials"
GRAFANA_URL="http://grafana.${NAMESPACE}.svc.cluster.local"
GRAFANA_ADMIN_USER="${GRAFANA_ADMIN_USER:-admin}"
GRAFANA_ADMIN_PASSWORD="${GRAFANA_ADMIN_PASSWORD:-admin}"
SA_NAME="mcp-grafana"
TOKEN_NAME="mcp-grafana-token-$(date +%s)"

# Create a service account + token in Grafana using a short-lived port-forward
echo "Creating Grafana service account and token..."
kubectl -n "$NAMESPACE" port-forward svc/grafana 3000:80 >/dev/null 2>&1 &
PF_PID=$!
trap 'kill "$PF_PID" 2>/dev/null || true' EXIT

# Wait for the port-forward to be ready
for i in $(seq 1 30); do
  if curl -fsS -o /dev/null "http://localhost:3000/api/health"; then
    break
  fi
  sleep 1
done

AUTH="${GRAFANA_ADMIN_USER}:${GRAFANA_ADMIN_PASSWORD}"

# Find existing service account or create a new one
SA_ID=$(curl -fsS -u "$AUTH" \
  "http://localhost:3000/api/serviceaccounts/search?query=${SA_NAME}" \
  | grep -o "\"id\":[0-9]*" | head -1 | cut -d: -f2 || true)

if [ -z "${SA_ID:-}" ]; then
  SA_ID=$(curl -fsS -u "$AUTH" \
    -H "Content-Type: application/json" \
    -X POST "http://localhost:3000/api/serviceaccounts" \
    -d "{\"name\":\"${SA_NAME}\",\"role\":\"Admin\",\"isDisabled\":false}" \
    | grep -o "\"id\":[0-9]*" | head -1 | cut -d: -f2)
fi

if [ -z "${SA_ID:-}" ]; then
  echo "ERROR: failed to create or find Grafana service account."
  exit 1
fi
echo "Service account id: $SA_ID"

GRAFANA_API_KEY=$(curl -fsS -u "$AUTH" \
  -H "Content-Type: application/json" \
  -X POST "http://localhost:3000/api/serviceaccounts/${SA_ID}/tokens" \
  -d "{\"name\":\"${TOKEN_NAME}\"}" \
  | grep -o '"key":"[^"]*"' | cut -d'"' -f4)

if [ -z "${GRAFANA_API_KEY:-}" ]; then
  echo "ERROR: failed to issue Grafana service account token."
  exit 1
fi

kill "$PF_PID" 2>/dev/null || true
trap - EXIT

# Create / update the secret
kubectl -n "$NAMESPACE" create secret generic "$SECRET_NAME" \
  --from-literal=GRAFANA_URL="$GRAFANA_URL" \
  --from-literal=GRAFANA_API_KEY="$GRAFANA_API_KEY" \
  --dry-run=client -o yaml | kubectl apply -f -

# Apply the manifest
echo "Applying MCP Grafana manifest..."
kubectl apply -f "$MANIFEST"

# Restart so the (possibly rotated) token is picked up
kubectl -n "$NAMESPACE" rollout restart deployment/mcp-grafana

# Wait for rollout
echo "Waiting for MCP Grafana rollout..."
kubectl -n "$NAMESPACE" rollout status deployment/mcp-grafana --timeout=180s

echo ""
echo "Done. MCP Grafana available on NodePort :30090 (SSE on /sse)"
