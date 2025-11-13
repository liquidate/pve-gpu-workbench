#!/usr/bin/env bash
# Template for creating LXC containers with NVIDIA GPU support
# Copy this file and customize for your application
#
# This template shows how simple it is to create GPU-enabled LXC containers
# using the shared library modules.

# Get script directory and source shared libraries
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/../includes/colors.sh"
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/../includes/progress.sh"
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/../includes/logging.sh"
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/../includes/lxc-common.sh"
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/../includes/lxc-gpu-nvidia.sh"

# ═══════════════════════════════════════════════════════════════
# APPLICATION CONFIGURATION
# ═══════════════════════════════════════════════════════════════

APP_NAME="My GPU Application"
APP_PORT=8080
CONTAINER_ID=200
HOSTNAME="my-app"
IP_ADDRESS="192.168.111.200"
MEMORY=8          # GB
CORES=4
DISK_SIZE=32      # GB
STORAGE="local-lvm"

# Total installation steps (update based on your app)
TOTAL_STEPS=6

# ═══════════════════════════════════════════════════════════════
# SETUP LOGGING
# ═══════════════════════════════════════════════════════════════

setup_logging "my-app-lxc-install" "${APP_NAME} Installation"

# ═══════════════════════════════════════════════════════════════
# DISPLAY HEADER
# ═══════════════════════════════════════════════════════════════

clear
echo ""
echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${GREEN}${APP_NAME} LXC Container Setup${NC}"
echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""
echo -e "  ${CYAN}Container ID:${NC}    ${GREEN}$CONTAINER_ID${NC}"
echo -e "  ${CYAN}Hostname:${NC}        ${GREEN}$HOSTNAME${NC}"
echo -e "  ${CYAN}IP Address:${NC}      ${GREEN}$IP_ADDRESS${NC}"
echo -e "  ${CYAN}Memory:${NC}          ${GREEN}${MEMORY}GB${NC}"
echo -e "  ${CYAN}CPU Cores:${NC}       ${GREEN}$CORES${NC}"
echo -e "  ${CYAN}Disk Size:${NC}       ${GREEN}${DISK_SIZE}GB${NC}"
echo ""
read -r -p "Proceed with installation? [Y/n]: " CONFIRM
CONFIRM=${CONFIRM:-Y}
if [[ ! "$CONFIRM" =~ ^[Yy]$ ]]; then
    echo "Installation cancelled"
    exit 0
fi

# Get root password
echo ""
echo -e "${CYAN}Set root password for SSH access:${NC}"
echo -n "Enter password: "
read -s ROOT_PASSWORD
echo ""
echo -n "Confirm password: "
read -s ROOT_PASSWORD_CONFIRM
echo ""

if [ "$ROOT_PASSWORD" != "$ROOT_PASSWORD_CONFIRM" ]; then
    echo -e "${RED}ERROR: Passwords do not match${NC}"
    exit 1
fi

# ═══════════════════════════════════════════════════════════════
# INSTALLATION
# ═══════════════════════════════════════════════════════════════

clear
echo ""
echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${GREEN}Installing ${APP_NAME}${NC}"
echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo "  Container ID: $CONTAINER_ID | IP: $IP_ADDRESS"
echo "  Resources: ${DISK_SIZE}GB disk, ${MEMORY}GB RAM, $CORES cores"
echo ""
show_log_info

# Step 1: Create container
show_progress 1 $TOTAL_STEPS "Creating container"
create_lxc_container "$CONTAINER_ID" "$HOSTNAME" "$IP_ADDRESS" "$MEMORY" "$CORES" "$DISK_SIZE" "$STORAGE"
complete_progress "Container created"

# Step 2: Configure GPU passthrough
show_progress 2 $TOTAL_STEPS "Configuring NVIDIA GPU passthrough"
configure_nvidia_gpu_passthrough "$CONTAINER_ID"
complete_progress "GPU passthrough configured"

# Step 3: Start container
show_progress 3 $TOTAL_STEPS "Starting container"
start_lxc_container "$CONTAINER_ID"
complete_progress "Container started"

# Step 4: Configure SSH and set password
show_progress 4 $TOTAL_STEPS "Configuring SSH access"
set_root_password "$CONTAINER_ID" "$ROOT_PASSWORD"
configure_ssh "$CONTAINER_ID"
complete_progress "SSH configured"

# Step 5: Install your application
show_progress 5 $TOTAL_STEPS "Installing ${APP_NAME}"

pct exec $CONTAINER_ID -- bash -c "
    apt-get update -qq
    apt-get install -y your-application-here
    
    # Add your app-specific setup here
    echo 'Application installation commands go here'
" >> "$LOG_FILE" 2>&1

complete_progress "${APP_NAME} installed"

# Step 6: Verify GPU access (optional but recommended)
show_progress 6 $TOTAL_STEPS "Verifying GPU access"
verify_gpu_access "$CONTAINER_ID"
complete_progress "GPU verification complete"

# ═══════════════════════════════════════════════════════════════
# COMPLETION
# ═══════════════════════════════════════════════════════════════

show_container_info "$HOSTNAME" "$IP_ADDRESS" "$APP_PORT" "${APP_NAME}"
show_log_summary

echo -e "${YELLOW}⚠  Note: GPU driver and CUDA toolkit may need additional setup${NC}"
echo -e "${DIM}   Run 'pct exec $CONTAINER_ID -- nvidia-smi' to verify GPU access${NC}"
echo ""

exit 0

