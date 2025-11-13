#!/usr/bin/env bash
# SCRIPT_DESC: Upgrade NVIDIA driver version
# SCRIPT_CATEGORY: host-maintenance
# SCRIPT_DETECT: 

# Get script directory and source utilities
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/../includes/colors.sh"
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/../includes/gpu-detect.sh"

# Setup logging
LOG_FILE="/tmp/nvidia-upgrade-$(date +%Y%m%d-%H%M%S).log"
{
    echo "==================================="
    echo "NVIDIA Driver Upgrade Log"
    echo "Started: $(date)"
    echo "==================================="
    echo ""
} > "$LOG_FILE"

# Progress tracking functions
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
    
    tput civis  # Hide cursor
    
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
    tput cnorm  # Show cursor
}

# Check if NVIDIA GPU is present
if ! detect_nvidia_gpus; then
    echo -e "${YELLOW}========================================${NC}"
    echo -e "${YELLOW}No NVIDIA GPUs detected on this system${NC}"
    echo -e "${YELLOW}========================================${NC}"
    echo ""
    exit 0
fi

echo -e "${GREEN}>>> NVIDIA Driver Upgrade${NC}"
echo ""
echo -e "${CYAN}📋 Upgrade Log:${NC}"
echo "  File: $LOG_FILE"
echo -e "  Watch live: ${YELLOW}tail -f $LOG_FILE${NC}"
echo ""

# Define total steps
TOTAL_STEPS=4

# Check current driver version and installed packages
CURRENT_DRIVER=""
if command -v nvidia-smi &>/dev/null; then
    CURRENT_DRIVER=$(nvidia-smi --query-gpu=driver_version --format=csv,noheader 2>/dev/null | head -1)
fi

# Detect currently installed kernel module type
CURRENT_KERNEL_MODULE=""
if dpkg -l | grep -q "^ii.*nvidia-kernel-open-dkms"; then
    CURRENT_KERNEL_MODULE="nvidia-kernel-open-dkms"
elif dpkg -l | grep -q "^ii.*nvidia-kernel-dkms"; then
    CURRENT_KERNEL_MODULE="nvidia-kernel-dkms"
fi

if [ -n "$CURRENT_DRIVER" ]; then
    echo -e "${CYAN}Current driver version:${NC} $CURRENT_DRIVER"
fi

if [ -n "$CURRENT_KERNEL_MODULE" ]; then
    MODULE_TYPE=$(echo "$CURRENT_KERNEL_MODULE" | grep -q "open" && echo "Open Source" || echo "Proprietary")
    echo -e "${CYAN}Kernel module:${NC} $MODULE_TYPE ($CURRENT_KERNEL_MODULE)"
fi

if [ -z "$CURRENT_DRIVER" ] || [ -z "$CURRENT_KERNEL_MODULE" ]; then
    echo -e "${RED}No NVIDIA drivers currently installed${NC}"
    echo ""
    echo -e "${YELLOW}Run 'nvidia-drivers' to perform initial installation${NC}"
    exit 1
fi

# Ensure Debian non-free repository is enabled
if ! grep -q "non-free non-free-firmware" /etc/apt/sources.list.d/debian.sources 2>/dev/null; then
    echo ""
    echo -e "${YELLOW}Enabling Debian non-free repository...${NC}"
    sed -i 's/Components: main contrib non-free-firmware/Components: main contrib non-free non-free-firmware/' /etc/apt/sources.list.d/debian.sources
fi

# Ensure NVIDIA repository is configured
if [ ! -f /etc/apt/sources.list.d/cuda-debian12-x86_64.list ]; then
    echo ""
    echo -e "${YELLOW}NVIDIA repository not configured. Adding it now...${NC}"
    wget -q https://developer.download.nvidia.com/compute/cuda/repos/debian12/x86_64/cuda-keyring_1.1-1_all.deb
    dpkg -i cuda-keyring_1.1-1_all.deb
    rm cuda-keyring_1.1-1_all.deb
fi

# Update package cache
echo ""
show_progress 1 $TOTAL_STEPS "Checking available driver versions"
apt-get update -qq >> "$LOG_FILE" 2>&1
complete_progress "Available driver versions fetched"

# Fetch available driver versions from nvidia-driver package versions
AVAILABLE_VERSIONS=$(apt-cache policy nvidia-driver 2>/dev/null | \
    grep -oP '^\s+\K[0-9]+\.[0-9]+\.[0-9]+-[0-9]+' | \
    sort -V -r | \
    head -20)

if [ -z "$AVAILABLE_VERSIONS" ]; then
    echo -e "${RED}Could not fetch available driver versions${NC}"
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

# Get current branch from current driver version
CURRENT_BRANCH=$(echo "$CURRENT_DRIVER" | cut -d'.' -f1)

# Display available versions
echo ""
echo -e "${YELLOW}Available NVIDIA driver branches (latest versions):${NC}"
BRANCH_COUNT=0
for branch in "${BRANCH_ORDER[@]}"; do
    [ $BRANCH_COUNT -ge 10 ] && break
    version="${DRIVER_BRANCHES[$branch]}"
    
    if [ "$branch" = "$CURRENT_BRANCH" ]; then
        case "$branch" in
            550) echo -e "  $branch ($version) - Long-lived branch ${GREEN}[INSTALLED]${NC}" ;;
            545|555|560|565|570|575|580) echo -e "  $branch ($version) - Production branch ${GREEN}[INSTALLED]${NC}" ;;
            *) echo -e "  $branch ($version) ${GREEN}[INSTALLED]${NC}" ;;
        esac
    else
        case "$branch" in
            550) echo -e "  $branch ($version) - Long-lived branch" ;;
            545|555|560|565|570|575|580) echo -e "  $branch ($version) - Production branch" ;;
            *) echo -e "  $branch ($version)" ;;
        esac
    fi
    ((BRANCH_COUNT++))
done

echo ""
echo -e "${DIM}Branches: 550 = stable long-lived, higher numbers = newer${NC}"
echo -e "${DIM}Full version will be installed (e.g., 550 → 550.163.01)${NC}"
echo ""

# Get user selection
read -r -p "Select driver branch to install (or press Enter to cancel): " NEW_BRANCH

if [ -z "$NEW_BRANCH" ]; then
    echo "Cancelled."
    exit 0
fi

# Validate branch selection
if [ -z "${DRIVER_BRANCHES[$NEW_BRANCH]}" ]; then
    echo -e "${RED}ERROR: Driver branch ${NEW_BRANCH} not found${NC}"
    echo -e "${YELLOW}Available branches: ${BRANCH_ORDER[*]}${NC}"
    exit 1
fi

# Get the specific version for this branch
NEW_VERSION="${DRIVER_BRANCHES[$NEW_BRANCH]}"

# Check if it's the same version
if [ "$NEW_BRANCH" = "$CURRENT_BRANCH" ]; then
    echo -e "${GREEN}✓ Driver version ${NEW_BRANCH} is already installed${NC}"
    echo ""
    echo -e "${YELLOW}Would you like to change the kernel module type?${NC}"
    read -r -p "Change kernel module? [y/N]: " CHANGE_MODULE
    CHANGE_MODULE=${CHANGE_MODULE:-N}
    if [[ ! "$CHANGE_MODULE" =~ ^[Yy]$ ]]; then
        exit 0
    fi
fi

# Detect GPU and Secure Boot for kernel module recommendation
GPU_NAME=$(lspci | grep -i "VGA.*NVIDIA\|3D.*NVIDIA" | head -1)
SECURE_BOOT_ENABLED=false
if mokutil --sb-state 2>/dev/null | grep -q "SecureBoot enabled"; then
    SECURE_BOOT_ENABLED=true
fi

RECOMMEND_OPEN=false
if echo "$GPU_NAME" | grep -Ei "RTX (20|30|40|50|A)[0-9]|A[0-9]{3,4}|L[0-9]{1,2}"; then
    RECOMMEND_OPEN=true
fi

# Kernel module selection
echo ""
echo -e "${CYAN}>>> Selecting kernel module...${NC}"
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

# Show current module
MODULE_TYPE=$(echo "$CURRENT_KERNEL_MODULE" | grep -q "open" && echo "2 (Open)" || echo "1 (Proprietary)")
echo -e "${CYAN}Currently installed: $MODULE_TYPE${NC}"

# Determine default based on GPU and Secure Boot
if [ "$SECURE_BOOT_ENABLED" = true ] || [ "$RECOMMEND_OPEN" = true ]; then
    DEFAULT_CHOICE="2"
    if [ "$RECOMMEND_OPEN" = true ]; then
        echo -e "${GREEN}Recommendation: Open kernel module (better for your GPU)${NC}"
    else
        echo -e "${GREEN}Recommendation: Open kernel module (required for Secure Boot)${NC}"
    fi
else
    DEFAULT_CHOICE="1"
fi

echo ""
read -r -p "Select kernel module [${DEFAULT_CHOICE}]: " KERNEL_CHOICE
KERNEL_CHOICE=${KERNEL_CHOICE:-${DEFAULT_CHOICE}}

case "$KERNEL_CHOICE" in
    1)
        NEW_KERNEL_MODULE="nvidia-kernel-dkms"
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
                echo "Cancelled."
                exit 0
            fi
        fi
        ;;
    2)
        NEW_KERNEL_MODULE="nvidia-kernel-open-dkms"
        ;;
    *)
        echo -e "${RED}Invalid choice${NC}"
        exit 1
        ;;
esac

# Confirm upgrade
echo ""
echo -e "${YELLOW}This will upgrade your NVIDIA driver:${NC}"
echo "  From: Driver ${CURRENT_DRIVER} ($CURRENT_KERNEL_MODULE)"
echo "  To:   Driver ${NEW_VERSION} ($NEW_KERNEL_MODULE)"
echo ""
read -r -p "Continue? [y/N]: " CONFIRM
CONFIRM=${CONFIRM:-N}

if [[ ! "$CONFIRM" =~ ^[Yy]$ ]]; then
    echo "Cancelled."
    exit 0
fi

echo ""
echo -e "${CYAN}>>> Upgrading NVIDIA driver to version ${NEW_VERSION}${NC}"
echo -e "${DIM}Kernel module: ${NEW_KERNEL_MODULE}${NC}"
echo ""

# Remove old driver and kernel module packages
show_progress 3 $TOTAL_STEPS "Removing old driver packages"
apt-get remove -y nvidia-driver nvidia-kernel-dkms nvidia-kernel-open-dkms >> "$LOG_FILE" 2>&1 || true
complete_progress "Old driver packages removed"

# Install new driver
echo ""
show_progress 4 $TOTAL_STEPS "Installing NVIDIA driver ${NEW_VERSION} (this may take 3-5 minutes)"
DEBIAN_FRONTEND=noninteractive apt-get install -y \
    nvidia-driver=${NEW_VERSION} \
    ${NEW_KERNEL_MODULE}=${NEW_VERSION} \
    nvidia-driver-cuda=${NEW_VERSION} >> "$LOG_FILE" 2>&1

if [ $? -eq 0 ]; then
    complete_progress "NVIDIA driver ${NEW_VERSION} installed"
else
    stop_spinner
    echo -e "${RED}✗ Driver installation failed${NC}"
    echo -e "${YELLOW}  Check log: $LOG_FILE${NC}"
    exit 1
fi

# Handle MOK enrollment if switching to open kernel module with Secure Boot
if [ "$NEW_KERNEL_MODULE" = "nvidia-kernel-open-dkms" ] && \
   [ "$CURRENT_KERNEL_MODULE" != "nvidia-kernel-open-dkms" ] && \
   [ "$SECURE_BOOT_ENABLED" = true ]; then
    echo ""
    echo -e "${YELLOW}╔══════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${YELLOW}║            Secure Boot Detected - Action Required           ║${NC}"
    echo -e "${YELLOW}╚══════════════════════════════════════════════════════════════╝${NC}"
    echo ""
    echo -e "${CYAN}Switching to open kernel module requires authorization.${NC}"
    echo ""
    echo -e "${YELLOW}You have TWO options:${NC}"
    echo ""
    echo -e "${GREEN}Option 1: MOK Enrollment${NC}"
    echo "  • Keeps Secure Boot enabled (more secure)"
    echo "  • One-time setup during next boot"
    echo "  • You'll enter a password in MOK Manager before Proxmox boots"
    echo ""
    echo -e "${GREEN}Option 2: Disable Secure Boot${NC}"
    echo "  • Simpler - no enrollment needed"
    echo "  • Disable Secure Boot in your BIOS/UEFI settings"
    echo "  • Modules will load automatically after reboot"
    echo ""
    
    read -r -p "Continue with MOK enrollment? [y/N]: " CONTINUE_MOK
    CONTINUE_MOK=${CONTINUE_MOK:-N}
    
    if [[ ! "$CONTINUE_MOK" =~ ^[Yy]$ ]]; then
        echo ""
        echo -e "${YELLOW}Skipping MOK enrollment.${NC}"
        echo ""
        echo -e "${CYAN}To complete upgrade:${NC}"
        echo "  1. Reboot into BIOS/UEFI settings"
        echo "  2. Find 'Secure Boot' setting (usually in Security or Boot menu)"
        echo "  3. Set to: ${GREEN}Disabled${NC}"
        echo "  4. Save and reboot"
        echo "  5. NVIDIA driver will load automatically"
        echo ""
        echo -e "${GREEN}>>> NVIDIA driver upgrade completed${NC}"
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
    
    # Validate password length
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

echo ""
echo -e "${GREEN}>>> NVIDIA driver upgrade completed${NC}"
echo -e "${YELLOW}⚠  Reboot required to load new driver version${NC}"
echo ""
echo -e "${CYAN}📋 Full upgrade log saved to:${NC}"
echo "  $LOG_FILE"
echo ""
echo -e "${CYAN}After reboot, verify with: nvidia-smi${NC}"
echo ""

exit 3  # Exit code 3 = success but reboot required

