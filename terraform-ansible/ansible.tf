locals {
  seed_hosts      = jsonencode(aws_instance.node[*].private_ip)
  initial_masters = jsonencode([for i in range(var.cluster_size) : "${var.cluster_name}-${i + 1}"])
}

resource "ansible_host" "node" {
  count  = var.cluster_size
  name   = aws_instance.node[count.index].public_ip
  groups = ["elasticsearch", count.index == 0 ? "primary" : "secondary"]

  variables = {
    ansible_user                 = "ec2-user"
    ansible_ssh_private_key_file = "${path.module}/ssh_key.pem"
    ansible_ssh_common_args      = "-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null"
    private_ip                   = aws_instance.node[count.index].private_ip
    is_first_node                = tostring(count.index == 0)
    node_name                    = "${var.cluster_name}-${count.index + 1}"
  }
}

resource "ansible_group" "elasticsearch" {
  name = "elasticsearch"

  variables = {
    cluster_name = var.cluster_name
  }
}

resource "null_resource" "wait_for_ssh" {
  count = var.cluster_size

  connection {
    type        = "ssh"
    host        = aws_instance.node[count.index].public_ip
    user        = "ec2-user"
    private_key = tls_private_key.ssh.private_key_pem
    timeout     = "5m"
  }

  provisioner "remote-exec" {
    inline = ["echo 'SSH is ready'"]
  }

  depends_on = [aws_instance.node, local_sensitive_file.ssh_key]
}

resource "ansible_playbook" "bootstrap_primary" {
  playbook   = "${path.module}/plays/01_bootstrap_primary.yml"
  name       = ansible_host.node[0].name
  replayable = false

  extra_vars = {
    node_name       = "${var.cluster_name}-1"
    private_ip      = aws_instance.node[0].private_ip
    is_first_node   = "true"
    seed_hosts      = local.seed_hosts
    initial_masters = local.initial_masters
  }

  lifecycle {
    ignore_changes = [extra_vars]
  }

  depends_on = [
    ansible_host.node,
    local_sensitive_file.ssh_key,
    null_resource.wait_for_ssh
  ]
}

resource "ansible_playbook" "join_secondary" {
  count      = var.cluster_size - 1
  playbook   = "${path.module}/plays/02_join_secondary.yml"
  name       = ansible_host.node[count.index + 1].name
  replayable = false

  extra_vars = {
    node_name       = "${var.cluster_name}-${count.index + 2}"
    private_ip      = aws_instance.node[count.index + 1].private_ip
    is_first_node   = "false"
    seed_hosts      = local.seed_hosts
    initial_masters = local.initial_masters
  }

  lifecycle {
    ignore_changes = [extra_vars]
  }

  depends_on = [ansible_playbook.bootstrap_primary]
}

resource "ansible_playbook" "configure_auth" {
  playbook   = "${path.module}/plays/03_configure_auth.yml"
  name       = ansible_host.node[0].name
  replayable = true

  extra_vars = {
    node_name        = "${var.cluster_name}-1"
    private_ip       = aws_instance.node[0].private_ip
    is_first_node    = "true"
    elastic_password = var.elastic_password
  }

  depends_on = [ansible_playbook.join_secondary]
}

resource "ansible_playbook" "validate_cluster" {
  playbook   = "${path.module}/plays/04_validate_cluster.yml"
  name       = ansible_host.node[0].name
  replayable = true

  extra_vars = {
    node_name        = "${var.cluster_name}-1"
    private_ip       = aws_instance.node[0].private_ip
    is_first_node    = "true"
    elastic_password = var.elastic_password
    cluster_size     = tostring(var.cluster_size)
  }

  depends_on = [ansible_playbook.configure_auth]
}
