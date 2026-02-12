#!/bin/bash
# Script Name: 01_initial_hardening.sh
# Purpose: Baseline security hardening setup
# Prerequisites: Root access, Ubuntu/Debian
# Usage: sudo ./01_initial_hardening.sh
# Dependencies: ./lib/common.sh, ./lib/logger.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/common.sh"
source "$SCRIPT_DIR/lib/logger.sh"

if [[ -f .env ]]; then
	source .env
fi

main() {
	log_script_start "01_initial_hardening.sh"

	log_step 1 1 "Verifying prerequisites"
	check_root
	check_os

	log_step 1 10 "Updating and upgrading system packages"
	apt-get update
	apt-get upgrade -y

	log_step 2 10 "Installing core packages"
	apt-get install -y ufw fail2ban sudo curl wget git htop ncdu

	log_step 3 10 "Configuring SSH"
	backup_file "/etc/ssh/sshd_config"

	sed -i "s/#PermitRootLogin yes/PermitRootLogin no/" /etc/ssh/sshd_config
	sed -i "s/#PermitRootLogin prohibit-password/PermitRootLogin no/" /etc/ssh/sshd_config
	sed -i "s/PermitRootLogin yes/PermitRootLogin no/" /etc/ssh/sshd_config
	sed -i "s/#PasswordAuthentication yes/PasswordAuthentication no/" /etc/ssh/sshd_config
	sed -i "s/PasswordAuthentication yes/PasswordAuthentication no/" /etc/ssh/sshd_config

	if grep -q "^Port " /etc/ssh/sshd_config; then
		sed -i "s/^Port .*/Port ${SSH_PORT:-2222}/" /etc/ssh/sshd_config
	else
		echo "Port ${SSH_PORT:-2222}" >>/etc/ssh/sshd_config
	fi

	log_step 4 10 "Restarting SSH service"
	systemctl restart sshd
	log_success "SSH configured on port ${SSH_PORT:-2222}"

	log_step 5 10 "Creating non-root user"
	if id "${NEW_USERNAME:-vpsadmin}" &>/dev/null; then
		log_info "User ${NEW_USERNAME:-vpsadmin} already exists"
	else
		adduser --gecos "" "${NEW_USERNAME:-vpsadmin}"
		usermod -aG sudo "${NEW_USERNAME:-vpsadmin}"
		log_success "User ${NEW_USERNAME:-vpsadmin} created with sudo privileges"
	fi

	log_step 6 10 "Configuring UFW firewall"
	ufw default deny incoming
	ufw default allow outgoing
	ufw allow "${SSH_PORT:-2222}"/tcp
	ufw --force enable
	log_success "UFW firewall enabled"

	log_step 7 10 "Installing security tools"
	apt-get install -y rkhunter chkrootkit lynis
	log_success "Security tools installed: rkhunter, chkrootkit, lynis"

	log_step 8 10 "Disabling unused services"
	systemctl disable telnet.socket 2>/dev/null || true
	systemctl disable rsh.socket 2>/dev/null || true
	log_success "Disabled unused services"

	log_step 9 10 "Configuring unattended-upgrades"
	apt-get install -y unattended-upgrades

	cat >/etc/apt/apt.conf.d/50unattended-upgrades <<'EOF'
Unattended-Upgrade::Allowed-Origins {
    "${distro_id}:${distro_codename}";
    "${distro_id}:${distro_codename}-security";
    "${distro_id}ESMApps:${distro_codename}-apps-security";
    "${distro_id}ESMInfrastructure:${distro_codename}-infra-security";
};

Unattended-Upgrade::AutoFixInterruptedDpkg "true";
Unattended-Upgrade::MinimalSteps "true";
Unattended-Upgrade::Remove-Unused-Dependencies "true";
Unattended-Upgrade::Automatic-Reboot "false";
EOF

	dpkg-reconfigure -plow unattended-upgrades
	log_success "Automatic security updates enabled"

	log_step 10 10 "Cleaning up unnecessary packages"
	apt-get autoremove -y
	apt-get clean
	log_success "Cleanup complete"

	log_script_end "01_initial_hardening.sh"

	echo ""
	log_success "Initial hardening complete!"
	echo ""
	echo "Next steps:"
	echo "1. Run: sudo ./02_docker_setup.sh"
	echo "2. After that: sudo ./03_wireguard_setup.sh"
	echo ""
	echo "SSH is now available on port ${SSH_PORT:-2222} with key authentication only."
	echo "User account: ${NEW_USERNAME:-vpsadmin}"
}

main "$@"
