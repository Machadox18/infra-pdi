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

resource "digitalocean_droplet" "app" {
  name     = "pdi-app"
  image    = "ubuntu-24-04-x64"
  size     = var.size
  region   = var.region
  ssh_keys = [digitalocean_ssh_key.me.fingerprint]

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
  })
}

resource "digitalocean_firewall" "web" {
  name        = "pdi-fw"
  droplet_ids = [digitalocean_droplet.app.id]

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