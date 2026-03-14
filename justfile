#!/usr/bin/env -S just --justfile
# ^ A shebang isn't required, but allows a justfile to be executed
#   like a script, with `./justfile test`, for example.

install:
	just update
	sudo apt-get install ansible-core
	curl --proto '=https' --tlsv1.2 -fsSL https://get.opentofu.org/install-opentofu.sh -o install-opentofu.sh
	chmod +x install-opentofu.sh
	./install-opentofu.sh --install-method deb
	rm -f install-opentofu.sh

update:
	sudo apt-get update && sudo apt-get upgrade

## terraform/tofu stuff
init:
	cd terraform && tofu init

plan *args:
	cd terraform && tofu plan -out tfplan {{args}}

apply *args:
	cd terraform && tofu apply {{args}}

destroy:
	cd terraform && tofu destroy -exclude=proxmox_virtual_environment_download_file.ubuntu_cloud_image_1 -exclude=proxmox_virtual_environment_download_file.ubuntu_cloud_image_2 -exclude=proxmox_virtual_environment_download_file.ubuntu_cloud_image_3 -exclude=proxmox_virtual_environment_download_file.pf_sense_iso_2

apply_target TARGET:
	cd terraform && tofu apply -target={{TARGET}}

destroy_target TARGET:
	cd terraform && tofu destroy -target={{TARGET}}

## terraform/tofu targeted commands
dns01 action:
	cd terraform && tofu {{action}} -target=proxmox_virtual_environment_vm.dns01

## ansible stuff
whoami:
	cd ansible && ansible-playbook -b whoami.yaml
atest:
	cd ansible && ansible-playbook -i inventory.yaml all -m ping

run HOST *TAGS:
	cd ansible && ansible-playbook -b run.yaml --limit {{HOST}} {{TAGS}}

run_all:
	cd ansible && ansible-playbook -b run.yaml

update_everything:
	cd ansible && ansible-playbook -b update_everything.yaml

## repo stuff
# optionally use --force to force reinstall all requirements
reqs *FORCE:
	cd ansible && ansible-galaxy install -r requirements.yaml {{FORCE}}

# ansible vault (encrypt/decrypt/edit)
vault ACTION:
	cd ansible && EDITOR='code --wait' ansible-vault {{ACTION}} vars/secrets.yaml