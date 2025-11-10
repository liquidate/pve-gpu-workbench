#!/usr/bin/env bash
# SCRIPT_DESC: Create Ollama LXC container (AMD GPU, native installation)
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

# Detect GPU PCI address
echo ""
echo -e "${GREEN}>>> Detecting GPU PCI address...${NC}"
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
    --unprivileged 1 \
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

echo -e "${GREEN}>>> Updating system packages...${NC}"
pct exec $CONTAINER_ID -- apt update -qq
pct exec $CONTAINER_ID -- apt upgrade -y -qq -o Dpkg::Options::="--force-confdef" -o Dpkg::Options::="--force-confold" >/dev/null 2>&1
echo -e "${GREEN}✓ System packages updated${NC}"

echo -e "${GREEN}>>> Installing dependencies (curl)...${NC}"
pct exec $CONTAINER_ID -- apt install -y curl >/dev/null 2>&1

echo -e "${GREEN}>>> Installing Ollama...${NC}"
pct exec $CONTAINER_ID -- bash -c "curl -fsSL https://ollama.com/install.sh | sh"

echo ""
echo -e "${GREEN}>>> Configuring Ollama to listen on all interfaces...${NC}"
# Create systemd override to set OLLAMA_HOST
pct exec $CONTAINER_ID -- mkdir -p /etc/systemd/system/ollama.service.d
pct exec $CONTAINER_ID -- bash -c 'cat > /etc/systemd/system/ollama.service.d/override.conf << "EOFMARKER"
[Service]
Environment="OLLAMA_HOST=0.0.0.0:11434"
EOFMARKER'

echo ""
echo -e "${GREEN}>>> Starting Ollama service...${NC}"
pct exec $CONTAINER_ID -- systemctl daemon-reload
pct exec $CONTAINER_ID -- systemctl enable ollama 2>/dev/null || true
pct exec $CONTAINER_ID -- systemctl start ollama 2>/dev/null || true
sleep 3

echo -e "${GREEN}✓ Ollama installed and running on 0.0.0.0:11434${NC}"

echo ""
echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}Ollama LXC Complete!${NC}"
echo -e "${GREEN}========================================${NC}"
echo ""
echo -e "${CYAN}Container Details:${NC}"
echo "  Hostname: $HOSTNAME"
echo "  IP Address: $IP_ADDRESS"
echo "  Container ID: $CONTAINER_ID"
echo ""
echo -e "${CYAN}Access Ollama:${NC}"
echo "  SSH into container:"
echo -e "    ${GREEN}ssh root@$IP_ADDRESS${NC}"
echo ""
echo "  Run a model:"
echo -e "    ${GREEN}ollama run llama3.2:3b${NC}"
echo ""
echo "  API access from other machines:"
echo -e "    ${GREEN}curl http://$IP_ADDRESS:11434/api/generate -d '{\"model\":\"llama3.2:3b\",\"prompt\":\"Hello\"}'${NC}"
echo ""
echo -e "${CYAN}Install Open WebUI (optional):${NC}"
echo "  ChatGPT-like interface for Ollama"
echo ""
echo "  1. In Proxmox web UI: Datacenter → Shell"
echo "  2. Run this command:"
echo -e "     ${GREEN}bash -c \"\$(wget -qLO - https://github.com/community-scripts/ProxmoxVE/raw/main/ct/openwebui.sh)\"${NC}"
echo "  3. Configure Open WebUI to point to:"
echo -e "     ${GREEN}http://$IP_ADDRESS:11434${NC}"
echo ""
echo "  More info: https://community-scripts.github.io/ProxmoxVE/scripts?id=openwebui"
echo ""
echo -e "${CYAN}Monitor GPU usage:${NC}"
echo -e "  ${GREEN}ssh root@$IP_ADDRESS${NC}"
echo -e "  ${GREEN}watch -n 0.5 rocm-smi --showuse --showmemuse${NC}"
echo ""
echo -e "${CYAN}Update Ollama later:${NC}"
echo -e "  ${GREEN}ssh root@$IP_ADDRESS${NC}"
echo -e "  ${GREEN}curl -fsSL https://ollama.com/install.sh | sh${NC}"
echo -e "  ${GREEN}systemctl restart ollama${NC}"
echo ""

