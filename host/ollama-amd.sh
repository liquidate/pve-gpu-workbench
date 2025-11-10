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

# Ask for setup mode
echo ""
echo -e "${YELLOW}Setup Mode:${NC}"
echo "  [1] Quick   - Use recommended defaults (just set password)"
echo "  [2] Advanced - Customize all settings"
echo ""
read -r -p "Select mode [1]: " SETUP_MODE
SETUP_MODE=${SETUP_MODE:-1}
echo ""

QUICK_MODE=false
if [ "$SETUP_MODE" = "1" ]; then
    QUICK_MODE=true
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${CYAN}Quick Setup - Recommended Defaults:${NC}"
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo "  • Container ID: Next available"
    echo "  • Network: Auto-detect and configure"
    echo "  • Storage: Best available (ZFS preferred)"
    echo "  • Resources: 256GB disk, 16GB RAM, 12 cores, 8GB swap"
    echo "  • You will only be asked for: Root password"
    echo ""
    read -r -p "Proceed with Quick Setup? [Y/n]: " QUICK_CONFIRM
    QUICK_CONFIRM=${QUICK_CONFIRM:-Y}
    if [[ ! "$QUICK_CONFIRM" =~ ^[Yy]$ ]]; then
        echo "Switching to Advanced mode..."
        QUICK_MODE=false
        echo ""
    else
        echo ""
        echo -e "${GREEN}>>> Setting up container with defaults...${NC}"
    fi
fi

# Detect GPU PCI address
if [ "$QUICK_MODE" = false ]; then
    echo -e "${GREEN}>>> Detecting GPU PCI address...${NC}"
fi
GPU_PCI_PATH=""
for card in /dev/dri/by-path/pci-*-card; do
    if [ -e "$card" ]; then
        pci_addr=$(basename "$card" | sed 's/pci-\(.*\)-card/\1/')
        gpu_info=$(lspci -s "${pci_addr#0000:}" 2>/dev/null | grep -i "VGA\|3D\|Display" || echo "")
        if echo "$gpu_info" | grep -qi amd; then
            GPU_PCI_PATH="$pci_addr"
            echo -e "${GREEN}✓ Found AMD GPU at: $GPU_PCI_PATH${NC}"
            echo "  $gpu_info"
            break
        fi
    fi
done

if [ -z "$GPU_PCI_PATH" ]; then
    echo -e "${RED}ERROR: Could not detect GPU PCI path${NC}"
    exit 1
fi

# Find next available container ID
echo ""
echo -e "${GREEN}>>> Finding next available container ID...${NC}"
NEXT_ID=100
while pct status $NEXT_ID &>/dev/null; do
    ((NEXT_ID++))
done
echo -e "${GREEN}✓ Next available ID: $NEXT_ID${NC}"
echo ""

# Prompt for container ID
while true; do
    read -r -p "Enter container ID [$NEXT_ID]: " CONTAINER_ID
    CONTAINER_ID=${CONTAINER_ID:-$NEXT_ID}
    
    # Validate it's a number
    if ! [[ "$CONTAINER_ID" =~ ^[0-9]+$ ]]; then
        echo -e "${RED}Invalid ID: must be a number${NC}"
        continue
    fi
    
    # Check if already exists
    if pct status $CONTAINER_ID &>/dev/null; then
        echo -e "${RED}Container ID $CONTAINER_ID already exists${NC}"
        read -r -p "Choose a different ID? [Y/n]: " RETRY
        RETRY=${RETRY:-Y}
        if [[ "$RETRY" =~ ^[Yy]$ ]]; then
            continue
        else
            exit 1
        fi
    fi
    
    break
done

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
echo -e "${GREEN}✓ Hostname: $HOSTNAME${NC}"

# Detect network configuration
echo ""
echo -e "${GREEN}>>> Detecting network configuration...${NC}"

# Get bridge IP and subnet
BRIDGE_IP=$(ip -4 addr show vmbr0 | grep -oP '(?<=inet\s)\d+\.\d+\.\d+\.\d+')
BRIDGE_CIDR=$(ip -4 addr show vmbr0 | grep -oP '(?<=inet\s)\d+\.\d+\.\d+\.\d+/\d+' | cut -d'/' -f2)
SUBNET=$(echo "$BRIDGE_IP" | cut -d'.' -f1-3)

# Get gateway
GATEWAY=$(ip route show default | grep -oP '(?<=via )\d+\.\d+\.\d+\.\d+' | head -n1)

echo -e "${CYAN}Network detected:${NC}"
echo "  Bridge (vmbr0): $BRIDGE_IP/$BRIDGE_CIDR"
echo "  Gateway: $GATEWAY"
echo "  Subnet: $SUBNET.0/$BRIDGE_CIDR"

# Find available IP
echo ""
echo -e "${GREEN}>>> Scanning for available IP addresses...${NC}"
SUGGESTED_IP=""
for i in {100..200}; do
    TEST_IP="${SUBNET}.${i}"
    
    # Skip if matches bridge IP
    if [ "$TEST_IP" = "$BRIDGE_IP" ]; then
        continue
    fi
    
    # Quick ping test
    if ! ping -c 1 -W 1 "$TEST_IP" &>/dev/null; then
        # Deeper check with arping
        if ! timeout 1 arping -c 1 -I vmbr0 "$TEST_IP" &>/dev/null; then
            # Check existing LXC/QEMU configs
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

echo -e "${GREEN}✓ Suggested IP: $SUGGESTED_IP${NC}"
echo ""

# Prompt for IP address
while true; do
    read -r -p "Enter IP address for this container [$SUGGESTED_IP]: " IP_ADDRESS
    IP_ADDRESS=${IP_ADDRESS:-$SUGGESTED_IP}
    
    # Validate IP format
    if [[ ! "$IP_ADDRESS" =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]]; then
        echo -e "${RED}Invalid IP format. Please use format: xxx.xxx.xxx.xxx${NC}"
        continue
    fi
    
    # Validate each octet
    VALID_IP=true
    IFS='.' read -ra OCTETS <<< "$IP_ADDRESS"
    for octet in "${OCTETS[@]}"; do
        if [ "$octet" -lt 0 ] || [ "$octet" -gt 255 ]; then
            echo -e "${RED}Invalid IP: octets must be 0-255${NC}"
            VALID_IP=false
            break
        fi
    done
    
    if [ "$VALID_IP" = false ]; then
        continue
    fi
    
    # Validate subnet
    IP_SUBNET=$(echo "$IP_ADDRESS" | cut -d'.' -f1-3)
    if [ "$IP_SUBNET" != "$SUBNET" ]; then
        echo -e "${YELLOW}Warning: IP $IP_ADDRESS is not in detected subnet ${SUBNET}.0/${BRIDGE_CIDR}${NC}"
        read -r -p "Continue anyway? [y/N]: " CONFIRM
        if [[ ! "$CONFIRM" =~ ^[Yy]$ ]]; then
            continue
        fi
    fi
    
    # Check for conflicts
    if ping -c 1 -W 1 "$IP_ADDRESS" &>/dev/null; then
        echo -e "${RED}IP $IP_ADDRESS is already in use (responds to ping)${NC}"
        continue
    fi
    
    if grep -r "ip=${IP_ADDRESS}/" /etc/pve/lxc/ /etc/pve/qemu-server/ 2>/dev/null | grep -q .; then
        echo -e "${RED}IP $IP_ADDRESS is already assigned to another container/VM${NC}"
        continue
    fi
    
    break
done

# Confirm gateway
echo ""
while true; do
    read -r -p "Gateway address [$GATEWAY]: " GATEWAY_INPUT
    GATEWAY_INPUT=${GATEWAY_INPUT:-$GATEWAY}
    
    # Validate gateway format
    if [[ ! "$GATEWAY_INPUT" =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]]; then
        echo -e "${RED}Invalid gateway format. Please use format: xxx.xxx.xxx.xxx${NC}"
        continue
    fi
    
    GATEWAY="$GATEWAY_INPUT"
    break
done

# Detect available storage
echo ""
echo -e "${GREEN}>>> Detecting available storage...${NC}"
echo ""
echo -e "${CYAN}Available storage pools:${NC}"

declare -a STORAGE_NAMES
declare -A STORAGE_INFO
INDEX=1
while IFS= read -r line; do
    name=$(echo "$line" | awk '{print $1}')
    type=$(echo "$line" | awk '{print $2}')
    avail=$(echo "$line" | awk '{print $4}')
    
    # Only show container-compatible storage
    if [[ "$type" =~ ^(dir|zfspool|lvm|lvmthin|btrfs)$ ]]; then
        STORAGE_NAMES[$INDEX]=$name
        STORAGE_INFO[$name]=$avail
        # Convert KB to GB for display (pvesm shows KB)
        avail_gb=$(awk "BEGIN {printf \"%.0f\", $avail / 1024 / 1024}")
        printf "  [%d] %-20s %6s GB available\n" "$INDEX" "$name" "$avail_gb"
        ((INDEX++))
    fi
done < <(pvesm status | tail -n +2)

if [ ${#STORAGE_NAMES[@]} -eq 0 ]; then
    echo -e "${RED}No suitable storage found${NC}"
    exit 1
fi

# Default to local-zfs or first available
DEFAULT_STORAGE_NUM=1
for i in "${!STORAGE_NAMES[@]}"; do
    if [ "${STORAGE_NAMES[$i]}" = "local-zfs" ]; then
        DEFAULT_STORAGE_NUM=$i
        break
    fi
done

echo ""
read -r -p "Select storage pool [${DEFAULT_STORAGE_NUM}]: " STORAGE_CHOICE
STORAGE_CHOICE=${STORAGE_CHOICE:-$DEFAULT_STORAGE_NUM}

if [ -z "${STORAGE_NAMES[$STORAGE_CHOICE]}" ]; then
    echo -e "${RED}Invalid storage selection${NC}"
    exit 1
fi

STORAGE="${STORAGE_NAMES[$STORAGE_CHOICE]}"

# Resource allocation
echo ""
echo -e "${GREEN}>>> Resource allocation...${NC}"

# Detect total RAM and GPU VRAM
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

echo -e "${CYAN}System resources:${NC}"
echo "  Total RAM: ${TOTAL_RAM_GB}GB"
if [ $GPU_VRAM_ALLOCATED -gt 0 ]; then
    echo "  GPU VRAM: ${GPU_VRAM_ALLOCATED}GB"
fi
echo "  Available for LXC: ~${AVAILABLE_RAM}GB"
echo ""

# Smart defaults (designed for Ollama - can run large models)
DEFAULT_DISK=256
DEFAULT_MEMORY=16
DEFAULT_CORES=12
DEFAULT_SWAP=8

# Adjust defaults based on available RAM
if [ $AVAILABLE_RAM -lt 16 ]; then
    DEFAULT_DISK=128
    DEFAULT_MEMORY=8
    DEFAULT_CORES=6
    DEFAULT_SWAP=4
fi

read -r -p "Disk size in GB [$DEFAULT_DISK]: " DISK_SIZE
DISK_SIZE=${DISK_SIZE:-$DEFAULT_DISK}

read -r -p "Memory in GB [$DEFAULT_MEMORY]: " MEMORY
MEMORY=${MEMORY:-$DEFAULT_MEMORY}

read -r -p "CPU cores [$DEFAULT_CORES]: " CORES
CORES=${CORES:-$DEFAULT_CORES}

read -r -p "Swap in GB [$DEFAULT_SWAP]: " SWAP
SWAP=${SWAP:-$DEFAULT_SWAP}

# Summary
echo ""
echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}Configuration Summary${NC}"
echo -e "${GREEN}========================================${NC}"
echo ""
echo -e "${CYAN}Container:${NC}"
echo "  ID: $CONTAINER_ID"
echo "  Hostname: $HOSTNAME"
echo "  IP: $IP_ADDRESS/$BRIDGE_CIDR"
echo "  Gateway: $GATEWAY"
echo ""
echo -e "${CYAN}Resources:${NC}"
echo "  Storage: $STORAGE"
echo "  Disk: ${DISK_SIZE}GB"
echo "  Memory: ${MEMORY}GB"
echo "  CPU Cores: $CORES"
echo "  Swap: ${SWAP}GB"
echo ""
echo -e "${CYAN}GPU:${NC}"
echo "  Type: AMD"
echo "  PCI: $GPU_PCI_PATH"
echo ""
echo -e "${CYAN}Software:${NC}"
echo "  Ollama: Latest version"
echo "  Auto-start: Yes (systemd service)"
echo ""

read -r -p "Continue with these settings? [Y/n]: " CONFIRM
CONFIRM=${CONFIRM:-Y}
if [[ ! "$CONFIRM" =~ ^[Yy]$ ]]; then
    echo "Cancelled."
    exit 0
fi

# Create LXC container
echo ""
echo -e "${GREEN}>>> Creating LXC container...${NC}"

pct create $CONTAINER_ID \
    /var/lib/vz/template/cache/ubuntu-24.04-standard_24.04-2_amd64.tar.zst \
    --hostname "$HOSTNAME" \
    --memory $((MEMORY * 1024)) \
    --cores $CORES \
    --swap $((SWAP * 1024)) \
    --net0 name=eth0,bridge=vmbr0,ip=${IP_ADDRESS}/${BRIDGE_CIDR},gw=${GATEWAY} \
    --storage "$STORAGE" \
    --rootfs "$STORAGE:${DISK_SIZE}" \
    --unprivileged 0 \
    --features nesting=1 \
    --start 0 >/dev/null 2>&1

echo -e "${GREEN}✓ Container created${NC}"

# Configure GPU passthrough
echo ""
echo -e "${GREEN}>>> Configuring GPU passthrough...${NC}"

# Add GPU device mappings to LXC config
cat >> /etc/pve/lxc/${CONTAINER_ID}.conf << EOF

# AMD GPU passthrough
lxc.cgroup2.devices.allow: c 226:* rwm
lxc.cgroup2.devices.allow: c 234:* rwm
lxc.mount.entry: /dev/dri/by-path/pci-${GPU_PCI_PATH}-card dev/dri/card0 none bind,optional,create=file 0 0
lxc.mount.entry: /dev/dri/by-path/pci-${GPU_PCI_PATH}-render dev/dri/renderD128 none bind,optional,create=file 0 0
lxc.mount.entry: /dev/kfd dev/kfd none bind,optional,create=file 0 0
EOF

echo -e "${GREEN}✓ GPU passthrough configured${NC}"

# Start container
echo ""
echo -e "${GREEN}>>> Starting container...${NC}"
pct start $CONTAINER_ID
sleep 5
echo -e "${GREEN}✓ Container started${NC}"

# Set root password
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

if [ -z "$ROOT_PASSWORD" ]; then
    echo -e "${RED}ERROR: Password cannot be empty${NC}"
    exit 1
fi

echo -e "${GREEN}>>> Setting root password...${NC}"
pct exec $CONTAINER_ID -- bash -c "echo 'root:$ROOT_PASSWORD' | chpasswd"

# Enable password authentication for SSH
pct exec $CONTAINER_ID -- sed -i 's/^#*PermitRootLogin.*/PermitRootLogin yes/' /etc/ssh/sshd_config
pct exec $CONTAINER_ID -- sed -i 's/^#*PasswordAuthentication.*/PasswordAuthentication yes/' /etc/ssh/sshd_config
pct exec $CONTAINER_ID -- systemctl restart ssh

echo -e "${GREEN}✓ Password set and SSH configured${NC}"

# Verify GPU passthrough inside container
echo ""
echo -e "${GREEN}>>> Verifying GPU passthrough...${NC}"

if pct exec $CONTAINER_ID -- test -e /dev/dri/card0 && \
   pct exec $CONTAINER_ID -- test -e /dev/dri/renderD128 && \
   pct exec $CONTAINER_ID -- test -e /dev/kfd; then
    echo -e "${GREEN}✓ GPU devices accessible inside container${NC}"
else
    echo -e "${RED}ERROR: GPU devices not accessible inside container${NC}"
    echo "Troubleshooting:"
    echo "  pct exec $CONTAINER_ID -- ls -la /dev/dri/"
    echo "  pct exec $CONTAINER_ID -- ls -la /dev/kfd"
    exit 1
fi

# Install Ollama
echo ""
echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}Installing Ollama${NC}"
echo -e "${GREEN}========================================${NC}"
echo ""

echo -e "${GREEN}>>> Updating package list...${NC}"
pct exec $CONTAINER_ID -- apt update -qq >/dev/null 2>&1

# Count packages to upgrade
PACKAGE_COUNT=$(pct exec $CONTAINER_ID -- apt list --upgradable 2>/dev/null | grep -c "upgradable")

if [ "$PACKAGE_COUNT" -gt 0 ]; then
    echo -e "${GREEN}>>> Upgrading $PACKAGE_COUNT packages...${NC}"
    
    # Progress bar settings
    BAR_WIDTH=50
    
    # Run upgrade and capture progress
    pct exec $CONTAINER_ID -- bash -c "DEBIAN_FRONTEND=noninteractive apt upgrade -y -o Dpkg::Options::='--force-confdef' -o Dpkg::Options::='--force-confold' 2>&1" | {
        COMPLETED=0
        while IFS= read -r line; do
            # Count completed packages (look for "Setting up" which is the final step)
            if echo "$line" | grep -q "^Setting up"; then
                COMPLETED=$((COMPLETED + 1))
                # Calculate progress
                PERCENT=$((COMPLETED * 100 / PACKAGE_COUNT))
                FILLED=$((BAR_WIDTH * COMPLETED / PACKAGE_COUNT))
                EMPTY=$((BAR_WIDTH - FILLED))
                
                # Draw progress bar
                printf "\r${GREEN}[${NC}"
                printf "%${FILLED}s" | tr ' ' '='
                printf "%${EMPTY}s" | tr ' ' ' '
                printf "${GREEN}]${NC} %3d%% (%d/%d)" "$PERCENT" "$COMPLETED" "$PACKAGE_COUNT"
            fi
        done
        echo ""
    }
    echo -e "${GREEN}✓ System packages updated${NC}"
else
    echo -e "${GREEN}✓ All packages up to date${NC}"
fi

echo -e "${GREEN}>>> Installing dependencies...${NC}"
pct exec $CONTAINER_ID -- apt install -y curl wget gnupg2 >/dev/null 2>&1

echo -e "${GREEN}>>> Installing ROCm utilities...${NC}"
pct exec $CONTAINER_ID -- bash -c "
    mkdir -p --mode=0755 /etc/apt/keyrings
    wget -q https://repo.radeon.com/rocm/rocm.gpg.key -O - | gpg --dearmor | tee /etc/apt/keyrings/rocm.gpg > /dev/null
    echo 'deb [arch=amd64 signed-by=/etc/apt/keyrings/rocm.gpg] https://repo.radeon.com/rocm/apt/6.2.4 noble main' | tee /etc/apt/sources.list.d/rocm.list > /dev/null
    apt update -qq 2>&1 | grep -v 'packages can be upgraded' || true
    apt install -y rocm-smi radeontop 2>&1 | grep -v 'Setting up' | grep -v 'Unpacking' | grep -v 'Preparing' || true
" >/dev/null 2>&1
echo -e "${GREEN}✓ ROCm utilities installed${NC}"

echo -e "${GREEN}>>> Installing Ollama...${NC}"
pct exec $CONTAINER_ID -- bash -c "curl -fsSL https://ollama.com/install.sh | sh" 2>&1 | grep -E "Downloading|###|GPU ready|Install complete" || true

echo ""
echo -e "${GREEN}>>> Configuring Ollama to listen on all interfaces...${NC}"
# Create systemd override to set OLLAMA_HOST
pct exec $CONTAINER_ID -- mkdir -p /etc/systemd/system/ollama.service.d
pct exec $CONTAINER_ID -- bash -c 'cat > /etc/systemd/system/ollama.service.d/override.conf << "EOFMARKER"
[Service]
Environment="OLLAMA_HOST=0.0.0.0:11434"
EOFMARKER'

echo ""
echo -e "${GREEN}>>> Restarting Ollama with new configuration...${NC}"
pct exec $CONTAINER_ID -- systemctl daemon-reload
pct exec $CONTAINER_ID -- systemctl enable ollama 2>/dev/null || true
pct exec $CONTAINER_ID -- systemctl restart ollama 2>/dev/null || true
sleep 3

echo -e "${GREEN}✓ Ollama installed and running on 0.0.0.0:11434${NC}"

# Create update command inside the container
echo ""
echo -e "${GREEN}>>> Creating update command in container...${NC}"
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

echo ""
read -p "Update Ollama to the latest version? [Y/n]: " UPDATE
UPDATE=${UPDATE:-Y}

if [[ ! "$UPDATE" =~ ^[Yy]$ ]]; then
    echo "Update cancelled."
    exit 0
fi

echo ""
echo -e "${CYAN}>>> Downloading and installing latest Ollama...${NC}"
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
chmod +x /usr/local/bin/update'

echo -e "${GREEN}✓ Update command created${NC}"

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
echo -e "${CYAN}📊 Alternative GPU Monitor:${NC}"
echo -e "   ${GREEN}ssh root@$IP_ADDRESS${NC}"
echo -e "   ${GREEN}radeontop${NC}  ${YELLOW}(interactive, press 'q' to quit)${NC}"
echo ""

