# GPU Detection and Verification Improvements

## Summary of Changes

This update makes the Proxmox setup scripts smarter and more robust by adding proper GPU detection and verification throughout the installation process.

## Key Improvements

### 1. **Proper GPU Verification** (No More Silent Failures)
   - Scripts now **actually verify** that GPUs are working instead of ignoring failures
   - Clear error messages with troubleshooting steps when verification fails
   - Script 031 will fail fast if GPU isn't accessible, preventing wasted time

### 2. **Automatic GPU Type Detection**
   - Script 031 now auto-detects if you have AMD or NVIDIA GPUs
   - Only prompts for GPU type selection if you have both types
   - Shows clear error if no compatible GPUs are found

### 3. **Smart Script Execution**
   - AMD-specific scripts (003, 005, 030) check for AMD GPUs before running
   - NVIDIA-specific scripts (004, 006) check for NVIDIA GPUs before running
   - Scripts ask for confirmation before proceeding if wrong GPU type detected

### 4. **Shared GPU Detection Utility**
   - New `/includes/gpu-detect.sh` provides reusable GPU detection functions
   - Consistent GPU detection across all scripts
   - Easy to extend for future improvements

## Files Modified

### New Files
- `includes/gpu-detect.sh` - Shared GPU detection library

### Modified Files
1. `host/003 - install-amd-drivers.sh` - Added GPU type check
2. `host/004 - install-nvidia-drivers.sh` - Added GPU type check
3. `host/005 - verify-amd-drivers.sh` - Complete rewrite with proper verification
4. `host/006 - verify-nvidia-drivers.sh` - Complete rewrite with proper verification
5. `host/031 - create-gpu-lxc.sh` - Auto-detect GPU type, improved flow
6. `lxc/install-docker-and-amd-drivers-in-lxc.sh` - Proper GPU verification with clear errors
7. `lxc/install-docker-and-nvidia-drivers-in-lxc.sh` - Better non-interactive mode handling

## What Fixed Option 031

### The Original Problem
Script 031 was failing after ROCm installation because:
1. Verification commands (`rocminfo`, `rocm-smi`) were returning non-zero exit codes
2. The script had `set -e` which caused it to exit on any command failure
3. We were ignoring failures instead of properly checking GPU accessibility

### The Solution
1. **Proper verification** - Scripts now check specific conditions:
   - Is `/dev/kfd` accessible?
   - Is `/dev/dri/card0` and `/dev/dri/renderD128` mounted?
   - Does `rocminfo` detect GPU agents?
   - Can `rocm-smi` read GPU info?

2. **Clear error messages** - When verification fails, you get:
   - Specific error about what's wrong
   - Troubleshooting steps
   - Commands to check and fix the issue

3. **Fail fast** - If GPU isn't working, script stops immediately with helpful feedback

## Testing Your Setup

### Step 1: Verify GPU Detection
```bash
cd /root/proxmox-setup-scripts
source includes/colors.sh
source includes/gpu-detect.sh
print_gpu_summary
```

Expected output (for your system):
```
✓ AMD GPU(s) detected
  ⚠ AMD drivers NOT installed
```

### Step 2: Install AMD Drivers (if needed)
```bash
./guided-install.sh
# Choose option: 003
```

Script will:
- Detect your AMD GPU automatically
- Install ROCm drivers
- Ask you to reboot

### Step 3: Verify AMD Drivers
```bash
./guided-install.sh
# Choose option: 005
```

This will thoroughly test:
- GPU detection
- Driver loading
- `/dev/kfd` accessibility
- `rocminfo` agent detection
- `rocm-smi` functionality

**Important**: This must pass before creating LXC containers!

### Step 4: Create LXC Container
```bash
./guided-install.sh
# Choose option: 031
```

Script will:
- Auto-detect AMD GPU
- Show available PCI addresses
- Create container with proper GPU passthrough
- Install Docker and ROCm in container
- **Verify GPU works inside container**

## Troubleshooting

### If GPU Verification Fails

#### AMD GPU Issues

**Problem**: `rocminfo` doesn't detect GPU agents
```bash
# Check if devices are accessible
ls -la /dev/kfd /dev/dri/

# Check if user is in correct groups
groups root

# Add to groups if needed
usermod -a -G render,video root

# Check kernel module
lsmod | grep amdgpu
```

**Problem**: `/dev/kfd` missing
```bash
# Check if ROCm drivers are installed
apt list --installed | grep rocm

# Reinstall if needed
./guided-install.sh  # Choose 003
```

#### LXC Container Issues

**Problem**: GPU devices not visible in container
```bash
# On host, check container config
cat /etc/pve/lxc/100.conf | grep -A 20 "GPU Passthrough"

# Verify devices exist on host
ls -la /dev/dri/by-path/
ls -la /dev/kfd

# Restart container
pct restart 100

# Check inside container
pct exec 100 -- ls -la /dev/kfd /dev/dri/
```

**Problem**: `rocminfo` fails in container
```bash
# Enter container
pct enter 100

# Check group membership
groups root

# Check environment variables
echo $HSA_OVERRIDE_GFX_VERSION

# Try with explicit override (for Strix Halo/gfx1150)
HSA_OVERRIDE_GFX_VERSION=11.5.1 rocminfo
```

## Benefits

1. **Time Savings** - Catch GPU issues early before wasting time on full installation
2. **Clear Feedback** - Know exactly what's wrong and how to fix it
3. **No Guessing** - Auto-detection removes user error
4. **Better UX** - Proper warnings and confirmations at every step
5. **Maintainable** - Shared utility makes updates easier

## Your System Configuration

Based on script 000 output:
- **GPU**: AMD Strix Halo (Radeon 8050S/8060S)
- **PCI Address**: `0000:c3:00.0`
- **Current Mapping**: card1 / renderD128
- **ROCm Support**: `/dev/kfd` detected

**Next Steps for You**:
1. Run script 003 to install AMD drivers
2. Reboot
3. Run script 005 to verify drivers
4. Run script 031 to create LXC container

The new verification in script 005 will ensure your GPU is fully working before you create any containers!

