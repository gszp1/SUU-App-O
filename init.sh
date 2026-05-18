#!/bin/bash
set -e
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# Install Terraform
cd /tmp
curl -fsSL https://releases.hashicorp.com/terraform/1.12.1/terraform_1.12.1_linux_amd64.zip -o terraform.zip
unzip -qo terraform.zip
sudo mv terraform /usr/local/bin/
rm -f terraform.zip LICENSE.txt
echo "Terraform: $(terraform --version | head -1)"

# Install Helm
curl -fsSL https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 2>/dev/null | bash 2>/dev/null
echo "Helm: $(helm version --short)"

# Terraform
cd "$SCRIPT_DIR/terraform"
terraform init -input=false
terraform apply -auto-approve
PUBLIC_IP=$(terraform output -raw instance_public_ip)
echo "EC2: $PUBLIC_IP"

# Wait for k3s and fetch kubeconfig
echo "Waiting for k3s (~2-3 min)..."
for i in $(seq 1 30); do
  if scp -i k3s-key.pem -o StrictHostKeyChecking=no -o ConnectTimeout=5 \
    ec2-user@${PUBLIC_IP}:/etc/rancher/k3s/k3s.yaml ./kubeconfig.yaml 2>/dev/null; then
    echo "kubeconfig ready after ~$((i*10))s"
    break
  fi
  sleep 10
done

if [ ! -f ./kubeconfig.yaml ]; then
  echo "ERROR: kubeconfig not available after 5 min"
  exit 1
fi

sed -i "s/127.0.0.1/${PUBLIC_IP}/g" kubeconfig.yaml
export KUBECONFIG="$(pwd)/kubeconfig.yaml"
kubectl get nodes

# Deploy stack
cd "$SCRIPT_DIR"
chmod +x deploy-k8s.sh deploy-mcp.sh
./deploy-k8s.sh
./deploy-mcp.sh

echo ""
echo "Grafana:         http://${PUBLIC_IP}:30300  (admin/admin)"
echo "Online Boutique: http://${PUBLIC_IP}:30080"
echo "Grafana MCP Server: http://${PUBLIC_IP}:30090"