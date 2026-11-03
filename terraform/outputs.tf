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