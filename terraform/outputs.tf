output "server_ip" {
  value = digitalocean_droplet.app.ipv4_address
}