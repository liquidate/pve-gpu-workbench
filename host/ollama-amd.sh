#!/usr/bin/env bash
# SCRIPT_DESC: Create Ollama LXC (AMD GPU)
# SCRIPT_DETECT: 

# All-in-one script: Creates GPU-enabled LXC + Installs Ollama natively
# Optimized for AMD GPUs with ROCm support

set -e

# Get script directory and source utilities
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/../includes/colors.sh"

echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}Ollama LXC Creation${NC}"
echo -e "${GREEN}========================================${NC}"
echo ""
echo -e "${CYAN}This script will:${NC}"
echo "  • Create a new GPU-enabled LXC container"
echo "  • Pass through AMD GPU for hardware acceleration"
echo "  • Install Ollama with full GPU support"
echo "  • Configure systemd service for auto-start"
echo "  • Ready to run AI models locally"
echo ""

# Check for AMD GPU
echo -e "${GREEN}>>> Detecting AMD GPU...${NC}"
if ! lspci -nn | grep -i "VGA\|3D\|Display" | grep -qi amd; then
    echo -e "${RED}ERROR: No AMD GPU detected on this system${NC}"
    echo ""
    echo -e "${YELLOW}Available GPUs:${NC}"
    lspci -nn | grep -i "VGA\|3D\|Display"
    echo ""
    echo -e "${YELLOW}This script is for AMD GPUs only.${NC}"
    echo -e "${YELLOW}For NVIDIA GPUs, use script 040 - create-nvidia-ollama-lxc.sh${NC}"
    exit 1
fi
echo -e "${GREEN}✓ AMD GPU detected${NC}"

# Prepare for installation
LOG_FILE="/tmp/ollama-lxc-install-$(date +%Y%m%d-%H%M%S).log"

# Clean up old log files (keep only the 5 most recent)
if ls /tmp/ollama-lxc-install-*.log 1> /dev/null 2>&1; then
    ls -t /tmp/ollama-lxc-install-*.log | tail -n +6 | xargs -r rm -f
fi

# Initialize log file
echo "Starting Ollama LXC installation at $(date)" > "$LOG_FILE"

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

echo ""
echo -e "${CYAN}>>> Calculating recommended configuration...${NC}"
echo ""

# ═══════════════════════════════════════════════════════════════
# STEP 1: Calculate ALL defaults (silently, no prompting)
# ═══════════════════════════════════════════════════════════════

# Detect GPU PCI address
GPU_PCI_PATH=""
GPU_MODEL=""
for card in /dev/dri/by-path/pci-*-card; do
    if [ -e "$card" ]; then
        pci_addr=$(basename "$card" | sed 's/pci-\(.*\)-card/\1/')
        gpu_info=$(lspci -s "${pci_addr#0000:}" 2>/dev/null | grep -i "VGA\|3D\|Display" || echo "")
        if echo "$gpu_info" | grep -qi amd; then
            GPU_PCI_PATH="$pci_addr"
            GPU_MODEL=$(echo "$gpu_info" | sed -E 's/.*\[AMD\/ATI\] //' | sed -E 's/ \(rev.*\)//')
            break
        fi
    fi
done

if [ -z "$GPU_PCI_PATH" ]; then
    echo -e "${RED}ERROR: Could not detect GPU PCI path${NC}"
    exit 1
fi

# Find next available container ID
NEXT_ID=100
while pct status $NEXT_ID &>/dev/null; do
    ((NEXT_ID++))
done
CONTAINER_ID=$NEXT_ID

# Determine hostname
BASE_HOSTNAME="ollama"
if pct list 2>/dev/null | grep -q "[[:space:]]${BASE_HOSTNAME}[[:space:]]"; then
    SUFFIX=2
    while pct list 2>/dev/null | grep -q "[[:space:]]${BASE_HOSTNAME}-${SUFFIX}[[:space:]]"; do
        ((SUFFIX++))
    done
    HOSTNAME="${BASE_HOSTNAME}-${SUFFIX}"
else
    HOSTNAME="${BASE_HOSTNAME}"
fi

# Detect network configuration
BRIDGE_IP=$(ip -4 addr show vmbr0 | grep -oP '(?<=inet\s)\d+\.\d+\.\d+\.\d+')
BRIDGE_CIDR=$(ip -4 addr show vmbr0 | grep -oP '(?<=inet\s)\d+\.\d+\.\d+\.\d+/\d+' | cut -d'/' -f2)
SUBNET=$(echo "$BRIDGE_IP" | cut -d'.' -f1-3)
GATEWAY=$(ip route show default | grep -oP '(?<=via )\d+\.\d+\.\d+\.\d+' | head -n1)

# Find available IP
SUGGESTED_IP=""
for i in {100..200}; do
    TEST_IP="${SUBNET}.${i}"
    if [ "$TEST_IP" = "$BRIDGE_IP" ]; then
        continue
    fi
    if ! ping -c 1 -W 1 "$TEST_IP" &>/dev/null; then
        if ! timeout 1 arping -c 1 -I vmbr0 "$TEST_IP" &>/dev/null 2>&1; then
            if ! grep -r "ip=${TEST_IP}/" /etc/pve/lxc/ /etc/pve/qemu-server/ 2>/dev/null | grep -q .; then
                SUGGESTED_IP="$TEST_IP"
                break
            fi
        fi
    fi
done

if [ -z "$SUGGESTED_IP" ]; then
    SUGGESTED_IP="${SUBNET}.100"
fi
IP_ADDRESS="$SUGGESTED_IP"

# Detect available storage pools (container-compatible, sorted by space)
declare -a STORAGE_NAMES
declare -A STORAGE_INFO
declare -a STORAGE_LIST
INDEX=1

while IFS= read -r line; do
    name=$(echo "$line" | awk '{print $1}')
    type=$(echo "$line" | awk '{print $2}')
    avail=$(echo "$line" | awk '{print $4}')
    
    if grep -A 10 "^${type}: ${name}$" /etc/pve/storage.cfg 2>/dev/null | grep -q "content.*rootdir"; then
        STORAGE_LIST+=("${INDEX}|${name}|${avail}")
        ((INDEX++))
    fi
done < <(pvesm status | tail -n +2)

if [ ${#STORAGE_LIST[@]} -eq 0 ]; then
    echo -e "${RED}No suitable storage found${NC}"
    echo -e "${YELLOW}Make sure you have storage configured with 'rootdir' content type${NC}"
    exit 1
fi

# Sort by available space and populate arrays
INDEX=1
while IFS='|' read -r _ name avail; do
    STORAGE_NAMES[$INDEX]=$name
    STORAGE_INFO[$name]=$avail
    if [ $INDEX -eq 1 ]; then
        STORAGE="$name"  # Default to largest
        STORAGE_AVAIL_GB=$(awk "BEGIN {printf \"%.0f\", $avail / 1024 / 1024}")
    fi
    ((INDEX++))
done < <(printf '%s\n' "${STORAGE_LIST[@]}" | sort -t'|' -k3 -rn)

# Resource allocation defaults
TOTAL_RAM_GB=$(free -g | awk '/^Mem:/{print $2}')
GPU_VRAM_ALLOCATED=0
if grep -q "amdgpu.gttsize=98304" /proc/cmdline 2>/dev/null; then
    GPU_VRAM_ALLOCATED=96
elif grep -q "amdgpu.gttsize" /proc/cmdline 2>/dev/null; then
    GPU_VRAM_ALLOCATED=$(grep -oP 'amdgpu.gttsize=\K\d+' /proc/cmdline | head -n1)
    GPU_VRAM_ALLOCATED=$((GPU_VRAM_ALLOCATED / 1024))
fi

AVAILABLE_RAM=$((TOTAL_RAM_GB - GPU_VRAM_ALLOCATED - 4))
if [ $AVAILABLE_RAM -lt 0 ]; then
    AVAILABLE_RAM=$((TOTAL_RAM_GB - 4))
fi

# Smart defaults
DISK_SIZE=256
MEMORY=16
CORES=12
SWAP=8

# Adjust if limited RAM
if [ $AVAILABLE_RAM -lt 16 ]; then
    DISK_SIZE=128
    MEMORY=8
    CORES=6
    SWAP=4
fi

# ═══════════════════════════════════════════════════════════════
# STEP 2: Show summary of planned configuration
# ═══════════════════════════════════════════════════════════════

echo -e "${GREEN}✓ Configuration calculated${NC}"
echo ""
echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${CYAN}Planned Configuration:${NC}"
echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""
echo -e "${BOLD}Container:${NC}"
echo "  ID: $CONTAINER_ID"
echo "  Hostname: $HOSTNAME"
echo ""
echo -e "${BOLD}GPU:${NC}"
echo "  Model: $GPU_MODEL"
echo "  PCI: $GPU_PCI_PATH"
echo ""
echo -e "${BOLD}Network:${NC}"
echo "  IP: $IP_ADDRESS/$BRIDGE_CIDR"
echo "  Gateway: $GATEWAY"
echo "  Bridge: vmbr0"
echo ""
echo -e "${BOLD}Storage:${NC}"
echo "  Pool: $STORAGE ($STORAGE_AVAIL_GB GB available)"
echo "  Disk: ${DISK_SIZE}GB"
echo ""
echo -e "${BOLD}Resources:${NC}"
echo "  RAM: ${MEMORY}GB (of ${AVAILABLE_RAM}GB available)"
echo "  CPU Cores: $CORES"
echo "  Swap: ${SWAP}GB"
echo ""
echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""
read -r -p "Proceed with this configuration? [Y/n] (enter 'n' to customize): " PROCEED
PROCEED=${PROCEED:-Y}
echo ""

# ═══════════════════════════════════════════════════════════════
# STEP 3: Handle customization if requested
# ═══════════════════════════════════════════════════════════════

if [[ ! "$PROCEED" =~ ^[Yy]$ ]]; then
    echo -e "${YELLOW}Entering customization mode...${NC}"
    echo ""
    
    # Customize Container ID
    while true; do
        read -r -p "Container ID [$CONTAINER_ID]: " CUSTOM_ID
        CUSTOM_ID=${CUSTOM_ID:-$CONTAINER_ID}
        
        if ! [[ "$CUSTOM_ID" =~ ^[0-9]+$ ]]; then
            echo -e "${RED}Invalid ID: must be a number${NC}"
            continue
        fi
        
        if pct status $CUSTOM_ID &>/dev/null && [ "$CUSTOM_ID" != "$CONTAINER_ID" ]; then
            echo -e "${RED}Container ID $CUSTOM_ID already exists${NC}"
            continue
        fi
        
        CONTAINER_ID=$CUSTOM_ID
        break
    done
    
    # Customize Hostname
    read -r -p "Hostname [$HOSTNAME]: " CUSTOM_HOSTNAME
    HOSTNAME=${CUSTOM_HOSTNAME:-$HOSTNAME}
    
    # Customize IP Address
    while true; do
        read -r -p "IP Address [$IP_ADDRESS]: " CUSTOM_IP
        CUSTOM_IP=${CUSTOM_IP:-$IP_ADDRESS}
        
        if [[ ! "$CUSTOM_IP" =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]]; then
            echo -e "${RED}Invalid IP format${NC}"
            continue
        fi
        
        IP_ADDRESS=$CUSTOM_IP
        break
    done
    
    # Customize Gateway
    while true; do
        read -r -p "Gateway [$GATEWAY]: " CUSTOM_GW
        CUSTOM_GW=${CUSTOM_GW:-$GATEWAY}
        
        if [[ ! "$CUSTOM_GW" =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]]; then
            echo -e "${RED}Invalid gateway format${NC}"
            continue
        fi
        
        GATEWAY=$CUSTOM_GW
        break
    done
    
    # Customize Storage
    echo ""
    echo "Available storage pools:"
    for i in "${!STORAGE_NAMES[@]}"; do
        name="${STORAGE_NAMES[$i]}"
        avail="${STORAGE_INFO[$name]}"
        avail_gb=$(awk "BEGIN {printf \"%.0f\", $avail / 1024 / 1024}")
        printf "  [%d] %-20s %6s GB available\n" "$i" "$name" "$avail_gb"
    done
    echo ""
    read -r -p "Select storage pool [1]: " STORAGE_CHOICE
    STORAGE_CHOICE=${STORAGE_CHOICE:-1}
    
    if [ -n "${STORAGE_NAMES[$STORAGE_CHOICE]}" ]; then
        STORAGE="${STORAGE_NAMES[$STORAGE_CHOICE]}"
    fi
    
    # Customize Resources
    echo ""
    read -r -p "Disk size in GB [$DISK_SIZE]: " CUSTOM_DISK
    DISK_SIZE=${CUSTOM_DISK:-$DISK_SIZE}
    
    read -r -p "RAM in GB [$MEMORY]: " CUSTOM_MEM
    MEMORY=${CUSTOM_MEM:-$MEMORY}
    
    read -r -p "CPU cores [$CORES]: " CUSTOM_CORES
    CORES=${CUSTOM_CORES:-$CORES}
    
    read -r -p "Swap in GB [$SWAP]: " CUSTOM_SWAP
    SWAP=${CUSTOM_SWAP:-$SWAP}
    
    echo ""
    echo -e "${GREEN}✓ Configuration updated${NC}"
    echo ""
fi

# ═══════════════════════════════════════════════════════════════
# STEP 4: Get root password
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
# STEP 5: Prepare for installation
# ═══════════════════════════════════════════════════════════════

# Check if Ubuntu template exists, download if needed
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

# Create LXC container
TOTAL_STEPS=9

# Clear screen and show header for installation phase
clear
echo ""
echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${GREEN}Installing Ollama LXC Container${NC}"
echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo "  Container ID: $CONTAINER_ID | IP: $IP_ADDRESS"
echo "  Resources: ${DISK_SIZE}GB disk, ${MEMORY}GB RAM, $CORES cores"
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
        --unprivileged 0 \
        --features nesting=1 \
        --start 0
} >> "$LOG_FILE" 2>&1

complete_progress "Container created"
show_progress 2 $TOTAL_STEPS "Configuring GPU passthrough"

# Configure GPU passthrough

# Add GPU device mappings to LXC config
{
    cat >> /etc/pve/lxc/${CONTAINER_ID}.conf << EOF

# AMD GPU passthrough
lxc.cgroup2.devices.allow: c 226:* rwm
lxc.cgroup2.devices.allow: c 234:* rwm
lxc.mount.entry: /dev/dri/by-path/pci-${GPU_PCI_PATH}-card dev/dri/card0 none bind,optional,create=file 0 0
lxc.mount.entry: /dev/dri/by-path/pci-${GPU_PCI_PATH}-render dev/dri/renderD128 none bind,optional,create=file 0 0
lxc.mount.entry: /dev/kfd dev/kfd none bind,optional,create=file 0 0
EOF
} >> "$LOG_FILE" 2>&1

complete_progress "GPU passthrough configured"
show_progress 3 $TOTAL_STEPS "Starting container"

# Start container
pct start $CONTAINER_ID >> "$LOG_FILE" 2>&1
sleep 5

complete_progress "Container started"

# Set root password (already collected earlier)
show_progress 4 $TOTAL_STEPS "Setting password and SSH"

{
    pct exec $CONTAINER_ID -- bash -c "echo 'root:$ROOT_PASSWORD' | chpasswd"

    # Enable password authentication for SSH
    pct exec $CONTAINER_ID -- sed -i 's/^#*PermitRootLogin.*/PermitRootLogin yes/' /etc/ssh/sshd_config
    pct exec $CONTAINER_ID -- sed -i 's/^#*PasswordAuthentication.*/PasswordAuthentication yes/' /etc/ssh/sshd_config
    pct exec $CONTAINER_ID -- systemctl restart ssh
} >> "$LOG_FILE" 2>&1

complete_progress "Password and SSH configured"
show_progress 5 $TOTAL_STEPS "Verifying GPU passthrough"

# Verify GPU passthrough inside container
if pct exec $CONTAINER_ID -- test -e /dev/dri/card0 && \
   pct exec $CONTAINER_ID -- test -e /dev/dri/renderD128 && \
   pct exec $CONTAINER_ID -- test -e /dev/kfd; then
    complete_progress "GPU passthrough verified"
else
    echo -e "${RED}ERROR: GPU devices not accessible inside container${NC}"
    echo "Troubleshooting:"
    echo "  pct exec $CONTAINER_ID -- ls -la /dev/dri/"
    echo "  pct exec $CONTAINER_ID -- ls -la /dev/kfd"
    exit 1
fi

# Install Ollama
show_progress 6 $TOTAL_STEPS "Updating system packages"

{
    pct exec $CONTAINER_ID -- apt update -qq
    
    # Count packages to upgrade
    PACKAGE_COUNT=$(pct exec $CONTAINER_ID -- apt list --upgradable 2>/dev/null | grep -c "upgradable")
    
    if [ "$PACKAGE_COUNT" -gt 0 ]; then
        pct exec $CONTAINER_ID -- bash -c "DEBIAN_FRONTEND=noninteractive apt upgrade -y -o Dpkg::Options::='--force-confdef' -o Dpkg::Options::='--force-confold'"
    fi
} >> "$LOG_FILE" 2>&1

complete_progress "System packages updated ($PACKAGE_COUNT packages)"
show_progress 7 $TOTAL_STEPS "Installing Ollama and ROCm utilities"

{
    pct exec $CONTAINER_ID -- apt install -y curl wget gnupg2
    
    # Install ROCm utilities
    pct exec $CONTAINER_ID -- bash -c "
        mkdir -p --mode=0755 /etc/apt/keyrings
        wget -q https://repo.radeon.com/rocm/rocm.gpg.key -O - | gpg --dearmor | tee /etc/apt/keyrings/rocm.gpg > /dev/null
        echo 'deb [arch=amd64 signed-by=/etc/apt/keyrings/rocm.gpg] https://repo.radeon.com/rocm/apt/6.2.4 noble main' | tee /etc/apt/sources.list.d/rocm.list > /dev/null
        apt update -qq
        apt install -y hsa-rocr rocm-core rocm-smi rocminfo radeontop
    "
    
    # Install Ollama
    pct exec $CONTAINER_ID -- bash -c "curl -fsSL https://ollama.com/install.sh | sh"
} >> "$LOG_FILE" 2>&1

complete_progress "Ollama and ROCm utilities installed"
show_progress 8 $TOTAL_STEPS "Configuring Ollama service"
{
    # Create systemd override to set OLLAMA_HOST
    pct exec $CONTAINER_ID -- mkdir -p /etc/systemd/system/ollama.service.d
    pct exec $CONTAINER_ID -- bash -c 'cat > /etc/systemd/system/ollama.service.d/override.conf << "EOFMARKER"
[Service]
Environment="OLLAMA_HOST=0.0.0.0:11434"
EOFMARKER'

    pct exec $CONTAINER_ID -- systemctl daemon-reload
    pct exec $CONTAINER_ID -- systemctl enable ollama
    pct exec $CONTAINER_ID -- systemctl restart ollama
    sleep 3
} >> "$LOG_FILE" 2>&1

complete_progress "Ollama configured and running"

# Create update command inside the container
pct exec $CONTAINER_ID -- bash -c 'cat > /usr/local/bin/update << '\''UPDATEEOF'\''
#!/usr/bin/env bash
#
# Update Ollama to the latest version
#

set -e

GREEN='\''\033[0;32m'\''
YELLOW='\''\033[1;33m'\''
CYAN='\''\033[0;36m'\''
NC='\''\033[0m'\''

echo ""
echo -e "${GREEN}╔══════════════════════════════════════╗${NC}"
echo -e "${GREEN}║      Ollama Update                   ║${NC}"
echo -e "${GREEN}╚══════════════════════════════════════╝${NC}"
echo ""

# Show current version
if command -v ollama &>/dev/null; then
    CURRENT_VERSION=$(ollama --version 2>/dev/null | grep -oP '\''ollama version is \K[0-9.]+'\'' || echo "unknown")
    echo -e "${CYAN}Current Ollama version:${NC} $CURRENT_VERSION"
else
    echo -e "${YELLOW}Ollama not found${NC}"
    CURRENT_VERSION="not installed"
fi

# Fetch latest version from GitHub
echo -e "${CYAN}Checking for updates...${NC}"
LATEST_VERSION=$(curl -s https://api.github.com/repos/ollama/ollama/releases/latest | grep -oP '\''"tag_name": "v\K[0-9.]+'\'' 2>/dev/null || echo "unknown")

if [ "$LATEST_VERSION" = "unknown" ]; then
    echo -e "${YELLOW}Could not fetch latest version. Proceeding anyway...${NC}"
elif [ "$CURRENT_VERSION" = "$LATEST_VERSION" ]; then
    echo ""
    echo -e "${GREEN}✓ Already on latest version: $CURRENT_VERSION${NC}"
    echo ""
    exit 0
else
    echo -e "${YELLOW}Update available: $CURRENT_VERSION → $LATEST_VERSION${NC}"
fi

echo ""
read -p "Update Ollama to the latest version? [Y/n]: " UPDATE
UPDATE=${UPDATE:-Y}

if [[ ! "$UPDATE" =~ ^[Yy]$ ]]; then
    echo "Update cancelled."
    exit 0
fi

echo ""
echo -e "${CYAN}>>> Downloading and installing Ollama $LATEST_VERSION...${NC}"
curl -fsSL https://ollama.com/install.sh | sh

echo ""
echo -e "${CYAN}>>> Restarting Ollama service...${NC}"
systemctl restart ollama

# Wait a moment for service to start
sleep 2

if systemctl is-active --quiet ollama; then
    NEW_VERSION=$(ollama --version 2>/dev/null | grep -oP '\''ollama version is \K[0-9.]+'\'' || echo "unknown")
    echo ""
    echo -e "${GREEN}✓ Ollama updated successfully!${NC}"
    if [ "$CURRENT_VERSION" != "$NEW_VERSION" ]; then
        echo -e "${CYAN}Version:${NC} $CURRENT_VERSION → $NEW_VERSION"
    else
        echo -e "${CYAN}Already on latest version:${NC} $NEW_VERSION"
    fi
    echo ""
else
    echo -e "${YELLOW}⚠  Service may need manual restart${NC}"
    exit 1
fi
UPDATEEOF
chmod +x /usr/local/bin/update' >> "$LOG_FILE" 2>&1

# Create gpu-verify command inside the container
pct exec $CONTAINER_ID -- bash -c 'cat > /usr/local/bin/gpu-verify << '\''GPUVERIFYEOF'\''
#!/usr/bin/env bash
#
# GPU Verification for LXC Container
# Checks if AMD GPU is accessible and functional
#

GREEN='\''\033[0;32m'\''
RED='\''\033[0;31m'\''
YELLOW='\''\033[1;33m'\''
CYAN='\''\033[0;36m'\''
NC='\''\033[0m'\''

echo ""
echo -e "${GREEN}╔══════════════════════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║         GPU Verification - LXC Container                     ║${NC}"
echo -e "${GREEN}╚══════════════════════════════════════════════════════════════╝${NC}"
echo ""

# Track results
CHECKS_PASSED=0
CHECKS_TOTAL=0

check_result() {
    local status=$1
    local message=$2
    ((CHECKS_TOTAL++))
    if [ "$status" -eq 0 ]; then
        echo -e "${GREEN}✓${NC} $message"
        ((CHECKS_PASSED++))
    else
        echo -e "${RED}✗${NC} $message"
    fi
}

echo -e "${CYAN}═══ GPU DEVICE FILES ═══${NC}"

# Check for DRI devices
if [ -e /dev/dri/card0 ]; then
    check_result 0 "/dev/dri/card0 present"
else
    check_result 1 "/dev/dri/card0 missing"
fi

if [ -e /dev/dri/renderD128 ]; then
    check_result 0 "/dev/dri/renderD128 present"
else
    check_result 1 "/dev/dri/renderD128 missing"
fi

# Check for KFD (ROCm compute interface)
if [ -e /dev/kfd ]; then
    check_result 0 "/dev/kfd present (ROCm compute interface)"
else
    check_result 1 "/dev/kfd missing (ROCm compute unavailable)"
fi

# Check permissions
if [ -r /dev/dri/card0 ] && [ -w /dev/dri/card0 ]; then
    check_result 0 "/dev/dri/card0 has read/write permissions"
else
    check_result 1 "/dev/dri/card0 lacks read/write permissions"
fi

if [ -r /dev/kfd ] && [ -w /dev/kfd ]; then
    check_result 0 "/dev/kfd has read/write permissions"
else
    check_result 1 "/dev/kfd lacks read/write permissions"
fi

echo ""
echo -e "${CYAN}═══ ROCM TOOLS ═══${NC}"

# Check for ROCm tools
if command -v rocm-smi >/dev/null 2>&1; then
    check_result 0 "rocm-smi installed"
else
    check_result 1 "rocm-smi not installed"
fi

if command -v rocminfo >/dev/null 2>&1; then
    check_result 0 "rocminfo installed"
else
    check_result 1 "rocminfo not installed"
fi

echo ""
echo -e "${CYAN}═══ GPU DETECTION ═══${NC}"

# Test rocm-smi
if command -v rocm-smi >/dev/null 2>&1; then
    if rocm-smi --showproductname 2>&1 | grep -qi "GPU"; then
        check_result 0 "rocm-smi detects GPU"
        echo -e "${CYAN}GPU Info:${NC}"
        rocm-smi --showproductname 2>&1 | grep -i GPU | sed '\''s/^/  /'\''
    else
        check_result 1 "rocm-smi does NOT detect GPU"
    fi
else
    check_result 1 "rocm-smi not available"
fi

# Test rocminfo
if command -v rocminfo >/dev/null 2>&1; then
    if rocminfo 2>/dev/null | grep -qi "gfx"; then
        check_result 0 "rocminfo detects GPU agents"
        echo -e "${CYAN}GPU Agent Details:${NC}"
        # Show GPU-specific info (Marketing Name and gfx architecture)
        rocminfo 2>/dev/null | grep -E "Marketing Name:|Name:.*gfx" | grep -v "CPU" | head -5 | sed '\''s/^/  /'\''
    else
        check_result 1 "rocminfo does NOT detect GPU agents"
    fi
else
    check_result 1 "rocminfo not available"
fi

echo ""
echo -e "${CYAN}═══ OLLAMA GPU STATUS ═══${NC}"

# Check if Ollama is installed and can see GPU
if command -v ollama >/dev/null 2>&1; then
    check_result 0 "Ollama installed"
    
    # Check if Ollama service is running
    if systemctl is-active --quiet ollama 2>/dev/null; then
        check_result 0 "Ollama service running"
        
        # Try to get GPU info from Ollama (it shows GPU info in logs/ps output)
        if pgrep -f ollama >/dev/null && ollama list >/dev/null 2>&1; then
            check_result 0 "Ollama responding to commands"
        else
            check_result 1 "Ollama not responding"
        fi
    else
        check_result 1 "Ollama service not running"
    fi
else
    echo -e "  ${YELLOW}Ollama not installed (skipping)${NC}"
fi

echo ""
echo -e "${GREEN}════════════════════════════════════════════════════════════${NC}"
if [ "$CHECKS_PASSED" -eq "$CHECKS_TOTAL" ]; then
    echo -e "${GREEN}✓ ALL CHECKS PASSED ($CHECKS_PASSED/$CHECKS_TOTAL)${NC}"
    echo -e "${GREEN}════════════════════════════════════════════════════════════${NC}"
    echo ""
    echo -e "${CYAN}GPU is fully functional in this container!${NC}"
    echo ""
    exit 0
else
    echo -e "${YELLOW}⚠ SOME CHECKS FAILED ($CHECKS_PASSED/$CHECKS_TOTAL passed)${NC}"
    echo -e "${GREEN}════════════════════════════════════════════════════════════${NC}"
    echo ""
    echo -e "${YELLOW}Troubleshooting:${NC}"
    echo "  1. Verify host GPU setup: Run '\''amd-verify'\'' on the host"
    echo "  2. Check LXC config: cat /etc/pve/lxc/${HOSTNAME}.conf"
    echo "  3. Restart container: pct restart <VMID>"
    echo "  4. Check host GPU: lspci | grep -i amd"
    echo ""
    exit 1
fi
GPUVERIFYEOF
chmod +x /usr/local/bin/gpu-verify' >> "$LOG_FILE" 2>&1

# Run GPU verification
show_progress 9 9 "Verifying GPU in container"
echo "" >> "$LOG_FILE" 2>&1
echo "═══ Running GPU Verification ═══" >> "$LOG_FILE" 2>&1

# Use full path and give container a moment to sync filesystem
sleep 2

# Capture GPU verification output
GPU_VERIFY_OUTPUT=$(pct exec $CONTAINER_ID -- /usr/local/bin/gpu-verify 2>&1)
GPU_VERIFY_EXIT=$?

# Log the output
echo "$GPU_VERIFY_OUTPUT" >> "$LOG_FILE" 2>&1

# Parse results for summary
GPU_CHECKS_PASSED=$(echo "$GPU_VERIFY_OUTPUT" | grep -oP '\d+/\d+ passed' | head -1)
GPU_MODEL=$(echo "$GPU_VERIFY_OUTPUT" | grep -i "Card series\|Card model" | head -1 | sed 's/.*: *//' | xargs)
GPU_STATUS=""

if [ $GPU_VERIFY_EXIT -eq 0 ]; then
    complete_progress "GPU verified and working in container"
    GPU_STATUS="✓ ALL CHECKS PASSED"
else
    complete_progress "GPU verification completed (some checks failed)"
    GPU_STATUS="⚠ SOME CHECKS FAILED"
fi

# Store for display in completion message
GPU_VERIFY_SUMMARY="$GPU_STATUS ($GPU_CHECKS_PASSED)"
[ -n "$GPU_MODEL" ] && GPU_VERIFY_DETAILS="$GPU_MODEL" || GPU_VERIFY_DETAILS="AMD GPU"

# Pause to let user read the final step
sleep 3

# Clear screen and show completion message
clear
echo ""

echo ""
echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${GREEN}                 🎉  Ollama LXC Complete!${NC}"
echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""
echo -e "${CYAN}📋 Container Info:${NC}"
echo -e "   Hostname:     ${GREEN}$HOSTNAME${NC}"
echo -e "   IP Address:   ${GREEN}$IP_ADDRESS${NC}"
echo -e "   Container ID: ${GREEN}$CONTAINER_ID${NC}"
echo -e "   Ollama API:   ${GREEN}http://$IP_ADDRESS:11434${NC}"
echo ""

# Display GPU verification results
if [ $GPU_VERIFY_EXIT -eq 0 ]; then
    echo -e "${CYAN}🎮 GPU Status:${NC} ${GREEN}$GPU_VERIFY_SUMMARY${NC}"
    echo -e "   ${GREEN}$GPU_VERIFY_DETAILS${NC}"
    echo -e "   ${GREEN}✓${NC} Device files accessible"
    echo -e "   ${GREEN}✓${NC} ROCm tools functional"
    echo -e "   ${GREEN}✓${NC} Ollama service running"
else
    echo -e "${CYAN}🎮 GPU Status:${NC} ${YELLOW}$GPU_VERIFY_SUMMARY${NC}"
    echo -e "   ${DIM}Run 'pct exec $CONTAINER_ID /usr/local/bin/gpu-verify' for details${NC}"
fi

echo ""
echo -e "${CYAN}📄 Installation Log:${NC} ${GREEN}$LOG_FILE${NC}"

echo ""
echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${CYAN}🚀 Quick Start - Verify Everything Works:${NC}"
echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""
echo -e "${CYAN}1. SSH into your container:${NC}"
echo -e "   ${GREEN}ssh root@$IP_ADDRESS${NC}"
echo ""
echo -e "${CYAN}2. Pull a model and test it:${NC}"
echo -e "   ${GREEN}ollama pull llama3.2:3b${NC}"
echo -e "   ${GREEN}ollama run llama3.2:3b \"Why is the sky blue? One sentence.\"${NC}"
echo ""
echo -e "${CYAN}3. Monitor GPU usage (in a new terminal):${NC}"
echo -e "   ${GREEN}ssh root@$IP_ADDRESS${NC}"
echo -e "   ${GREEN}watch -n 0.5 rocm-smi --showuse --showmemuse${NC}"
echo ""
echo -e "   ${YELLOW}→ You should see GPU usage spike when running models${NC}"
echo ""
echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${CYAN}📚 Next Steps:${NC}"
echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""
echo -e "${CYAN}💬 Add a ChatGPT-like Web UI:${NC}"
echo -e "   Install Open WebUI from Proxmox Community Scripts:"
echo -e "   ${GREEN}https://community-scripts.github.io/ProxmoxVE/scripts?id=openwebui${NC}"
echo ""
echo -e "   Then configure it to connect to: ${GREEN}http://$IP_ADDRESS:11434${NC}"
echo ""
echo -e "${CYAN}🔄 Update Ollama (when new versions are released):${NC}"
echo -e "   ${GREEN}ssh root@$IP_ADDRESS${NC}"
echo -e "   ${GREEN}update${NC}"
echo ""
echo -e "${CYAN}🔍 Verify GPU (troubleshoot GPU issues):${NC}"
echo -e "   ${GREEN}ssh root@$IP_ADDRESS${NC}"
echo -e "   ${GREEN}gpu-verify${NC}"
echo ""
echo -e "${CYAN}📊 Alternative GPU Monitor:${NC}"
echo -e "   ${GREEN}ssh root@$IP_ADDRESS${NC}"
echo -e "   ${GREEN}radeontop${NC}  ${YELLOW}(interactive, press 'q' to quit)${NC}"
echo ""

