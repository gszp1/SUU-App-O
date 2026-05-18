#!/bin/bash
set -ex
exec > >(tee /var/log/user_data.log) 2>&1
echo "=== user_data.sh started at $(date) ==="

TOKEN=$(curl -s -X PUT "http://169.254.169.254/latest/api/token" \
  -H "X-aws-ec2-metadata-token-ttl-seconds: 21600")

PUBLIC_IP=$(curl -s -H "X-aws-ec2-metadata-token: $TOKEN" \
  http://169.254.169.254/latest/meta-data/public-ipv4 || echo "")

PRIVATE_IP=$(curl -s -H "X-aws-ec2-metadata-token: $TOKEN" \
  http://169.254.169.254/latest/meta-data/local-ipv4)

echo "Public IP:  $PUBLIC_IP"
echo "Private IP: $PRIVATE_IP"

mkdir -p /etc/rancher/k3s

TLS_SANS="- \"127.0.0.1\"\n  - \"$PRIVATE_IP\""
if [ -n "$PUBLIC_IP" ]; then
  TLS_SANS="$TLS_SANS\n  - \"$PUBLIC_IP\""
fi

cat > /etc/rancher/k3s/config.yaml <<EOF
write-kubeconfig-mode: "0644"
tls-san:
  $(echo -e "$TLS_SANS")
kube-controller-manager-arg:
  - "bind-address=0.0.0.0"
kube-proxy-arg:
  - "metrics-bind-address=0.0.0.0"
kube-scheduler-arg:
  - "bind-address=0.0.0.0"
etcd-expose-metrics: true
EOF

echo "=== k3s config.yaml ==="
cat /etc/rancher/k3s/config.yaml

curl -sfL https://get.k3s.io | sh -

echo "Waiting for k3s to be ready..."
for i in $(seq 1 60); do
  if kubectl get nodes 2>/dev/null | grep -q " Ready"; then
    echo "k3s is ready after ${i}s"
    break
  fi
  sleep 1
done
kubectl get nodes

curl -fsSL https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash

echo "=== user_data.sh completed at $(date) ==="
touch /tmp/user_data_complete
