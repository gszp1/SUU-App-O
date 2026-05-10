#!/bin/bash
set -e
echo "=============================="
echo " SUU-App-O Environment Setup"
echo "=============================="
echo "[1/3] Installing Terraform..."
cd /tmp
curl -fsSL https://releases.hashicorp.com/terraform/1.12.1/terraform_1.12.1_linux_amd64.zip -o terraform.zip
unzip -qo terraform.zip
sudo mv terraform /usr/local/bin/
rm -f terraform.zip LICENSE.txt
echo "  Terraform $(terraform --version | head -1)"
echo "[2/3] Installing Helm..."
curl -fsSL https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 2>/dev/null | bash 2>/dev/null
echo "  Helm $(helm version --short)"
echo "[3/3] Cloning repo..."
cd ~
if [ -d "SUU-App-O" ]; then
  cd SUU-App-O && git pull
else
  git clone https://github.com/gszp1/SUU-App-O.git
  cd SUU-App-O
fi
echo ""
echo "=============================="
echo " Setup complete!"
echo " cd ~/SUU-App-O/terraform"
echo " terraform init && terraform apply"
echo "=============================="
