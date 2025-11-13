#!/usr/bin/env bash
# SCRIPT_DESC: Create Open WebUI LXC
# SCRIPT_DETECT: 

# Creates an LXC container with Open WebUI that connects to existing Ollama instance
# Open WebUI provides a ChatGPT-like interface for Ollama

set -e

# Get script directory and source utilities
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/../includes/colors.sh"

echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}Open WebUI LXC Creation${NC}"
echo -e "${GREEN}========================================${NC}"
echo ""
echo -e "${CYAN}This script will:${NC}"
echo "  • Create a new LXC container for Open WebUI"
echo "  • Install Open WebUI (ChatGPT-like web interface)"
echo "  • Connect to your existing Ollama instance"
echo "  • Configure systemd service for auto-start"
echo "  • Ready to chat with AI models via web browser"
echo ""
read -r -p "Press Enter to continue..."
echo ""

# Prepare for installation
LOG_FILE="/tmp/openwebui-lxc-install-$(date +%Y%m%d-%H%M%S).log"

# Clean up old log files (keep only the 5 most recent)
if ls /tmp/openwebui-lxc-install-*.log 1> /dev/null 2>&1; then
    ls -t /tmp/openwebui-lxc-install-*.log | tail -n +6 | xargs -r rm -f
fi

# Initialize log file
echo "Starting Open WebUI LXC installation at $(date)" > "$LOG_FILE"

# Error handler - called on any error
error_handler() {
    local exit_code=$?
    local line_number=$1
    
    # Stop spinner if running
    if [ -n "$SPINNER_PID" ]; then
        kill "$SPINNER_PID" 2>/dev/null || true
        wait "$SPINNER_PID" 2>/dev/null || true
        SPINNER_PID=""
    fi
    
    # Show cursor
    tput cnorm 2>/dev/null || true
    
    # Clear line and show error
    echo -ne "\r\033[K"
    echo ""
    echo -e "${RED}✗ Failed: openwebui${NC}"
    echo ""
    echo -e "${YELLOW}An error occurred at line $line_number${NC}"
    echo -e "${CYAN}Check the log for details:${NC}"
    echo -e "  ${DIM}cat $LOG_FILE${NC}"
    echo ""
    echo -e "${DIM}Or view the last 50 lines:${NC}"
    echo -e "  ${DIM}tail -50 $LOG_FILE${NC}"
    echo ""
    
    exit $exit_code
}

# Set up error trap
trap 'error_handler $LINENO' ERR

# Progress indicator functions
show_progress() {
    local step=$1
    local total=$2
    local message=$3
    echo -ne "\r\033[K${CYAN}[Step $step/$total]${NC} $message..."
}

complete_progress() {
    echo -e "\r\033[K${GREEN}✓${NC} $1"
}

# Spinner for long-running commands
SPINNER_PID=""
start_spinner() {
    local message="$1"
    local spinner_chars="⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏"
    
    # Hide cursor
    tput civis
    
    (
        local i=0
        while true; do
            local char="${spinner_chars:$i:1}"
            echo -ne "\r\033[K${CYAN}${char}${NC} ${message}"
            i=$(( (i + 1) % ${#spinner_chars} ))
            sleep 0.1
        done
    ) &
    SPINNER_PID=$!
}

stop_spinner() {
    if [ -n "$SPINNER_PID" ]; then
        kill "$SPINNER_PID" 2>/dev/null || true
        wait "$SPINNER_PID" 2>/dev/null || true
        SPINNER_PID=""
    fi
    echo -ne "\r\033[K"
    # Show cursor
    tput cnorm
}

echo ""
echo -e "${CYAN}>>> Detecting existing Ollama containers...${NC}"
echo ""

# Find Ollama containers
OLLAMA_CONTAINERS=()
OLLAMA_IPS=()
OLLAMA_NAMES=()

while IFS= read -r line; do
    if [[ "$line" =~ ollama-(amd|nvidia) ]]; then
        CONTAINER_ID=$(echo "$line" | awk '{print $1}')
        CONTAINER_NAME=$(echo "$line" | awk '{print $3}')
        CONTAINER_IP=$(pct exec "$CONTAINER_ID" -- hostname -I 2>/dev/null | awk '{print $1}' || echo "")
        
        if [ -n "$CONTAINER_IP" ]; then
            # Check if Ollama is running
            if pct exec "$CONTAINER_ID" -- systemctl is-active --quiet ollama 2>/dev/null; then
                OLLAMA_CONTAINERS+=("$CONTAINER_ID")
                OLLAMA_IPS+=("$CONTAINER_IP")
                OLLAMA_NAMES+=("$CONTAINER_NAME")
            fi
        fi
    fi
done < <(pct list 2>/dev/null | tail -n +2)

if [ ${#OLLAMA_CONTAINERS[@]} -eq 0 ]; then
    echo -e "${RED}ERROR: No running Ollama containers found${NC}"
    echo ""
    echo -e "${YELLOW}Please create an Ollama LXC first:${NC}"
    echo -e "  ${GREEN}./host/ollama-nvidia.sh${NC}  ${DIM}(for NVIDIA GPUs)${NC}"
    echo -e "  ${GREEN}./host/ollama-amd.sh${NC}     ${DIM}(for AMD GPUs)${NC}"
    echo ""
    exit 1
fi

echo -e "${GREEN}✓ Found ${#OLLAMA_CONTAINERS[@]} Ollama container(s)${NC}"
echo ""

# If only one Ollama container, use it automatically
if [ ${#OLLAMA_CONTAINERS[@]} -eq 1 ]; then
    SELECTED_INDEX=0
    OLLAMA_CONTAINER_ID="${OLLAMA_CONTAINERS[0]}"
    OLLAMA_IP="${OLLAMA_IPS[0]}"
    OLLAMA_NAME="${OLLAMA_NAMES[0]}"
    
    echo -e "${CYAN}Connecting to:${NC} ${GREEN}${OLLAMA_NAME}${NC} ${DIM}(${OLLAMA_IP})${NC}"
    echo ""
else
    # Multiple containers - let user choose
    echo -e "${CYAN}Select which Ollama instance to connect to:${NC}"
    echo ""
    
    for i in "${!OLLAMA_CONTAINERS[@]}"; do
        echo -e "  ${GREEN}$((i+1)))${NC} ${OLLAMA_NAMES[$i]} ${DIM}(${OLLAMA_IPS[$i]})${NC}"
    done
    echo ""
    
    while true; do
        read -r -p "Enter selection [1]: " SELECTION
        SELECTION=${SELECTION:-1}
        
        if [[ "$SELECTION" =~ ^[0-9]+$ ]] && [ "$SELECTION" -ge 1 ] && [ "$SELECTION" -le ${#OLLAMA_CONTAINERS[@]} ]; then
            SELECTED_INDEX=$((SELECTION - 1))
            OLLAMA_CONTAINER_ID="${OLLAMA_CONTAINERS[$SELECTED_INDEX]}"
            OLLAMA_IP="${OLLAMA_IPS[$SELECTED_INDEX]}"
            OLLAMA_NAME="${OLLAMA_NAMES[$SELECTED_INDEX]}"
            break
        else
            echo -e "${RED}Invalid selection. Please enter a number between 1 and ${#OLLAMA_CONTAINERS[@]}${NC}"
        fi
    done
    
    echo ""
    echo -e "${CYAN}Selected:${NC} ${GREEN}${OLLAMA_NAME}${NC} ${DIM}(${OLLAMA_IP})${NC}"
    echo ""
fi

# Verify Ollama is accessible
echo -e "${CYAN}>>> Verifying Ollama connection...${NC}"
if curl -s "http://${OLLAMA_IP}:11434/api/tags" >/dev/null 2>&1; then
    echo -e "${GREEN}✓ Ollama API is accessible${NC}"
else
    echo -e "${YELLOW}⚠ Warning: Could not reach Ollama API at http://${OLLAMA_IP}:11434${NC}"
    echo -e "${YELLOW}  Open WebUI will be configured, but may not work until Ollama is accessible${NC}"
fi
echo ""

# ═══════════════════════════════════════════════════════════════
# STEP 1: Calculate defaults for LXC
# ═══════════════════════════════════════════════════════════════

echo -e "${CYAN}>>> Calculating recommended configuration...${NC}"
echo ""

# Find next available container ID
NEXT_ID=100
while pct status $NEXT_ID &>/dev/null; do
    ((NEXT_ID++))
done
CONTAINER_ID=$NEXT_ID

# Determine hostname based on connected Ollama instance
# Extract GPU type from Ollama name (e.g., "ollama-nvidia" -> "openwebui-nvidia")
if [[ "$OLLAMA_NAME" =~ ollama-(.*) ]]; then
    GPU_SUFFIX="${BASH_REMATCH[1]}"
    BASE_HOSTNAME="openwebui-${GPU_SUFFIX}"
else
    # Fallback if name doesn't match expected pattern
    BASE_HOSTNAME="openwebui"
fi

# Check if this hostname already exists, if so add numeric suffix
if pct list 2>/dev/null | grep -q "[[:space:]]${BASE_HOSTNAME}[[:space:]]"; then
    SUFFIX=2
    while pct list 2>/dev/null | grep -q "[[:space:]]${BASE_HOSTNAME}-${SUFFIX}[[:space:]]"; do
        ((SUFFIX++))
    done
    HOSTNAME="${BASE_HOSTNAME}-${SUFFIX}"
else
    HOSTNAME="${BASE_HOSTNAME}"
fi

# Calculate resources (Open WebUI includes sentence-transformers which needs torch/CUDA)
DISK_SIZE=20  # 20GB for Open WebUI + all dependencies (includes PyTorch + CUDA)
MEMORY=4      # 4GB RAM
SWAP=2        # 2GB swap
CORES=2       # 2 CPU cores

# Get network configuration from Proxmox
BRIDGE_INFO=$(ip -o -f inet addr show vmbr0 2>/dev/null | awk '{print $4}')
if [ -z "$BRIDGE_INFO" ]; then
    echo -e "${RED}ERROR: Could not detect vmbr0 network configuration${NC}"
    exit 1
fi

BRIDGE_CIDR=$(echo "$BRIDGE_INFO" | cut -d'/' -f2)
BRIDGE_NETWORK=$(echo "$BRIDGE_INFO" | cut -d'.' -f1-3)
GATEWAY=$(ip route show dev vmbr0 2>/dev/null | grep default | awk '{print $3}' | head -1)

# Find next available IP
BASE_IP=200
while ping -c 1 -W 1 "${BRIDGE_NETWORK}.${BASE_IP}" &>/dev/null || pct list 2>/dev/null | grep -q "${BRIDGE_NETWORK}.${BASE_IP}"; do
    ((BASE_IP++))
    if [ $BASE_IP -gt 250 ]; then
        echo -e "${YELLOW}Warning: IP range 200-250 exhausted, using higher range${NC}"
        BASE_IP=101
        break
    fi
done
IP_ADDRESS="${BRIDGE_NETWORK}.${BASE_IP}"

# Determine storage
STORAGE=$(pvesm status -content rootdir 2>/dev/null | awk 'NR==2 {print $1}')
if [ -z "$STORAGE" ]; then
    echo -e "${RED}No suitable storage found${NC}"
    echo -e "${YELLOW}Make sure you have storage configured with 'rootdir' content type${NC}"
    exit 1
fi

# ═══════════════════════════════════════════════════════════════
# STEP 2: Show configuration and confirm
# ═══════════════════════════════════════════════════════════════

echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${CYAN}Proposed Configuration:${NC}"
echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""
echo -e "  ${CYAN}Container ID:${NC}    ${GREEN}$CONTAINER_ID${NC}"
echo -e "  ${CYAN}Hostname:${NC}        ${GREEN}$HOSTNAME${NC}"
echo -e "  ${CYAN}IP Address:${NC}      ${GREEN}$IP_ADDRESS/$BRIDGE_CIDR${NC}"
echo -e "  ${CYAN}Gateway:${NC}         ${GREEN}$GATEWAY${NC}"
echo -e "  ${CYAN}Storage:${NC}         ${GREEN}$STORAGE${NC}"
echo -e "  ${CYAN}Disk Size:${NC}       ${GREEN}${DISK_SIZE}GB${NC}"
echo -e "  ${CYAN}Memory:${NC}          ${GREEN}${MEMORY}GB${NC}"
echo -e "  ${CYAN}Swap:${NC}            ${GREEN}${SWAP}GB${NC}"
echo -e "  ${CYAN}CPU Cores:${NC}       ${GREEN}$CORES${NC}"
echo ""
echo -e "  ${CYAN}Ollama Instance:${NC} ${GREEN}${OLLAMA_NAME}${NC} ${DIM}(http://${OLLAMA_IP}:11434)${NC}"
echo ""
echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""

read -r -p "Proceed with this configuration? [Y/n]: " CONFIRM
CONFIRM=${CONFIRM:-Y}
if [[ ! "$CONFIRM" =~ ^[Yy]$ ]]; then
    echo -e "${YELLOW}Installation cancelled${NC}"
    exit 0
fi

echo ""

# ═══════════════════════════════════════════════════════════════
# STEP 3: Get root password
# ═══════════════════════════════════════════════════════════════

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

if [ -z "$ROOT_PASSWORD" ]; then
    echo -e "${RED}ERROR: Password cannot be empty${NC}"
    exit 1
fi

echo ""
echo -e "${GREEN}✓ Password set${NC}"
echo ""

# ═══════════════════════════════════════════════════════════════
# STEP 4: Download template if needed
# ═══════════════════════════════════════════════════════════════

TEMPLATE_NAME="ubuntu-24.04-standard_24.04-2_amd64.tar.zst"
TEMPLATE_PATH="/var/lib/vz/template/cache/$TEMPLATE_NAME"

if [ ! -f "$TEMPLATE_PATH" ]; then
    echo -e "${YELLOW}Downloading Ubuntu 24.04 template (~135MB)...${NC}"
    if pveam download local "$TEMPLATE_NAME" >> "$LOG_FILE" 2>&1; then
        echo -e "${GREEN}✓ Template downloaded${NC}"
        echo ""
    else
        echo -e "${RED}✗ Failed to download template${NC}"
        echo -e "${YELLOW}Check log: $LOG_FILE${NC}"
        exit 1
    fi
fi

# ═══════════════════════════════════════════════════════════════
# STEP 5: Create and configure LXC
# ═══════════════════════════════════════════════════════════════

TOTAL_STEPS=7

# Clear screen and show header for installation phase
clear
echo ""
echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${GREEN}Installing Open WebUI LXC Container${NC}"
echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo "  Container ID: $CONTAINER_ID | IP: $IP_ADDRESS"
echo "  Resources: ${DISK_SIZE}GB disk, ${MEMORY}GB RAM, $CORES cores"
echo ""
echo -e "${CYAN}📋 Installation Log:${NC}"
echo "  File: $LOG_FILE"
echo -e "  Watch live: ${YELLOW}tail -f $LOG_FILE${NC}"
echo ""
show_progress 1 $TOTAL_STEPS "Creating container"

{
    pct create $CONTAINER_ID \
        "$TEMPLATE_PATH" \
        --hostname "$HOSTNAME" \
        --memory $((MEMORY * 1024)) \
        --cores $CORES \
        --swap $((SWAP * 1024)) \
        --net0 name=eth0,bridge=vmbr0,ip=${IP_ADDRESS}/${BRIDGE_CIDR},gw=${GATEWAY} \
        --storage "$STORAGE" \
        --rootfs "$STORAGE:${DISK_SIZE}" \
        --unprivileged 1 \
        --features nesting=1 \
        --start 0
} >> "$LOG_FILE" 2>&1

complete_progress "Container created"
show_progress 2 $TOTAL_STEPS "Starting container"

pct start $CONTAINER_ID >> "$LOG_FILE" 2>&1
sleep 5

complete_progress "Container started"
show_progress 3 $TOTAL_STEPS "Setting password and SSH"

{
    pct exec $CONTAINER_ID -- bash -c "echo 'root:$ROOT_PASSWORD' | chpasswd"
    
    # Enable password authentication for SSH
    pct exec $CONTAINER_ID -- sed -i 's/^#*PermitRootLogin.*/PermitRootLogin yes/' /etc/ssh/sshd_config
    pct exec $CONTAINER_ID -- sed -i 's/^#*PasswordAuthentication.*/PasswordAuthentication yes/' /etc/ssh/sshd_config
    pct exec $CONTAINER_ID -- systemctl restart ssh
} >> "$LOG_FILE" 2>&1

complete_progress "Password and SSH configured"

# Install Open WebUI
show_progress 4 $TOTAL_STEPS "Updating system packages"
pct exec $CONTAINER_ID -- apt update -qq >> "$LOG_FILE" 2>&1

# Count packages to upgrade
PACKAGE_COUNT=$(pct exec $CONTAINER_ID -- apt list --upgradable 2>/dev/null | grep -c "upgradable")

if [ "$PACKAGE_COUNT" -gt 0 ]; then
    echo "Upgrading $PACKAGE_COUNT packages..." >> "$LOG_FILE"
    start_spinner "${CYAN}[Step 4/$TOTAL_STEPS]${NC} Upgrading $PACKAGE_COUNT packages - this may take 2-5 minutes..."
    pct exec $CONTAINER_ID -- bash -c "DEBIAN_FRONTEND=noninteractive apt upgrade -y -o Dpkg::Options::='--force-confdef' -o Dpkg::Options::='--force-confold'" >> "$LOG_FILE" 2>&1
    stop_spinner
fi

complete_progress "System packages updated ($PACKAGE_COUNT packages)"

# Install prerequisites (ffmpeg has 950+ package dependencies, takes time)
echo "Installing prerequisites..." >> "$LOG_FILE"
start_spinner "${CYAN}[Step 5/$TOTAL_STEPS]${NC} Installing prerequisites - ffmpeg plus 950 dependencies, 2-4 minutes..."
pct exec $CONTAINER_ID -- apt install -y curl wget gnupg2 ffmpeg python3-pip >> "$LOG_FILE" 2>&1
stop_spinner
complete_progress "Prerequisites installed"

# Install uv and Open WebUI
echo "Installing uv (Python package installer)..." >> "$LOG_FILE"
start_spinner "${CYAN}[Step 6/$TOTAL_STEPS]${NC} Installing Open WebUI - 3-5 minutes..."

pct exec $CONTAINER_ID -- bash -c "
    # Install uv
    curl -LsSf https://astral.sh/uv/install.sh | sh
    
    # Install Open WebUI (includes sentence-transformers + PyTorch/CUDA for local embeddings)
    # Increase timeout for large packages (torch is 858MB)
    export UV_HTTP_TIMEOUT=300
    /root/.local/bin/uv tool install --python 3.12 open-webui
" >> "$LOG_FILE" 2>&1

stop_spinner
complete_progress "Open WebUI installed"

# Configure Open WebUI service
show_progress 7 $TOTAL_STEPS "Configuring Open WebUI service"

{
    # Create environment file with Ollama URL
    pct exec $CONTAINER_ID -- bash -c "cat > /root/.env << 'ENVEOF'
OLLAMA_BASE_URL=http://${OLLAMA_IP}:11434
ENABLE_OLLAMA_API=false
DATA_DIR=/root/.open-webui
ENVEOF"

    # Create systemd service
    pct exec $CONTAINER_ID -- bash -c 'cat > /etc/systemd/system/open-webui.service << '\''SERVICEEOF'\''
[Unit]
Description=Open WebUI Service
After=network.target

[Service]
Type=simple
EnvironmentFile=/root/.env
ExecStart=/root/.local/bin/open-webui serve
WorkingDirectory=/root
Restart=on-failure
RestartSec=5
User=root

[Install]
WantedBy=multi-user.target
SERVICEEOF'

    pct exec $CONTAINER_ID -- systemctl daemon-reload
    pct exec $CONTAINER_ID -- systemctl enable open-webui
    pct exec $CONTAINER_ID -- systemctl start open-webui
    sleep 3
} >> "$LOG_FILE" 2>&1

complete_progress "Open WebUI configured and running"

# Clear screen and show completion message
clear
echo ""

echo ""
echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${GREEN}                 🎉  Open WebUI LXC Complete!${NC}"
echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""
echo -e "${CYAN}📋 Container Info:${NC}"
echo -e "   Hostname:     ${GREEN}$HOSTNAME${NC}"
echo -e "   IP Address:   ${GREEN}$IP_ADDRESS${NC}"
echo -e "   Container ID: ${GREEN}$CONTAINER_ID${NC}"
echo -e "   Web UI:       ${GREEN}http://$IP_ADDRESS:8080${NC}"
echo ""
echo -e "${CYAN}🔗 Connected to Ollama:${NC}"
echo -e "   Instance:     ${GREEN}${OLLAMA_NAME}${NC}"
echo -e "   API URL:      ${GREEN}http://${OLLAMA_IP}:11434${NC}"
echo ""
echo -e "${CYAN}📄 Installation Log:${NC} ${GREEN}$LOG_FILE${NC}"

echo ""
echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${CYAN}🚀 Quick Start:${NC}"
echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""
echo -e "${CYAN}1. Open Open WebUI in your browser:${NC}"
echo -e "   ${GREEN}http://$IP_ADDRESS:8080${NC}"
echo ""
echo -e "${CYAN}2. Create your account:${NC}"
echo -e "   ${YELLOW}→ First user to sign up becomes the admin${NC}"
echo ""
echo -e "${CYAN}3. Start chatting:${NC}"
echo -e "   ${YELLOW}→ Select a model from the dropdown${NC}"
echo -e "   ${YELLOW}→ If no models appear, pull them in your Ollama container:${NC}"
echo -e "   ${GREEN}ssh root@${OLLAMA_IP}${NC}"
echo -e "   ${GREEN}ollama pull llama3.2:3b${NC}"
echo ""
echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${CYAN}📚 Next Steps:${NC}"
echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""
echo -e "${CYAN}🔄 Update Open WebUI (when new versions are released):${NC}"
echo -e "   ${GREEN}ssh root@$IP_ADDRESS${NC}"
echo -e "   ${GREEN}systemctl stop open-webui${NC}"
echo -e "   ${GREEN}/root/.local/bin/uv tool install --python 3.12 open-webui[all]${NC}"
echo -e "   ${GREEN}systemctl start open-webui${NC}"
echo ""
echo -e "${CYAN}🔍 Check service status:${NC}"
echo -e "   ${GREEN}ssh root@$IP_ADDRESS${NC}"
echo -e "   ${GREEN}systemctl status open-webui${NC}"
echo ""
echo -e "${CYAN}📊 View logs:${NC}"
echo -e "   ${GREEN}ssh root@$IP_ADDRESS${NC}"
echo -e "   ${GREEN}journalctl -u open-webui -f${NC}"
echo ""
echo -e "${CYAN}🔒 Credentials:${NC}"
echo -e "   Root Password: ${GREEN}$ROOT_PASSWORD${NC}"
echo ""

echo -e "${GREEN}✓ Completed: openwebui${NC}"
echo ""
read -r -p "Press Enter to continue..."

