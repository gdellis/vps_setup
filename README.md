# VPS Setup

Automated scripts to set up a secure, production-ready VPS with essential security tools, containerization, VPN access, comprehensive monitoring, and alerting.

## Features

- **Initial Hardening**: SSH configuration, UFW firewall, Fail2Ban, user management
- **Docker**: Container runtime with security hardening
- **WireGuard VPN**: Secure management access via encrypted tunnel
- **Monitoring Stack**: Prometheus, Grafana, Node Exporter, cAdvisor, Fail2Ban Exporter
- **Alerting**: Email notifications via Alertmanager

## Quick Start

### Prerequisites

- Ubuntu 20.04+ / Debian 11+
- Root access
- Fresh VPS installation

### Installation

1. Clone the repository:
```bash
git clone https://github.com/gdellis/vps_setup.git
cd vps_setup
```

2. Copy and configure environment variables:
```bash
cp .env.example .env
nano .env  # Edit settings as needed
```

3. Run the full installation:
```bash
sudo ./install_all.sh
```

Alternatively, run individual modules:
```bash
sudo ./01_initial_hardening.sh
sudo ./02_docker_setup.sh
sudo ./03_wireguard_setup.sh
sudo ./04_monitoring_setup.sh
sudo ./05_alerting_setup.sh
```

## Post-Installation

### SSH Access

After installation, SSH access is available on port 2222 with key authentication only:

```bash
ssh vpsadmin@your-vps-ip -p 2222
```

### WireGuard VPN

1. Copy the generated client configuration file
2. Import into WireGuard client (desktop) or scan QR code (mobile)
3. Connect to VPN: you'll be assigned IP 10.0.0.2
4. Test connectivity: `ping 10.0.0.1`

### Monitoring Dashboards

Access via VPN only:

- **Grafana**: http://10.0.0.1:3000
  - Username: `admin`
  - Password: set in `.env`

Pre-configured dashboards:
- System Overview
- Docker Containers
- Security Status

## Documentation

- [Design.md]( DESIGN.md) - Complete architecture and system design
- [AGENTS.md](AGENTS.md) - Coding guidelines and contribution standards

## Configuration

See `.env.example` for all configurable options:

| Setting | Default | Description |
|---------|---------|-------------|
| `SSH_PORT` | 2222 | SSH port |
| `NEW_USERNAME` | vpsadmin | Non-root admin user |
| `WG_CLIENT_NAME` | laptop | WireGuard client identifier |
| `GRAFANA_ADMIN_PASSWORD` | changeme123 | Grafana admin password |
| `SMTP_SERVER` | smtp.gmail.com | Alert email server |

## Security

- SSH: Non-standard port, key authentication only, root login disabled
- Firewall: Default deny, minimal public ports (SSH, WireGuard)
- VPN: All monitoring tools accessible only via WireGuard
- Updates: Automatic security patches enabled

## Troubleshooting

### WireGuard won't connect
```bash
sudo wg show  # Check interface status
sudo systemctl restart wg-quick@wg0
```

### Monitoring not working
```bash
curl http://localhost:9090/api/v1/targets  # Check Prometheus targets
sudo systemctl status node_exporter
```

### SSH access issues
Check `/var/log/auth.log` for authentication failures.

## License

This project is provided as-is for educational and production use.

## Contributing

Please follow the guidelines in [AGENTS.md](AGENTS.md) when contributing.

## Support

For issues and questions, please use the GitHub issue tracker.