#!/usr/bin/env bash
# SCRIPT_DESC: Create GPU-enabled LXC container (AMD or NVIDIA or BOTH)
# SCRIPT_DETECT: 

# Enhanced LXC GPU container creation script with automatic GPU detection
# This script ensures correct GPU mapping using persistent PCI paths

set -e

# Get script directory and source colors
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/../includes/colors.sh"

# Prompt for container ID
read -r -p "Enter container ID [100]: " CONTAINER_ID
CONTAINER_ID=${CONTAINER_ID:-100}

# Auto-detect available GPU types
echo ""
echo -e "${GREEN}>>> Detecting available GPUs...${NC}"
HAS_AMD=false
HAS_NVIDIA=false

# Check for AMD GPUs
if lspci -nn | grep -i "VGA\|3D\|Display" | grep -qi amd; then
    HAS_AMD=true
    echo -e "${GREEN}✓ AMD GPU detected${NC}"
fi

# Check for NVIDIA GPUs
if lspci -nn | grep -i "VGA\|3D\|Display" | grep -qi nvidia; then
    HAS_NVIDIA=true
    echo -e "${GREEN}✓ NVIDIA GPU detected${NC}"
fi

if [ "$HAS_AMD" = false ] && [ "$HAS_NVIDIA" = false ]; then
    echo -e "${RED}ERROR: No AMD or NVIDIA GPUs detected on this system${NC}"
    echo ""
    echo -e "${YELLOW}Available GPUs:${NC}"
    lspci -nn | grep -i "VGA\|3D\|Display"
    echo ""
    exit 1
fi

# Prompt for GPU type only if multiple types detected
GPU_TYPE=""
GPU_NAME=""
ADDITIONAL_TAGS=""

if [ "$HAS_AMD" = true ] && [ "$HAS_NVIDIA" = true ]; then
    echo ""
    echo "Multiple GPU types detected. Select GPU type for this container:"
    echo "1) AMD GPU"
    echo "2) NVIDIA GPU"
    read -r -p "Enter selection [1]: " GPU_TYPE
    GPU_TYPE=${GPU_TYPE:-1}
elif [ "$HAS_AMD" = true ]; then
    echo -e "${GREEN}Auto-selecting AMD GPU${NC}"
    GPU_TYPE="1"
elif [ "$HAS_NVIDIA" = true ]; then
    echo -e "${GREEN}Auto-selecting NVIDIA GPU${NC}"
    GPU_TYPE="2"
fi

# Prompt for GPU PCI address
echo ""

# Auto-detect first GPU of selected type for default
TEMPLATE_FIRST_PCI_PATH=""

if [ "$GPU_TYPE" == "1" ]; then
    GPU_NAME="AMD"
    ADDITIONAL_TAGS="amd"
    echo "=== Available AMD GPUs ==="
    echo ""
    # Show AMD GPUs from lspci
    lspci -nn -D | grep -i amd | grep -i "VGA\|3D\|Display" && echo "" || echo "No AMD GPUs found via lspci"
    
    # Show AMD GPU DRI paths and capture first one for default
    echo "Available AMD GPU PCI paths:"
    for card in /dev/dri/by-path/pci-*-card; do
        if [ -e "$card" ]; then
            # Extract PCI address from path
            pci_addr=$(basename "$card" | sed 's/pci-\(.*\)-card/\1/')
            # Get GPU info from lspci
            gpu_info=$(lspci -s "${pci_addr#0000:}" 2>/dev/null | grep -i "VGA\|3D\|Display" || echo "")
            if echo "$gpu_info" | grep -qi amd; then
                echo "  $pci_addr -> $(ls -l "$card" | awk '{print $NF}') (AMD)"
                echo "    $gpu_info"
                # Set default to first AMD GPU found
                if [ -z "$TEMPLATE_FIRST_PCI_PATH" ]; then
                    TEMPLATE_FIRST_PCI_PATH="$pci_addr"
                fi
            fi
        fi
    done
    echo ""
else
    GPU_NAME="NVIDIA"
    ADDITIONAL_TAGS="nvidia"
    echo "=== Available NVIDIA GPUs ==="
    echo ""
    # Show NVIDIA GPUs with full domain:bus:device.function format
    lspci -nn -D | grep -i nvidia | grep -i "VGA\|3D\|Display" && echo "" || echo "No NVIDIA GPUs found"
    
    echo "Available NVIDIA GPU PCI paths:"
    for card in /dev/dri/by-path/pci-*-card; do
        if [ -e "$card" ]; then
            pci_addr=$(basename "$card" | sed 's/pci-\(.*\)-card/\1/')
            gpu_info=$(lspci -s "${pci_addr#0000:}" 2>/dev/null | grep -i "VGA\|3D\|Display" || echo "")
            if echo "$gpu_info" | grep -qi nvidia; then
                echo "  $pci_addr -> $(ls -l "$card" | awk '{print $NF}') (NVIDIA)"
                echo "    $gpu_info"
                # Set default to first NVIDIA GPU found
                if [ -z "$TEMPLATE_FIRST_PCI_PATH" ]; then
                    TEMPLATE_FIRST_PCI_PATH="$pci_addr"
                fi
            fi
        fi
    done
    echo ""
fi

# Prompt with default value
if [ -n "$TEMPLATE_FIRST_PCI_PATH" ]; then
    read -r -p "Enter GPU PCI address [$TEMPLATE_FIRST_PCI_PATH]: " PCI_ADDRESS
    PCI_ADDRESS=${PCI_ADDRESS:-$TEMPLATE_FIRST_PCI_PATH}
else
    read -r -p "Enter GPU PCI address (e.g., 0000:a1:00.0): " PCI_ADDRESS
fi

if [ -z "$PCI_ADDRESS" ]; then
    echo -e "${RED}Error: PCI address is required${NC}"
    exit 1
fi

# Validate PCI path exists
CARD_PATH="/dev/dri/by-path/pci-${PCI_ADDRESS}-card"
RENDER_PATH="/dev/dri/by-path/pci-${PCI_ADDRESS}-render"

if [ ! -e "$CARD_PATH" ]; then
    echo -e "${RED}Error: $CARD_PATH does not exist${NC}"
    exit 1
fi
if [ ! -e "$RENDER_PATH" ]; then
    echo -e "${RED}Error: $RENDER_PATH does not exist${NC}"
    exit 1
fi

if [ "$GPU_TYPE" == "1" ]; then
    # AMD GPU - validate KFD device
    if [ ! -e "/dev/kfd" ]; then
        echo -e "${YELLOW}Warning: /dev/kfd does not exist. AMD ROCm may not work.${NC}"
        echo -e "${YELLOW}Make sure AMD GPU drivers are properly installed on the host.${NC}"
    fi
    
    echo -e "${GREEN}✓ Found AMD GPU at $PCI_ADDRESS${NC}"
    echo "  Card device: $CARD_PATH"
    echo "  Render device: $RENDER_PATH"
    echo "  KFD device: $([ -e "/dev/kfd" ] && echo "✓ Available" || echo "✗ Not found")"
else
    # NVIDIA GPU - validate NVIDIA-specific devices
    echo -e "${GREEN}✓ Found NVIDIA GPU at $PCI_ADDRESS${NC}"
    echo "  Card device: $CARD_PATH"
    echo "  Render device: $RENDER_PATH"
    echo ""
    echo "Validating NVIDIA driver devices:"
    
    NVIDIA_DEVICES=("/dev/nvidia0" "/dev/nvidiactl" "/dev/nvidia-modeset" "/dev/nvidia-uvm")
    MISSING_DEVICES=()
    
    for dev in "${NVIDIA_DEVICES[@]}"; do
        if [ -e "$dev" ]; then
            echo "  ✓ $dev"
        else
            echo "  ✗ $dev (missing)"
            MISSING_DEVICES+=("$dev")
        fi
    done
    
    if [ ${#MISSING_DEVICES[@]} -gt 0 ]; then
        echo ""
        echo -e "${YELLOW}Warning: Some NVIDIA devices are missing:${NC}"
        for dev in "${MISSING_DEVICES[@]}"; do
            echo -e "${YELLOW}  - $dev${NC}"
        done
        echo -e "${YELLOW}Make sure NVIDIA drivers are properly installed on the host.${NC}"
        echo -e "${YELLOW}The container may not function correctly without these devices.${NC}"
        echo ""
        read -r -p "Continue anyway? [y/N]: " CONTINUE
        CONTINUE=${CONTINUE:-N}
        if [[ ! "$CONTINUE" =~ ^[Yy]$ ]]; then
            echo "Cancelled."
            exit 1
        fi
    fi
fi

echo ""
HOSTNAME_TEMPLATE="gpu-lxc-${GPU_NAME,,}-$CONTAINER_ID"
read -r -p "Enter hostname [$HOSTNAME_TEMPLATE]: " HOSTNAME
HOSTNAME=${HOSTNAME:-$HOSTNAME_TEMPLATE}

# Auto-detect network configuration from vmbr0
echo ""
echo -e "${GREEN}>>> Detecting network configuration...${NC}"

# Get vmbr0 IP and calculate subnet
BRIDGE_IP=$(ip -4 addr show vmbr0 2>/dev/null | grep -oP '(?<=inet\s)\d+(\.\d+){3}')
BRIDGE_CIDR=$(ip -4 addr show vmbr0 2>/dev/null | grep -oP '(?<=inet\s)\d+(\.\d+){3}/\d+' | cut -d'/' -f2)

if [ -n "$BRIDGE_IP" ] && [ -n "$BRIDGE_CIDR" ]; then
    # Extract network prefix (e.g., 192.168.111 from 192.168.111.5)
    NETWORK_PREFIX=$(echo "$BRIDGE_IP" | cut -d'.' -f1-3)
    
    # Get the actual gateway from routing table (not the bridge IP)
    GW_TEMPLATE=$(ip route show default | grep -oP '(?<=via )\d+(\.\d+){3}' | head -n1)
    
    # If no default gateway found, try to detect .1 as common gateway
    if [ -z "$GW_TEMPLATE" ]; then
        GW_TEMPLATE="${NETWORK_PREFIX}.1"
    fi
    
    # Suggest an available IP in the same subnet
    echo -e "${GREEN}✓ Detected network: ${NETWORK_PREFIX}.0/${BRIDGE_CIDR}${NC}"
    echo -e "${GREEN}✓ Gateway: ${GW_TEMPLATE}${NC}"
    echo ""
    
    # Find an available IP by checking what's in use
    echo -e "${YELLOW}Scanning for available IPs (this may take a few seconds)...${NC}"
    IP_FOUND=false
    
    # Check if arping is available for more reliable detection
    HAS_ARPING=false
    if command -v arping >/dev/null 2>&1; then
        HAS_ARPING=true
    fi
    
    for i in $(seq 100 200); do
        TEST_IP="${NETWORK_PREFIX}.${i}"
        IP_IN_USE=false
        
        # Method 1: Check existing LXC container configs
        if grep -r "ip=${TEST_IP}/" /etc/pve/lxc/*.conf 2>/dev/null | grep -q .; then
            IP_IN_USE=true
            continue
        fi
        
        # Method 2: Check existing QEMU VM configs
        if grep -r "ip=${TEST_IP}" /etc/pve/qemu-server/*.conf 2>/dev/null | grep -q .; then
            IP_IN_USE=true
            continue
        fi
        
        # Method 3: ARP scan (most reliable - detects even devices blocking ping)
        if [ "$HAS_ARPING" = true ]; then
            if arping -c 1 -w 1 -I vmbr0 "$TEST_IP" >/dev/null 2>&1; then
                IP_IN_USE=true
                continue
            fi
        fi
        
        # Method 4: Ping check (fallback or additional verification)
        if ping -c 1 -W 1 "$TEST_IP" >/dev/null 2>&1; then
            IP_IN_USE=true
            continue
        fi
        
        # If we got here, IP appears to be available
        if [ "$IP_IN_USE" = false ]; then
            IP_TEMPLATE="$TEST_IP"
            IP_FOUND=true
            echo -e "${GREEN}✓ Found available IP: ${IP_TEMPLATE}${NC}"
            break
        fi
    done
    
    if [ "$IP_FOUND" = false ]; then
        # Fallback: suggest based on container ID
        IP_TEMPLATE="${NETWORK_PREFIX}.$((100 + CONTAINER_ID))"
        echo -e "${YELLOW}⚠ Could not verify availability, suggesting: ${IP_TEMPLATE}${NC}"
    fi
else
    # Fallback to old defaults if detection fails
    echo -e "${YELLOW}⚠ Could not detect network, using defaults${NC}"
    IP_TEMPLATE="10.0.0.$CONTAINER_ID"
    GW_TEMPLATE="10.0.0.1"
fi

echo ""
read -r -p "Enter container IP address [$IP_TEMPLATE]: " IP_ADDRESS
IP_ADDRESS=${IP_ADDRESS:-$IP_TEMPLATE}

# Validate the entered IP address
echo ""
echo -e "${GREEN}>>> Validating IP address: $IP_ADDRESS${NC}"

# Check if IP format is valid
if [[ ! "$IP_ADDRESS" =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]]; then
    echo -e "${RED}✗ Invalid IP address format${NC}"
    echo -e "${YELLOW}IP must be in format: xxx.xxx.xxx.xxx${NC}"
    exit 1
fi

# Check each octet is 0-255
IFS='.' read -r -a octets <<< "$IP_ADDRESS"
for octet in "${octets[@]}"; do
    if [ "$octet" -gt 255 ] || [ "$octet" -lt 0 ]; then
        echo -e "${RED}✗ Invalid IP address: octets must be 0-255${NC}"
        exit 1
    fi
done
echo -e "${GREEN}✓ IP format is valid${NC}"

# Check if in same subnet (if we detected one)
if [ -n "$NETWORK_PREFIX" ]; then
    ENTERED_PREFIX=$(echo "$IP_ADDRESS" | cut -d'.' -f1-3)
    if [ "$ENTERED_PREFIX" != "$NETWORK_PREFIX" ]; then
        echo -e "${YELLOW}⚠ Warning: IP $IP_ADDRESS is not in detected network ${NETWORK_PREFIX}.0/${BRIDGE_CIDR}${NC}"
        read -r -p "Continue anyway? [y/N]: " CONTINUE
        CONTINUE=${CONTINUE:-N}
        if [[ ! "$CONTINUE" =~ ^[Yy]$ ]]; then
            echo "Cancelled."
            exit 0
        fi
    else
        echo -e "${GREEN}✓ IP is in correct subnet${NC}"
    fi
fi

# Check for IP conflicts
echo -e "${YELLOW}Checking for IP conflicts...${NC}"
CONFLICT_FOUND=false
CONFLICT_REASONS=()

# Check LXC configs
if grep -r "ip=${IP_ADDRESS}/" /etc/pve/lxc/*.conf 2>/dev/null | grep -q .; then
    CONFLICT_FOUND=true
    CONFLICT_REASONS+=("IP already assigned to an LXC container")
fi

# Check QEMU VM configs
if grep -r "ip=${IP_ADDRESS}" /etc/pve/qemu-server/*.conf 2>/dev/null | grep -q .; then
    CONFLICT_FOUND=true
    CONFLICT_REASONS+=("IP already assigned to a QEMU VM")
fi

# ARP check
if [ "$HAS_ARPING" = true ]; then
    if arping -c 1 -w 1 -I vmbr0 "$IP_ADDRESS" >/dev/null 2>&1; then
        CONFLICT_FOUND=true
        CONFLICT_REASONS+=("Device responding to ARP at this IP")
    fi
fi

# Ping check
if ping -c 1 -W 1 "$IP_ADDRESS" >/dev/null 2>&1; then
    CONFLICT_FOUND=true
    CONFLICT_REASONS+=("Device responding to ping at this IP")
fi

if [ "$CONFLICT_FOUND" = true ]; then
    echo -e "${RED}========================================${NC}"
    echo -e "${RED}⚠ IP CONFLICT DETECTED${NC}"
    echo -e "${RED}========================================${NC}"
    echo ""
    echo -e "${YELLOW}The IP address $IP_ADDRESS appears to be in use:${NC}"
    for reason in "${CONFLICT_REASONS[@]}"; do
        echo -e "${YELLOW}  • $reason${NC}"
    done
    echo ""
    echo -e "${YELLOW}Using this IP may cause network conflicts!${NC}"
    echo ""
    read -r -p "Use this IP anyway? [y/N]: " FORCE_IP
    FORCE_IP=${FORCE_IP:-N}
    if [[ ! "$FORCE_IP" =~ ^[Yy]$ ]]; then
        echo "Cancelled. Please run the script again with a different IP."
        exit 0
    fi
    echo -e "${YELLOW}⚠ Proceeding with potentially conflicting IP${NC}"
else
    echo -e "${GREEN}✓ No conflicts detected${NC}"
fi

echo ""
read -r -p "Enter gateway [$GW_TEMPLATE]: " GATEWAY
GATEWAY=${GATEWAY:-$GW_TEMPLATE}

# Generate random MAC address
MAC_ADDRESS=$(printf 'BC:24:11:%02X:%02X:%02X\n' $((RANDOM%256)) $((RANDOM%256)) $((RANDOM%256)))

echo ""
echo -e "${GREEN}>>> Detecting available storage...${NC}"

# Get list of storage that supports containers
AVAILABLE_STORAGE=()
declare -A STORAGE_INFO

while IFS= read -r line; do
    storage_name=$(echo "$line" | awk '{print $1}')
    storage_type=$(echo "$line" | awk '{print $2}')
    storage_avail_kb=$(echo "$line" | awk '{print $4}')
    
    # Only include storage types that support containers
    if [[ "$storage_type" =~ ^(dir|zfspool|lvm|lvmthin|btrfs)$ ]]; then
        # Convert KB to human readable format
        if [ "$storage_avail_kb" -gt 1073741824 ]; then
            # TB
            storage_avail=$(awk "BEGIN {printf \"%.1fTB\", $storage_avail_kb/1073741824}")
        elif [ "$storage_avail_kb" -gt 1048576 ]; then
            # GB
            storage_avail=$(awk "BEGIN {printf \"%.0fGB\", $storage_avail_kb/1048576}")
        else
            # MB
            storage_avail=$(awk "BEGIN {printf \"%.0fMB\", $storage_avail_kb/1024}")
        fi
        
        AVAILABLE_STORAGE+=("$storage_name")
        STORAGE_INFO["$storage_name"]="$storage_type ($storage_avail available)"
    fi
done < <(pvesm status | tail -n +2)

if [ ${#AVAILABLE_STORAGE[@]} -eq 0 ]; then
    echo -e "${RED}✗ No suitable storage found for containers${NC}"
    echo -e "${YELLOW}Storage must be type: dir, zfspool, lvm, lvmthin, or btrfs${NC}"
    exit 1
fi

echo -e "${GREEN}✓ Found ${#AVAILABLE_STORAGE[@]} storage option(s)${NC}"
echo ""
echo -e "${YELLOW}Available storage for containers:${NC}"
for i in "${!AVAILABLE_STORAGE[@]}"; do
    storage="${AVAILABLE_STORAGE[$i]}"
    info="${STORAGE_INFO[$storage]}"
    echo "  $((i+1))) $storage - $info"
done

# Auto-select if only one option, otherwise prompt
if [ ${#AVAILABLE_STORAGE[@]} -eq 1 ]; then
    STORAGE="${AVAILABLE_STORAGE[0]}"
    echo ""
    echo -e "${GREEN}Auto-selected: $STORAGE${NC}"
else
    echo ""
    # Find index of local-zfs or first item as default
    DEFAULT_STORAGE_IDX=1
    for i in "${!AVAILABLE_STORAGE[@]}"; do
        if [ "${AVAILABLE_STORAGE[$i]}" = "local-zfs" ] || [ "${AVAILABLE_STORAGE[$i]}" = "local-lvm" ]; then
            DEFAULT_STORAGE_IDX=$((i+1))
            break
        fi
    done
    
    read -r -p "Select storage [${DEFAULT_STORAGE_IDX}]: " STORAGE_CHOICE
    STORAGE_CHOICE=${STORAGE_CHOICE:-$DEFAULT_STORAGE_IDX}
    
    # Validate choice
    if [ "$STORAGE_CHOICE" -lt 1 ] || [ "$STORAGE_CHOICE" -gt ${#AVAILABLE_STORAGE[@]} ]; then
        echo -e "${RED}✗ Invalid selection${NC}"
        exit 1
    fi
    
    STORAGE="${AVAILABLE_STORAGE[$((STORAGE_CHOICE-1))]}"
fi

echo ""
echo -e "${GREEN}>>> Detecting system resources...${NC}"

# Total RAM
TOTAL_RAM_GB=$(free -g | awk '/^Mem:/{print $2}')

# Check if GPU VRAM is allocated (from script 002)
GPU_VRAM_ALLOCATED=0
if grep -q "amdgpu.gttsize=98304" /proc/cmdline 2>/dev/null; then
    GPU_VRAM_ALLOCATED=96
    echo -e "${GREEN}✓ GPU VRAM allocated: ${GPU_VRAM_ALLOCATED}GB (models load here)${NC}"
elif grep -q "amdgpu.gttsize" /proc/cmdline 2>/dev/null; then
    # Detect custom VRAM size
    GPU_VRAM_ALLOCATED=$(grep -oP 'amdgpu.gttsize=\K\d+' /proc/cmdline | head -n1)
    GPU_VRAM_ALLOCATED=$((GPU_VRAM_ALLOCATED / 1024))  # Convert to GB
    echo -e "${GREEN}✓ GPU VRAM allocated: ${GPU_VRAM_ALLOCATED}GB${NC}"
fi

# Calculate available for LXC (Total - GPU VRAM - 4GB host overhead)
AVAILABLE_RAM=$((TOTAL_RAM_GB - GPU_VRAM_ALLOCATED - 4))
if [ $AVAILABLE_RAM -lt 0 ]; then
    AVAILABLE_RAM=$((TOTAL_RAM_GB - 4))
fi

echo -e "${CYAN}System Memory Overview:${NC}"
echo "  Total RAM:           ${TOTAL_RAM_GB}GB"
if [ $GPU_VRAM_ALLOCATED -gt 0 ]; then
    echo "  GPU VRAM:            ${GPU_VRAM_ALLOCATED}GB (for AI model weights)"
fi
echo "  Host overhead:       ~4GB"
echo "  Available for LXC:   ~${AVAILABLE_RAM}GB"
echo ""

# Determine smart defaults based on available RAM
DEFAULT_DISK="256"
DEFAULT_SWAP="8192"
DEFAULT_CORES="12"

if [ $AVAILABLE_RAM -ge 20 ]; then
    DEFAULT_MEMORY="16384"  # 16GB - comfortable for multi-service
elif [ $AVAILABLE_RAM -ge 12 ]; then
    DEFAULT_MEMORY="8192"   # 8GB - works for most single services
else
    DEFAULT_MEMORY="4096"   # 4GB - minimal
fi

echo -e "${GREEN}>>> Container resource configuration...${NC}"
echo ""
echo -e "${CYAN}Recommended for multi-service GPU workloads:${NC}"
echo "  • Disk: 256GB+ (OS, Docker, models, outputs)"
echo "  • RAM:  16GB+  (Docker overhead, preprocessing)"
echo "  • Note: AI models load into GPU VRAM, not LXC RAM"
echo ""

# Prompt for disk size
read -r -p "Enter disk size in GB [$DEFAULT_DISK]: " DISK_SIZE
DISK_SIZE=${DISK_SIZE:-$DEFAULT_DISK}

# Validate disk size
if ! [[ "$DISK_SIZE" =~ ^[0-9]+$ ]] || [ "$DISK_SIZE" -lt 8 ]; then
    echo -e "${RED}✗ Invalid disk size. Must be at least 8GB${NC}"
    exit 1
fi

# Warn if disk is small for multi-service
if [ "$DISK_SIZE" -lt 200 ]; then
    echo -e "${YELLOW}⚠️  Warning: ${DISK_SIZE}GB may be insufficient for multiple services${NC}"
    echo "   (Ollama models + ComfyUI + outputs can easily exceed 100GB)"
fi

# Prompt for memory
read -r -p "Enter memory in MB [$DEFAULT_MEMORY]: " MEMORY
MEMORY=${MEMORY:-$DEFAULT_MEMORY}

# Validate memory
if ! [[ "$MEMORY" =~ ^[0-9]+$ ]] || [ "$MEMORY" -lt 512 ]; then
    echo -e "${RED}✗ Invalid memory size. Must be at least 512MB${NC}"
    exit 1
fi

# Check if memory exceeds available
MEMORY_GB=$((MEMORY / 1024))
if [ $MEMORY_GB -gt $AVAILABLE_RAM ]; then
    echo -e "${YELLOW}⚠️  Warning: Requested ${MEMORY_GB}GB exceeds available ~${AVAILABLE_RAM}GB${NC}"
    if [ $GPU_VRAM_ALLOCATED -gt 0 ]; then
        echo "   (After accounting for ${GPU_VRAM_ALLOCATED}GB GPU VRAM)"
    fi
    echo ""
    read -r -p "Continue anyway? [y/N]: " CONTINUE
    if [[ ! "$CONTINUE" =~ ^[Yy]$ ]]; then
        MEMORY=$DEFAULT_MEMORY
        echo "Using ${MEMORY}MB instead"
    fi
fi

# Warn if memory is small
if [ $MEMORY_GB -lt 16 ]; then
    echo -e "${YELLOW}⚠️  Note: ${MEMORY_GB}GB RAM is minimal for running multiple GPU services${NC}"
    echo "   Recommended: 16GB+ for Ollama + ComfyUI + other services"
fi

# Prompt for CPU cores
read -r -p "Enter CPU cores [$DEFAULT_CORES]: " CORES
CORES=${CORES:-$DEFAULT_CORES}

# Validate cores
if ! [[ "$CORES" =~ ^[0-9]+$ ]] || [ "$CORES" -lt 1 ]; then
    echo -e "${RED}✗ Invalid CPU cores. Must be at least 1${NC}"
    exit 1
fi

# Prompt for swap
read -r -p "Enter swap in MB [$DEFAULT_SWAP]: " SWAP
SWAP=${SWAP:-$DEFAULT_SWAP}

# Validate swap
if ! [[ "$SWAP" =~ ^[0-9]+$ ]]; then
    echo -e "${RED}✗ Invalid swap size${NC}"
    exit 1
fi

echo ""
echo -e "${GREEN}>>> Configuration Summary${NC}"
echo "Container ID: $CONTAINER_ID"
echo "GPU Type: $([ "$GPU_TYPE" == "1" ] && echo "AMD" || echo "NVIDIA")"
echo "GPU PCI Address: $PCI_ADDRESS"
echo "Network:"
echo "  IP Address: $IP_ADDRESS"
echo "  Gateway: $GATEWAY"
echo "  Hostname: $HOSTNAME"
echo "  MAC Address: $MAC_ADDRESS"
echo "Resources:"
echo "  Storage: $STORAGE"
echo "  Disk Size: ${DISK_SIZE}GB"
echo "  Memory: ${MEMORY}MB"
echo "  CPU Cores: $CORES"
echo "  Swap: ${SWAP}MB"
echo ""
read -r -p "Proceed with container creation? [Y/n]: " CONFIRM
CONFIRM=${CONFIRM:-Y}

if [[ ! "$CONFIRM" =~ ^[Yy]$ ]]; then
    echo "Cancelled."
    exit 0
fi

echo ""
echo -e "${GREEN}>>> Updating Proxmox VE Appliance list${NC}"
pveam update

echo -e "${GREEN}>>> Downloading Ubuntu 24.04 LXC template to local storage${NC}"
pveam download local ubuntu-24.04-standard_24.04-2_amd64.tar.zst 2>/dev/null || echo "Template already exists"

echo -e "${GREEN}>>> Creating LXC container with GPU passthrough support${NC}"
pct create "$CONTAINER_ID" local:vztmpl/ubuntu-24.04-standard_24.04-2_amd64.tar.zst \
    --arch amd64 \
    --cores "$CORES" \
    --features nesting=1 \
    --hostname "$HOSTNAME" \
    --memory "$MEMORY" \
    --net0 "name=eth0,bridge=vmbr0,firewall=1,gw=$GATEWAY,hwaddr=$MAC_ADDRESS,ip=$IP_ADDRESS/24,type=veth" \
    --ostype ubuntu \
    --password testing \
    --rootfs "${STORAGE}:${DISK_SIZE}" \
    --swap "$SWAP" \
    --tags "docker;ollama;${ADDITIONAL_TAGS}" \
    --unprivileged 0

echo -e "${GREEN}>>> Added LXC container with ID $CONTAINER_ID${NC}"

# Configure GPU passthrough based on type
if [ "$GPU_TYPE" == "1" ]; then
    # AMD GPU Configuration
    echo -e "${GREEN}>>> Configuring AMD GPU passthrough${NC}"
    
    cat >> "/etc/pve/lxc/${CONTAINER_ID}.conf" << EOF
# ===== AMD GPU Passthrough Configuration =====
# PCI Address: $PCI_ADDRESS
# Using persistent by-path device names to ensure consistent mapping
# Allow access to cgroup devices (DRI and KFD)
lxc.cgroup2.devices.allow: c 226:* rwm
lxc.cgroup2.devices.allow: c 234:* rwm
# Mount DRI devices using persistent PCI paths
lxc.mount.entry: /dev/dri/by-path/pci-${PCI_ADDRESS}-card dev/dri/card0 none bind,optional,create=file
lxc.mount.entry: /dev/dri/by-path/pci-${PCI_ADDRESS}-render dev/dri/renderD128 none bind,optional,create=file
# Mount KFD device (ROCm compute interface - required for ROCm)
lxc.mount.entry: /dev/kfd dev/kfd none bind,optional,create=file
# Allow system-level capabilities for GPU drivers
lxc.apparmor.profile: unconfined
lxc.cap.drop:
# ===== End GPU Configuration =====
EOF
else
    # NVIDIA GPU Configuration
    echo -e "${GREEN}>>> Configuring NVIDIA GPU passthrough${NC}"
    
    cat >> "/etc/pve/lxc/${CONTAINER_ID}.conf" << EOF
# ===== NVIDIA GPU Passthrough Configuration =====
# PCI Address: $PCI_ADDRESS
# Allow access to cgroup devices (NVIDIA and DRI)
lxc.cgroup2.devices.allow: c 195:* rwm
lxc.cgroup2.devices.allow: c 226:* rwm
lxc.cgroup2.devices.allow: c 234:* rwm
lxc.cgroup2.devices.allow: c 237:* rwm
lxc.cgroup2.devices.allow: c 238:* rwm
lxc.cgroup2.devices.allow: c 239:* rwm
lxc.cgroup2.devices.allow: c 240:* rwm
lxc.cgroup2.devices.allow: c 508:* rwm
# Mount NVIDIA devices
lxc.mount.entry: /dev/nvidia0 dev/nvidia0 none bind,optional,create=file
lxc.mount.entry: /dev/nvidiactl dev/nvidiactl none bind,optional,create=file
lxc.mount.entry: /dev/nvidia-modeset dev/nvidia-modeset none bind,optional,create=file
lxc.mount.entry: /dev/nvidia-uvm dev/nvidia-uvm none bind,optional,create=file
lxc.mount.entry: /dev/nvidia-uvm-tools dev/nvidia-uvm-tools none bind,optional,create=file
lxc.mount.entry: /dev/nvidia-caps/nvidia-cap1 dev/nvidia-caps/nvidia-cap1 none bind,optional,create=file
lxc.mount.entry: /dev/nvidia-caps/nvidia-cap2 dev/nvidia-caps/nvidia-cap2 none bind,optional,create=file
# Mount DRI devices using persistent PCI paths
lxc.mount.entry: /dev/dri/by-path/pci-${PCI_ADDRESS}-card dev/dri/card0 none bind,optional,create=file
lxc.mount.entry: /dev/dri/by-path/pci-${PCI_ADDRESS}-render dev/dri/renderD128 none bind,optional,create=file
# Allow system-level capabilities for GPU drivers
lxc.apparmor.profile: unconfined
lxc.cap.drop:
# ===== End GPU Configuration =====
EOF
fi

echo -e "${GREEN}>>> Starting container${NC}"
pct start "$CONTAINER_ID"
sleep 5

echo -e "${GREEN}>>> Mounting scripts directory into container${NC}"
# Get the repository root directory (parent of host/)
REPO_DIR="$(dirname "$SCRIPT_DIR")"
# Add bind mount for scripts directory
pct set "$CONTAINER_ID" -mp0 "$REPO_DIR,mp=/root/proxmox-setup-scripts"

echo -e "${GREEN}>>> Enabling SSH root login${NC}"
pct exec "$CONTAINER_ID" -- bash -c "sed -i 's/#PermitRootLogin prohibit-password/PermitRootLogin yes/' /etc/ssh/sshd_config"
pct exec "$CONTAINER_ID" -- bash -c "sed -i 's/PermitRootLogin prohibit-password/PermitRootLogin yes/' /etc/ssh/sshd_config"
pct exec "$CONTAINER_ID" -- systemctl restart sshd

echo ""
echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}>>> LXC Container Setup Complete! <<<${NC}"
echo -e "${GREEN}========================================${NC}"
echo ""
echo "Container ID: $CONTAINER_ID"
echo "GPU Type: $([ "$GPU_TYPE" == "1" ] && echo "AMD" || echo "NVIDIA")"
echo "GPU PCI Address: $PCI_ADDRESS"
echo "SSH Access: ssh root@$IP_ADDRESS"
echo "Default Password: testing"
echo "Scripts mounted at: /root/proxmox-setup-scripts"
echo ""
echo -e "${YELLOW}IMPORTANT: Change the default password after first login!${NC}"
echo ""

# Verify GPU devices are accessible inside container
echo -e "${GREEN}>>> Verifying GPU passthrough in container...${NC}"
echo ""

if [ "$GPU_TYPE" == "1" ]; then
    # AMD GPU Configuration - Verify devices exist
    GPU_PASSTHROUGH_OK=true
    
    echo -e "${YELLOW}Checking /dev/dri/ devices:${NC}"
    if pct exec "$CONTAINER_ID" -- ls -la /dev/dri/ 2>/dev/null | grep -q "card0"; then
        echo -e "${GREEN}✓ /dev/dri/card0 accessible${NC}"
    else
        echo -e "${RED}✗ /dev/dri/card0 NOT accessible${NC}"
        GPU_PASSTHROUGH_OK=false
    fi
    
    if pct exec "$CONTAINER_ID" -- ls -la /dev/dri/ 2>/dev/null | grep -q "renderD128"; then
        echo -e "${GREEN}✓ /dev/dri/renderD128 accessible${NC}"
    else
        echo -e "${RED}✗ /dev/dri/renderD128 NOT accessible${NC}"
        GPU_PASSTHROUGH_OK=false
    fi
    
    echo ""
    echo -e "${YELLOW}Checking /dev/kfd:${NC}"
    if pct exec "$CONTAINER_ID" -- test -e /dev/kfd 2>/dev/null; then
        echo -e "${GREEN}✓ /dev/kfd accessible${NC}"
        pct exec "$CONTAINER_ID" -- ls -la /dev/kfd 2>/dev/null
    else
        echo -e "${RED}✗ /dev/kfd NOT accessible${NC}"
        GPU_PASSTHROUGH_OK=false
    fi
    
    echo ""
    if [ "$GPU_PASSTHROUGH_OK" = false ]; then
        echo -e "${RED}========================================${NC}"
        echo -e "${RED}GPU Passthrough Verification FAILED${NC}"
        echo -e "${RED}========================================${NC}"
        echo ""
        echo -e "${YELLOW}GPU devices are not accessible inside the container.${NC}"
        echo ""
        echo -e "${YELLOW}Troubleshooting:${NC}"
        echo "  1. Check container config: cat /etc/pve/lxc/${CONTAINER_ID}.conf"
        echo "  2. Verify PCI address is correct: $PCI_ADDRESS"
        echo "  3. Check host devices: ls -la /dev/dri/by-path/ /dev/kfd"
        echo "  4. Try restarting container: pct restart $CONTAINER_ID"
        echo ""
        read -r -p "Continue anyway? [y/N]: " CONTINUE
        CONTINUE=${CONTINUE:-N}
        if [[ ! "$CONTINUE" =~ ^[Yy]$ ]]; then
            echo ""
            echo -e "${YELLOW}Container created but GPU passthrough needs fixing.${NC}"
            echo "Container ID: $CONTAINER_ID"
            exit 1
        fi
    else
        echo -e "${GREEN}========================================${NC}"
        echo -e "${GREEN}✓ GPU Passthrough Verified Successfully${NC}"
        echo -e "${GREEN}========================================${NC}"
    fi
    
    echo ""
    read -r -p "Install Docker and AMD ROCm libraries now? [Y/n]: " RUN_INSTALL
    RUN_INSTALL=${RUN_INSTALL:-Y}
    
    if [[ "$RUN_INSTALL" =~ ^[Yy]$ ]]; then
        echo ""
        echo -e "${GREEN}>>> Running AMD GPU installation script...${NC}"
        pct exec "$CONTAINER_ID" -- bash /root/proxmox-setup-scripts/lxc/install-docker-and-amd-drivers-in-lxc.sh
        echo ""
        echo "  # You can SSH into container:"
        echo "  ssh root@$IP_ADDRESS"
        echo "  cd /root/proxmox-setup-scripts/lxc"
        echo "  ./install-docker-and-amd-drivers-in-lxc.sh"

    else
        echo ""
        echo -e "${YELLOW}Installation skipped. You can run it manually later:${NC}"
        echo "  # From Proxmox host:"
        echo "  pct exec $CONTAINER_ID -- bash /root/proxmox-setup-scripts/lxc/install-docker-and-amd-drivers-in-lxc.sh"
        echo ""
        echo "  # Or SSH into container:"
        echo "  ssh root@$IP_ADDRESS"
        echo "  cd /root/proxmox-setup-scripts/lxc"
        echo "  ./install-docker-and-amd-drivers-in-lxc.sh"
    fi
else
    # NVIDIA GPU Configuration - Verify devices exist
    GPU_PASSTHROUGH_OK=true
    
    echo -e "${YELLOW}Checking NVIDIA devices:${NC}"
    NVIDIA_DEVICES=("/dev/nvidia0" "/dev/nvidiactl" "/dev/nvidia-uvm")
    for dev in "${NVIDIA_DEVICES[@]}"; do
        dev_name=$(basename "$dev")
        if pct exec "$CONTAINER_ID" -- test -e "$dev" 2>/dev/null; then
            echo -e "${GREEN}✓ $dev accessible${NC}"
        else
            echo -e "${YELLOW}⚠ $dev not accessible (may be optional)${NC}"
        fi
    done
    
    echo ""
    echo -e "${YELLOW}Checking /dev/dri/ devices:${NC}"
    if pct exec "$CONTAINER_ID" -- ls -la /dev/dri/ 2>/dev/null | grep -q "card0"; then
        echo -e "${GREEN}✓ /dev/dri/card0 accessible${NC}"
    else
        echo -e "${RED}✗ /dev/dri/card0 NOT accessible${NC}"
        GPU_PASSTHROUGH_OK=false
    fi
    
    if pct exec "$CONTAINER_ID" -- ls -la /dev/dri/ 2>/dev/null | grep -q "renderD128"; then
        echo -e "${GREEN}✓ /dev/dri/renderD128 accessible${NC}"
    else
        echo -e "${RED}✗ /dev/dri/renderD128 NOT accessible${NC}"
        GPU_PASSTHROUGH_OK=false
    fi
    
    echo ""
    if [ "$GPU_PASSTHROUGH_OK" = false ]; then
        echo -e "${RED}========================================${NC}"
        echo -e "${RED}GPU Passthrough Verification FAILED${NC}"
        echo -e "${RED}========================================${NC}"
        echo ""
        echo -e "${YELLOW}GPU devices are not accessible inside the container.${NC}"
        echo ""
        echo -e "${YELLOW}Troubleshooting:${NC}"
        echo "  1. Check container config: cat /etc/pve/lxc/${CONTAINER_ID}.conf"
        echo "  2. Verify PCI address is correct: $PCI_ADDRESS"
        echo "  3. Check host devices: ls -la /dev/dri/by-path/ /dev/nvidia*"
        echo "  4. Check NVIDIA driver on host: nvidia-smi"
        echo "  5. Try restarting container: pct restart $CONTAINER_ID"
        echo ""
        read -r -p "Continue anyway? [y/N]: " CONTINUE
        CONTINUE=${CONTINUE:-N}
        if [[ ! "$CONTINUE" =~ ^[Yy]$ ]]; then
            echo ""
            echo -e "${YELLOW}Container created but GPU passthrough needs fixing.${NC}"
            echo "Container ID: $CONTAINER_ID"
            exit 1
        fi
    else
        echo -e "${GREEN}========================================${NC}"
        echo -e "${GREEN}✓ GPU Passthrough Verified Successfully${NC}"
        echo -e "${GREEN}========================================${NC}"
    fi
    
    echo ""
    read -r -p "Install Docker, NVIDIA libraries, and NVIDIA Container Toolkit now? [Y/n]: " RUN_INSTALL
    RUN_INSTALL=${RUN_INSTALL:-Y}
    
    if [[ "$RUN_INSTALL" =~ ^[Yy]$ ]]; then
        echo ""
        echo -e "${GREEN}>>> Running NVIDIA GPU installation script...${NC}"
        pct exec "$CONTAINER_ID" -- bash /root/proxmox-setup-scripts/lxc/install-docker-and-nvidia-drivers-in-lxc.sh
        echo ""
        echo "  # You can SSH into container:"
        echo "  ssh root@$IP_ADDRESS"
        echo "  cd /root/proxmox-setup-scripts/lxc"
        echo "  ./install-docker-and-nvidia-drivers-in-lxc.sh"
    else
        echo ""
        echo -e "${YELLOW}Installation skipped. You can run it manually later:${NC}"
        echo "  # From Proxmox host:"
        echo "  pct exec $CONTAINER_ID -- bash /root/proxmox-setup-scripts/lxc/install-docker-and-nvidia-drivers-in-lxc.sh"
        echo ""
        echo "  # Or SSH into container:"
        echo "  ssh root@$IP_ADDRESS"
        echo "  cd /root/proxmox-setup-scripts/lxc"
        echo "  ./install-docker-and-nvidia-drivers-in-lxc.sh"
    fi
fi
echo ""
echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}LXC Container Setup and Testing Complete!${NC}"
echo -e "${GREEN}========================================${NC}"
echo ""
echo "Container ID: $CONTAINER_ID"
echo "GPU Type: $([ "$GPU_TYPE" == "1" ] && echo "AMD" || echo "NVIDIA")"
echo "GPU PCI Address: $PCI_ADDRESS"
echo "SSH Access: ssh root@$IP_ADDRESS"
echo "Default Password: testing"
echo "Scripts mounted at: /root/proxmox-setup-scripts"
echo ""
echo -e "${YELLOW}IMPORTANT: Change the default password after first login!${NC}"
echo ""

# Offer to install add-on services
echo ""
echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}Optional Add-ons${NC}"
echo -e "${GREEN}========================================${NC}"
echo ""
echo "Install additional services in this container?"
echo ""
echo -e "${CYAN}Available add-ons:${NC}"
echo "  [1] Portainer       - Docker management web UI"
echo "  [2] Ollama          - Run LLMs (Llama, Mistral, etc.)"
echo "  [3] Open WebUI      - ChatGPT-like interface for Ollama"
echo "  [4] ComfyUI         - Stable Diffusion image generation"
echo "  [5] All of the above"
echo "  [6] None - I'll install manually later"
echo ""
read -r -p "Select options (comma-separated, e.g. 1,2,3) [6]: " ADDON_CHOICE
ADDON_CHOICE=${ADDON_CHOICE:-6}

# Parse choices
INSTALL_PORTAINER=false
INSTALL_OLLAMA=false
INSTALL_OPENWEBUI=false
INSTALL_COMFYUI=false

if [[ "$ADDON_CHOICE" == "5" ]]; then
    INSTALL_PORTAINER=true
    INSTALL_OLLAMA=true
    INSTALL_OPENWEBUI=true
    INSTALL_COMFYUI=true
elif [[ "$ADDON_CHOICE" != "6" ]]; then
    IFS=',' read -ra CHOICES <<< "$ADDON_CHOICE"
    for choice in "${CHOICES[@]}"; do
        choice=$(echo "$choice" | tr -d ' ')
        case "$choice" in
            1) INSTALL_PORTAINER=true ;;
            2) INSTALL_OLLAMA=true ;;
            3) INSTALL_OPENWEBUI=true ;;
            4) INSTALL_COMFYUI=true ;;
        esac
    done
fi

# Install selected add-ons
if [ "$INSTALL_PORTAINER" = true ] || [ "$INSTALL_OLLAMA" = true ] || [ "$INSTALL_OPENWEBUI" = true ] || [ "$INSTALL_COMFYUI" = true ]; then
    echo ""
    echo -e "${GREEN}>>> Installing selected add-ons...${NC}"
    echo ""
    
    if [ "$INSTALL_PORTAINER" = true ]; then
        echo -e "${CYAN}=== Installing Portainer ===${NC}"
        bash "${SCRIPT_DIR}/031 - install-portainer.sh" "$CONTAINER_ID" || echo -e "${YELLOW}⚠️  Portainer installation had issues${NC}"
        echo ""
    fi
    
    if [ "$INSTALL_OLLAMA" = true ]; then
        echo -e "${CYAN}=== Installing Ollama ===${NC}"
        bash "${SCRIPT_DIR}/032 - install-ollama.sh" "$CONTAINER_ID" || echo -e "${YELLOW}⚠️  Ollama installation had issues${NC}"
        echo ""
    fi
    
    if [ "$INSTALL_OPENWEBUI" = true ]; then
        echo -e "${CYAN}=== Installing Open WebUI ===${NC}"
        bash "${SCRIPT_DIR}/033 - install-open-webui.sh" "$CONTAINER_ID" || echo -e "${YELLOW}⚠️  Open WebUI installation had issues${NC}"
        echo ""
    fi
    
    if [ "$INSTALL_COMFYUI" = true ]; then
        echo -e "${CYAN}=== Installing ComfyUI ===${NC}"
        bash "${SCRIPT_DIR}/034 - install-comfyui.sh" "$CONTAINER_ID" || echo -e "${YELLOW}⚠️  ComfyUI installation had issues${NC}"
        echo ""
    fi
    
    echo ""
    echo -e "${GREEN}========================================${NC}"
    echo -e "${GREEN}Add-on Installation Complete!${NC}"
    echo -e "${GREEN}========================================${NC}"
    echo ""
    
    # Show access URLs
    echo -e "${CYAN}Access your services:${NC}"
    if [ "$INSTALL_PORTAINER" = true ]; then
        echo "  Portainer:  https://$IP_ADDRESS:9443"
    fi
    if [ "$INSTALL_OLLAMA" = true ]; then
        echo "  Ollama:     ssh root@$IP_ADDRESS, then: ollama run llama3.2:3b"
    fi
    if [ "$INSTALL_OPENWEBUI" = true ]; then
        echo "  Open WebUI: http://$IP_ADDRESS:3000"
    fi
    if [ "$INSTALL_COMFYUI" = true ]; then
        echo "  ComfyUI:    http://$IP_ADDRESS:8188"
    fi
    echo ""
else
    echo ""
    echo -e "${CYAN}You can install add-ons later by running:${NC}"
    echo "  ./guided-install.sh → Choose 031-034"
    echo ""
fi

echo ""
