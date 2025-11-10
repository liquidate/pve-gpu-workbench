#!/usr/bin/env bash

# Combined Docker + AMD ROCm Runtime installation for LXC containers
# This script installs Docker, AMD ROCm libraries, and verifies GPU access inside the LXC container

set -e

# Set non-interactive mode for apt
export DEBIAN_FRONTEND=noninteractive
export NEEDRESTART_MODE=a

# Check if verbose mode is enabled (set VERBOSE=1 to see all output)
VERBOSE=${VERBOSE:-0}
if [ "$VERBOSE" = "1" ]; then
    QUIET=""
    QUIET_APT=""
else
    QUIET=">/dev/null 2>&1"
    QUIET_APT="-qq"
fi

# Progress spinner function
show_progress() {
    local pid=$1
    local message=$2
    local spin='⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏'
    local i=0
    
    while kill -0 $pid 2>/dev/null; do
        i=$(( (i+1) %10 ))
        printf "\r${GREEN}${message} ${spin:$i:1}${NC}"
        sleep 0.1
    done
    printf "\r${GREEN}✓ ${message}${NC}\n"
}

# Get script directory and source colors
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/../includes/colors.sh"

echo -e "${GREEN}==========================================${NC}"
echo -e "${GREEN}Docker + AMD GPU Setup for LXC${NC}"
echo -e "${GREEN}==========================================${NC}"
echo ""
echo -e "${YELLOW}IMPORTANT: Make sure AMD drivers are installed on the Proxmox HOST first!${NC}"
echo -e "${YELLOW}Run '003 - install-amd-drivers.sh' on the host if not already done.${NC}"
echo ""

# Verify GPU is visible
echo -e "${GREEN}>>> Checking if GPU devices are accessible...${NC}"
GPU_FOUND=false
if [ -e /dev/kfd ]; then
    echo -e "${GREEN}✓ AMD GPU devices found:${NC}"
    ls -la /dev/kfd 2>/dev/null || true
    GPU_FOUND=true
fi

if [ -e /dev/dri/card0 ]; then
    echo -e "${GREEN}✓ DRI devices found:${NC}"
    ls -la /dev/dri/ 2>/dev/null || true
    GPU_FOUND=true
fi

if [ "$GPU_FOUND" = false ]; then
    echo -e "${RED}WARNING: No GPU devices found!${NC}"
    echo -e "${YELLOW}Make sure the LXC container has GPU passthrough configured correctly.${NC}"
    echo ""
    read -r -p "Continue anyway? [y/N]: " CONTINUE
    CONTINUE=${CONTINUE:-N}
    if [[ ! "$CONTINUE" =~ ^[Yy]$ ]]; then
        echo -e "${RED}Cancelled.${NC}"
        exit 1
    fi
fi
echo ""

# Remove debian-provided packages
echo -e "${GREEN}>>> Removing old Docker packages...${NC}"
apt remove -y docker-compose docker docker.io containerd runc 2>/dev/null || true

# Update package list and upgrade existing packages
if [ "$VERBOSE" = "1" ]; then
    echo -e "${GREEN}>>> Updating system packages...${NC}"
    apt update
    apt upgrade -y -o Dpkg::Options::="--force-confdef" -o Dpkg::Options::="--force-confold"
    echo -e "${GREEN}✓ System packages updated${NC}"
else
    apt update $QUIET_APT >/dev/null 2>&1 &
    show_progress $! "Updating package cache"
    apt upgrade -y $QUIET_APT -o Dpkg::Options::="--force-confdef" -o Dpkg::Options::="--force-confold" >/dev/null 2>&1 &
    show_progress $! "Upgrading system packages"
fi

# Install Docker prerequisites
echo -e "${GREEN}>>> Installing Docker prerequisites...${NC}"
if [ "$VERBOSE" = "1" ]; then
    apt install -y ca-certificates curl gnupg lsb-release sudo pciutils
else
    apt install -y $QUIET_APT ca-certificates curl gnupg lsb-release sudo pciutils >/dev/null 2>&1
fi
echo -e "${GREEN}✓ Prerequisites installed${NC}"

# Add Docker's official GPG key
mkdir -p /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg

# Add Docker repository
echo \
  "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu \
  $(lsb_release -cs) stable" | tee /etc/apt/sources.list.d/docker.list > /dev/null

# Update package list
echo -e "${GREEN}>>> Updating package cache...${NC}"
if [ "$VERBOSE" = "1" ]; then
    apt update
else
    apt update $QUIET_APT >/dev/null 2>&1
fi

# Install Docker Engine (latest stable)
echo -e "${GREEN}>>> Installing Docker Engine...${NC}"
if [ "$VERBOSE" = "1" ]; then
    apt install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
else
    apt install -y $QUIET_APT docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin >/dev/null 2>&1
fi
echo -e "${GREEN}✓ Docker Engine installed${NC}"

# Start Docker daemon
systemctl start docker
systemctl enable docker

# Add root user to docker group
usermod -a -G docker root

# Verify Docker installation
echo -e "${GREEN}>>> Docker version installed:${NC}"
docker --version
echo -e "${GREEN}>>> Docker Compose version installed:${NC}"
docker compose version
echo -e "${GREEN}>>> Containerd version installed:${NC}"
containerd --version
echo -e "${GREEN}>>> Docker installation completed.${NC}"

# Install docker-compose bash completion
echo -e "${GREEN}>>> Installing Docker bash completion...${NC}"
curl -L https://raw.githubusercontent.com/docker/cli/master/contrib/completion/bash/docker \
    -o /etc/bash_completion.d/docker-compose

echo ""
echo -e "${GREEN}==========================================${NC}"
echo -e "${GREEN}Installing AMD ROCm Libraries${NC}"
echo -e "${GREEN}==========================================${NC}"
echo ""

# Add AMD ROCm repository
echo -e "${GREEN}>>> Adding AMD ROCm repository...${NC}"
# Add AMD ROCm GPG key
# Make the directory if it doesn't exist yet.
# This location is recommended by the distribution maintainers.
sudo mkdir --parents --mode=0755 /etc/apt/keyrings

# Download the key, convert the signing-key to a full
# keyring required by apt and store in the keyring directory
wget https://repo.radeon.com/rocm/rocm.gpg.key -O - | \
    gpg --dearmor | sudo tee /etc/apt/keyrings/rocm.gpg > /dev/null

# Add ROCm 7.1.0 repository (Noble/24.04)
sudo tee /etc/apt/sources.list.d/rocm.list << EOF
deb [arch=amd64 signed-by=/etc/apt/keyrings/rocm.gpg] https://repo.radeon.com/rocm/apt/7.1 noble main
deb [arch=amd64 signed-by=/etc/apt/keyrings/rocm.gpg] https://repo.radeon.com/graphics/7.1/ubuntu noble main
EOF

sudo tee /etc/apt/preferences.d/rocm-pin-600 << EOF
Package: *
Pin: release o=repo.radeon.com
Pin-Priority: 600
EOF

echo -e "${GREEN}>>> Updating package cache...${NC}"
if [ "$VERBOSE" = "1" ]; then
    apt update
else
    apt update $QUIET_APT >/dev/null 2>&1
fi

# Install AMD libraries (user-space only, NO kernel modules)
# Note: We install the latest available version, but it must match the host driver

# Install ROCm 7.1.0 (runtime libraries without DKMS)
if [ "$VERBOSE" = "1" ]; then
    echo -e "${GREEN}>>> Installing AMD ROCm libraries...${NC}"
    apt install -y rocm-libs rocm-smi rocminfo rocm-device-libs rocm-utils
    echo -e "${GREEN}✓ ROCm libraries installed${NC}"
else
    apt install -y $QUIET_APT rocm-libs rocm-smi rocminfo rocm-device-libs rocm-utils >/dev/null 2>&1 &
    show_progress $! "Installing AMD ROCm libraries [2-3 min]"
fi

# Install ROCm development packages (needed for Ollama Docker to compile if needed)
if [ "$VERBOSE" = "1" ]; then
    echo -e "${GREEN}>>> Installing ROCm development packages...${NC}"
    apt install -y rocm-core rocm-dev hipcc
    echo -e "${GREEN}✓ ROCm dev packages installed${NC}"
else
    apt install -y $QUIET_APT rocm-core rocm-dev hipcc >/dev/null 2>&1 &
    show_progress $! "Installing ROCm development packages [1-2 min]"
fi

# Install monitoring tools
if [ "$VERBOSE" = "1" ]; then
    echo -e "${GREEN}>>> Installing monitoring tools...${NC}"
    apt install -y nvtop radeontop
    echo -e "${GREEN}✓ Monitoring tools installed${NC}"
else
    apt install -y $QUIET_APT nvtop radeontop >/dev/null 2>&1 &
    show_progress $! "Installing monitoring tools"
fi

# Add root user to render and video groups (critical for GPU access)
usermod -a -G render,video root
usermod -a -G video,render root

# Set up ROCm environment variables
cat >> /root/.bashrc << 'EOF'

# ROCm Environment Variables
export PATH="/opt/rocm/bin:${PATH}"
export LD_LIBRARY_PATH="/opt/rocm/lib:${LD_LIBRARY_PATH}"
export HSA_OVERRIDE_GFX_VERSION=11.5.1  # Required for gfx1150 support
export HSA_ENABLE_SDMA=0  # May be needed for APU stability

EOF

# Create system-wide ROCm profile
cat > /etc/profile.d/rocm.sh << 'EOF'
export PATH="/opt/rocm/bin:${PATH}"
export LD_LIBRARY_PATH="/opt/rocm/lib:${LD_LIBRARY_PATH}"
export HSA_OVERRIDE_GFX_VERSION=11.5.1  # Required for gfx1150 support
export HSA_ENABLE_SDMA=0  # May be needed for APU stability

EOF

chmod +x /etc/profile.d/rocm.sh

# Source the new environment
source /root/.bashrc
source /etc/profile.d/rocm.sh


# Verify ROCm installation
echo ""
echo -e "${GREEN}==========================================${NC}"
echo -e "${GREEN}Verifying ROCm LXC installation...${NC}"
echo -e "${GREEN}==========================================${NC}"
echo ""

# Check if tools are installed
if ! which rocm-smi rocminfo nvtop radeontop >/dev/null 2>&1; then
    echo -e "${RED}ERROR: ROCm tools not found in PATH${NC}"
    exit 1
fi
echo -e "${GREEN}✓ ROCm tools installed${NC}"

# Verify devices are accessible
if [ ! -e /dev/kfd ]; then
    echo -e "${RED}ERROR: /dev/kfd not found - GPU not accessible in container${NC}"
    echo -e "${YELLOW}Troubleshooting:${NC}"
    echo "  1. Check LXC config: cat /etc/pve/lxc/\${CONTAINER_ID}.conf"
    echo "  2. Verify mount entry exists: lxc.mount.entry: /dev/kfd dev/kfd none bind,optional,create=file"
    echo "  3. On host, check: ls -la /dev/kfd"
    echo "  4. Restart container: pct restart \${CONTAINER_ID}"
    exit 1
fi
echo -e "${GREEN}✓ /dev/kfd accessible${NC}"

if [ ! -e /dev/dri/card0 ] || [ ! -e /dev/dri/renderD128 ]; then
    echo -e "${RED}ERROR: DRI devices not found - GPU not accessible in container${NC}"
    echo -e "${YELLOW}Current DRI devices:${NC}"
    ls -la /dev/dri/ 2>/dev/null || echo "  None found"
    echo -e "${YELLOW}Troubleshooting:${NC}"
    echo "  1. Check LXC config: cat /etc/pve/lxc/\${CONTAINER_ID}.conf"
    echo "  2. Verify PCI address is correct"
    echo "  3. On host, check: ls -la /dev/dri/by-path/"
    echo "  4. Restart container: pct restart \${CONTAINER_ID}"
    exit 1
fi
echo -e "${GREEN}✓ DRI devices accessible${NC}"
ls -la /dev/dri/ | grep -E "(card0|renderD128)"

# Test rocminfo - must detect GPU agent
echo ""
echo -e "${YELLOW}>>> Testing rocminfo (must detect GPU agent):${NC}"
ROCM_OUTPUT=$(rocminfo 2>&1)
if echo "$ROCM_OUTPUT" | grep -qi "Agent [0-9]"; then
    echo "$ROCM_OUTPUT" | grep -i -A5 'Agent [0-9]' | head -20
    echo -e "${GREEN}✓ rocminfo detected GPU agent${NC}"
else
    echo -e "${RED}ERROR: rocminfo did not detect any GPU agents${NC}"
    echo ""
    echo -e "${YELLOW}Full rocminfo output:${NC}"
    echo "$ROCM_OUTPUT"
    echo ""
    echo -e "${YELLOW}This usually means:${NC}"
    echo "  1. GPU devices are not properly mounted in the container"
    echo "  2. HSA_OVERRIDE_GFX_VERSION environment variable may be needed"
    echo "  3. User needs to be in 'video' and 'render' groups"
    echo ""
    echo -e "${YELLOW}Checking group membership:${NC}"
    groups root
    echo ""
    exit 1
fi

# Test rocm-smi
echo ""
echo -e "${YELLOW}>>> Testing rocm-smi:${NC}"
if rocm-smi --showproductname 2>&1 | grep -qi "GPU"; then
    rocm-smi --showproductname --showmeminfo --showuse 2>&1 || true
    echo -e "${GREEN}✓ rocm-smi can access GPU${NC}"
else
    echo -e "${YELLOW}Warning: rocm-smi may not fully access GPU (this can be normal for some GPUs)${NC}"
    rocm-smi 2>&1 || true
fi

# Verify installation
echo ""
echo -e "${GREEN}==========================================${NC}"
echo -e "${GREEN}Testing GPU Access in Docker${NC}"
echo -e "${GREEN}==========================================${NC}"
echo ""
echo -e "${GREEN}>>> Verifying AMD ROCm installation with Docker...${NC}"
echo ""
echo -e "${YELLOW}Test 1: ROCM Info and SMI test${NC}"
echo -e "${YELLOW}Image: rocm/rocm:5.4.3-ubuntu22.04 (~1GB)${NC}"
echo -e "${YELLOW}Command: docker run --rm --name rcom-smi --device /dev/kfd --device /dev/dri -e HSA_OVERRIDE_GFX_VERSION=11.5.1 -e HSA_ENABLE_SDMA=0 --group-add video --cap-add=SYS_PTRACE --security-opt seccomp=unconfined --ipc=host rocm/rocm-terminal bash -c \"rocm-smi --showmemuse --showuse --showmeminfo all --showhw --showproductname && rocminfo | grep -i -A5 'Agent [0-9]'\"${NC}"
echo ""

# Check if running interactively or via pct exec
if [ -t 0 ]; then
    read -r -p "Run Test 1? This will download ~1GB. [Y/n]: " RUN_TEST1
    RUN_TEST1=${RUN_TEST1:-Y}
else
    # Non-interactive mode (pct exec) - skip Docker test by default
    echo -e "${YELLOW}Non-interactive mode detected. Skipping Docker test.${NC}"
    RUN_TEST1="n"
fi

if [[ "$RUN_TEST1" =~ ^[Yy]$ ]]; then
    docker run --rm --name rcom-smi --device /dev/kfd --device /dev/dri -e HSA_OVERRIDE_GFX_VERSION=11.5.1 -e HSA_ENABLE_SDMA=0 --group-add video --cap-add=SYS_PTRACE --security-opt seccomp=unconfined --ipc=host rocm/rocm-terminal bash -c "rocm-smi --showmemuse --showuse --showmeminfo all --showhw --showproductname && rocminfo | grep -i -A5 'Agent [0-9]'" || echo -e "${YELLOW}Warning: Docker test failed${NC}"
    
    if [ $? -eq 0 ]; then
        echo ""
        echo -e "${GREEN}✓ Test 1 passed!${NC}"
    fi
fi

echo ""
echo -e "${GREEN}==========================================${NC}"
echo -e "${GREEN}Installation Complete!${NC}"
echo -e "${GREEN}==========================================${NC}"
echo ""
echo -e "${GREEN}Your LXC container is now ready to use AMD GPUs in Docker containers.${NC}"
echo ""
echo -e "${YELLOW}You can manually test Docker GPU access later with:${NC}"
echo "  docker run --rm --name rcom-smi --device /dev/kfd --device /dev/dri -e HSA_OVERRIDE_GFX_VERSION=11.5.1 -e HSA_ENABLE_SDMA=0 --group-add video --cap-add=SYS_PTRACE --security-opt seccomp=unconfined --ipc=host rocm/rocm-terminal bash -c \"rocm-smi --showmemuse --showuse --showmeminfo all --showhw --showproductname && rocminfo | grep -i -A5 'Agent [0-9]'\""
echo ""