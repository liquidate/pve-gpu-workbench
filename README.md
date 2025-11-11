# Proxmox GPU Setup Scripts

**Professional, automated GPU setup for Proxmox VE with LXC container support.**

A polished, production-ready tool for configuring AMD GPUs on Proxmox and creating GPU-enabled LXC containers. Built with a focus on user experience, safety, and comprehensive verification.

## Quick Start (Fresh Proxmox Install)

Run this **one command** on your fresh Proxmox VE installation:

```bash
bash -c "$(curl -fsSL https://raw.githubusercontent.com/liquidate/proxmox-setup-scripts/feature/gpu-detection-improvements/bootstrap.sh)"
```

This will:
1. Clone the repository to `/root/proxmox-setup-scripts`
2. Create system-wide commands: `pve-gpu` and `pve-gpu-update`
3. Launch the guided installer automatically

Then just type: **`setup`** (or press Enter) and follow the prompts!

## System-Wide Commands

After installation, these commands are available from anywhere:

- **`pve-gpu`** - Launch the guided installer
- **`pve-gpu-update`** - Update scripts from GitHub

## What This Tool Does

### GPU Setup (Host)

- **`strix-igpu`** - Configure Strix Halo iGPU VRAM (1-96GB, user-selectable)
- **`amd-drivers`** - Install AMD ROCm drivers (6.0-7.1, dynamic version selection)
- **`amd-upgrade`** - Upgrade ROCm to a newer version
- **`amd-verify`** - Comprehensive GPU verification (20+ checks, detects reboot needs)
- **`gpu-udev`** - Set up udev rules for GPU device permissions
- **`power`** - Toggle GPU power management (powertop + AutoASPM)

### LXC Creation

- **`ollama-amd`** - Create GPU-enabled Ollama LXC container
  - **Quick Mode**: 2 prompts (mode selection, password) - uses recommended defaults
  - **Advanced Mode**: Full customization (ID, IP, storage, resources)
  - Clean no-scrolling progress indicators: `[Step X/9] Action...`
  - Automatic GPU verification (12 checks) after creation
  - Includes built-in commands: `update` and `gpu-verify`
  - GPU status displayed in completion message

### Special Commands

- **`setup`** - Run all GPU setup scripts in order (with auto-reboot detection)
- **`update`** - Update scripts from GitHub
- **`info`** - Comprehensive system dashboard
- **`quit`** - Exit the installer

### Tab Completion

Press **TAB** at any prompt to auto-complete command names or see available options.

## The Guided Installer

```
╔══════════════════════════════════════╗
║  Proxmox Setup - Guided Installer    ║
╚══════════════════════════════════════╝

═══ GPU SETUP ═══

  strix-igpu  - Configure Strix Halo iGPU VRAM allocation    [96GB VRAM]
  amd-drivers - Install AMD ROCm GPU drivers                 [INSTALLED]
  gpu-udev    - Setup udev GPU device permissions            [CONFIGURED]

═══ VERIFICATION ═══

  amd-verify  - Comprehensive AMD GPU setup verification     [PASSED]

═══ OPTIONAL ═══

  power       - Toggle power management                      [ENABLED]
  amd-upgrade - Upgrade AMD ROCm to a different version      [UP TO DATE]

═══ LXC CONTAINERS ═══

  ollama-amd  - Create Ollama LXC (AMD GPU)

Commands:
  setup           - Run all GPU Setup scripts (reboot + verify after)
  <command>       - Run specific script (e.g., strix-igpu, ollama-amd)
  [u]pdate        - Update scripts from GitHub
  [i]nfo          - Show system information
  [q]uit          - Exit

Tip: Press TAB for command completion

Enter your choice [setup]: _
```

## Key Features

### 🎯 Professional UX

- **Tab completion** for all commands
- **Clean, no-scrolling installation** (both Quick & Advanced modes)
- **Color-coded status indicators** (✓ Passed / ⚠ Warning / ✗ Failed)
- **Right-aligned status flags** in menu
- **Progress indicators**: `[Step X/Y] Action...` with ✓ checkmarks
- **Automatic screen clearing** for clean output

### 🔍 Comprehensive Verification

**Host Verification (`amd-verify`):**
- Hardware detection
- Kernel module status
- `/dev/kfd` and DRI devices
- VRAM allocation (iGPU)
- ROCm installation
- User permissions (render/video groups)
- udev rules
- Environment variables
- Functional tests (rocminfo, rocm-smi)
- **Automatic reboot detection**

**LXC Verification (`gpu-verify`):**
- GPU device files (`/dev/dri/*`, `/dev/kfd`)
- Device permissions (read/write access)
- ROCm tools (rocm-smi, rocminfo)
- GPU detection and agents
- Ollama service status
- **Runs automatically after LXC creation**
- **Results displayed in completion message**

### 📊 Info Dashboard

Type `info` to see a comprehensive system overview:

- Script version (git branch, commit, date)
- Proxmox VE & kernel version
- **GPU health status**: ✓ Working / ⚠ Reboot needed / ✗ Not configured
- ROCm/CUDA version
- iGPU VRAM allocation
- All storage pools with usage percentages
- Network bridges and their status
- LXC containers with IPs and running status

### 🧹 Smart Maintenance

- **Auto log cleanup** (keeps last 5 logs)
- **Idempotent scripts** (safe to re-run multiple times)
- **Just-in-time tool installation** (only installs when needed)
- **Minimal host footprint** (no unnecessary packages)
- **Dynamic version fetching** (ROCm versions from AMD repo)

## Inside LXC Containers

After creating an Ollama LXC, these commands are available inside the container:

```bash
ssh root@<container-ip>

# Update Ollama to latest version (checks version first)
update

# Verify GPU is working (12 comprehensive checks)
gpu-verify

# Monitor GPU usage in real-time
rocm-smi --showuse --showmemuse
watch -n 0.5 rocm-smi --showuse --showmemuse
radeontop  # Interactive, press 'q' to quit
```

## Typical Workflows

### First Time Setup (Fresh Install)

1. Run the one-liner bootstrap command
2. At the prompt, type: `setup` (or press Enter)
3. Scripts run in order, prompting before each one
4. Reboot when prompted
5. After reboot, run: `pve-gpu` → `amd-verify` to confirm
6. Create your first LXC: `pve-gpu` → `ollama-amd`

### Creating Additional LXCs

```bash
pve-gpu
ollama-amd  # Quick mode: just set password, everything else is automatic
```

### Upgrading ROCm Drivers

```bash
pve-gpu
amd-upgrade  # Shows current version, fetches available versions from AMD
```

### Changing iGPU VRAM Allocation

```bash
pve-gpu
strix-igpu  # Shows current allocation, prompts for new value (1-96GB)
```

### Checking System Status

```bash
pve-gpu
info  # Dashboard view: GPU status, storage, network, LXCs
```

### Updating the Scripts

```bash
pve-gpu-update  # From anywhere on your system
```

## Supported Hardware

### AMD GPUs
- AMD Radeon RX/Pro series
- AMD Radeon Pro WX series
- **AMD Strix Halo APU** (with configurable iGPU VRAM: 1-96GB)

### ROCm Versions
- Dynamically fetched from AMD's repository
- Currently supports ROCm 6.0 - 7.1
- Automatic version detection and update availability
- In-menu status: "UP TO DATE" or "X.Y AVAILABLE"

## What Gets Installed

### On the Host (Proxmox)
- AMD ROCm drivers and libraries
- GPU monitoring tools (rocm-smi, radeontop, nvtop)
- GPU udev rules for container passthrough
- Kernel parameters for iGPU VRAM (Strix Halo only)
- Optional: Power management tools (powertop, AutoASPM)

### In LXC Containers (Ollama)
- Ubuntu 24.04 LTS base
- Ollama (latest version)
- ROCm utilities (rocm-smi, rocminfo, radeontop)
- GPU passthrough configuration
- Systemd service for Ollama
- Pre-configured for network access (0.0.0.0:11434)
- Built-in `update` and `gpu-verify` commands

## Requirements

- **Proxmox VE 8.x** (tested on PVE 8.2+)
- **AMD GPU or APU**
- **Root access**
- **Internet connection** (for package downloads)
- **Fresh install recommended** (or existing system with no conflicting GPU setup)

## Advanced Usage

### Manual Script Execution

You can run individual scripts directly:

```bash
cd /root/proxmox-setup-scripts

# Configure iGPU VRAM
./host/strix-igpu.sh

# Install AMD drivers
./host/amd-drivers.sh

# Verify setup
./host/amd-verify.sh

# Create Ollama LXC
./host/ollama-amd.sh
```

### LXC Container Management

```bash
# List all containers
pct list

# Start/Stop container
pct start 100
pct stop 100

# Execute command in container
pct exec 100 -- gpu-verify

# Enter container console
pct enter 100
```

## Troubleshooting

### GPU Not Detected

```bash
# Check GPU hardware
lspci | grep -i amd

# Verify kernel module
lsmod | grep amdgpu

# Run comprehensive verification
pve-gpu → amd-verify
```

### Verification Fails

The `amd-verify` script provides detailed diagnostics:
- Shows which specific checks failed
- Indicates if a reboot is needed
- Provides troubleshooting suggestions

### GPU Not Working in LXC

```bash
# From host, check container GPU access
pct exec 100 -- ls -la /dev/dri/ /dev/kfd

# From inside container, run verification
ssh root@<container-ip>
gpu-verify

# Check LXC config
cat /etc/pve/lxc/100.conf
```

### ROCm Installation Issues

- Try a different ROCm version: `pve-gpu` → `amd-upgrade`
- Check available versions are fetching correctly
- Verify internet connectivity to AMD repositories
- Check installation log: `/tmp/ollama-lxc-install-*.log`

### Reboot Required

Some changes require a reboot:
- Kernel parameter changes (iGPU VRAM)
- ROCm driver installation
- udev rule updates (sometimes)

The `amd-verify` script will detect when a reboot is needed and display: **"REBOOT REQUIRED"**

## What We Built 🎉

This tool evolved from a collection of numbered scripts into a polished, professional setup tool. Here are the highlights:

### UI/UX Improvements
✅ Menu alignment and formatting (right-aligned status flags)  
✅ Shortened descriptions to avoid ellipses  
✅ Clean no-scrolling installation (both Quick & Advanced modes)  
✅ Tab completion for all commands  
✅ Fixed GPU description lengths  
✅ Fixed storage pool percentages  
✅ Fixed LXC container color rendering  
✅ Fixed Proxmox version display  

### Features Added
✅ Command-based navigation (replaced numbered scripts)  
✅ Explicit execution order for scripts  
✅ Dynamic ROCm version fetching  
✅ `amd-upgrade` command for ROCm updates  
✅ User-configurable iGPU VRAM allocation (1-96GB)  
✅ Comprehensive info dashboard with GPU health  
✅ GPU verification in LXCs (`gpu-verify` command)  
✅ Automatic GPU validation after LXC creation  
✅ Beautiful GPU status in completion message  
✅ LXC `update` command (checks version first)  
✅ Automatic log cleanup (keeps last 5)  
✅ One-liner bootstrap installation  
✅ System-wide commands (`pve-gpu`, `pve-gpu-update`)  

### Verification & Safety
✅ Enhanced `amd-verify` (20+ checks, reboot detection)  
✅ LXC `gpu-verify` (12 checks: device files, permissions, ROCm)  
✅ Idempotent scripts (safe to re-run)  
✅ Just-in-time tool installation  
✅ Minimal host footprint  

### The Journey
From a collection of numbered scripts to a polished, professional, production-ready GPU setup tool for Proxmox. Every detail was refined for the best possible user experience.

## Updating

### System-Wide Update Command

```bash
pve-gpu-update  # From anywhere on your system
```

### Manual Update

```bash
cd /root/proxmox-setup-scripts
git pull
```

### Re-run Bootstrap

```bash
bash -c "$(curl -fsSL https://raw.githubusercontent.com/liquidate/proxmox-setup-scripts/feature/gpu-detection-improvements/bootstrap.sh)"
```

## Contributing

Contributions welcome! Please:
1. Test on a fresh Proxmox VE installation
2. Follow the existing code style
3. Update documentation for any new features
4. Ensure scripts remain idempotent

## Support

- **GitHub**: https://github.com/liquidate/proxmox-setup-scripts
- **Branch**: feature/gpu-detection-improvements
- **Issues**: Open an issue on GitHub

## License

MIT License - See LICENSE file for details

## Acknowledgments

- Proxmox VE team for an amazing virtualization platform
- AMD ROCm team for GPU compute support
- Proxmox Community Scripts project for inspiration
- The Proxmox + AMD GPU community

---

**Built with care for the Proxmox + AMD GPU community.** 🚀

Enjoy your GPU-accelerated containers!
