resource "digitalocean_ssh_key" "me" {
  name       = "pdi-key"
  public_key = var.ssh_public_key
}

resource "random_password" "pg" {
  length  = 32
  special = false
}

resource "random_password" "redis" {
  length  = 32
  special = false
}

resource "random_password" "n8n" {
  length  = 32
  special = false
}

resource "random_password" "kc" {
  length  = 24
  special = false
}

resource "random_password" "evo" {
  length  = 32
  special = false
}

resource "digitalocean_vpc" "pdi" {
  name     = "pdi-vpc"
  region   = var.region
  ip_range = "10.10.10.0/24"
}

resource "digitalocean_droplet" "app" {
  name     = "pdi-app"
  image    = "ubuntu-24-04-x64"
  size     = var.size
  region   = var.region
  ssh_keys = [digitalocean_ssh_key.me.fingerprint]
  resize_disk = false
  vpc_uuid = digitalocean_vpc.pdi.id

  user_data = templatefile("${path.module}/cloud-init.yaml.tftpl", {
    ssh_public_key = var.ssh_public_key
    domain         = var.domain
    acme_email     = var.acme_email
    repo_url       = var.repo_url
    pg_password    = random_password.pg.result
    redis_password = random_password.redis.result
    n8n_key        = random_password.n8n.result
    kc_password    = random_password.kc.result
    evo_key        = random_password.evo.result
    traefik_auth   = var.traefik_dashboard_auth
    vpc_cidr       = digitalocean_vpc.pdi.ip_range
  })
}

resource "digitalocean_droplet" "worker" {
  count    = var.worker_count
  name     = "pdi-worker-${count.index + 1}"
  image    = "ubuntu-24-04-x64"
  size     = "s-2vcpu-2gb"
  region   = var.region
  vpc_uuid = digitalocean_vpc.pdi.id
  ssh_keys = [digitalocean_ssh_key.me.fingerprint]

  user_data = templatefile("${path.module}/cloud-init-worker.yaml.tftpl", {
    ssh_public_key = var.ssh_public_key
    vpc_cidr       = digitalocean_vpc.pdi.ip_range
  })
}

resource "digitalocean_firewall" "web" {
  name        = "pdi-fw"
  droplet_ids = concat([digitalocean_droplet.app.id], digitalocean_droplet.worker[*].id)
    dynamic "inbound_rule" {
    for_each = ["tcp", "udp"]
    content {
      protocol         = inbound_rule.value
      port_range       = "1-65535"
      source_addresses = [digitalocean_vpc.pdi.ip_range]
    }
  }

  inbound_rule {
    protocol         = "icmp"
    source_addresses = [digitalocean_vpc.pdi.ip_range]
  }

  dynamic "inbound_rule" {
    for_each = ["22", "80", "443"]
    content {
      protocol         = "tcp"
      port_range       = inbound_rule.value
      source_addresses = ["0.0.0.0/0", "::/0"]
    }
  }

  dynamic "outbound_rule" {
    for_each = ["tcp", "udp"]
    content {
      protocol              = outbound_rule.value
      port_range            = "1-65535"
      destination_addresses = ["0.0.0.0/0", "::/0"]
    }
  }

  outbound_rule {
    protocol              = "icmp"
    destination_addresses = ["0.0.0.0/0", "::/0"]
  }
}