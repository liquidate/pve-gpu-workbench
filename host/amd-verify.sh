#!/usr/bin/env bash
# SCRIPT_DESC: Comprehensive AMD GPU setup verification
# SCRIPT_DETECT: false

# Comprehensive AMD GPU Verification
# This script checks ALL aspects of AMD GPU setup:
# - Hardware detection
# - Kernel module and driver
# - ROCm tools and libraries
# - VRAM allocation (for iGPU)
# - udev rules
# - User permissions
# - Environment variables
# - Detects if reboot is needed

# Get script directory and source utilities
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/../includes/colors.sh"
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/../includes/gpu-detect.sh"

echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}Comprehensive AMD GPU Verification${NC}"
echo -e "${GREEN}========================================${NC}"
echo ""

# Track overall status
CHECKS_PASSED=0
CHECKS_TOTAL=0
REBOOT_NEEDED=false

# Helper function to report check results
check_result() {
    local status=$1
    local message=$2
    ((CHECKS_TOTAL++))
    if [ "$status" -eq 0 ]; then
        echo -e "${GREEN}✓${NC} $message"
        ((CHECKS_PASSED++))
    else
        echo -e "${RED}✗${NC} $message"
    fi
}

echo -e "${CYAN}═══ HARDWARE DETECTION ═══${NC}"
# Check if AMD GPU is present
if detect_amd_gpus; then
    check_result 0 "AMD GPU detected"
    lspci | grep -i "VGA\|3D\|Display" | grep -i AMD | sed 's/^/  /'
else
    check_result 1 "AMD GPU not detected"
    echo -e "${YELLOW}Available GPUs:${NC}"
    lspci -nn | grep -i "VGA\|3D\|Display" | sed 's/^/  /'
    echo ""
    exit 1
fi
echo ""

echo -e "${CYAN}═══ KERNEL & DRIVER ═══${NC}"
# Check if driver is loaded
rocm_installed=false
if [ -d "/opt/rocm" ] || command -v rocm-smi &>/dev/null; then
    rocm_installed=true
fi

if lsmod | grep -q amdgpu; then
    check_result 0 "amdgpu kernel module loaded"
else
    check_result 1 "amdgpu kernel module NOT loaded"
    if [ "$rocm_installed" = true ]; then
        echo -e "${YELLOW}  → Reboot required to load kernel module${NC}"
        REBOOT_NEEDED=true
    else
        echo -e "${YELLOW}  → Run 'amd-drivers' then reboot${NC}"
    fi
fi

# Check for /dev/kfd
if [ -e /dev/kfd ]; then
    check_result 0 "/dev/kfd present (ROCm compute interface)"
else
    check_result 1 "/dev/kfd not found (ROCm compute unavailable)"
fi

# Check for DRI devices
if ls /dev/dri/card* >/dev/null 2>&1 && ls /dev/dri/renderD* >/dev/null 2>&1; then
    check_result 0 "DRI devices present ($(ls /dev/dri/card* /dev/dri/renderD* 2>/dev/null | wc -l) devices)"
else
    check_result 1 "DRI devices missing"
fi
echo ""

echo -e "${CYAN}═══ VRAM ALLOCATION (iGPU) ═══${NC}"
# Check GTT size allocation (for iGPU)
grub_has_gtt=false
active_has_gtt=false

# Check if configured in GRUB
if grep -q "amdgpu.gttsize=" /etc/default/grub 2>/dev/null || \
   grep -q "amdgpu.gttsize=" /etc/kernel/cmdline 2>/dev/null; then
    grub_has_gtt=true
fi

# Check if active in running kernel
if grep -q "amdgpu.gttsize=" /proc/cmdline 2>/dev/null; then
    active_has_gtt=true
    gtt_size=$(grep -oP 'amdgpu.gttsize=\K[0-9]+' /proc/cmdline)
    gtt_gb=$((gtt_size / 1024))
    check_result 0 "GTT size active (${gtt_gb}GB)"
    grep -o 'amdgpu.gttsize=[^ ]*' /proc/cmdline | sed 's/^/  /'
fi

# Detect reboot needed
if [ "$grub_has_gtt" = true ] && [ "$active_has_gtt" = false ]; then
    check_result 1 "GTT size configured but not active"
    echo -e "${YELLOW}  → Reboot required to apply kernel parameters${NC}"
    REBOOT_NEEDED=true
elif [ "$grub_has_gtt" = false ]; then
    check_result 1 "GTT size not configured (Strix Halo needs this!)"
    echo -e "${YELLOW}  → Run 'strix-igpu' to allocate 96GB${NC}"
fi
echo ""

echo -e "${CYAN}═══ ROCM INSTALLATION ═══${NC}"
# Check for ROCm tools
command -v rocm-smi >/dev/null 2>&1 && check_result 0 "rocm-smi installed" || check_result 1 "rocm-smi missing"
command -v rocminfo >/dev/null 2>&1 && check_result 0 "rocminfo installed" || check_result 1 "rocminfo missing"
command -v nvtop >/dev/null 2>&1 && check_result 0 "nvtop installed" || check_result 1 "nvtop missing"
command -v radeontop >/dev/null 2>&1 && check_result 0 "radeontop installed" || check_result 1 "radeontop missing"

# Check ROCm directory
if [ -d /opt/rocm ]; then
    check_result 0 "ROCm directory present (/opt/rocm)"
else
    check_result 1 "ROCm directory missing"
fi
echo ""

echo -e "${CYAN}═══ USER PERMISSIONS ═══${NC}"
# Check if root is in render group
if groups root | grep -q render; then
    check_result 0 "root user in 'render' group"
else
    check_result 1 "root user NOT in 'render' group"
fi

# Check if root is in video group
if groups root | grep -q video; then
    check_result 0 "root user in 'video' group"
else
    check_result 1 "root user NOT in 'video' group"
fi
echo ""

echo -e "${CYAN}═══ UDEV RULES ═══${NC}"
# Check for GPU udev rules
if [ -f /etc/udev/rules.d/99-gpu-passthrough.rules ]; then
    check_result 0 "GPU udev rules installed"
    echo -e "${DIM}  $(wc -l < /etc/udev/rules.d/99-gpu-passthrough.rules) rules configured${NC}"
else
    check_result 1 "GPU udev rules missing"
    echo -e "${YELLOW}  → Run 'gpu-udev' to set up device permissions${NC}"
fi
echo ""

echo -e "${CYAN}═══ ENVIRONMENT ═══${NC}"
# Check for ROCm environment file
if [ -f /etc/profile.d/rocm.sh ]; then
    check_result 0 "ROCm environment configured (/etc/profile.d/rocm.sh)"
else
    check_result 1 "ROCm environment file missing"
fi

# Check if ROCm is in PATH
if echo "$PATH" | grep -q "/opt/rocm"; then
    check_result 0 "ROCm in PATH"
else
    check_result 1 "ROCm NOT in PATH (may need to source /etc/profile.d/rocm.sh)"
fi
echo ""

echo -e "${CYAN}═══ FUNCTIONAL TESTS ═══${NC}"
# Test rocminfo
if command -v rocminfo >/dev/null 2>&1; then
    if rocminfo 2>/dev/null | grep -qi "Agent [0-9]"; then
        check_result 0 "rocminfo detects GPU agents"
        rocminfo 2>/dev/null | grep -i -A3 'Agent [0-9]' | head -20 | sed 's/^/  /'
    else
        check_result 1 "rocminfo does NOT detect GPU agents"
    fi
else
    check_result 1 "rocminfo not available"
fi

# Test rocm-smi
if command -v rocm-smi >/dev/null 2>&1; then
    if rocm-smi --showproductname 2>&1 | grep -qi "GPU"; then
        check_result 0 "rocm-smi functional"
        echo -e "${DIM}GPU Info:${NC}"
        rocm-smi --showproductname 2>&1 | grep -i GPU | sed 's/^/  /'
    else
        check_result 1 "rocm-smi not detecting GPU"
    fi
else
    check_result 1 "rocm-smi not available"
fi
echo ""

echo -e "${GREEN}========================================${NC}"
if [ "$CHECKS_PASSED" -eq "$CHECKS_TOTAL" ]; then
    echo -e "${GREEN}✓ ALL CHECKS PASSED ($CHECKS_PASSED/$CHECKS_TOTAL)${NC}"
    echo -e "${GREEN}========================================${NC}"
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
    echo -e "${YELLOW}⚠ SOME CHECKS FAILED ($CHECKS_PASSED/$CHECKS_TOTAL passed)${NC}"
    echo -e "${GREEN}========================================${NC}"
    exit 1
fi
