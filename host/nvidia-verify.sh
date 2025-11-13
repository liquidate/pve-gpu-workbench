#!/usr/bin/env bash
# SCRIPT_DESC: Verify NVIDIA GPU setup and drivers
# SCRIPT_DETECT: false

# Comprehensive NVIDIA GPU Verification
# This script checks ALL aspects of NVIDIA GPU setup:
# - Hardware detection
# - Kernel module and driver
# - CUDA toolkit and tools
# - Device files
# - udev rules
# - Driver version
# - Detects if reboot is needed

# Get script directory and source utilities
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/../includes/colors.sh"
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/../includes/gpu-detect.sh"

echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}Comprehensive NVIDIA GPU Verification${NC}"
echo -e "${GREEN}========================================${NC}"
echo ""

# Track overall status
CHECKS_PASSED=0
CHECKS_TOTAL=0
OPTIONAL_CHECKS_FAILED=0
REBOOT_NEEDED=false

# Helper function to report check results
check_result() {
    local status=$1
    local message=$2
    local is_optional=false
    
    # Check if this is an optional check
    if [[ "$message" == *"(optional)"* ]]; then
        is_optional=true
    fi
    
    ((CHECKS_TOTAL++))
    if [ "$status" -eq 0 ]; then
        echo -e "${GREEN}✓${NC} $message"
        ((CHECKS_PASSED++))
    else
        echo -e "${RED}✗${NC} $message"
        if [ "$is_optional" = true ]; then
            ((OPTIONAL_CHECKS_FAILED++))
        fi
    fi
}

echo -e "${CYAN}═══ HARDWARE DETECTION ═══${NC}"
# Check if NVIDIA GPU is present
if detect_nvidia_gpus; then
    check_result 0 "NVIDIA GPU detected"
    lspci | grep -i "VGA\|3D\|Display" | grep -i NVIDIA | sed 's/^/  /'
else
    check_result 1 "NVIDIA GPU not detected"
    echo -e "${YELLOW}Available GPUs:${NC}"
    lspci -nn | grep -i "VGA\|3D\|Display" | sed 's/^/  /'
    echo ""
    exit 1
fi
echo ""

echo -e "${CYAN}═══ KERNEL & DRIVER ═══${NC}"
# Check if nvidia drivers are installed
nvidia_installed=false
if dpkg -l | grep -q "nvidia-kernel-dkms\|nvidia-driver"; then
    nvidia_installed=true
    check_result 0 "NVIDIA driver packages installed"
else
    check_result 1 "NVIDIA driver packages NOT installed"
    echo -e "${YELLOW}  → Run 'nvidia-drivers' to install${NC}"
fi

# Check if nvidia kernel module is loaded
if lsmod | grep -q "^nvidia "; then
    check_result 0 "nvidia kernel module loaded"
    # Get driver version from module
    DRIVER_VERSION=$(modinfo nvidia 2>/dev/null | grep "^version:" | awk '{print $2}')
    if [ -n "$DRIVER_VERSION" ]; then
        echo -e "${DIM}  Driver version: $DRIVER_VERSION${NC}"
    fi
else
    check_result 1 "nvidia kernel module NOT loaded"
    if [ "$nvidia_installed" = true ]; then
        echo -e "${YELLOW}  → Reboot required to load kernel module${NC}"
        REBOOT_NEEDED=true
    else
        echo -e "${YELLOW}  → Install nvidia drivers first${NC}"
    fi
fi

# Check for nvidia_uvm module (required for CUDA)
if lsmod | grep -q "nvidia_uvm"; then
    check_result 0 "nvidia_uvm module loaded (CUDA support)"
else
    check_result 1 "nvidia_uvm module not loaded"
    if [ "$nvidia_installed" = true ] && lsmod | grep -q "^nvidia "; then
        echo -e "${YELLOW}  → May need: modprobe nvidia_uvm${NC}"
    fi
fi
echo ""

echo -e "${CYAN}═══ DEVICE FILES ═══${NC}"
# Check for /dev/nvidia0
if [ -e /dev/nvidia0 ]; then
    check_result 0 "/dev/nvidia0 present"
    ls -la /dev/nvidia0 | sed 's/^/  /'
else
    check_result 1 "/dev/nvidia0 not found"
    if [ "$nvidia_installed" = true ]; then
        echo -e "${YELLOW}  → Reboot required${NC}"
        REBOOT_NEEDED=true
    fi
fi

# Check for /dev/nvidiactl
if [ -e /dev/nvidiactl ]; then
    check_result 0 "/dev/nvidiactl present"
else
    check_result 1 "/dev/nvidiactl not found"
fi

# Check for /dev/nvidia-uvm
if [ -e /dev/nvidia-uvm ]; then
    check_result 0 "/dev/nvidia-uvm present (CUDA Unified Memory)"
else
    check_result 1 "/dev/nvidia-uvm not found"
fi

# Count NVIDIA devices
NVIDIA_DEV_COUNT=$(ls /dev/nvidia* 2>/dev/null | grep -v "nvidia-caps" | wc -l)
if [ "$NVIDIA_DEV_COUNT" -gt 0 ]; then
    check_result 0 "NVIDIA device files present (${NVIDIA_DEV_COUNT} devices)"
else
    check_result 1 "No NVIDIA device files found"
fi
echo ""

echo -e "${CYAN}═══ NVIDIA TOOLS ═══${NC}"
# Check for nvidia-smi
if command -v nvidia-smi >/dev/null 2>&1; then
    check_result 0 "nvidia-smi installed"
else
    check_result 1 "nvidia-smi missing"
    echo -e "${YELLOW}  → Install nvidia-utils package${NC}"
fi

# Check for nvtop (monitoring tool)
if command -v nvtop >/dev/null 2>&1; then
    check_result 0 "nvtop installed (GPU monitoring)"
else
    check_result 1 "nvtop not installed (optional)"
fi
echo ""

echo -e "${CYAN}═══ UDEV RULES ═══${NC}"
# Check for GPU udev rules
if [ -f /etc/udev/rules.d/99-gpu-passthrough.rules ]; then
    check_result 0 "GPU udev rules installed"
    echo -e "${DIM}  $(wc -l < /etc/udev/rules.d/99-gpu-passthrough.rules) rules configured${NC}"
    
    # Check if NVIDIA rules are present
    if grep -q "nvidia" /etc/udev/rules.d/99-gpu-passthrough.rules; then
        check_result 0 "NVIDIA-specific udev rules present"
    else
        check_result 1 "NVIDIA-specific udev rules missing"
    fi
else
    check_result 1 "GPU udev rules missing"
    echo -e "${YELLOW}  → Run 'gpu-udev' to set up device permissions${NC}"
fi
echo ""

echo -e "${CYAN}═══ FUNCTIONAL TESTS ═══${NC}"
# Test nvidia-smi
if command -v nvidia-smi >/dev/null 2>&1; then
    if nvidia-smi &>/dev/null; then
        check_result 0 "nvidia-smi functional"
        echo ""
        echo -e "${CYAN}GPU Information:${NC}"
        nvidia-smi --query-gpu=index,name,driver_version,memory.total --format=csv,noheader 2>/dev/null | sed 's/^/  GPU /' || echo "  Unable to query GPU"
        echo ""
        echo -e "${CYAN}Full nvidia-smi output:${NC}"
        nvidia-smi 2>/dev/null | sed 's/^/  /'
    else
        check_result 1 "nvidia-smi not working"
        echo -e "${YELLOW}  → Check driver installation and reboot if needed${NC}"
    fi
else
    check_result 1 "nvidia-smi not available"
fi
echo ""

echo -e "${GREEN}========================================${NC}"
if [ "$CHECKS_PASSED" -eq "$CHECKS_TOTAL" ]; then
    echo -e "${GREEN}✓ ALL CHECKS PASSED ($CHECKS_PASSED/$CHECKS_TOTAL)${NC}"
    echo -e "${GREEN}========================================${NC}"
    echo ""
    echo -e "${CYAN}Your NVIDIA GPU is fully functional!${NC}"
    echo ""
    echo -e "${CYAN}Next steps:${NC}"
    echo "  • Create GPU-enabled LXC: Run 'ollama-nvidia'"
    echo "  • Monitor GPU: nvidia-smi -l 1"
    echo ""
    exit 0
elif [ "$REBOOT_NEEDED" = true ]; then
    echo -e "${YELLOW}⚠ REBOOT REQUIRED ($CHECKS_PASSED/$CHECKS_TOTAL passed)${NC}"
    echo -e "${GREEN}========================================${NC}"
    echo ""
    echo -e "${YELLOW}Changes have been made but require a reboot to take effect.${NC}"
    echo -e "${CYAN}After rebooting, run this verification again.${NC}"
    echo ""
    exit 2
else
    # Calculate critical checks (total - optional)
    CRITICAL_FAILED=$((CHECKS_TOTAL - CHECKS_PASSED - OPTIONAL_CHECKS_FAILED))
    
    if [ "$CRITICAL_FAILED" -eq 0 ]; then
        # All critical checks passed, only optional tools missing
        echo -e "${GREEN}✓ ALL CRITICAL CHECKS PASSED ($CHECKS_PASSED/$CHECKS_TOTAL total)${NC}"
        echo -e "${GREEN}========================================${NC}"
        echo ""
        if [ "$OPTIONAL_CHECKS_FAILED" -gt 0 ]; then
            echo -e "${DIM}Note: $OPTIONAL_CHECKS_FAILED optional tool(s) not installed (non-critical)${NC}"
            echo -e "${DIM}Install with: apt install nvtop${NC}"
            echo ""
        fi
        exit 0
    else
        # Critical checks failed
        echo -e "${YELLOW}⚠ SOME CHECKS FAILED ($CHECKS_PASSED/$CHECKS_TOTAL passed)${NC}"
        echo -e "${GREEN}========================================${NC}"
        echo ""
        echo -e "${YELLOW}Troubleshooting:${NC}"
        echo "  1. Install drivers: Run 'nvidia-drivers'"
        echo "  2. Reboot the system"
        echo "  3. Run this verification again"
        echo "  4. Check kernel logs: dmesg | grep -i nvidia"
        echo ""
        exit 1
    fi
fi
