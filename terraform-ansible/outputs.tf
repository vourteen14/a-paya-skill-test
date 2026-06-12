output "public_ips" {
  description = "Public IP addresses of all cluster nodes"
  value       = aws_instance.node[*].public_ip
}

output "private_ips" {
  description = "Private IP addresses for intra-cluster communication"
  value       = aws_instance.node[*].private_ip
}

output "elasticsearch_url" {
  description = "Elasticsearch HTTPS endpoint"
  value       = "https://${aws_instance.node[0].public_ip}:9200"
}

output "ssh_command" {
  description = "SSH access to primary node"
  value       = "ssh -i ssh_key.pem ec2-user@${aws_instance.node[0].public_ip}"
}
