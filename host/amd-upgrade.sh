#!/usr/bin/env bash
# SCRIPT_DESC: Upgrade AMD ROCm to a different version
# SCRIPT_CATEGORY: host-maintenance
# SCRIPT_DETECT: [ -f /etc/apt/sources.list.d/rocm.list ]

# Get script directory and source utilities
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/../includes/colors.sh"

# Setup logging
LOG_FILE="/tmp/amd-upgrade-$(date +%Y%m%d-%H%M%S).log"
{
    echo "==================================="
    echo "AMD ROCm Upgrade Log"
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

# Check if ROCm is installed
if ! [ -f /etc/apt/sources.list.d/rocm.list ]; then
    echo -e "${RED}========================================${NC}"
    echo -e "${RED}ROCm not installed${NC}"
    echo -e "${RED}========================================${NC}"
    echo ""
    echo -e "${YELLOW}ROCm repository not found. Please run 'amd-drivers' first.${NC}"
    exit 1
fi

# Detect current ROCm version from repo
CURRENT_VERSION=$(grep -oP 'rocm/apt/\K[0-9]+\.[0-9]+' /etc/apt/sources.list.d/rocm.list | head -1)

echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}AMD ROCm Version Upgrade${NC}"
echo -e "${GREEN}========================================${NC}"
echo ""
echo -e "${CYAN}📋 Upgrade Log:${NC}"
echo "  File: $LOG_FILE"
echo -e "  Watch live: ${YELLOW}tail -f $LOG_FILE${NC}"
echo ""

# Define total steps
TOTAL_STEPS=4

echo -e "${CYAN}Current ROCm version: ${CURRENT_VERSION}${NC}"
echo ""

# Check installed ROCm package version
if command -v rocminfo &>/dev/null; then
    INSTALLED_VERSION=$(rocminfo 2>/dev/null | grep -oP 'Runtime Version:\s*\K[0-9]+\.[0-9]+' || echo "Unknown")
    echo -e "${CYAN}Installed packages: ${INSTALLED_VERSION}${NC}"
    echo ""
fi

# Fetch available ROCm versions from AMD repository
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

complete_progress "Available ROCm versions fetched"

# Display available versions
echo ""
echo -e "${YELLOW}Available ROCm versions (latest 5):${NC}"
echo "$AVAILABLE_VERSIONS" | awk '{printf "  %s\n", $1}'
echo ""
read -r -p "Select ROCm version to upgrade to [${CURRENT_VERSION}]: " NEW_VERSION
NEW_VERSION=${NEW_VERSION:-${CURRENT_VERSION}}

# Validate version format
if ! [[ "$NEW_VERSION" =~ ^[0-9]+\.[0-9]+$ ]]; then
    echo -e "${RED}Invalid version format. Must be X.Y (e.g., 7.1)${NC}"
    exit 1
fi

# Check if same version
if [ "$NEW_VERSION" = "$CURRENT_VERSION" ]; then
    echo ""
    echo -e "${YELLOW}Selected version (${NEW_VERSION}) is the same as current version.${NC}"
    read -r -p "Continue to reinstall/update packages? [y/N]: " CONTINUE
    CONTINUE=${CONTINUE:-N}
    if [[ ! "$CONTINUE" =~ ^[Yy]$ ]]; then
        echo "Cancelled."
        exit 0
    fi
fi

echo ""
echo -e "${CYAN}>>> Upgrading ROCm from ${CURRENT_VERSION} to ${NEW_VERSION}${NC}"

# Ensure required tools are available
for tool in curl wget gpg; do
    if ! command -v $tool &>/dev/null; then
        echo ">>> Installing required tool: $tool"
        apt-get update -qq && apt-get install -y $tool >/dev/null 2>&1
    fi
done

# Update repository to new version
show_progress 2 $TOTAL_STEPS "Updating ROCm repository to version ${NEW_VERSION}"
tee /etc/apt/sources.list.d/rocm.list << EOF >> "$LOG_FILE"
deb [arch=amd64 signed-by=/etc/apt/keyrings/rocm.gpg] https://repo.radeon.com/rocm/apt/${NEW_VERSION} noble main
deb [arch=amd64 signed-by=/etc/apt/keyrings/rocm.gpg] https://repo.radeon.com/graphics/${NEW_VERSION}/ubuntu noble main
EOF

complete_progress "ROCm repository updated"

show_progress 3 $TOTAL_STEPS "Updating package cache"
apt update >> "$LOG_FILE" 2>&1
complete_progress "Package cache updated"

show_progress 4 $TOTAL_STEPS "Upgrading ROCm packages (this may take 3-5 minutes)"
apt install -y --allow-downgrades rocm-smi rocminfo rocm-libs >> "$LOG_FILE" 2>&1

if command -v rocm-smi &>/dev/null; then
    complete_progress "ROCm packages upgraded to ${NEW_VERSION}"
else
    stop_spinner
    echo -e "${RED}✗ ROCm upgrade failed${NC}"
    echo -e "${YELLOW}  Check log: $LOG_FILE${NC}"
    exit 1
fi

echo ""
echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}✓ ROCm Upgrade Complete!${NC}"
echo -e "${GREEN}========================================${NC}"
echo ""
echo -e "${CYAN}New version: ${NEW_VERSION}${NC}"
echo ""
echo -e "${YELLOW}⚠  Reboot recommended to ensure all changes take effect${NC}"
echo ""
echo -e "${CYAN}📋 Full upgrade log saved to:${NC}"
echo "  $LOG_FILE"
echo ""
echo "Run 'amd-verify' after reboot to verify the upgrade."

