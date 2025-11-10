#!/usr/bin/env bash

# GPU Detection Utility
# Source this file to detect GPU types and get GPU information

# Detect AMD GPUs
detect_amd_gpus() {
    if lspci -nn | grep -i "VGA\|3D\|Display" | grep -qi amd; then
        return 0
    else
        return 1
    fi
}

# Detect NVIDIA GPUs
detect_nvidia_gpus() {
    if lspci -nn | grep -i "VGA\|3D\|Display" | grep -qi nvidia; then
        return 0
    else
        return 1
    fi
}

# Get list of AMD GPU PCI addresses
get_amd_gpu_pci_addresses() {
    lspci -nn -D | grep -i "VGA\|3D\|Display" | grep -i amd | awk '{print $1}'
}

# Get list of NVIDIA GPU PCI addresses
get_nvidia_gpu_pci_addresses() {
    lspci -nn -D | grep -i "VGA\|3D\|Display" | grep -i nvidia | awk '{print $1}'
}

# Check if AMD drivers are installed on host
check_amd_drivers_installed() {
    if [ -e /dev/kfd ] && lsmod | grep -q amdgpu; then
        return 0
    else
        return 1
    fi
}

# Check if NVIDIA drivers are installed on host
check_nvidia_drivers_installed() {
    if [ -e /dev/nvidia0 ] && lsmod | grep -q nvidia; then
        return 0
    else
        return 1
    fi
}

# Print GPU summary
print_gpu_summary() {
    local has_amd=false
    local has_nvidia=false
    
    if detect_amd_gpus; then
        has_amd=true
        echo -e "${GREEN}✓ AMD GPU(s) detected${NC}"
        if check_amd_drivers_installed; then
            echo -e "${GREEN}  ✓ AMD drivers installed${NC}"
        else
            echo -e "${YELLOW}  ⚠ AMD drivers NOT installed${NC}"
        fi
    fi
    
    if detect_nvidia_gpus; then
        has_nvidia=true
        echo -e "${GREEN}✓ NVIDIA GPU(s) detected${NC}"
        if check_nvidia_drivers_installed; then
            echo -e "${GREEN}  ✓ NVIDIA drivers installed${NC}"
        else
            echo -e "${YELLOW}  ⚠ NVIDIA drivers NOT installed${NC}"
        fi
    fi
    
    if [ "$has_amd" = false ] && [ "$has_nvidia" = false ]; then
        echo -e "${RED}✗ No AMD or NVIDIA GPUs detected${NC}"
        return 1
    fi
    
    return 0
}

