#!/usr/bin/env bash
# SCRIPT_DESC: Upgrade AMD ROCm to a different version
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
echo -e "${CYAN}Current ROCm version: ${CURRENT_VERSION}${NC}"
echo ""

# Check installed ROCm package version
if command -v rocminfo &>/dev/null; then
    INSTALLED_VERSION=$(rocminfo 2>/dev/null | grep -oP 'Runtime Version:\s*\K[0-9]+\.[0-9]+' || echo "Unknown")
    echo -e "${CYAN}Installed packages: ${INSTALLED_VERSION}${NC}"
    echo ""
fi

# Fetch available ROCm versions from AMD repository
echo -e "${CYAN}>>> Fetching available ROCm versions...${NC}"
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
echo ">>> Updating ROCm repository to version ${NEW_VERSION}"
tee /etc/apt/sources.list.d/rocm.list << EOF
deb [arch=amd64 signed-by=/etc/apt/keyrings/rocm.gpg] https://repo.radeon.com/rocm/apt/${NEW_VERSION} noble main
deb [arch=amd64 signed-by=/etc/apt/keyrings/rocm.gpg] https://repo.radeon.com/graphics/${NEW_VERSION}/ubuntu noble main
EOF

echo ">>> Updating package lists with new ROCm repository"
apt update >> "$LOG_FILE" 2>&1
echo "  ✓ Package cache updated"

echo ">>> Upgrading ROCm packages"
echo -e "${DIM}This may take a few minutes...${NC}"
apt install -y --allow-downgrades rocm-smi rocminfo rocm-libs >> "$LOG_FILE" 2>&1

if command -v rocm-smi &>/dev/null; then
    echo "  ✓ ROCm packages upgraded"
else
    echo -e "${RED}  ✗ ROCm upgrade failed${NC}"
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

