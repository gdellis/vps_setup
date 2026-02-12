#!/bin/bash
# Script Name: 04_monitoring_setup.sh
# Purpose: Deploy comprehensive monitoring stack
# Prerequisites: Completed Docker setup and WireGuard setup
# Usage: sudo ./04_monitoring_setup.sh
# Dependencies: ./lib/common.sh, ./lib/logger.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/common.sh"
source "$SCRIPT_DIR/lib/logger.sh"

if [[ -f .env ]]; then
	source .env
fi

main() {
	log_script_start "04_monitoring_setup.sh"

	log_step 1 1 "Verifying prerequisites"
	check_root
	check_os

	# Install Node Exporter
	log_step 1 5 "Installing Node Exporter"
	NODE_EXPORTER_VERSION=$(get_latest_release "prometheus/node_exporter")
	NODE_EXPORTER_DIR="/opt/node_exporter"
	NODE_EXPORTER_USER="node_exporter"

	if [[ ! -d "$NODE_EXPORTER_DIR" ]]; then
		mkdir -p "$NODE_EXPORTER_DIR"
		cd /tmp

		arch=$(dpkg --print-architecture)
		case "$arch" in
		amd64) arch="amd64" ;;
		arm64) arch="arm64" ;;
		*)
			log_error "Unsupported architecture: $arch"
			exit 1
			;;
		esac

		wget -qO node_exporter.tar.gz "https://github.com/prometheus/node_exporter/releases/download/${NODE_EXPORTER_VERSION}/node_exporter-${NODE_EXPORTER_VERSION#v}.linux-${arch}.tar.gz"
		tar -xzf node_exporter.tar.gz --strip-components=1 -C "$NODE_EXPORTER_DIR"

		useradd -rs /bin/false "$NODE_EXPORTER_USER" 2>/dev/null || true
		cp "$SCRIPT_DIR/configs/node_exporter.service" /etc/systemd/system/ 2>/dev/null || true
		cat >/etc/systemd/system/node_exporter.service <<EOF
[Unit]
Description=Node Exporter
After=network.target

[Service]
User=$NODE_EXPORTER_USER
ExecStart=$NODE_EXPORTER_DIR/node_exporter
Restart=always

[Install]
WantedBy=multi-user.target
EOF

		systemctl daemon-reload
		enable_service node_exporter
		log_success "Node Exporter installed on port 9100"
	else
		log_info "Node Exporter already installed"
	fi

	# Install cAdvisor as Docker container
	log_step 2 5 "Installing cAdvisor"
	if ! docker ps -a | grep -q cadvisor; then
		docker run -d \
			--name=cadvisor \
			--restart=always \
			-v /:/rootfs:ro \
			-v /var/run:/var/run:ro \
			-v /sys:/sys:ro \
			-v /var/lib/docker/:/var/lib/docker:ro \
			-p 8080:8080 \
			gcr.io/cadvisor/cadvisor:latest
		log_success "cAdvisor installed on port 8080"
	else
		docker start cadvisor 2>/dev/null || true
		log_info "cAdvisor already running"
	fi

	# Install Prometheus
	log_step 3 5 "Installing Prometheus"
	PROMETHEUS_VERSION=$(get_latest_release "prometheus/prometheus")
	PROMETHEUS_DIR="/opt/prometheus"
	PROMETHEUS_USER="prometheus"
	PROMETHEUS_RETENTION="${PROMETHEUS_RETENTION:-15d}"

	if [[ ! -d "$PROMETHEUS_DIR" ]]; then
		mkdir -p "$PROMETHEUS_DIR"/{data,configs}
		cd /tmp

		arch=$(dpkg --print-architecture)
		case "$arch" in
		amd64) arch="amd64" ;;
		arm64) arch="arm64" ;;
		*)
			log_error "Unsupported architecture: $arch"
			exit 1
			;;
		esac

		wget -qO prometheus.tar.gz "https://github.com/prometheus/prometheus/releases/download/${PROMETHEUS_VERSION}/prometheus-${PROMETHEUS_VERSION#v}.linux-${arch}.tar.gz"
		tar -xzf prometheus.tar.gz --strip-components=1 -C "$PROMETHEUS_DIR"

		useradd -rs /bin/false "$PROMETHEUS_USER" 2>/dev/null || true
		chown -R "$PROMETHEUS_USER:$PROMETHEUS_USER" "$PROMETHEUS_DIR"

		cat >"$PROMETHEUS_DIR/configs/prometheus.yml" <<'EOF'
global:
  scrape_interval: 15s
  evaluation_interval: 15s

scrape_configs:
  - job_name: 'node_exporter'
    static_configs:
      - targets: ['localhost:9100']

  - job_name: 'cadvisor'
    static_configs:
      - targets: ['localhost:8080']

  - job_name: 'fail2ban_exporter'
    static_configs:
      - targets: ['localhost:9191']
EOF

		cat >/etc/systemd/system/prometheus.service <<EOF
[Unit]
Description=Prometheus
After=network.target

[Service]
User=$PROMETHEUS_USER
ExecStart=$PROMETHEUS_DIR/prometheus \\
  --config.file=$PROMETHEUS_DIR/configs/prometheus.yml \\
  --storage.tsdb.path=$PROMETHEUS_DIR/data \\
  --storage.tsdb.retention.time=$PROMETHEUS_RETENTION
Restart=always

[Install]
WantedBy=multi-user.target
EOF

		systemctl daemon-reload
		enable_service prometheus
		log_success "Prometheus installed on port 9090"
	else
		log_info "Prometheus already installed"
	fi

	# Install Grafana
	log_step 4 5 "Installing Grafana"
	if ! command -v grafana-server &>/dev/null; then
		wget -qO- https://packages.grafana.com/gpg.key | gpg --dearmor >/etc/apt/keyrings/grafana.gpg
		echo "deb [signed-by=/etc/apt/keyrings/grafana.gpg] https://packages.grafana.com/oss/deb stable main" >/etc/apt/sources.list.d/grafana.list

		apt-get update
		apt-get install -y grafana

		backup_file "/etc/grafana/grafana.ini"

		GRAFANA_PASS="${GRAFANA_ADMIN_PASSWORD:-changeme123}"
		sed -i "s/^;admin_password = .*/admin_password = $GRAFANA_PASS/" /etc/grafana/grafana.ini
		sed -i "s/^;anonymous_enabled = .*/anonymous_enabled = false/" /etc/grafana/grafana.ini

		enable_service grafana-server
		log_success "Grafana installed on port ${GRAFANA_PORT:-3000}"
	else
		log_info "Grafana already installed"
	fi

	# Configure firewall for monitoring (VPN only)
	log_step 5 5 "Configuring firewall"
	ufw allow from 10.0.0.0/24 to any port 9100 proto tcp comment "Node Exporter - VPN only"
	ufw allow from 10.0.0.0/24 to any port 8080 proto tcp comment "cAdvisor - VPN only"
	ufw allow from 10.0.0.0/24 to any port 9090 proto tcp comment "Prometheus - VPN only"
	ufw allow from 10.0.0.0/24 to any port "3000" proto tcp comment "Grafana - VPN only"
	log_success "Firewall configured for VPN-only monitoring access"

	log_script_end "04_monitoring_setup.sh"

	echo ""
	log_success "Monitoring setup complete!"
	echo ""
	echo "Monitoring endpoints (VPN only):"
	echo "  Grafana:      http://10.0.0.1:${GRAFANA_PORT:-3000}"
	echo "  Prometheus:   http://10.0.0.1:9090"
	echo ""
	echo "Grafana credentials:"
	echo "  Username: admin"
	echo "  Password: ${GRAFANA_ADMIN_PASSWORD:-changeme123}"
	echo ""
	echo "Next steps:"
	echo "1. Connect via VPN and access Grafana"
	echo "2. Run: sudo ./05_alerting_setup.sh"
}

main "$@"
