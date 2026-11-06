TF = terraform -chdir=terraform
DOMAIN ?= $(shell grep '^domain' terraform/terraform.tfvars 2>/dev/null | cut -d'"' -f2)
DUCKDNS_NAME = $(firstword $(subst ., ,$(DOMAIN)))

.PHONY: up down recreate ssh

up:
	$(TF) init -input=false
	$(TF) apply -auto-approve
	curl -s "https://www.duckdns.org/update?domains=$(DUCKDNS_NAME)&token=$${DUCKDNS_TOKEN}&ip=$$($(TF) output -raw server_ip)"; echo
	./scripts/wait-ready.sh https://n8n.$(DOMAIN)

down:
	$(TF) destroy -auto-approve

recreate: down up

ssh:
	ssh-keygen -R $$($(TF) output -raw server_ip) 2>/dev/null; ssh deploy@$$($(TF) output -raw server_ip)