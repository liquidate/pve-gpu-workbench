#!/usr/bin/env bash
# SCRIPT_DESC: Install AMD ROCm GPU drivers
# SCRIPT_DETECT: lsmod | grep -q amdgpu

# Get script directory and source utilities
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/../includes/colors.sh"
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/../includes/gpu-detect.sh"

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

# Ensure required tools are available
for tool in curl wget gpg; do
    if ! command -v $tool &>/dev/null; then
        echo ">>> Installing required tool: $tool"
        apt-get update -qq && apt-get install -y $tool >/dev/null 2>&1
    fi
done

# Fetch available ROCm versions from AMD repository
echo ""
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

# Get the latest version as default
DEFAULT_VERSION=$(echo "$AVAILABLE_VERSIONS" | tail -1)

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

echo ""
echo -e "${CYAN}>>> Installing ROCm ${ROCM_VERSION}${NC}"
echo ">>> Adding AMD ROCm ${ROCM_VERSION} repository"
mkdir --parents /etc/apt/keyrings
chmod 0755 /etc/apt/keyrings
wget https://repo.radeon.com/rocm/rocm.gpg.key -O - | \
gpg --dearmor | tee /etc/apt/keyrings/rocm.gpg > /dev/null

tee /etc/apt/sources.list.d/rocm.list << EOF
deb [arch=amd64 signed-by=/etc/apt/keyrings/rocm.gpg] https://repo.radeon.com/rocm/apt/${ROCM_VERSION} noble main
deb [arch=amd64 signed-by=/etc/apt/keyrings/rocm.gpg] https://repo.radeon.com/graphics/${ROCM_VERSION}/ubuntu noble main
EOF

tee /etc/apt/preferences.d/rocm-pin-600 << EOF
Package: *
Pin: release o=repo.radeon.com
Pin-Priority: 600
EOF

echo ">>> Updating package lists after adding ROCm repository"
apt update

echo ">>> Installing AMD ROCm drivers and tools"
apt install -y rocm-smi rocminfo rocm-libs
apt install -y nvtop radeontop

echo ">>> Adding root user to render and video groups for GPU access"
usermod -a -G render,video root

echo ">>> Verifying root user group membership"
groups root

echo ">>> Setting up environment variables for ROCm"
cat > /etc/profile.d/rocm.sh << 'EOF'
export PATH="${PATH:+${PATH}:}/opt/rocm/bin/"
export LD_LIBRARY_PATH="${LD_LIBRARY_PATH:+${LD_LIBRARY_PATH}:}/opt/rocm/lib/"
EOF

echo ">>> Making /etc/profile.d/rocm.sh executable and sourcing it"
chmod +x /etc/profile.d/rocm.sh
# shellcheck disable=SC1091
source /etc/profile.d/rocm.sh

echo ">>> AMD ROCm driver installation completed."
echo ">>> Run '005 - verify-amd-drivers.sh' to verify the installation."
