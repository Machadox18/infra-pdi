output "server_ip" {
  value = digitalocean_droplet.app.ipv4_address
}

output "keycloak_admin_password" {
  value     = random_password.kc.result
  sensitive = true
}

output "evolution_api_key" {
  value     = random_password.evo.result
  sensitive = true
}

output "app_private_ip" {
  value = digitalocean_droplet.app.ipv4_address_private
}

output "worker_ips" {
  value = join(" ", digitalocean_droplet.worker[*].ipv4_address)
}