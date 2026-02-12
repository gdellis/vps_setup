#!/bin/bash
# Script Name: 05_alerting_setup.sh
# Purpose: Configure email-based alerting for system events
# Prerequisites: Completed monitoring setup
# Usage: sudo ./05_alerting_setup.sh
# Dependencies: ./lib/common.sh, ./lib/logger.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/common.sh"
source "$SCRIPT_DIR/lib/logger.sh"

if [[ -f .env ]]; then
	source .env
fi

main() {
	log_script_start "05_alerting_setup.sh"

	log_step 1 1 "Verifying prerequisites"
	check_root
	check_os

	# Install Alertmanager
	log_step 1 3 "Installing Alertmanager"
	ALERTMANAGER_VERSION=$(get_latest_release "prometheus/alertmanager")
	ALERTMANAGER_DIR="/opt/alertmanager"
	ALERTMANAGER_USER="alertmanager"

	if [[ ! -d "$ALERTMANAGER_DIR" ]]; then
		mkdir -p "$ALERTMANAGER_DIR"
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

		wget -qO alertmanager.tar.gz "https://github.com/prometheus/alertmanager/releases/download/${ALERTMANAGER_VERSION}/alertmanager-${ALERTMANAGER_VERSION#v}.linux-${arch}.tar.gz"
		tar -xzf alertmanager.tar.gz --strip-components=1 -C "$ALERTMANAGER_DIR"

		useradd -rs /bin/false "$ALERTMANAGER_USER" 2>/dev/null || true
		chown -R "$ALERTMANAGER_USER:$ALERTMANAGER_USER" "$ALERTMANAGER_DIR"

		SMTP_SERVER="${SMTP_SERVER:-smtp.gmail.com}"
		SMTP_PORT="${SMTP_PORT:-587}"
		SMTP_USERNAME="${SMTP_USERNAME:-}"
		SMTP_PASSWORD="${SMTP_PASSWORD:-}"
		ALERT_FROM="${ALERT_FROM:-noreply@vps.local}"
		ALERT_TO="${ALERT_TO:-admin@localhost}"

		if [[ -z "$SMTP_PASSWORD" ]]; then
			log_warning "SMTP_PASSWORD not set in .env. Email alerts may not work."
		fi

		cat >"$ALERTMANAGER_DIR/alertmanager.yml" <<EOF
global:
  resolve_timeout: 5m
  smtp_smarthost: '$SMTP_SERVER:$SMTP_PORT'
  smtp_from: '$ALERT_FROM'
  smtp_auth_username: '$SMTP_USERNAME'
  smtp_auth_password: '$SMTP_PASSWORD'

route:
  group_by: ['alertname', 'severity']
  group_wait: 10s
  group_interval: 10s
  repeat_interval: 12h
  receiver: 'default-receiver'
  routes:
    - match:
        severity: critical
      receiver: 'critical-receiver'
      repeat_interval: 5m

receivers:
- name: 'default-receiver'
  email_configs:
  - to: '$ALERT_TO'
    from: '$ALERT_FROM'
    smarthost: '$SMTP_SERVER:$SMTP_PORT'
    auth_username: '$SMTP_USERNAME'
    auth_password: '$SMTP_PASSWORD'

- name: 'critical-receiver'
  email_configs:
  - to: '$ALERT_TO'
    from: '$ALERT_FROM'
    smarthost: '$SMTP_SERVER:$SMTP_PORT'
    auth_username: '$SMTP_USERNAME'
    auth_password: '$SMTP_PASSWORD'
EOF

		cat >/etc/systemd/system/alertmanager.service <<EOF
[Unit]
Description=Alertmanager
After=network.target

[Service]
User=$ALERTMANAGER_USER
ExecStart=$ALERTMANAGER_DIR/alertmanager \\
  --config.file=$ALERTMANAGER_DIR/alertmanager.yml \\
  --storage.path=$ALERTMANAGER_DIR/data
Restart=always

[Install]
WantedBy=multi-user.target
EOF

		systemctl daemon-reload
		enable_service alertmanager
		log_success "Alertmanager installed on port 9093"
	else
		log_info "Alertmanager already installed"
	fi

	# Configure Prometheus alert rules
	log_step 2 3 "Configuring Prometheus alert rules"
	PROMETHEUS_DIR="/opt/prometheus"

	if [[ -d "$PROMETHEUS_DIR/configs" ]]; then
		backup_file "$PROMETHEUS_DIR/configs/prometheus.yml"

		cat >"$PROMETHEUS_DIR/configs/prometheus_rules.yml" <<'EOF'
groups:
  - name: system_alerts
    interval: 1m
    rules:
      - alert: DiskSpaceHigh
        expr: (node_filesystem_avail_bytes{!fstype!="tmpfs"} / node_filesystem_size_bytes{!fstype!="tmpfs"}) * 100 < 20
        for: 5m
        labels:
          severity: warning
        annotations:
          summary: "Disk space high on {{ $labels.instance }}"
          description: "Disk space is below 20%. Available: {{ $value }}%"

      - alert: DiskSpaceCritical
        expr: (node_filesystem_avail_bytes{!fstype!="tmpfs"} / node_filesystem_size_bytes{!fstype!="tmpfs"}) * 100 < 10
        for: 5m
        labels:
          severity: critical
        annotations:
          summary: "Disk space critical on {{ $labels.instance }}"
          description: "Disk space is below 10%. Available: {{ $value }}%"

      - alert: CPUHigh
        expr: 100 - (avg by(instance) (irate(node_cpu_seconds_total{mode="idle"}[5m])) * 100) > 80
        for: 5m
        labels:
          severity: warning
        annotations:
          summary: "High CPU usage on {{ $labels.instance }}"
          description: "CPU usage is above 80% for 5 minutes. Current: {{ $value }}%"

      - alert: CPUCritical
        expr: 100 - (avg by(instance) (irate(node_cpu_seconds_total{mode="idle"}[10m])) * 100) > 90
        for: 10m
        labels:
          severity: critical
        annotations:
          summary: "Critical CPU usage on {{ $labels.instance }}"
          description: "CPU usage is above 90% for 10 minutes. Current: {{ $value }}%"

      - alert: MemoryHigh
        expr: (1 - node_memory_MemAvailable_bytes / node_memory_MemTotal_bytes) * 100 > 80
        for: 5m
        labels:
          severity: warning
        annotations:
          summary: "High memory usage on {{ $labels.instance }}"
          description: "Memory usage is above 80% for 5 minutes. Current: {{ $value }}%"

      - alert: MemoryCritical
        expr: (1 - node_memory_MemAvailable_bytes / node_memory_MemTotal_bytes) * 100 > 90
        for: 10m
        labels:
          severity: critical
        annotations:
          summary: "Critical memory usage on {{ $labels.instance }}"
          description: "Memory usage is above 90% for 10 minutes. Current: {{ $value }}%"

      - alert: ServiceDown
        expr: up == 0
        for: 5m
        labels:
          severity: critical
        annotations:
          summary: "Service down: {{ $labels.job }} on {{ $labels.instance }}"
          description: "Service has been down for 5 minutes"

      - alert: PrometheusTargetDown
        expr: up == 0
        for: 5m
        labels:
          severity: warning
        annotations:
          summary: "Prometheus target down: {{ $labels.job }}"
          description: "Target {{ $labels.instance }} has been unreachable for 5 minutes"
EOF

		if ! grep -q "prometheus_rules.yml" "$PROMETHEUS_DIR/configs/prometheus.yml"; then
			sed -i '/^rules_files/a\  - prometheus_rules.yml' "$PROMETHEUS_DIR/configs/prometheus.yml" || true
		fi

		systemctl restart prometheus
		log_success "Prometheus alert rules configured"
	fi

	# Configure firewall
	log_step 3 3 "Configuring firewall"
	ufw allow from 10.0.0.0/24 to any port 9191 proto tcp comment "Fail2Ban Exporter - VPN only"
	ufw allow from 10.0.0.0/24 to any port 9093 proto tcp comment "Alertmanager - VPN only"
	log_success "Firewall configured"

	log_script_end "05_alerting_setup.sh"

	echo ""
	log_success "Alerting setup complete!"
	echo ""
	echo "Alerting endpoints (VPN only):"
	echo "  Alertmanager: http://10.0.0.1:9093"
	echo ""
	echo "Email alerts configured for:"
	echo "  To: ${ALERT_TO:-admin@localhost}"
	echo "  Via: ${SMTP_SERVER:-smtp.gmail.com}"
	echo ""
	echo "Alert rules configured:"
	echo "  - Disk space warning (>80%) and critical (>90%)"
	echo "  - CPU high (>80%) and critical (>90%)"
	echo "  - Memory high (>80%) and critical (>90%)"
	echo "  - Service down"
	echo "  - Target unreachable"
}

main "$@"
