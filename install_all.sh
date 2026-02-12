#!/bin/bash
# Script Name: install_all.sh
# Purpose: Master installation script to run all setup modules
# Prerequisites: Root access, Ubuntu/Debian
# Usage: sudo ./install_all.sh
# Dependencies: ./lib/common.sh, ./lib/logger.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/common.sh"
source "$SCRIPT_DIR/lib/logger.sh"

if [[ -f .env ]]; then
	source .env
fi

main() {
	log_script_start "install_all.sh"
	setup_logging

	log_info "Starting VPS Setup..."

	if [[ ! -f .env ]]; then
		log_warning ".env file not found, copying from .env.example"
		cp .env.example .env
		log_info "Please edit .env with your configuration values and run again"
		exit 1
	fi

	log_step 1 5 "Running initial hardening..."
	if ./01_initial_hardening.sh; then
		log_success "Stage 1 complete"
	else
		log_error "Stage 1 failed"
		exit 1
	fi

	log_step 2 5 "Setting up Docker..."
	if ./02_docker_setup.sh; then
		log_success "Stage 2 complete"
	else
		log_error "Stage 2 failed"
		exit 1
	fi

	log_step 3 5 "Configuring WireGuard VPN..."
	if ./03_wireguard_setup.sh; then
		log_success "Stage 3 complete"
	else
		log_error "Stage 3 failed"
		exit 1
	fi

	log_step 4 5 "Deploying monitoring stack..."
	if ./04_monitoring_setup.sh; then
		log_success "Stage 4 complete"
	else
		log_error "Stage 4 failed"
		exit 1
	fi

	log_step 5 5 "Configuring alerting..."
	if ./05_alerting_setup.sh; then
		log_success "Stage 5 complete"
	else
		log_error "Stage 5 failed"
		exit 1
	fi

	log_success "VPS Setup Complete!"

	echo ""
	echo "============================================"
	echo "         Connection Summary"
	echo "============================================"
	echo ""
	echo "SSH:"
	echo "  ssh ${NEW_USERNAME:-vpsadmin}@<IP> -p ${SSH_PORT:-2222}"
	echo ""
	echo "WireGuard:"
	echo "  Server IP: ${WG_SERVER_IP:-10.0.0.1}"
	echo "  Client IP: 10.0.0.2"
	echo "  Config:    configs/wg-${WG_CLIENT_NAME:-laptop}.conf"
	echo ""
	echo "Monitoring (VPN-only):"
	echo "  Grafana:      http://${WG_SERVER_IP:-10.0.0.1}:${GRAFANA_PORT:-3000}"
	echo "  Prometheus:   http://${WG_SERVER_IP:-10.0.0.1}:9090"
	echo "  Alertmanager: http://${WG_SERVER_IP:-10.0.0.1}:9093"
	echo ""
	echo "Grafana credentials:"
	echo "  Username: admin"
	echo "  Password: ${GRAFANA_ADMIN_PASSWORD:-changeme123}"
	echo ""
	echo "============================================"

	log_script_end "install_all.sh"
}

main "$@"
