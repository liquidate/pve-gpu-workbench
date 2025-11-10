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
    
    # Check if running in interactive terminal and verbose mode is off
    if [ "$VERBOSE" = "1" ] || [ ! -t 1 ]; then
        # Non-interactive or verbose - just show message and wait
        echo -e "${GREEN}>>> ${message}...${NC}"
        wait $pid
        echo -e "${GREEN}✓ ${message}${NC}"
    else
        # Interactive - show spinner
        local spin='⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏'
        local i=0
        
        echo -n "${GREEN}${message} "
        while kill -0 $pid 2>/dev/null; do
            i=$(( (i+1) %10 ))
            printf "\b${spin:$i:1}"
            sleep 0.1
        done
        printf "\b✓${NC}\n"
    fi
}

# Get script directory and source colors
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/../includes/colors.sh"

echo -e "${GREEN}==========================================${NC}"
echo -e "${GREEN}Docker + AMD GPU Setup for LXC${NC}"
echo -e "${GREEN}==========================================${NC}"
echo ""

# Check if AMD drivers are installed on the HOST (not in this container)
echo -e "${GREEN}>>> Checking host AMD drivers...${NC}"
if ! nsenter -t 1 -m -- lsmod | grep -q amdgpu; then
    echo -e "${RED}✗ AMD drivers NOT installed on Proxmox host${NC}"
    echo ""
    echo -e "${YELLOW}AMD GPU drivers must be installed on the host first!${NC}"
    echo -e "${YELLOW}Please run: ${GREEN}003 - install-amd-drivers.sh${YELLOW} on the host${NC}"
    echo ""
    read -r -p "Continue anyway? [y/N]: " CONTINUE
    CONTINUE=${CONTINUE:-N}
    if [[ ! "$CONTINUE" =~ ^[Yy]$ ]]; then
        echo -e "${RED}Installation cancelled.${NC}"
        exit 1
    fi
else
    echo -e "${GREEN}✓ AMD drivers detected on host${NC}"
fi
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

# Remove debian-provided packages (silently)
apt remove -y docker-compose docker docker.io containerd runc >/dev/null 2>&1 || true

# Update package list and upgrade existing packages
if [ "$VERBOSE" = "1" ]; then
echo -e "${GREEN}>>> Updating system packages...${NC}"
    apt update
    apt upgrade -y -o Dpkg::Options::="--force-confdef" -o Dpkg::Options::="--force-confold"
    echo -e "${GREEN}✓ System packages updated${NC}"
else
    echo -e "${GREEN}>>> Updating package cache...${NC}"
    apt update $QUIET_APT >/dev/null 2>&1
    echo -e "${GREEN}✓ Package cache updated${NC}"
    echo -e "${GREEN}>>> Upgrading system packages...${NC}"
    apt upgrade -y $QUIET_APT -o Dpkg::Options::="--force-confdef" -o Dpkg::Options::="--force-confold" >/dev/null 2>&1
    echo -e "${GREEN}✓ System packages upgraded${NC}"
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
systemctl start docker >/dev/null 2>&1
systemctl enable docker >/dev/null 2>&1

# Add root user to docker group
usermod -a -G docker root >/dev/null 2>&1

# Verify Docker installation
if [ "$VERBOSE" = "1" ]; then
echo -e "${GREEN}>>> Docker version installed:${NC}"
docker --version
echo -e "${GREEN}>>> Docker Compose version installed:${NC}"
docker compose version
echo -e "${GREEN}>>> Containerd version installed:${NC}"
containerd --version
fi
echo -e "${GREEN}✓ Docker installation completed${NC}"

# Install docker-compose bash completion
if [ "$VERBOSE" = "1" ]; then
curl -L https://raw.githubusercontent.com/docker/cli/master/contrib/completion/bash/docker \
    -o /etc/bash_completion.d/docker-compose
else
    curl -sL https://raw.githubusercontent.com/docker/cli/master/contrib/completion/bash/docker \
        -o /etc/bash_completion.d/docker-compose 2>/dev/null
fi

echo ""
echo -e "${GREEN}==========================================${NC}"
echo -e "${GREEN}Installing AMD ROCm Libraries${NC}"
echo -e "${GREEN}==========================================${NC}"
echo ""

# Add AMD ROCm repository
# Add AMD ROCm GPG key
# Make the directory if it doesn't exist yet.
# This location is recommended by the distribution maintainers.
sudo mkdir --parents --mode=0755 /etc/apt/keyrings 2>/dev/null

# Download the key, convert the signing-key to a full
# keyring required by apt and store in the keyring directory
if [ "$VERBOSE" = "1" ]; then
    echo -e "${GREEN}>>> Adding AMD ROCm repository...${NC}"
wget https://repo.radeon.com/rocm/rocm.gpg.key -O - | \
    gpg --dearmor | sudo tee /etc/apt/keyrings/rocm.gpg > /dev/null
else
    wget -q https://repo.radeon.com/rocm/rocm.gpg.key -O - 2>/dev/null | \
        gpg --dearmor 2>/dev/null | sudo tee /etc/apt/keyrings/rocm.gpg >/dev/null 2>&1
    echo -e "${GREEN}✓ Added AMD ROCm repository${NC}"
fi

# Add ROCm 7.1.0 repository (Noble/24.04)
sudo tee /etc/apt/sources.list.d/rocm.list >/dev/null << EOF
deb [arch=amd64 signed-by=/etc/apt/keyrings/rocm.gpg] https://repo.radeon.com/rocm/apt/7.1 noble main
deb [arch=amd64 signed-by=/etc/apt/keyrings/rocm.gpg] https://repo.radeon.com/graphics/7.1/ubuntu noble main
EOF

sudo tee /etc/apt/preferences.d/rocm-pin-600 >/dev/null << EOF
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
    echo -e "${GREEN}>>> Installing AMD ROCm libraries [2-3 min]...${NC}"
    apt install -y $QUIET_APT rocm-libs rocm-smi rocminfo rocm-device-libs rocm-utils >/dev/null 2>&1
    echo -e "${GREEN}✓ ROCm libraries installed${NC}"
fi

# Install ROCm development packages (needed for Ollama Docker to compile if needed)
if [ "$VERBOSE" = "1" ]; then
    echo -e "${GREEN}>>> Installing ROCm development packages...${NC}"
apt install -y rocm-core rocm-dev hipcc
    echo -e "${GREEN}✓ ROCm dev packages installed${NC}"
else
    echo -e "${GREEN}>>> Installing ROCm development packages [1-2 min]...${NC}"
    apt install -y $QUIET_APT rocm-core rocm-dev hipcc >/dev/null 2>&1
    echo -e "${GREEN}✓ ROCm dev packages installed${NC}"
fi

# Install monitoring and utility tools
if [ "$VERBOSE" = "1" ]; then
    echo -e "${GREEN}>>> Installing monitoring and utility tools...${NC}"
    apt install -y nvtop radeontop btop htop nano vim curl wget git
    echo -e "${GREEN}✓ Monitoring and utility tools installed${NC}"
else
    echo -e "${GREEN}>>> Installing monitoring and utility tools...${NC}"
    apt install -y $QUIET_APT nvtop radeontop btop htop nano vim curl wget git >/dev/null 2>&1
    echo -e "${GREEN}✓ Monitoring and utility tools installed${NC}"
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
if ! which rocm-smi rocminfo nvtop radeontop btop htop nano vim >/dev/null 2>&1; then
    echo -e "${RED}ERROR: Required tools not found in PATH${NC}"
    exit 1
fi
echo -e "${GREEN}✓ ROCm, monitoring, and utility tools installed${NC}"

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
    rocm-smi --showproductname --showuse 2>&1 || true
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
echo -e "${YELLOW}=== Monitoring Tools ===${NC}"
        echo ""
echo -e "${GREEN}GPU Monitoring:${NC}"
echo "  nvtop                                   # GPU monitor (AMD/NVIDIA)"
echo "  radeontop                               # AMD-specific GPU monitor"
echo "  watch -n 0.5 rocm-smi --showuse --showmemuse  # Real-time GPU stats"
        echo ""
echo -e "${GREEN}System Monitoring:${NC}"
echo "  btop                                    # Modern resource monitor (best)"
echo "  htop                                    # Classic process monitor"
    echo ""
echo -e "${GREEN}GPU Information:${NC}"
echo "  rocm-smi --showproductname --showhw     # GPU details"
echo "  rocminfo | grep -A 10 'Agent 2'         # ROCm agent info"
    echo ""