#!/bin/bash
# Script Name: 02_docker_setup.sh
# Purpose: Install and configure container runtime
# Prerequisites: Completed initial hardening, Docker should be setup before WireGuard
# Usage: sudo ./02_docker_setup.sh
# Dependencies: ./lib/common.sh, ./lib/logger.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/common.sh"
source "$SCRIPT_DIR/lib/logger.sh"

if [[ -f .env ]]; then
	source .env
fi

main() {
	log_script_start "02_docker_setup.sh"

	log_step 1 1 "Verifying prerequisites"
	check_root
	check_os

	log_step 1 7 "Installing Docker prerequisites"
	apt-get update
	apt-get install -y ca-certificates curl gnupg lsb-release

	log_step 2 7 "Adding Docker GPG key"
	install -m 0755 -d /etc/apt/keyrings
	curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
	chmod a+r /etc/apt/keyrings/docker.gpg
	log_success "Docker GPG key added"

	log_step 3 7 "Adding Docker repository"
	echo \
		"deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu \
    $(. /etc/os-release && echo "$VERSION_CODENAME") stable" |
		tee /etc/apt/sources.list.d/docker.list >/dev/null
	log_success "Docker repository added"

	log_step 4 7 "Installing Docker CE"
	apt-get update
	apt-get install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin
	log_success "Docker CE installed"

	log_step 5 7 "Creating docker group"
	if ! getent group docker >/dev/null 2>&1; then
		groupadd docker
		log_success "Docker group created"
	else
		log_info "Docker group already exists"
	fi

	docker_user="${DOCKER_USER:-vpsadmin}"
	if id "$docker_user" &>/dev/null; then
		usermod -aG docker "$docker_user"
		log_success "User $docker_user added to docker group"
	else
		log_warning "User $docker_user does not exist, skipping group membership"
	fi

	log_step 6 7 "Configuring Docker daemon"
	mkdir -p /etc/docker

	cat >/etc/docker/daemon.json <<'EOF'
{
  "log-driver": "json-file",
  "log-opts": {
    "max-size": "10m",
    "max-file": "3"
  },
  "live-restore": true,
  "dns": ["1.1.1.1", "8.8.8.8"]
}
EOF

	log_success "Docker daemon configured"

	log_step 7 7 "Starting and enabling Docker service"
	systemctl enable docker
	systemctl start docker

	if systemctl is-active --quiet docker; then
		log_success "Docker service is running"
	else
		log_error "Docker service failed to start"
		exit 1
	fi

	if command -v docker &>/dev/null; then
		local docker_version=$(docker --version)
		log_success "$docker_version"
	fi

	log_script_end "02_docker_setup.sh"

	echo ""
	log_success "Docker setup complete!"
	echo ""
	echo "Next steps:"
	echo "1. Run: sudo ./03_wireguard_setup.sh"
	echo ""
}

main "$@"
