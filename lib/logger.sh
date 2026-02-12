#!/bin/bash
# Library: logger.sh
# Purpose: Logging functionality for VPS setup scripts
# Dependencies: ./lib/common.sh

readonly LOG_DIR="/var/log"
readonly LOG_FILE="${LOG_DIR}/vps_setup.log"

setup_logging() {
	log_dir_exists=$(ls -ld "$LOG_DIR" 2>/dev/null | grep -c "^d")
	if [[ ! "$log_dir_exists" -gt 0 ]]; then
		log_error "Log directory $LOG_DIR does not exist"
		return 1
	fi

	log_info "Logging to $LOG_FILE"
	log_to_file "INFO" "VPS Setup started at $(date)"
}

log_to_file() {
	local level="$1"
	local message="$2"
	local timestamp=$(date '+%Y-%m-%d %H:%M:%S')

	echo "[$timestamp] [$level] $message" >>"$LOG_FILE"
}

log_script_start() {
	local script_name="$1"
	log_to_file "INFO" "Starting script: $script_name"
}

log_script_end() {
	local script_name="$1"
	log_to_file "INFO" "Completed script: $script_name"
}

log_step() {
	local step_number="$1"
	local total_steps="$2"
	local description="$3"

	log_info "[$step_number/$total_steps] $description"
	log_to_file "INFO" "[$step_number/$total_steps] $description"
}

log_command() {
	local command="$1"
	log_to_file "DEBUG" "Executing: $command"
}
