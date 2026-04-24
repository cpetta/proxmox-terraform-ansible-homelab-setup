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

	sudo apt-get install pipx
	sudo pipx install checkov
	pipx ensurepath

	sudo apt-get install curl gpg apt-transport-https --yes
	curl -fsSL https://packages.buildkite.com/helm-linux/helm-debian/gpgkey | gpg --dearmor | sudo tee /usr/share/keyrings/helm.gpg > /dev/null
	echo "deb [signed-by=/usr/share/keyrings/helm.gpg] https://packages.buildkite.com/helm-linux/helm-debian/any/ any main" | sudo tee /etc/apt/sources.list.d/helm-stable-debian.list
	sudo apt-get update
	sudo apt-get install helm

update:
	sudo apt-get update && sudo apt-get upgrade

check:
	checkov -d ./

## terraform/tofu stuff
init:
	cd terraform && tofu init

tformat:
	cd terraform && terraform fmt

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

# Kubernetes Stuff
kinstall:
	sudo apt-get update
	sudo apt-get install -y apt-transport-https ca-certificates curl gnupg
	curl -fsSL https://pkgs.k8s.io/core:/stable:/v1.35/deb/Release.key | sudo gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg
	sudo chmod 644 /etc/apt/keyrings/kubernetes-apt-keyring.gpg
	echo 'deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/v1.35/deb/ /' | sudo tee /etc/apt/sources.list.d/kubernetes.list
	sudo chmod 644 /etc/apt/sources.list.d/kubernetes.list
	sudo apt-get update
	sudo apt-get install -y kubectl

kconfig:
	cp ./kubeconfig ~/.kube/config

yamltotf FILE:
	tfk8s -f {{FILE}} -o {{FILE}}.tf