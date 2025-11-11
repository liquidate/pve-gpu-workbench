# Proxmox GPU Setup Scripts

Automated GPU passthrough setup for Proxmox VE with LXC container support.

## Quick Start

Run this on your Proxmox VE host:

```bash
bash -c "$(curl -fsSL https://raw.githubusercontent.com/liquidate/proxmox-setup-scripts/feature/gpu-detection-improvements/bootstrap.sh)"
```

This will clone the repository, create system-wide commands (`pve-gpu`, `pve-gpu-update`), and launch the guided installer.

## Usage

### System-Wide Commands

- **`pve-gpu`** - Launch the guided installer
- **`pve-gpu-update`** - Update scripts from GitHub

### Guided Installer

The main menu provides an interactive interface with real-time status checks:

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
  setup           - Run all GPU Setup scripts
  <command>       - Run specific script (e.g., strix-igpu, ollama-amd)
  [u]pdate        - Update scripts from GitHub
  [i]nfo          - Show system information
  [q]uit          - Exit

Enter your choice [setup]: _
```

Press **TAB** for command completion.

## Available Commands

### GPU Setup (Host)

- **`strix-igpu`** - Configure iGPU VRAM allocation (1-96GB, Strix Halo only)
- **`amd-drivers`** - Install AMD ROCm drivers (versions 6.0-7.1)
- **`amd-upgrade`** - Upgrade to a different ROCm version
- **`amd-verify`** - Verify GPU setup (20+ checks, detects reboot requirements)
- **`gpu-udev`** - Configure udev rules for GPU device permissions
- **`power`** - Toggle power management (powertop + AutoASPM)

### LXC Containers

- **`ollama-amd`** - Create GPU-enabled Ollama LXC
  - Quick Mode: Uses defaults, minimal prompts
  - Advanced Mode: Full customization
  - Includes automatic GPU verification

### Special Commands

- **`setup`** - Run all GPU setup scripts in order
- **`update`** - Update scripts from GitHub
- **`info`** - Show system dashboard (GPU status, storage, network, containers)
- **`quit`** - Exit

## Inside LXC Containers

Commands available inside created containers:

```bash
# Update Ollama to latest version
update

# Verify GPU is working
gpu-verify

# Monitor GPU usage
rocm-smi --showuse --showmemuse
watch -n 0.5 rocm-smi --showuse --showmemuse
radeontop
```

## Features

- Interactive menu with real-time status indicators
- Tab completion for commands
- Comprehensive verification (host and LXC)
- Dynamic ROCm version fetching from AMD repository
- Automatic reboot detection
- Clean, no-scrolling installation progress
- Idempotent scripts (safe to re-run)
- Just-in-time tool installation (minimal host footprint)
- System information dashboard

## Supported Hardware

### AMD GPUs
- AMD Radeon RX/Pro series
- AMD Radeon Pro WX series
- AMD Strix Halo APU (with configurable iGPU VRAM)

### ROCm Versions
- Dynamically fetched from AMD's repository
- Currently supports ROCm 6.0 - 7.1

## Requirements

- Proxmox VE 8.x
- AMD GPU or APU
- Root access
- Internet connection

## What Gets Installed

### Host
- AMD ROCm drivers and libraries
- GPU monitoring tools (rocm-smi, radeontop, nvtop)
- GPU udev rules for container passthrough
- Kernel parameters for iGPU VRAM (Strix Halo)

### LXC Containers
- Ubuntu 24.04 LTS base
- Ollama (latest version)
- ROCm utilities (rocm-smi, rocminfo, radeontop)
- GPU passthrough configuration
- Pre-configured for network access (0.0.0.0:11434)

## Typical Workflow

### First Time Setup
1. Run bootstrap command
2. Type: `setup` (or press Enter)
3. Follow prompts, reboot when asked
4. After reboot: `pve-gpu` → `amd-verify`
5. Create LXC: `pve-gpu` → `ollama-amd`

### Creating Additional LXCs
```bash
pve-gpu
ollama-amd  # Quick mode by default
```

### Upgrading ROCm
```bash
pve-gpu
amd-upgrade  # Shows current and available versions
```

### Changing iGPU VRAM
```bash
pve-gpu
strix-igpu  # Interactive, shows current allocation
```

## Troubleshooting

### GPU Not Detected
```bash
pve-gpu
amd-verify  # Provides detailed diagnostics
```

### GPU Not Working in LXC
```bash
# From host
pct exec <container-id> -- ls -la /dev/dri/ /dev/kfd

# From inside container
ssh root@<container-ip>
gpu-verify
```

### Reboot Required
Some changes require a reboot:
- Kernel parameter changes (iGPU VRAM)
- ROCm driver installation

The `amd-verify` script will detect when a reboot is needed.

## Manual Installation

If you prefer not to use the one-liner:

```bash
apt update && apt install -y git
git clone https://github.com/liquidate/proxmox-setup-scripts.git
cd proxmox-setup-scripts
./guided-install.sh
```

## Updating

```bash
pve-gpu-update  # From anywhere
```

Or manually:
```bash
cd /root/proxmox-setup-scripts
git pull
```

## Advanced Usage

Individual scripts can be run directly:

```bash
cd /root/proxmox-setup-scripts

# Configure iGPU VRAM
./host/strix-igpu.sh

# Install AMD drivers
./host/amd-drivers.sh

# Create Ollama LXC
./host/ollama-amd.sh
```

## Contributing

Contributions welcome! Please test on a fresh Proxmox VE installation before submitting.

## Support

- **GitHub**: https://github.com/liquidate/proxmox-setup-scripts
- **Branch**: feature/gpu-detection-improvements
- **Issues**: Open an issue on GitHub

## License

MIT License - See LICENSE file for details

## Acknowledgments

- **jammsen** - Original author of [proxmox-setup-scripts](https://github.com/jammsen/proxmox-setup-scripts)
- Proxmox VE team
- AMD ROCm team
- Proxmox Community Scripts project
