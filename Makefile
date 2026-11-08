TF = terraform -chdir=terraform
DOMAIN ?= $(shell grep '^domain' terraform/terraform.tfvars 2>/dev/null | cut -d'"' -f2)
DUCKDNS_NAME = $(firstword $(subst ., ,$(DOMAIN)))

.PHONY: init up down recreate ssh

init:
	$(TF) init -input=false

up: init
	$(TF) apply -auto-approve
	curl -s "https://www.duckdns.org/update?domains=$(DUCKDNS_NAME)&token=$${DUCKDNS_TOKEN}&ip=$$($(TF) output -raw server_ip)"; echo
	./scripts/wait-ready.sh https://n8n.$(DOMAIN)

down: init
	$(TF) destroy -auto-approve

recreate: down up

ssh: init
	ssh-keygen -R $$($(TF) output -raw server_ip) 2>/dev/null; ssh deploy@$$($(TF) output -raw server_ip)