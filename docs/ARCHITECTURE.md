# Architecture Documentation

## Overview

This project uses a modular architecture with shared libraries to eliminate code duplication and ensure consistency across all installation scripts.

## Directory Structure

```
proxmox-setup-scripts/
├── includes/              # Shared library modules
│   ├── colors.sh         # Color definitions and formatting
│   ├── gpu-detect.sh     # GPU hardware detection
│   ├── progress.sh       # Progress tracking and spinners
│   ├── logging.sh        # Log file management
│   ├── lxc-common.sh     # LXC container operations
│   ├── lxc-gpu-nvidia.sh # NVIDIA GPU passthrough
│   └── lxc-gpu-amd.sh    # AMD GPU passthrough (coming soon)
│
├── host/                  # Host-level installation scripts
│   ├── nvidia-drivers.sh # NVIDIA driver installation
│   ├── nvidia-upgrade.sh # NVIDIA driver upgrade
│   ├── amd-drivers.sh    # AMD ROCm installation
│   ├── amd-upgrade.sh    # AMD ROCm upgrade
│   ├── ollama-nvidia.sh  # Ollama LXC with NVIDIA GPU
│   ├── ollama-amd.sh     # Ollama LXC with AMD GPU
│   └── openwebui.sh      # Open WebUI LXC
│
└── templates/             # Templates for new containers
    └── lxc-nvidia-template.sh  # NVIDIA GPU LXC template
```

## Shared Libraries

### `includes/progress.sh`

Provides consistent progress tracking across all scripts:

- `show_progress(step, total, message)` - Display step counter
- `complete_progress(message)` - Show completion checkmark
- `start_spinner(message)` - Animated spinner for long operations
- `stop_spinner()` - Stop spinner and cleanup

**Usage:**
```bash
source "${SCRIPT_DIR}/../includes/progress.sh"

TOTAL_STEPS=5
show_progress 1 $TOTAL_STEPS "Installing packages"
# ... do work ...
complete_progress "Packages installed"
```

### `includes/logging.sh`

Centralized logging with timestamped log files:

- `setup_logging(name, description)` - Create timestamped log file
- `show_log_info()` - Display log location and tail command
- `show_log_summary()` - Show final log location

**Usage:**
```bash
source "${SCRIPT_DIR}/../includes/logging.sh"

setup_logging "my-app" "My Application Installation"
show_log_info

# All output can go to: >> "$LOG_FILE" 2>&1
apt-get install something >> "$LOG_FILE" 2>&1
```

### `includes/lxc-common.sh`

Common LXC container operations:

- `ensure_ubuntu_template()` - Download Ubuntu template if needed
- `create_lxc_container(...)` - Create container with standard config
- `start_lxc_container(id)` - Start container with retry logic
- `set_root_password(id, password)` - Set root password
- `configure_ssh(id)` - Enable root SSH access
- `show_container_info(...)` - Display access information

**Usage:**
```bash
source "${SCRIPT_DIR}/../includes/lxc-common.sh"

create_lxc_container "$CTID" "$HOSTNAME" "$IP" "$MEMORY" "$CORES" "$DISK" "$STORAGE"
start_lxc_container "$CTID"
```

### `includes/lxc-gpu-nvidia.sh`

NVIDIA GPU passthrough with all critical fixes:

- `configure_nvidia_gpu_passthrough(id)` - Apply GPU config to container
- `install_cuda_toolkit(id, version)` - Install CUDA in container
- `verify_gpu_access(id)` - Test GPU accessibility

**Critical Knowledge Embedded:**
- Correct cgroup device numbers (195, 511, 236)
- AppArmor workaround for Proxmox 9
- All required device mounts
- DRI and nvidia-caps handling

**Usage:**
```bash
source "${SCRIPT_DIR}/../includes/lxc-gpu-nvidia.sh"

configure_nvidia_gpu_passthrough "$CONTAINER_ID"
verify_gpu_access "$CONTAINER_ID"
```

## Creating New LXC Containers

### Quick Start

1. Copy the template:
```bash
cp templates/lxc-nvidia-template.sh host/my-new-app.sh
```

2. Edit configuration section:
```bash
APP_NAME="My GPU Application"
APP_PORT=8080
CONTAINER_ID=200
HOSTNAME="my-app"
IP_ADDRESS="192.168.111.200"
```

3. Add your app-specific installation in Step 5:
```bash
show_progress 5 $TOTAL_STEPS "Installing ${APP_NAME}"
pct exec $CONTAINER_ID -- bash -c "
    apt-get update -qq
    apt-get install -y your-packages
    # Your setup commands
" >> "$LOG_FILE" 2>&1
complete_progress "${APP_NAME} installed"
```

4. Done! You have a GPU-enabled LXC container script.

### Benefits

**Before (monolithic scripts):**
- 500-700 lines per script
- Duplicate progress tracking (~50 lines × 7 = 350 lines)
- Duplicate GPU config (~80 lines × 3 = 240 lines)
- Inconsistent UX
- Bug fixes need updating multiple files

**After (modular architecture):**
- 150-200 lines per script
- Shared progress tracking (DRY)
- Centralized GPU knowledge
- Consistent UX everywhere
- Bug fixes apply automatically

**Time to create new container:**
- Before: ~1 day (copy, modify, debug, test)
- After: ~1 hour (copy template, customize app section)

## GPU Passthrough Critical Knowledge

### NVIDIA GPU Requirements

**Correct cgroup device permissions** (discovered 2025-11-13):

```bash
lxc.cgroup2.devices.allow: c 195:* rwm  # nvidia devices
lxc.cgroup2.devices.allow: c 511:* rwm  # nvidia-uvm (CRITICAL!)
lxc.cgroup2.devices.allow: c 236:* rwm  # nvidia-caps (CRITICAL!)
```

**Why these are critical:**
- `c 195` - Basic NVIDIA device access (nvidia0, nvidiactl)
- `c 511` - NVIDIA Unified Memory (required for CUDA compute)
- `c 236` - NVIDIA capabilities (required for GPU features)

**AppArmor workaround** for Proxmox 9:

```bash
lxc.apparmor.profile: unconfined
lxc.mount.entry: /dev/null sys/module/apparmor/parameters/enabled none bind 0 0
```

Reference: https://blog.ktz.me/apparmors-awkward-aftermath-atop-proxmox-9/

### Common Issues

**GPU not detected (total vram=0 B):**
- ✅ Solution: Use correct cgroup numbers (511, 236)
- ❌ Wrong: Using 234, 237 (old patterns)

**Docker fails in LXC:**
- ✅ Solution: Apply AppArmor workaround
- Reference: ktz.me blog post

**Ollama installs CPU-only version:**
- ✅ Solution: Set LD_LIBRARY_PATH during install
- Export paths before running `curl -fsSL https://ollama.com/install.sh | sh`

## Development Workflow

### Adding New Features

1. **Identify common patterns** across multiple scripts
2. **Extract to shared library** in `includes/`
3. **Update existing scripts** to use shared code
4. **Test thoroughly** before committing
5. **Document** in this file

### Testing

Always test refactored scripts ensure:
- ✅ Same behavior as before
- ✅ Clean error handling
- ✅ Logs are detailed
- ✅ Progress tracking works
- ✅ GPU detection succeeds

### Committing Changes

Use conventional commits:
- `feat:` - New features or shared libraries
- `fix:` - Bug fixes
- `refactor:` - Code restructuring without behavior change
- `docs:` - Documentation updates

## Future Enhancements

### Planned Shared Libraries

- `lxc-gpu-amd.sh` - AMD ROCm GPU passthrough
- `lxc-network.sh` - Network configuration helpers
- `lxc-docker.sh` - Docker in LXC setup
- `app-install.sh` - Common app installation patterns

### Planned Container Scripts

- Stable Diffusion WebUI
- ComfyUI
- Automatic1111
- Text Generation WebUI
- Jupyter with GPU support
- Code Server with GPU
- VS Code Server with GPU

## References

- [Ollama LXC GPU Reddit Thread](https://www.reddit.com/r/Proxmox/comments/1ij523z/)
- [AppArmor Proxmox 9 Issues](https://blog.ktz.me/apparmors-awkward-aftermath-atop-proxmox-9/)
- [NVIDIA Device Numbers](https://github.com/NVIDIA/nvidia-container-toolkit/issues)
- [LXC cgroup2 Documentation](https://linuxcontainers.org/lxc/manpages/man5/lxc.container.conf.5.html)

## Contributing

When adding new shared libraries:
1. Keep functions focused and single-purpose
2. Add comprehensive comments
3. Include usage examples
4. Update this documentation
5. Test with multiple scripts before committing

