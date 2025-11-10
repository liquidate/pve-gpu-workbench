# Proxmox GPU Setup Scripts

Automated setup scripts for GPU passthrough to LXC containers on Proxmox VE.

## Features

- **AMD GPU Support**: ROCm drivers, Strix Halo iGPU VRAM configuration
- **GPU Passthrough**: Automated udev rules and device permissions
- **LXC Creation**: Pre-configured containers for Ollama with GPU access
- **Interactive Menu**: Guided installation with real-time status checks
- **Version Management**: Selectable ROCm versions with update detection

## Quick Start

### One-Line Installation

Run this command on your fresh Proxmox VE installation:

```bash
bash -c "$(curl -fsSL https://raw.githubusercontent.com/liquidate/proxmox-setup-scripts/main/bootstrap.sh)"
```

This will:
1. Install git (if not present)
2. Clone this repository to `/root/proxmox-setup-scripts`
3. Set up permissions
4. Optionally create system-wide commands (`pve-gpu`, `pve-gpu-update`)
5. Launch the guided installer

### Manual Installation

```bash
# Install git
apt update && apt install -y git

# Clone repository
git clone https://github.com/liquidate/proxmox-setup-scripts.git
cd proxmox-setup-scripts

# Run guided installer
./guided-install.sh
```

## Usage

### System-Wide Commands (Recommended)

If you accepted the system-wide commands during installation, you can run from anywhere:

```bash
# Launch guided installer
pve-gpu

# Update scripts from GitHub
pve-gpu-update
```

### Guided Installer

The main menu provides an interactive interface:

```
╔══════════════════════════════════════╗
║  Proxmox Setup - Guided Installer    ║
╚══════════════════════════════════════╝

═══ GPU SETUP ═══

  strix-igpu - Configure Strix Halo iGPU VRAM allocation [96GB VRAM]
  amd-drivers - Install AMD ROCm GPU drivers              [INSTALLED]
  gpu-udev - Setup udev GPU device permissions           [CONFIGURED]

═══ VERIFICATION ═══

  amd-verify - Comprehensive AMD GPU setup verification     [PASSED]

═══ OPTIONAL ═══

  power - Toggle power management (powertop + AutoASPM)    [ENABLED]
  amd-upgrade - Upgrade AMD ROCm to a different version [UP TO DATE]

═══ LXC CONTAINERS ═══

  ollama-amd - Create Ollama LXC (AMD GPU)

Commands:
  setup           - Run all GPU Setup scripts (reboot + verify after)
  <command>       - Run specific script (e.g., strix-igpu, ollama-amd)
  [i]nfo          - Show system information
  [q]uit          - Exit
```

### Quick Setup

For a complete setup, simply run:

```bash
./guided-install.sh
# At the prompt, type: setup
```

This will:
1. Run all necessary host configuration scripts
2. Prompt for reboot (if needed)
3. Run verification scripts after reboot

### Individual Scripts

You can also run individual scripts directly:

```bash
# Configure Strix Halo iGPU VRAM
./host/strix-igpu.sh

# Install AMD ROCm drivers
./host/amd-drivers.sh

# Create Ollama LXC container
./host/ollama-amd.sh
```

## Supported Hardware

### AMD GPUs
- AMD Radeon RX/Pro series
- AMD Radeon Pro WX series
- AMD Strix Halo APU (with iGPU VRAM configuration)

### ROCm Versions
- Dynamically fetched from AMD's repository
- Currently supports ROCm 6.x - 7.x
- Automatic update detection

## What Gets Installed

### Host Configuration
- AMD ROCm drivers and libraries
- GPU udev rules for container passthrough
- Kernel parameters for iGPU VRAM (Strix Halo only)
- Optional: Power management tools (powertop, AutoASPM)

### LXC Containers
- **Ollama**: Native installation with AMD GPU support
  - ROCm utilities (rocm-smi, radeontop)
  - Pre-configured for network access
  - Ready for Open WebUI integration

## Requirements

- Proxmox VE 8.x (tested on PVE 8.2+)
- AMD GPU or APU
- Root access
- Internet connection (for package downloads)

## Updating

To update the scripts:

```bash
cd /root/proxmox-setup-scripts
git pull
```

Or use the bootstrap script again:

```bash
bash -c "$(curl -fsSL https://raw.githubusercontent.com/liquidate/proxmox-setup-scripts/main/bootstrap.sh)"
```

## Troubleshooting

### Verification Fails
Run the verification script for detailed diagnostics:
```bash
./host/amd-verify.sh
```

### GPU Not Detected in Container
1. Verify udev rules: `./host/gpu-udev.sh`
2. Check device permissions: `ls -l /dev/dri/ /dev/kfd`
3. Reboot if kernel parameters were changed

### ROCm Installation Issues
- Check AMD ROCm version compatibility
- Try a different version: `./host/amd-upgrade.sh`
- Verify internet connectivity to AMD repositories

## Contributing

Contributions welcome! Please test on a fresh Proxmox VE installation before submitting.

## License

MIT License - See LICENSE file for details

## Acknowledgments

- Proxmox VE team
- AMD ROCm team
- Community Scripts project for inspiration
