terraform {
  # Specifies terraform API provider to use for `hcloud`
  required_providers {
    hcloud = {
      source  = "hetznercloud/hcloud"
      version = "1.45.0"
    }
  }
}

# Configures hcloud provider for deploy
provider "hcloud" {
  # Hetzner API token 
  token = var.HCLOUD_TOKEN
}

# Creates an SSH key used for redeploy
resource "hcloud_ssh_key" "redeploy" {
  name       = "deploy-demo redeploy key"
  public_key = data.local_sensitive_file.ssh_public_key.content
}

# Static IP for the instance
resource "hcloud_primary_ip" "primary_ip" {
  name          = "deploy-demo-ip"
  datacenter    = "nbg1-dc3"
  type          = "ipv4"
  assignee_type = "server"
  auto_delete   = false
}

# Hetzner instance itself
resource "hcloud_server" "deploy-demo" {
  name        = "deploy-demo"
  image       = "ubuntu-22.04"
  server_type = "cx22"
  datacenter  = "nbg1-dc3"

  public_net {
    ipv4_enabled = true
    ipv4         = hcloud_primary_ip.primary_ip.id
    ipv6_enabled = false
  }

  ssh_keys = [ hcloud_ssh_key.redeploy.name, "viktor.d" ]

  # Startup script for the instance
  # Installs docker, gcloud CLI, downloads docker images and starts the container
  user_data = templatefile("${path.module}/../cloud-init.tpl", {
    location              = "${var.REGION}"
    project_id            = "${var.PROJECT_ID}"
    repo_name             = "${var.REPO_NAME}"
    image_name            = "${var.IMAGE_NAME}"
    service_account_creds = "${replace(data.local_sensitive_file.service_account_creds.content, "\n", "")}"
  })
}

resource "terraform_data" "redeploy" {
  triggers_replace = timestamp()
  
  connection {
    type        = "ssh"
    user        = "root"
    private_key = data.local_sensitive_file.ssh_private_key.content
    host        = hcloud_primary_ip.primary_ip.ip_address
  }

  provisioner "file" {
    source      = "${path.module}/../redeploy.sh"
    destination = "/tmp/redeploy.sh"
  }

  provisioner "remote-exec" {
    inline = [
      "#!/bin/bash",
      "( tail -f -n1 /var/log/deploy-init.log & ) | grep -q 'Docker configuration file updated.'",
      "source /etc/environment",
      "chmod +x /tmp/redeploy.sh",
      "/tmp/redeploy.sh"
    ]
  }
}
