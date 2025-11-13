#!/usr/bin/env bash
# SCRIPT_DESC: Install NVIDIA CUDA drivers and modules
# SCRIPT_DETECT: command -v nvidia-smi &>/dev/null

# Get script directory and source utilities
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/../includes/colors.sh"
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/../includes/gpu-detect.sh"

# Check if NVIDIA GPU is present
if ! detect_nvidia_gpus; then
    echo -e "${YELLOW}========================================${NC}"
    echo -e "${YELLOW}No NVIDIA GPUs detected on this system${NC}"
    echo -e "${YELLOW}========================================${NC}"
    echo ""
    echo -e "${YELLOW}This script installs NVIDIA GPU drivers, but no NVIDIA GPUs were found.${NC}"
    echo ""
    echo -e "${YELLOW}Available GPUs:${NC}"
    lspci -nn | grep -i "VGA\|3D\|Display"
    echo ""
    read -r -p "Continue anyway? [y/N]: " CONTINUE
    CONTINUE=${CONTINUE:-N}
    if [[ ! "$CONTINUE" =~ ^[Yy]$ ]]; then
        echo "Skipped."
        exit 0
    fi
fi

echo -e "${GREEN}>>> Installing NVIDIA drivers${NC}"

# Ensure required tools are available
for tool in wget; do
    if ! command -v $tool &>/dev/null; then
        echo ">>> Installing required tool: $tool"
        apt-get update -qq && apt-get install -y $tool >/dev/null 2>&1
    fi
done

echo ""
echo -e "${CYAN}>>> Installing NVIDIA drivers and CUDA support${NC}"
echo ""

# Check if drivers are already installed
if command -v nvidia-smi &>/dev/null && lsmod | grep -q "^nvidia "; then
    CURRENT_VERSION=$(nvidia-smi --query-gpu=driver_version --format=csv,noheader 2>/dev/null | head -1)
    echo -e "${GREEN}✓ NVIDIA drivers already installed and loaded${NC}"
    echo -e "${DIM}Driver version: ${CURRENT_VERSION}${NC}"
    echo ""
    exit 0
fi

# Install prerequisites first
echo ">>> Installing prerequisites..."
apt-get update -qq 2>&1 | grep -v "Policy will reject signature"
apt-get install -y proxmox-headers-"$(uname -r)" wget 2>&1 | grep -v "Policy will reject signature"

# Enable Debian non-free repository (required for nvidia-driver packages)
echo ">>> Enabling Debian non-free repository..."
if ! grep -q "non-free non-free-firmware" /etc/apt/sources.list.d/debian.sources; then
    sed -i 's/Components: main contrib non-free-firmware/Components: main contrib non-free non-free-firmware/' /etc/apt/sources.list.d/debian.sources
    echo ">>> Enabled non-free component for NVIDIA drivers"
fi

# Add NVIDIA CUDA repository
if [ ! -f /etc/apt/sources.list.d/cuda-debian12-x86_64.list ]; then
    echo ">>> Adding NVIDIA CUDA repository..."
    wget -q https://developer.download.nvidia.com/compute/cuda/repos/debian12/x86_64/cuda-keyring_1.1-1_all.deb
    dpkg -i cuda-keyring_1.1-1_all.deb
    rm cuda-keyring_1.1-1_all.deb
fi

# Update package cache with new repositories
apt-get update -qq 2>&1 | grep -v "Policy will reject signature"

# Fetch available driver versions from nvidia-driver package versions
echo ""
echo -e "${CYAN}>>> Fetching available NVIDIA driver versions...${NC}"

# Query apt-cache policy to get all available versions of nvidia-driver
AVAILABLE_VERSIONS=$(apt-cache policy nvidia-driver 2>/dev/null | \
    grep -oP '^\s+\K[0-9]+\.[0-9]+\.[0-9]+-[0-9]+' | \
    sort -V -r | \
    head -20)

if [ -z "$AVAILABLE_VERSIONS" ]; then
    echo -e "${RED}ERROR: Could not fetch driver versions from repository${NC}"
    echo -e "${YELLOW}This usually means:${NC}"
    echo "  1. Network connectivity issue"
    echo "  2. Repository not properly configured"
    echo ""
    exit 1
fi

# Extract unique driver branches (e.g., 580, 575, 570, 565, etc.)
declare -A DRIVER_BRANCHES
declare -a BRANCH_ORDER
while read version; do
    branch=$(echo "$version" | cut -d'.' -f1)
    if [ -z "${DRIVER_BRANCHES[$branch]}" ]; then
        DRIVER_BRANCHES[$branch]=$version
        BRANCH_ORDER+=($branch)
    fi
done <<< "$AVAILABLE_VERSIONS"

# Show latest 6 driver branches
echo ""
echo -e "${YELLOW}Available NVIDIA driver branches (latest versions):${NC}"
BRANCH_COUNT=0
for branch in "${BRANCH_ORDER[@]}"; do
    [ $BRANCH_COUNT -ge 6 ] && break
    version="${DRIVER_BRANCHES[$branch]}"
    case "$branch" in
        550) echo "  $branch ($version) - Long-lived branch (most stable)" ;;
        545|555|560|565|570|575|580) echo "  $branch ($version) - Production branch" ;;
        *) echo "  $branch ($version)" ;;
    esac
    ((BRANCH_COUNT++))
done

# Default to the newest branch
DEFAULT_BRANCH="${BRANCH_ORDER[0]}"

echo ""
echo -e "${DIM}Branches: 550 = stable long-lived, higher numbers = newer${NC}"
echo -e "${DIM}Full version will be installed (e.g., 550 → 550.163.01)${NC}"
echo ""
read -r -p "Select driver branch to install [${DEFAULT_BRANCH}]: " DRIVER_BRANCH
DRIVER_BRANCH=${DRIVER_BRANCH:-${DEFAULT_BRANCH}}

# Validate branch selection
if [ -z "${DRIVER_BRANCHES[$DRIVER_BRANCH]}" ]; then
    echo -e "${RED}ERROR: Driver branch ${DRIVER_BRANCH} not found${NC}"
    echo -e "${YELLOW}Available branches: ${BRANCH_ORDER[*]}${NC}"
    exit 1
fi

# Get the specific version for this branch
DRIVER_VERSION="${DRIVER_BRANCHES[$DRIVER_BRANCH]}"

# Detect GPU architecture and Secure Boot status
GPU_ARCH=$(lspci -nn | grep -i "VGA.*NVIDIA\|3D.*NVIDIA" | head -1 | grep -oP '\[10de:[0-9a-f]+\]')
SECURE_BOOT_ENABLED=false
if mokutil --sb-state 2>/dev/null | grep -q "SecureBoot enabled"; then
    SECURE_BOOT_ENABLED=true
fi

# Determine which kernel module to recommend
# Open kernel module is recommended for Turing (20xx) and newer
# Reference: https://github.com/NVIDIA/open-gpu-kernel-modules
echo ""
echo -e "${CYAN}>>> Selecting kernel module...${NC}"

# Detect GPU generation for smart defaults
GPU_NAME=$(lspci | grep -i "VGA.*NVIDIA\|3D.*NVIDIA" | head -1)
RECOMMEND_OPEN=false

# Check for newer GPU architectures (Turing+: RTX 20xx, 30xx, 40xx, 50xx, A-series)
if echo "$GPU_NAME" | grep -Ei "RTX (20|30|40|50|A)[0-9]|A[0-9]{3,4}|L[0-9]{1,2}"; then
    RECOMMEND_OPEN=true
fi

echo ""
echo -e "${YELLOW}Kernel Module Options:${NC}"
echo ""
echo "  1) nvidia-kernel-dkms (Proprietary)"
echo "     • Mature and stable"
echo "     • Works with all NVIDIA GPUs"
if [ "$SECURE_BOOT_ENABLED" = true ]; then
    echo "     • ${RED}⚠ Requires Secure Boot to be disabled${NC}"
fi
echo ""
echo "  2) nvidia-kernel-open-dkms (Open Source)"
echo "     • Recommended for RTX 20xx and newer"
echo "     • Better performance on newer GPUs"
if [ "$SECURE_BOOT_ENABLED" = true ]; then
    echo "     • ${GREEN}✓ Works with Secure Boot (signed)${NC}"
fi
echo ""

if [ "$SECURE_BOOT_ENABLED" = true ]; then
    echo -e "${YELLOW}Note: Secure Boot is currently ENABLED on your system${NC}"
    echo ""
fi

# Determine default based on GPU and Secure Boot
if [ "$SECURE_BOOT_ENABLED" = true ] || [ "$RECOMMEND_OPEN" = true ]; then
    DEFAULT_CHOICE="2"
    echo -e "${CYAN}Detected: $GPU_NAME${NC}"
    if [ "$RECOMMEND_OPEN" = true ]; then
        echo -e "${GREEN}Recommendation: Open kernel module (better for your GPU)${NC}"
    else
        echo -e "${GREEN}Recommendation: Open kernel module (required for Secure Boot)${NC}"
    fi
else
    DEFAULT_CHOICE="1"
    echo -e "${CYAN}Detected: $GPU_NAME${NC}"
fi

echo ""
read -r -p "Select kernel module [${DEFAULT_CHOICE}]: " KERNEL_CHOICE
KERNEL_CHOICE=${KERNEL_CHOICE:-${DEFAULT_CHOICE}}

case "$KERNEL_CHOICE" in
    1)
        KERNEL_MODULE="nvidia-kernel-dkms"
        if [ "$SECURE_BOOT_ENABLED" = true ]; then
            echo ""
            echo -e "${YELLOW}⚠ WARNING: Secure Boot is enabled${NC}"
            echo -e "${YELLOW}The proprietary module will NOT load until you:${NC}"
            echo "  1. Disable Secure Boot in BIOS, OR"
            echo "  2. Sign the module with Machine Owner Key (MOK)"
            echo ""
            read -r -p "Continue anyway? [y/N]: " CONTINUE
            CONTINUE=${CONTINUE:-N}
            if [[ ! "$CONTINUE" =~ ^[Yy]$ ]]; then
                echo "Installation cancelled."
                exit 0
            fi
        fi
        ;;
    2)
        KERNEL_MODULE="nvidia-kernel-open-dkms"
        echo -e "${GREEN}Using open kernel module${NC}"
        ;;
    *)
        echo -e "${RED}Invalid choice${NC}"
        exit 1
        ;;
esac

echo ""
echo -e "${CYAN}>>> Installing NVIDIA driver ${DRIVER_VERSION} (branch ${DRIVER_BRANCH})${NC}"
echo -e "${DIM}Kernel module: ${KERNEL_MODULE}${NC}"
echo ""

# Install full driver stack
# Note: nvidia-driver-cuda provides nvidia-smi and CUDA integration for all versions
DEBIAN_FRONTEND=noninteractive apt-get install -y \
    nvidia-driver=${DRIVER_VERSION} \
    ${KERNEL_MODULE}=${DRIVER_VERSION} \
    nvidia-driver-cuda=${DRIVER_VERSION}

# Handle MOK enrollment for open kernel module with Secure Boot
if [ "$KERNEL_MODULE" = "nvidia-kernel-open-dkms" ] && [ "$SECURE_BOOT_ENABLED" = true ]; then
    echo ""
    echo -e "${YELLOW}╔══════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${YELLOW}║            Secure Boot Detected - Action Required           ║${NC}"
    echo -e "${YELLOW}╚══════════════════════════════════════════════════════════════╝${NC}"
    echo ""
    echo -e "${CYAN}The NVIDIA open kernel module requires authorization to load.${NC}"
    echo ""
    echo -e "${YELLOW}You have TWO options:${NC}"
    echo ""
    echo -e "${GREEN}Option 1: MOK Enrollment (Recommended)${NC}"
    echo "  • Keeps Secure Boot enabled (more secure)"
    echo "  • One-time setup during next boot"
    echo "  • You'll enter a password in MOK Manager before Proxmox boots"
    echo "  • Best for production environments"
    echo ""
    echo -e "${GREEN}Option 2: Disable Secure Boot${NC}"
    echo "  • Simpler - no enrollment needed"
    echo "  • Disable Secure Boot in your BIOS/UEFI settings"
    echo "  • Modules will load automatically after reboot"
    echo "  • Fine for most Proxmox hosts"
    echo ""
    echo -e "${DIM}Note: Most Proxmox users disable Secure Boot for simplicity.${NC}"
    echo ""
    
    read -r -p "Continue with MOK enrollment? [y/N]: " CONTINUE_MOK
    CONTINUE_MOK=${CONTINUE_MOK:-N}
    
    if [[ ! "$CONTINUE_MOK" =~ ^[Yy]$ ]]; then
        echo ""
        echo -e "${YELLOW}Skipping MOK enrollment.${NC}"
        echo ""
        echo -e "${CYAN}To complete installation:${NC}"
        echo "  1. Reboot into BIOS/UEFI settings"
        echo "  2. Find 'Secure Boot' setting (usually in Security or Boot menu)"
        echo "  3. Set to: ${GREEN}Disabled${NC}"
        echo "  4. Save and reboot"
        echo "  5. NVIDIA driver will load automatically"
        echo ""
        echo -e "${GREEN}>>> NVIDIA driver installation completed${NC}"
        echo -e "${YELLOW}⚠  Disable Secure Boot in BIOS, then reboot${NC}"
        echo ""
        exit 3
    fi
    
    echo ""
    echo -e "${CYAN}>>> Configuring MOK (Machine Owner Key) enrollment${NC}"
    echo ""
    echo -e "${DIM}Set a temporary password for MOK enrollment (4-256 characters):${NC}"
    echo -e "${DIM}This password is only used ONCE during the next boot.${NC}"
    echo -e "${DIM}Default: nvidia${NC}"
    echo ""
    
    read -r -p "Enter MOK enrollment password [nvidia]: " MOK_PASSWORD
    MOK_PASSWORD=${MOK_PASSWORD:-nvidia}
    
    # Validate password length (MOK requires 1-256 characters, but we recommend at least 4)
    while [ ${#MOK_PASSWORD} -lt 4 ] || [ ${#MOK_PASSWORD} -gt 256 ]; do
        echo -e "${RED}Password must be 4-256 characters${NC}"
        read -r -p "Enter MOK enrollment password [nvidia]: " MOK_PASSWORD
        MOK_PASSWORD=${MOK_PASSWORD:-nvidia}
    done
    
    # Enroll the MOK key
    echo ""
    echo ">>> Queuing MOK key for enrollment..."
    if echo -e "${MOK_PASSWORD}\n${MOK_PASSWORD}" | mokutil --import /var/lib/dkms/mok.pub 2>&1 | grep -q "input password"; then
        echo -e "${GREEN}✓ MOK key queued for enrollment${NC}"
        echo ""
        echo -e "${YELLOW}╔══════════════════════════════════════════════════════════════╗${NC}"
        echo -e "${YELLOW}║  IMPORTANT: MOK Enrollment Required on Next Boot            ║${NC}"
        echo -e "${YELLOW}╚══════════════════════════════════════════════════════════════╝${NC}"
        echo ""
        echo -e "${CYAN}After BIOS, before Proxmox boots, you'll see MOK Manager:${NC}"
        echo ""
        echo "  1. Select: ${GREEN}Enroll MOK${NC}"
        echo "  2. Select: ${GREEN}Continue${NC}"
        echo "  3. Select: ${GREEN}Yes${NC} to enroll the key"
        echo "  4. Enter password: ${GREEN}${MOK_PASSWORD}${NC}"
        echo "  5. Select: ${GREEN}Reboot${NC}"
        echo ""
        echo -e "${DIM}(Write down the password if needed: ${MOK_PASSWORD})${NC}"
        echo ""
    else
        echo -e "${YELLOW}⚠ Could not queue MOK enrollment automatically${NC}"
        echo -e "${YELLOW}You may need to enroll manually after reboot${NC}"
        echo ""
    fi
fi

# Optional: Install nvtop for GPU monitoring
echo ""
echo -e "${CYAN}>>> Optional: GPU Monitoring Tool${NC}"
echo ""
echo -e "${DIM}nvtop provides real-time GPU monitoring (like htop for GPUs)${NC}"
echo -e "${DIM}Useful for monitoring GPU usage, temperature, and processes${NC}"
echo ""

read -r -p "Install nvtop? [Y/n]: " INSTALL_NVTOP
INSTALL_NVTOP=${INSTALL_NVTOP:-Y}

if [[ "$INSTALL_NVTOP" =~ ^[Yy]$ ]]; then
    echo ""
    echo ">>> Installing nvtop..."
    apt-get install -y nvtop >/dev/null 2>&1
    if command -v nvtop &>/dev/null; then
        echo -e "${GREEN}✓ nvtop installed${NC}"
        echo -e "${DIM}Run 'nvtop' to monitor GPU in real-time${NC}"
    else
        echo -e "${YELLOW}⚠ nvtop installation failed (non-critical)${NC}"
    fi
else
    echo -e "${DIM}Skipped. You can install later: apt install nvtop${NC}"
fi

echo ""
echo -e "${GREEN}>>> NVIDIA driver installation completed${NC}"
echo -e "${YELLOW}⚠  Reboot required to load kernel module${NC}"
echo ""

exit 3  # Exit code 3 = success but reboot required