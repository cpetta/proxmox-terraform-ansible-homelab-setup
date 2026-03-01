#!/usr/bin/env -S just --justfile
# ^ A shebang isn't required, but allows a justfile to be executed
#   like a script, with `./justfile test`, for example.

install:
	just update
	sudo apt-get install sshpass
	sudo apt-get install ansible-core
	wget -O - https://apt.releases.hashicorp.com/gpg | sudo gpg --dearmor -o /usr/share/keyrings/hashicorp-archive-keyring.gpg
	echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/hashicorp-archive-keyring.gpg] https://apt.releases.hashicorp.com $(grep -oP '(?<=UBUNTU_CODENAME=).*' /etc/os-release || lsb_release -cs) main" | sudo tee /etc/apt/sources.list.d/hashicorp.list
	sudo apt update
	sudo apt install terraform

update:
	sudo apt-get update && sudo apt-get upgrade

## terraform stuff
init:
	cd terraform && terraform init

plan *args:
	cd terraform && terraform plan {{args}}

apply:
	cd terraform && terraform apply

destroy:
	cd terraform && terraform destroy -exclude=proxmox_virtual_environment_download_file.ubuntu_cloud_image

## terraform targeted commands
dns01 action:
	cd terraform && terraform {{action}} -target=proxmox_virtual_environment_vm.dns01

## ansible stuff
atest:
	cd ansible && ansible-playbook -i inventory.yaml all -m ping

run HOST *TAGS:
	cd ansible && ansible-playbook -b run.yaml --limit {{HOST}} {{TAGS}}

## repo stuff
# optionally use --force to force reinstall all requirements
reqs *FORCE:
	cd ansible && ansible-galaxy install -r requirements.yaml {{FORCE}}

# ansible vault (encrypt/decrypt/edit)
vault ACTION:
	cd ansible && EDITOR='code --wait' ansible-vault {{ACTION}} vars/secrets.yaml