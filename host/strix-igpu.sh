#!/usr/bin/env bash
# SCRIPT_DESC: Configure Strix Halo iGPU VRAM allocation
# SCRIPT_CATEGORY: host-setup
# SCRIPT_DETECT: grep -q "amdgpu.gttsize=" /proc/cmdline 2>/dev/null

# Get script directory and source colors
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/../includes/colors.sh"

echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}Strix Halo iGPU VRAM Configuration${NC}"
echo -e "${GREEN}========================================${NC}"
echo ""

# Check current configuration
current_gtt=""
if grep -q "amdgpu.gttsize=" /etc/default/grub 2>/dev/null; then
    current_gtt=$(grep -oP 'amdgpu.gttsize=\K[0-9]+' /etc/default/grub 2>/dev/null | head -1)
elif grep -q "amdgpu.gttsize=" /etc/kernel/cmdline 2>/dev/null; then
    current_gtt=$(grep -oP 'amdgpu.gttsize=\K[0-9]+' /etc/kernel/cmdline 2>/dev/null | head -1)
fi

if [ -n "$current_gtt" ]; then
    current_gb=$((current_gtt / 1024))
    echo -e "${CYAN}Current configuration:${NC} ${BOLD}${current_gb}GB${NC} VRAM allocated"
    echo ""
fi

# Prompt for desired allocation
echo -e "${YELLOW}Strix Halo can allocate up to 96GB for iGPU VRAM.${NC}"
echo ""
echo "Common allocations:"
echo "  16GB  - Light workloads (smaller models)"
echo "  32GB  - Medium workloads"
echo "  64GB  - Large models"
echo "  96GB  - Maximum (huge models)"
echo ""

# Default to 96GB
read -r -p "Enter VRAM allocation in GB [96]: " vram_gb
vram_gb=${vram_gb:-96}

# Validate input
if ! [[ "$vram_gb" =~ ^[0-9]+$ ]] || [ "$vram_gb" -lt 1 ] || [ "$vram_gb" -gt 96 ]; then
    echo -e "${RED}Invalid value. Must be between 1 and 96 GB.${NC}"
    exit 1
fi

# Check if configuration is already set to the desired value
if [ -n "$current_gtt" ]; then
    if [ "$current_gb" -eq "$vram_gb" ]; then
        echo ""
        echo -e "${GREEN}✓ Already configured with ${vram_gb}GB VRAM${NC}"
        echo -e "${DIM}No changes needed${NC}"
        echo ""
        exit 0
    fi
fi

# Convert to MB for gttsize parameter
gtt_size=$((vram_gb * 1024))

# Calculate ttm parameters (proportional to gttsize)
ttm_pages=$((gtt_size * 256))
ttm_pool=$((gtt_size * 256))

# Define the parameters to add
amdgpu_vram_string="amdgpu.gttsize=${gtt_size} ttm.pages_limit=${ttm_pages} ttm.page_pool_size=${ttm_pool}"

echo ""
echo -e "${CYAN}>>> Configuring iGPU VRAM to ${vram_gb}GB...${NC}"

# Check if the system is using ZFS (has /etc/kernel/cmdline)
if [ -f /etc/kernel/cmdline ]; then
    echo ">>> Detected ZFS system - using /etc/kernel/cmdline"
    
    # Remove any existing amdgpu parameters
    sed -i 's/amdgpu\.gttsize=[0-9]*//g; s/ttm\.pages_limit=[0-9]*//g; s/ttm\.page_pool_size=[0-9]*//g' /etc/kernel/cmdline
    # Clean up extra spaces
    sed -i 's/  */ /g; s/^ *//; s/ *$//' /etc/kernel/cmdline
    
    # Add new parameters
    echo ">>> Adding iGPU VRAM parameters to kernel cmdline"
    sed -i "1s/$/ $amdgpu_vram_string/" /etc/kernel/cmdline
    
    echo ">>> Refreshing Proxmox boot tool to apply changes"
    proxmox-boot-tool refresh
    
    echo ""
    echo -e "${GREEN}✓ Configuration updated successfully!${NC}"
    echo -e "${YELLOW}⚠  Reboot required to apply changes${NC}"
else
    echo ">>> Detected non-ZFS system - using /etc/default/grub"
    
    # Get the current GRUB_CMDLINE_LINUX_DEFAULT value
    current_cmdline=$(grep '^GRUB_CMDLINE_LINUX_DEFAULT=' /etc/default/grub | sed 's/^GRUB_CMDLINE_LINUX_DEFAULT="\(.*\)"$/\1/')
    
    # Remove any existing amdgpu parameters
    current_cmdline=$(echo "$current_cmdline" | sed 's/amdgpu\.gttsize=[0-9]*//g; s/ttm\.pages_limit=[0-9]*//g; s/ttm\.page_pool_size=[0-9]*//g; s/  */ /g; s/^ *//; s/ *$//')
    
    # Append the new parameters
    new_cmdline="$current_cmdline $amdgpu_vram_string"
    
    # Update the grub configuration
    echo ">>> Updating GRUB configuration"
    sed -i "s|^GRUB_CMDLINE_LINUX_DEFAULT=.*|GRUB_CMDLINE_LINUX_DEFAULT=\"$new_cmdline\"|" /etc/default/grub
    
    echo ">>> Running update-grub"
    update-grub
    
    echo ""
    echo -e "${GREEN}✓ Configuration updated successfully!${NC}"
    echo -e "${YELLOW}⚠  Reboot required to apply changes${NC}"
fi

echo ""
exit 3  # Exit code 3 = success but reboot required
