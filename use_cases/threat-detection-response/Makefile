# The Unhackable Blog — RHACS Threat Detection & Response demo
#
#   make            show this help
#   make install    first time only: CRC + RHACS + demo   (~45-60 min)
#   make up         start EVERYTHING, install what's missing, reset, verify — ready to show
#   make verify     re-run the end-to-end checks only
#   make reset      clean starting state before (and between) runs
#   make down       stop everything (deletes nothing)
#   make recreate   broken cluster? delete it and rebuild everything (~45-60 min)

SHELL := /bin/bash
S     := scripts

# crc needs libvirt as an *active* group. Right after install (no re-login yet) it is only
# in /etc/group, so run crc through `sg libvirt` — same trick as 00-crc-up.sh.
crc    = $(if $(filter libvirt,$(shell id -nG)),crc $(1),sg libvirt -c 'crc $(1)')

.DEFAULT_GOAL := help
.PHONY: help install crc rhacs setup apps up verify recreate down reset status \
        live reset-live web-terminal enforce contain fix images \
        act1 act2 act3 act4 act5 act6 c2 pwn \
        attacker-up attacker-down attacker-logs attacker-status \
        password check uninstall-rhacs destroy

##@ First time

install: crc rhacs setup ## Everything from scratch: CRC, RHACS, demo (~45-60 min)

crc: ## Install, configure and start OpenShift Local (CRC)
	$(S)/00-crc-up.sh

rhacs: ## Install RHACS 5.0 on CRC (operator, Central, SecuredCluster, API token)
	$(S)/01-rhacs-install.sh

setup: ## Build images, deploy the blog, load policies, lock baselines, start the attacker
	$(S)/02-demo-setup.sh

apps: ## Build + deploy the blog only (no RHACS needed; run while RHACS installs)
	$(S)/02-demo-setup.sh --apps

##@ Every session

up: ## Start EVERYTHING (CRC, RHACS, demo, attacker), install what's missing, reset, verify
	$(S)/up.sh

verify: ## End-to-end checks: cluster, RHACS, baselines, scanner, blog, attacker (no changes)
	@$(S)/up.sh --verify

down: ## Stop EVERYTHING: live views, attacker, CRC (deletes nothing; frees ~20 GiB RAM)
	$(S)/down.sh

recreate: ## Broken cluster? Delete CRC and rebuild everything from scratch (asks first, ~45-60 min)
	$(S)/up.sh --recreate

reset: ## Back to the start: v1, enforcement off, no NetworkPolicies, violations resolved
	$(S)/demo.sh reset

status: ## Where are we? Image, pod, enforcement, NetworkPolicies, violations, attacker
	@$(S)/demo.sh status
	@$(S)/attacker.sh status

password: ## RHACS console URL, user and password (password also copied to the clipboard)
	@source $$HOME/.bashrc.d/rhacs.sh && rox-ui

##@ Live mode — you type curl, everything reacts (recommended on stage)

live: ## Open the 4-pane tmux demo: attacker curl | C2 nc | RHACS live alerts | pods
	$(S)/live.sh

reset-live: ## Clean all 4 tmux panes and reset the demo (between runs, without reopening)
	$(S)/live.sh --reset

web-terminal: ## The 5 live panes as browser terminals (ttyd, 127.0.0.1:7681-7685) for the TALK.html deck
	$(S)/web-terminal.sh

enforce: ## Respond, step 1: Kill Pod on anything outside the baseline
	$(S)/demo.sh enforce

contain: ## Respond, step 2: NetworkPolicy — DNS + internet on 80/443 only
	$(S)/demo.sh contain

fix: ## Fix forward: roll out v2 (rule engine removed)
	$(S)/demo.sh fix

##@ Scripted acts (each act runs its attack for you)

act1: ## Unhackable — 0 CVEs, minimal risk, no violations
	$(S)/demo.sh act1

act2: ## Day zero — the link checker becomes remote code execution
	$(S)/demo.sh act2

act3: ## Loot — honeytoken, then lateral movement to payments-api
	$(S)/demo.sh act3

c2: ## (second terminal) the attacker's reverse-shell listener
	$(S)/attacker.sh c2

act4: ## Persistence — reverse shell + crypto miner (start `make c2` first)
	$(S)/demo.sh act4

act5: ## Respond — kill the pod, then apply the NetworkPolicy
	$(S)/demo.sh act5

act6: ## Fix forward — v2, no shell, still 0 CVEs
	$(S)/demo.sh act6

pwn: ## Run any command through the vulnerability: make pwn CMD='ls -la /tmp'
	@test -n "$(CMD)" || { echo "usage: make pwn CMD='ls -la /tmp'"; exit 2; }
	$(S)/demo.sh pwn "$(CMD)"

##@ The attacker (this laptop)

attacker-up: ## Start the attacker: address, firewall, DNS, payload server, mining pool
	$(S)/attacker.sh up

attacker-down: ## Stop the attacker and close the firewall again
	$(S)/attacker.sh down

attacker-logs: ## What the attacker's servers saw (downloads, DNS, miner shares)
	$(S)/attacker.sh logs

attacker-status: ## Attacker address, firewall and containers
	$(S)/attacker.sh status

##@ Maintenance

images: ## Rebuild and push blog v1/v2 after changing app/blog (cluster must be up)
	$(S)/build-images.sh

check: ## Syntax-check all scripts
	@for f in $(S)/*.sh $(S)/lib/*.sh docs/tools/shoot.sh; do bash -n "$$f" && echo "ok  $$f" || exit 1; done

uninstall-rhacs: ## Remove RHACS from the cluster (keeps CRC and the demo files)
	$(S)/01-rhacs-install.sh --uninstall

destroy: ## Delete the CRC cluster completely (asks for confirmation)
	@read -rp "Delete the CRC cluster and everything in it? [y/N] " a && [ "$$a" = y ]
	-$(S)/attacker.sh down
	$(call crc,delete -f)

##@ Help

help: ## Show this help
	@awk 'BEGIN {FS = ":.*##"} \
	  /^##@/ { printf "\n\033[1m%s\033[0m\n", substr($$0, 5); next } \
	  /^[a-zA-Z0-9_-]+:.*##/ { printf "  \033[36mmake %-16s\033[0m %s\n", $$1, $$2 }' $(MAKEFILE_LIST)
	@echo
