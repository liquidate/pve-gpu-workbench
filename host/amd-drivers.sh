#!/usr/bin/env bash
# SCRIPT_DESC: Install AMD ROCm GPU drivers
# SCRIPT_DETECT: lsmod | grep -q amdgpu

# Get script directory and source utilities
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/../includes/colors.sh"
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/../includes/gpu-detect.sh"

# Setup logging
LOG_FILE="/tmp/amd-drivers-install-$(date +%Y%m%d-%H%M%S).log"
{
    echo "==================================="
    echo "AMD ROCm Drivers Installation Log"
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

# Check if AMD GPU is present
if ! detect_amd_gpus; then
    echo -e "${YELLOW}========================================${NC}"
    echo -e "${YELLOW}No AMD GPUs detected on this system${NC}"
    echo -e "${YELLOW}========================================${NC}"
    echo ""
    echo -e "${YELLOW}This script installs AMD GPU drivers, but no AMD GPUs were found.${NC}"
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

echo -e "${GREEN}>>> Installing AMD ROCm drivers${NC}"
echo ""
echo -e "${CYAN}📋 Installation Log:${NC}"
echo "  File: $LOG_FILE"
echo -e "  Watch live: ${YELLOW}tail -f $LOG_FILE${NC}"
echo ""

# Define total steps
TOTAL_STEPS=5

# Ensure required tools are available
for tool in curl wget gpg; do
    if ! command -v $tool &>/dev/null; then
        echo ">>> Installing required tool: $tool"
        apt-get update -qq >> "$LOG_FILE" 2>&1 && apt-get install -y $tool >> "$LOG_FILE" 2>&1
    fi
done

# Fetch available ROCm versions from AMD repository
echo ""
show_progress 1 $TOTAL_STEPS "Fetching available ROCm versions"
AVAILABLE_VERSIONS=$(curl -s https://repo.radeon.com/rocm/apt/ | \
    grep -oP 'href="[0-9]+\.[0-9]+/"' | \
    grep -oP '[0-9]+\.[0-9]+' | \
    sort -V | \
    tail -5)

if [ -z "$AVAILABLE_VERSIONS" ]; then
    echo -e "${YELLOW}Could not fetch versions from repository. Using defaults.${NC}"
    AVAILABLE_VERSIONS="6.1
6.2
7.0
7.1
7.2"
fi

# Get the latest version as default
DEFAULT_VERSION=$(echo "$AVAILABLE_VERSIONS" | tail -1)

complete_progress "ROCm versions fetched"

# Display available versions
echo ""
echo -e "${YELLOW}Available ROCm versions (latest 5):${NC}"
echo "$AVAILABLE_VERSIONS" | awk '{printf "  %s\n", $1}'
echo ""
read -r -p "Select ROCm version to install [${DEFAULT_VERSION}]: " ROCM_VERSION
ROCM_VERSION=${ROCM_VERSION:-${DEFAULT_VERSION}}

# Validate version format
if ! [[ "$ROCM_VERSION" =~ ^[0-9]+\.[0-9]+$ ]]; then
    echo -e "${RED}Invalid version format. Must be X.Y (e.g., 7.1)${NC}"
    exit 1
fi

# Check if this version is already configured
if [ -f /etc/apt/sources.list.d/rocm.list ]; then
    current_version=$(grep -oP 'rocm/apt/\K[0-9]+\.[0-9]+' /etc/apt/sources.list.d/rocm.list 2>/dev/null | head -1)
    if [ "$current_version" = "$ROCM_VERSION" ]; then
        # Check if ROCm packages are actually installed
        if dpkg -l | grep -q "^ii.*rocm-smi"; then
            echo ""
            echo -e "${GREEN}✓ ROCm ${ROCM_VERSION} is already installed${NC}"
            echo -e "${DIM}No changes needed. Run 'amd-upgrade' to change versions.${NC}"
            echo ""
            exit 0
        fi
    fi
fi

echo ""
echo -e "${CYAN}>>> Installing ROCm ${ROCM_VERSION}${NC}"
echo ""
show_progress 2 $TOTAL_STEPS "Adding AMD ROCm ${ROCM_VERSION} repository"
mkdir --parents /etc/apt/keyrings
chmod 0755 /etc/apt/keyrings
wget https://repo.radeon.com/rocm/rocm.gpg.key -O - 2>> "$LOG_FILE" | \
gpg --dearmor 2>> "$LOG_FILE" | tee /etc/apt/keyrings/rocm.gpg >> "$LOG_FILE"

tee /etc/apt/sources.list.d/rocm.list << EOF
deb [arch=amd64 signed-by=/etc/apt/keyrings/rocm.gpg] https://repo.radeon.com/rocm/apt/${ROCM_VERSION} noble main
deb [arch=amd64 signed-by=/etc/apt/keyrings/rocm.gpg] https://repo.radeon.com/graphics/${ROCM_VERSION}/ubuntu noble main
EOF

tee /etc/apt/preferences.d/rocm-pin-600 << EOF
Package: *
Pin: release o=repo.radeon.com
Pin-Priority: 600
EOF

complete_progress "ROCm repository added"

show_progress 3 $TOTAL_STEPS "Updating package cache"
apt update >> "$LOG_FILE" 2>&1
complete_progress "Package cache updated"

show_progress 4 $TOTAL_STEPS "Installing AMD ROCm drivers and tools (this may take 3-5 minutes)"
apt install -y rocm-smi rocminfo rocm-libs >> "$LOG_FILE" 2>&1
apt install -y nvtop radeontop >> "$LOG_FILE" 2>&1

if command -v rocm-smi &>/dev/null; then
    complete_progress "AMD ROCm drivers installed"
else
    stop_spinner
    echo -e "${RED}✗ ROCm installation failed${NC}"
    echo -e "${YELLOW}  Check log: $LOG_FILE${NC}"
    exit 1
fi

show_progress 5 $TOTAL_STEPS "Configuring user groups and environment"
usermod -a -G render,video root

cat > /etc/profile.d/rocm.sh << 'EOF'
export PATH="${PATH:+${PATH}:}/opt/rocm/bin/"
export LD_LIBRARY_PATH="${LD_LIBRARY_PATH:+${LD_LIBRARY_PATH}:}/opt/rocm/lib/"
EOF

chmod +x /etc/profile.d/rocm.sh
# shellcheck disable=SC1091
source /etc/profile.d/rocm.sh

complete_progress "ROCm environment configured"

echo ">>> AMD ROCm driver installation completed."
echo -e "${YELLOW}⚠  Reboot recommended to ensure all drivers are loaded${NC}"
echo ""
echo -e "${CYAN}📋 Full installation log saved to:${NC}"
echo "  $LOG_FILE"
echo ""

exit 3  # Exit code 3 = success but reboot required
