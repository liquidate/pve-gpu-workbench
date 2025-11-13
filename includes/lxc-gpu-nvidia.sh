#!/usr/bin/env bash
# NVIDIA GPU passthrough configuration for LXC containers
# Source this file to configure NVIDIA GPU access in containers
#
# CRITICAL LEARNINGS (2025-11-13):
# ================================
# 1. CORRECT cgroup device numbers are ESSENTIAL for GPU detection:
#    - c 195:* rwm  = nvidia devices (nvidia0, nvidiactl, nvidia-modeset)  
#    - c 511:* rwm  = nvidia-uvm (CRITICAL for CUDA/compute operations)
#    - c 236:* rwm  = nvidia-caps (CRITICAL for GPU capabilities)
#
# 2. AppArmor workaround required for Proxmox 9:
#    - lxc.apparmor.profile: unconfined
#    - Bind mount /dev/null to apparmor/parameters/enabled
#    - Reference: https://blog.ktz.me/apparmors-awkward-aftermath-atop-proxmox-9/
#
# 3. All NVIDIA devices must be passed through:
#    - /dev/nvidia* (GPU devices)
#    - /dev/nvidia-uvm* (Unified memory)
#    - /dev/nvidia-caps/* (GPU capabilities)
#    - /dev/dri/* (Direct rendering)

# Configure NVIDIA GPU passthrough for LXC container
# Usage: configure_nvidia_gpu_passthrough <container_id>
configure_nvidia_gpu_passthrough() {
    local container_id="$1"
    local config_file="/etc/pve/lxc/${container_id}.conf"
    
    if [ ! -f "$config_file" ]; then
        echo -e "${RED}✗ Container config not found: $config_file${NC}"
        return 1
    fi
    
    # Get all NVIDIA device numbers
    local nvidia_devices=$(ls /dev/nvidia* 2>/dev/null | grep -v nvidia-caps)
    
    # Add GPU passthrough configuration
    cat >> "$config_file" << 'EOF'

# NVIDIA GPU passthrough with CORRECT device numbers
# c 195 = nvidia devices (nvidia0, nvidiactl, nvidia-modeset)
# c 511 = nvidia-uvm (CRITICAL for CUDA/compute)
# c 236 = nvidia-caps (CRITICAL for GPU features)
lxc.cgroup2.devices.allow: c 195:* rwm
lxc.cgroup2.devices.allow: c 511:* rwm
lxc.cgroup2.devices.allow: c 236:* rwm

# AppArmor workaround for Proxmox 9 (prevents Docker issues)
# See: https://blog.ktz.me/apparmors-awkward-aftermath-atop-proxmox-9/
lxc.apparmor.profile: unconfined
lxc.mount.entry: /dev/null sys/module/apparmor/parameters/enabled none bind 0 0
EOF
    
    # Mount all NVIDIA device nodes
    for dev in $nvidia_devices; do
        echo "lxc.mount.entry: ${dev} $(echo ${dev} | cut -c2-) none bind,optional,create=file 0 0" >> "$config_file"
    done
    
    # Add nvidia-uvm if it exists (CRITICAL for CUDA compute)
    if [ -e /dev/nvidia-uvm ]; then
        echo "lxc.mount.entry: /dev/nvidia-uvm dev/nvidia-uvm none bind,optional,create=file 0 0" >> "$config_file"
    fi
    
    # Add nvidia-uvm-tools if it exists
    if [ -e /dev/nvidia-uvm-tools ]; then
        echo "lxc.mount.entry: /dev/nvidia-uvm-tools dev/nvidia-uvm-tools none bind,optional,create=file 0 0" >> "$config_file"
    fi
    
    # Add DRI devices (needed for some GPU operations)
    if [ -e /dev/dri/card1 ]; then
        echo "lxc.mount.entry: /dev/dri/card1 dev/dri/card1 none bind,optional,create=file 0 0" >> "$config_file"
    fi
    if [ -e /dev/dri/renderD128 ]; then
        echo "lxc.mount.entry: /dev/dri/renderD128 dev/dri/renderD128 none bind,optional,create=file 0 0" >> "$config_file"
    fi
    
    # Add nvidia-caps directory if it exists (CRITICAL for GPU features)
    if [ -d /dev/nvidia-caps ]; then
        echo "lxc.mount.entry: /dev/nvidia-caps dev/nvidia-caps none bind,optional,create=dir 0 0" >> "$config_file"
    fi
}

# Install CUDA toolkit in container
# Usage: install_cuda_toolkit <container_id> [<cuda_version>]
install_cuda_toolkit() {
    local container_id="$1"
    local cuda_version="${2:-12.6}"
    
    pct exec $container_id -- bash -c "
        # Add NVIDIA CUDA repository
        wget -q https://developer.download.nvidia.com/compute/cuda/repos/ubuntu2404/x86_64/cuda-keyring_1.1-1_all.deb
        dpkg -i cuda-keyring_1.1-1_all.deb
        rm cuda-keyring_1.1-1_all.deb
        
        # Update and install CUDA toolkit
        apt-get update -qq
        apt-get install -y cuda-toolkit-${cuda_version/./-}
    " >> "$LOG_FILE" 2>&1
    
    if [ $? -ne 0 ]; then
        echo -e "${YELLOW}⚠ CUDA toolkit installation had issues${NC}"
        echo -e "${DIM}Check log: $LOG_FILE${NC}"
    fi
}

# Verify GPU is accessible in container
# Usage: verify_gpu_access <container_id>
verify_gpu_access() {
    local container_id="$1"
    
    # Check if nvidia-smi works
    if pct exec $container_id -- nvidia-smi >> "$LOG_FILE" 2>&1; then
        local gpu_name=$(pct exec $container_id -- nvidia-smi --query-gpu=name --format=csv,noheader 2>/dev/null | head -1)
        echo -e "${GREEN}✓ GPU accessible: $gpu_name${NC}"
        return 0
    else
        echo -e "${YELLOW}⚠ GPU not accessible via nvidia-smi${NC}"
        return 1
    fi
}

