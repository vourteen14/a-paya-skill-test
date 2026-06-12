resource "tls_private_key" "ssh" {
  algorithm = "RSA"
  rsa_bits  = 4096
}

resource "aws_key_pair" "main" {
  key_name   = var.cluster_name
  public_key = tls_private_key.ssh.public_key_openssh

  tags = {
    Name    = var.cluster_name
    Cluster = var.cluster_name
  }
}

resource "local_sensitive_file" "ssh_key" {
  content         = tls_private_key.ssh.private_key_pem
  filename        = "${path.module}/ssh_key.pem"
  file_permission = "0600"
}

resource "aws_instance" "node" {
  count = var.cluster_size

  ami                    = data.aws_ami.amazon_linux.id
  instance_type          = "t2.micro"
  key_name               = aws_key_pair.main.key_name
  subnet_id              = aws_subnet.public[count.index].id
  vpc_security_group_ids = [aws_security_group.elasticsearch.id]

  root_block_device {
    volume_size           = 30
    volume_type           = "gp2"
    encrypted             = true
    delete_on_termination = true
  }

  user_data = <<-EOF
    #!/bin/bash
    hostnamectl set-hostname ${var.cluster_name}-${count.index + 1}
    echo "preserve_hostname: true" >> /etc/cloud/cloud.cfg
  EOF

  tags = {
    Name      = "${var.cluster_name}-${count.index + 1}"
    Cluster   = var.cluster_name
    NodeIndex = tostring(count.index + 1)
  }
}
