resource "digitalocean_ssh_key" "me" {
  name       = "pdi-key"
  public_key = var.ssh_public_key
}

resource "digitalocean_droplet" "app" {
  name     = "pdi-app"
  image    = "ubuntu-24-04-x64"
  size     = var.size
  region   = var.region
  ssh_keys = [digitalocean_ssh_key.me.fingerprint]
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