#!/bin/bash
# Script Name: 03_wireguard_setup.sh
# Purpose: Establish secure VPN access for management
# Prerequisites: Completed initial hardening
# Usage: sudo ./03_wireguard_setup.sh
# Dependencies: ./lib/common.sh, ./lib/logger.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/common.sh"
source "$SCRIPT_DIR/lib/logger.sh"

if [[ -f .env ]]; then
	source .env
fi

WG_INTERFACE="${WG_INTERFACE:-wg0}"
WG_PORT="${WG_PORT:-51820}"
WG_SERVER_IP="${WG_SERVER_IP:-10.0.0.1}"
WG_CLIENT_IP="${WG_CLIENT_IP:-10.0.0.2/32}"
WG_CLIENT_NAME="${WG_CLIENT_NAME:-laptop}"
WG_DNS="${WG_DNS:-1.1.1.1,8.8.8.8}"

main() {
	log_script_start "03_wireguard_setup.sh"

	log_step 1 1 "Verifying prerequisites"
	check_root
	check_os

	log_step 1 9 "Installing WireGuard"
	apt-get update
	apt-get install -y wireguard tools

	mkdir -p /etc/wireguard
	log_success "WireGuard installed"

	log_step 2 9 "Generating server keys"
	cd /etc/wireguard

	if [[ ! -f "server_private.key" ]]; then
		wg genkey | tee server_private.key | wg pubkey >server_public.key
		chmod 600 server_private.key
		log_success "Server keys generated"
	else
		log_info "Server keys already exist"
	fi

	SERVER_PRIVATE=$(cat server_private.key)
	SERVER_PUBLIC=$(cat server_public.key)

	log_step 3 9 "Generating client keys"
	if [[ ! -f "client_${WG_CLIENT_NAME}_private.key" ]]; then
		wg genkey | tee "client_${WG_CLIENT_NAME}_private.key" | wg pubkey >"client_${WG_CLIENT_NAME}_public.key"
		chmod 600 "client_${WG_CLIENT_NAME}_private.key"
		log_success "Client keys generated for $WG_CLIENT_NAME"
	else
		log_info "Client keys already exist"
	fi

	CLIENT_PRIVATE=$(cat "client_${WG_CLIENT_NAME}_private.key")
	CLIENT_PUBLIC=$(cat "client_${WG_CLIENT_NAME}_public.key")

	log_step 4 9 "Creating WireGuard configuration"
	backup_file "/etc/wireguard/${WG_INTERFACE}.conf"

	cat >"/etc/wireguard/${WG_INTERFACE}.conf" <<EOF
[Interface]
 PrivateKey = ${SERVER_PRIVATE}
 Address = ${WG_SERVER_IP}/24
 ListenPort = ${WG_PORT}
 DNS = ${WG_DNS}

[Peer]
 PublicKey = ${CLIENT_PUBLIC}
 AllowedIPs = ${WG_CLIENT_IP}
EOF

	log_success "WireGuard configuration created"

	log_step 5 9 "Starting WireGuard interface"
	wg-quick up "$WG_INTERFACE"
	systemctl enable "wg-quick@$WG_INTERFACE"
	log_success "WireGuard interface started and enabled"

	log_step 6 9 "Enabling IP forwarding"
	echo "net.ipv4.ip_forward=1" >>/etc/sysctl.conf
	echo "net.ipv4.conf.all.forwarding=1" >>/etc/sysctl.conf
	sysctl -p
	log_success "IP forwarding enabled"

	log_step 7 9 "Configuring NAT for VPN internet access"
	PUBLIC_IFACE=$(ip route | grep default | awk '{print $5}')

	if ! iptables -t nat -C POSTROUTING -s "10.0.0.0/24" -o "$PUBLIC_IFACE" -j MASQUERADE 2>/dev/null; then
		iptables -t nat -A POSTROUTING -s "10.0.0.0/24" -o "$PUBLIC_IFACE" -j MASQUERADE
	fi

	apt-get install -y iptables-persistent
	iptables-save >/etc/iptables/rules.v4
	log_success "NAT configured and persisted"

	log_step 8 9 "Generating client configuration file"
	CLIENT_CONF="configs/wg-${WG_CLIENT_NAME}.conf"
	mkdir -p "$(dirname "$CLIENT_CONF")"

	cat >"$CLIENT_CONF" <<EOF
[Interface]
 PrivateKey = ${CLIENT_PRIVATE}
 Address = ${WG_CLIENT_IP}
 DNS = ${WG_DNS}

[Peer]
 PublicKey = ${SERVER_PUBLIC}
 Endpoint = $(curl -s ifconfig.me):${WG_PORT}
 AllowedIPs = 0.0.0.0/0
 PersistentKeepalive = 25
EOF

	log_success "Client configuration saved to $CLIENT_CONF"

	log_step 9 9 "Opening WireGuard port in UFW"
	ufw allow "${WG_PORT}"/udp comment "WireGuard VPN"
	log_success "Firewall rule added for port ${WG_PORT}/udp"

	log_script_end "03_wireguard_setup.sh"

	echo ""
	log_success "WireGuard setup complete!"
	echo ""
	echo "Server IP: $WG_SERVER_IP"
	echo "Client IP: ${WG_CLIENT_IP%/*}"
	echo ""
	echo "Client configuration: $CLIENT_CONF"
	echo ""
	echo "Next steps:"
	echo "1. Copy $CLIENT_CONF to your client device"
	echo "2. For mobile: Scan QR code and import into WireGuard app"
	echo "3. For desktop: Import config file into WireGuard client"
	echo "4. Activate VPN connection, test: ping $WG_SERVER_IP"
	echo ""
	echo "After VPN is connected, run: sudo ./04_monitoring_setup.sh"
}

main "$@"
