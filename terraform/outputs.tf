output "instance_public_ip" {
  description = "Public IP of the k3s node"
  value       = aws_instance.k3s.public_ip
}

output "ssh_command" {
  description = "SSH command to connect to the k3s node"
  value       = "ssh -i ${path.module}/k3s-key.pem ec2-user@${aws_instance.k3s.public_ip}"
}

output "fetch_kubeconfig" {
  description = "Command to fetch kubeconfig from the k3s node"
  value       = <<-EOT
    scp -i ${path.module}/k3s-key.pem -o StrictHostKeyChecking=no ec2-user@${aws_instance.k3s.public_ip}:/etc/rancher/k3s/k3s.yaml ./kubeconfig.yaml
    sed -i 's/127.0.0.1/${aws_instance.k3s.public_ip}/g' kubeconfig.yaml
    export KUBECONFIG=$(pwd)/kubeconfig.yaml
    kubectl get nodes
  EOT
}

output "grafana_url" {
  description = "Grafana URL (after deployment, NodePort 30300)"
  value       = "http://${aws_instance.k3s.public_ip}:30300"
}

output "boutique_url" {
  description = "Online Boutique URL (after deployment, NodePort 30080)"
  value       = "http://${aws_instance.k3s.public_ip}:30080"
}
