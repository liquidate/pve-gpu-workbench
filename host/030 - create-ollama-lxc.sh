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
echo "  • Install Ollama natively (fast, no Docker)"
echo "  • Configure systemd service for auto-start"
echo "  • Test with a small model"
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
CONTAINER_ID=100
while pct status $CONTAINER_ID &>/dev/null; do
    ((CONTAINER_ID++))
done
echo -e "${GREEN}✓ Will use container ID: $CONTAINER_ID${NC}"

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

# Detect available storage
echo ""
echo -e "${GREEN}>>> Detecting available storage...${NC}"
echo ""
echo -e "${CYAN}Available storage pools:${NC}"

declare -A STORAGE_POOLS
while IFS= read -r line; do
    name=$(echo "$line" | awk '{print $1}')
    type=$(echo "$line" | awk '{print $2}')
    avail=$(echo "$line" | awk '{print $4}')
    
    # Only show container-compatible storage
    if [[ "$type" =~ ^(dir|zfspool|lvm|lvmthin|btrfs)$ ]]; then
        STORAGE_POOLS[$name]=$avail
        printf "  %-20s %10s available\n" "$name" "$avail"
    fi
done < <(pvesm status | tail -n +2)

if [ ${#STORAGE_POOLS[@]} -eq 0 ]; then
    echo -e "${RED}No suitable storage found${NC}"
    exit 1
fi

# Default to local-zfs or first available
DEFAULT_STORAGE="local-zfs"
if [ -z "${STORAGE_POOLS[$DEFAULT_STORAGE]}" ]; then
    DEFAULT_STORAGE=$(echo "${!STORAGE_POOLS[@]}" | tr ' ' '\n' | head -n1)
fi

echo ""
read -r -p "Select storage pool [$DEFAULT_STORAGE]: " STORAGE
STORAGE=${STORAGE:-$DEFAULT_STORAGE}

if [ -z "${STORAGE_POOLS[$STORAGE]}" ]; then
    echo -e "${RED}Invalid storage pool${NC}"
    exit 1
fi

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

# Smart defaults
DEFAULT_DISK=128
DEFAULT_MEMORY=16
DEFAULT_CORES=8
DEFAULT_SWAP=4

# Adjust defaults based on available RAM
if [ $AVAILABLE_RAM -lt 16 ]; then
    DEFAULT_MEMORY=8
    DEFAULT_CORES=4
    DEFAULT_SWAP=2
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
echo "  Ollama: Native installation (no Docker)"
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
    --start 0

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

# Install Ollama natively
echo ""
echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}Installing Ollama (Native)${NC}"
echo -e "${GREEN}========================================${NC}"
echo ""

echo -e "${GREEN}>>> Installing Ollama...${NC}"
pct exec $CONTAINER_ID -- bash -c "curl -fsSL https://ollama.com/install.sh | sh"

echo ""
echo -e "${GREEN}>>> Starting Ollama service...${NC}"
pct exec $CONTAINER_ID -- systemctl enable ollama 2>/dev/null || true
pct exec $CONTAINER_ID -- systemctl start ollama 2>/dev/null || true
sleep 3

echo -e "${GREEN}✓ Ollama installed and running${NC}"

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
echo "    ${GREEN}ssh root@$IP_ADDRESS${NC}"
echo ""
echo "  Run a model:"
echo "    ${GREEN}ollama run llama3.2:3b${NC}"
echo ""
echo "  API access from other machines:"
echo "    ${GREEN}curl http://$IP_ADDRESS:11434/api/generate -d '{\"model\":\"llama3.2:3b\",\"prompt\":\"Hello\"}'${NC}"
echo ""
echo -e "${CYAN}Install Open WebUI (optional):${NC}"
echo "  Use Proxmox community script (tteck):"
echo "    Point it to: ${GREEN}http://$IP_ADDRESS:11434${NC}"
echo ""
echo -e "${CYAN}Monitor GPU usage:${NC}"
echo "  ${GREEN}ssh root@$IP_ADDRESS${NC}"
echo "  ${GREEN}watch -n 0.5 rocm-smi --showuse --showmemuse${NC}"
echo ""

