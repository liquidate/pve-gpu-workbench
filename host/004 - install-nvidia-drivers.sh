#!/usr/bin/env bash
# SCRIPT_DESC: Install NVIDIA Cuda and Kernel drivers
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
apt update
echo ">>> Installing Proxmox headers for current kernel"
apt install -y proxmox-headers-"$(uname -r)"
echo ">>> Downloading and installing NVIDIA CUDA keyring"
wget https://developer.download.nvidia.com/compute/cuda/repos/debian12/x86_64/cuda-keyring_1.1-1_all.deb
dpkg -i cuda-keyring_1.1-1_all.deb
rm cuda-keyring_1.1-1_all.deb
apt update
echo ">>> Installing NVIDIA driver packages"
apt install -y nvidia-driver-cuda nvidia-kernel-dkms
echo ">>> Please reboot the system now"