#!/usr/bin/env bash
# SCRIPT_DESC: Verify AMD driver installation
# SCRIPT_DETECT: lsmod | grep -q amdgpu

# Verify AMD ROCm driver installation
# This script checks if AMD drivers and tools are properly installed and accessible

# Get script directory and source utilities
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/../includes/colors.sh"
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/../includes/gpu-detect.sh"

echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}AMD Driver Verification${NC}"
echo -e "${GREEN}========================================${NC}"
echo ""

# Check if AMD GPU is present
if ! detect_amd_gpus; then
    echo -e "${RED}✗ No AMD GPUs detected on this system${NC}"
    echo ""
    echo -e "${YELLOW}Available GPUs:${NC}"
    lspci -nn | grep -i "VGA\|3D\|Display"
    echo ""
    exit 1
fi
echo -e "${GREEN}✓ AMD GPU detected${NC}"

# Check if driver is loaded
if ! lsmod | grep -q amdgpu; then
    echo -e "${RED}✗ amdgpu kernel module not loaded${NC}"
    echo ""
    echo -e "${YELLOW}Try:${NC}"
    echo "  1. Run script 003 to install AMD drivers"
    echo "  2. Reboot the system"
    echo ""
    exit 1
fi
echo -e "${GREEN}✓ amdgpu kernel module loaded${NC}"

# Check for /dev/kfd
if [ ! -e /dev/kfd ]; then
    echo -e "${RED}✗ /dev/kfd not found${NC}"
    echo -e "${YELLOW}ROCm compute interface not available${NC}"
    exit 1
fi
echo -e "${GREEN}✓ /dev/kfd present${NC}"

# Check for ROCm tools
echo ""
echo -e "${YELLOW}>>> Checking for ROCm tools...${NC}"
if ! which rocm-smi rocminfo nvtop radeontop >/dev/null 2>&1; then
    echo -e "${RED}✗ Some ROCm tools are missing${NC}"
    which rocm-smi rocminfo nvtop radeontop || true
    exit 1
fi
echo -e "${GREEN}✓ All ROCm tools installed${NC}"

# Test rocminfo
echo ""
echo -e "${YELLOW}>>> Testing rocminfo...${NC}"
if rocminfo | grep -qi "Agent [0-9]"; then
rocminfo | grep -i -A5 'Agent [0-9]'
    echo -e "${GREEN}✓ rocminfo detected GPU agents${NC}"
else
    echo -e "${RED}✗ rocminfo did not detect GPU agents${NC}"
    rocminfo
    exit 1
fi

# Test rocm-smi
echo ""
echo -e "${YELLOW}>>> Testing rocm-smi...${NC}"
if rocm-smi --showproductname 2>&1 | grep -qi "GPU"; then
rocm-smi --showmemuse --showuse --showmeminfo all --showhw --showproductname
    echo -e "${GREEN}✓ rocm-smi working${NC}"
else
    echo -e "${YELLOW}⚠ rocm-smi may not fully access GPU${NC}"
    rocm-smi || true
fi

echo ""
echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}✓ AMD Driver Verification Complete${NC}"
echo -e "${GREEN}========================================${NC}"
