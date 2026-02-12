#!/bin/bash
# Library: common.sh
# Purpose: Common utility functions for VPS setup scripts
# Dependencies: none

# Color codes for output
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m'

log_info() {
	echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
	echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
	echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
	echo -e "${RED}[ERROR]${NC} $1" >&2
}

check_root() {
	if [[ $EUID -ne 0 ]]; then
		log_error "This script must be run as root. Use 'sudo ./script-name.sh'"
		exit 1
	fi
}

check_os() {
	if [[ ! -f /etc/os-release ]]; then
		log_error "Cannot detect OS. /etc/os-release not found."
		exit 1
	fi

	source /etc/os-release

	case "$ID" in
	ubuntu | debian)
		log_info "Detected OS: $PRETTY_NAME"
		return 0
		;;
	*)
		log_error "Unsupported OS: $PRETTY_NAME. This script requires Ubuntu 20.04+ or Debian 11+"
		exit 1
		;;
	esac
}

install_if_missing() {
	local package="$1"

	if dpkg -l | grep -q "^ii  $package "; then
		log_info "$package is already installed"
		return 0
	else
		log_info "Installing $package..."
		apt-get install -y "$package" || {
			log_error "Failed to install $package"
			return 1
		}
		log_success "$package installed successfully"
		return 0
	fi
}

backup_file() {
	local filepath="$1"

	if [[ -f "$filepath" ]]; then
		local backup_path="${filepath}.bak.$(date +%Y%m%d%H%M%S)"
		cp "$filepath" "$backup_path"
		log_success "Backed up $filepath to $backup_path"
	else
		log_warning "File $filepath does not exist, skipping backup"
	fi
}

enable_service() {
	local service_name="$1"

	log_info "Enabling and starting $service_name..."
	systemctl enable "$service_name"
	systemctl start "$service_name"

	if systemctl is-active --quiet "$service_name"; then
		log_success "$service_name is running"
	else
		log_error "$service_name failed to start"
		return 1
	fi
}

get_latest_release() {
	local repo="$1"
	local api_url="https://api.github.com/repos/$repo/releases/latest"

	curl -s "$api_url" | grep '"tag_name":' | sed -E 's/.*"([^"]+)".*/\1/'
}

download_release() {
	local repo="$1"
	local binary_name="$2"
	local download_dir="$3"

	local version=$(get_latest_release "$repo")
	local base_url="https://github.com/$repo/releases/download/${version}"

	log_info "Downloading $binary_name version $version..."

	local arch
	arch=$(dpkg --print-architecture)

	case "$arch" in
	amd64 | x86_64)
		arch="amd64"
		;;
	arm64 | aarch64)
		arch="arm64"
		;;
	*)
		log_error "Unsupported architecture: $arch"
		return 1
		;;
	esac

	local download_file="${binary_name}_${version}_linux_${arch}.tar.gz"
	local download_url="${base_url}/${download_file}"

	cd "$download_dir" || {
		log_error "Cannot change to directory $download_dir"
		return 1
	}

	if wget -q "$download_url"; then
		log_success "Downloaded $download_file"
		echo "$download_file"
		return 0
	else
		log_error "Failed to download $download_file from $download_url"
		return 1
	fi
}
