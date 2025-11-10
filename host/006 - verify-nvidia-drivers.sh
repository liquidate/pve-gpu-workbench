#!/usr/bin/env bash
# SCRIPT_DESC: Verify NVIDIA driver installation
# SCRIPT_DETECT: command -v nvidia-smi &>/dev/null

# Verify NVIDIA driver installation
# This script checks if NVIDIA drivers and tools are properly installed and accessible

# Get script directory and source utilities
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/../includes/colors.sh"
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/../includes/gpu-detect.sh"

echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}NVIDIA Driver Verification${NC}"
echo -e "${GREEN}========================================${NC}"
echo ""

# Check if NVIDIA GPU is present
if ! detect_nvidia_gpus; then
    echo -e "${RED}✗ No NVIDIA GPUs detected on this system${NC}"
    echo ""
    echo -e "${YELLOW}Available GPUs:${NC}"
    lspci -nn | grep -i "VGA\|3D\|Display"
    echo ""
    exit 1
fi
echo -e "${GREEN}✓ NVIDIA GPU detected${NC}"

# Check if driver is loaded
if ! lsmod | grep -q nvidia; then
    echo -e "${RED}✗ nvidia kernel module not loaded${NC}"
    echo ""
    echo -e "${YELLOW}Try:${NC}"
    echo "  1. Run script 004 to install NVIDIA drivers"
    echo "  2. Reboot the system"
    echo ""
    exit 1
fi
echo -e "${GREEN}✓ nvidia kernel module loaded${NC}"

# Check for /dev/nvidia0
if [ ! -e /dev/nvidia0 ]; then
    echo -e "${RED}✗ /dev/nvidia0 not found${NC}"
    echo -e "${YELLOW}NVIDIA device interface not available${NC}"
    exit 1
fi
echo -e "${GREEN}✓ /dev/nvidia0 present${NC}"

# Check for nvidia-smi
echo ""
echo -e "${YELLOW}>>> Checking for NVIDIA tools...${NC}"
if ! which nvidia-smi >/dev/null 2>&1; then
    echo -e "${RED}✗ nvidia-smi not found${NC}"
    exit 1
fi
echo -e "${GREEN}✓ nvidia-smi installed${NC}"

# Test nvidia-smi
echo ""
echo -e "${YELLOW}>>> Testing nvidia-smi...${NC}"
if nvidia-smi >/dev/null 2>&1; then
nvidia-smi
    echo ""
    echo -e "${GREEN}✓ nvidia-smi working${NC}"
else
    echo -e "${RED}✗ nvidia-smi failed${NC}"
    nvidia-smi || true
    exit 1
fi

echo ""
echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}✓ NVIDIA Driver Verification Complete${NC}"
echo -e "${GREEN}========================================${NC}"