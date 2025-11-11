# 🚀 Fresh Proxmox Install Guide

## Quick Start (One-Liner Install)

On your **fresh Proxmox VE installation**, run:

```bash
bash -c "$(curl -fsSL https://raw.githubusercontent.com/liquidate/proxmox-setup-scripts/feature/gpu-detection-improvements/bootstrap.sh)"
```

This will:
1. Clone the repository to `/root/proxmox-setup-scripts`
2. Create system-wide commands: `pve-gpu` and `pve-gpu-update`
3. Launch the guided installer

## After Installation

### System-Wide Commands

- **`pve-gpu`** - Launch the guided installer from anywhere
- **`pve-gpu-update`** - Update scripts from GitHub

### Manual Launch (Alternative)

```bash
cd /root/proxmox-setup-scripts
./guided-install.sh
```

## What This Tool Does

### GPU Setup (Host)
- **strix-igpu** - Configure Strix Halo iGPU VRAM (1-96GB, user-selectable)
- **amd-drivers** - Install AMD ROCm drivers (6.0-7.1, dynamic version selection)
- **amd-upgrade** - Upgrade ROCm to newer version
- **amd-verify** - Comprehensive GPU verification (20+ checks, detects reboot needs)
- **gpu-udev** - Set up udev rules for GPU device permissions
- **power** - Toggle GPU power management

### LXC Creation
- **ollama-amd** - Create GPU-enabled Ollama LXC
  - Quick Mode: 2 prompts (mode, password) - uses defaults
  - Advanced Mode: Full customization
  - Auto GPU verification (12 checks)
  - Clean no-scrolling progress indicators
  - Includes: `update` and `gpu-verify` commands

### Special Commands
- **setup** - Run all GPU setup scripts in order (auto-reboot detection)
- **update** - Update scripts from GitHub
- **info** - System dashboard (GPU status, storage, network, LXCs)
- **quit** - Exit

## Key Features

### 🎯 Professional UX
- Tab completion for all commands
- Clean, no-scrolling installation
- Color-coded status indicators
- Right-aligned status flags in menu
- Progress indicators: `[Step X/Y] Action...`

### 🔍 Verification & Validation
- Host: `amd-verify` - Checks kernel, drivers, VRAM, udev, ROCm
- LXC: `gpu-verify` - Checks device files, permissions, ROCm, Ollama
- Automatic validation after LXC creation
- Detects reboot requirements

### 📊 Info Dashboard
- Script version (git branch, commit, date)
- Proxmox VE & kernel version
- GPU health status (✓ Working / ⚠ Reboot needed / ✗ Not configured)
- ROCm/CUDA version
- iGPU VRAM allocation
- All storage pools with usage
- Network bridges and IPs
- LXC containers with IPs and status

### 🧹 Maintenance
- Auto log cleanup (keeps last 5 logs)
- Idempotent scripts (safe to re-run)
- Just-in-time tool installation
- Minimal host footprint

## Inside LXC Containers

After creating an Ollama LXC, these commands are available inside:

```bash
ssh root@<container-ip>

# Update Ollama to latest version
update

# Verify GPU is working
gpu-verify

# Monitor GPU usage
rocm-smi --showuse --showmemuse
watch -n 0.5 rocm-smi --showuse --showmemuse
radeontop
```

## Typical Workflow

### First Time Setup
1. Fresh Proxmox install
2. Run one-liner bootstrap command
3. Type: `setup` (or just press Enter)
4. Scripts run in order, prompting before each
5. Reboot when prompted
6. Run `pve-gpu` → `amd-verify` to confirm
7. Create LXC: `pve-gpu` → `ollama-amd`

### Creating Additional LXCs
```bash
pve-gpu
ollama-amd  # Quick mode: just set password, uses defaults
```

### Upgrading ROCm
```bash
pve-gpu
amd-upgrade  # Shows current version, fetches available versions
```

### Changing iGPU VRAM
```bash
pve-gpu
strix-igpu  # Shows current allocation, prompts for new value (1-96GB)
```

### Checking System Status
```bash
pve-gpu
info  # Shows everything at a glance
```

## What We Built Together 🎉

### Session Highlights
- ✅ Clean no-scrolling UX (both Quick & Advanced modes)
- ✅ Automatic log cleanup (keeps last 5)
- ✅ Enhanced info dashboard with GPU health indicators
- ✅ Fixed UI issues (GPU descriptions, storage percentages, LXC colors)
- ✅ GPU verification in LXCs with automatic validation
- ✅ Tab completion for commands
- ✅ Beautiful completion message with GPU status
- ✅ Command-based navigation (replaced numbered scripts)
- ✅ Dynamic ROCm version fetching
- ✅ User-configurable iGPU VRAM allocation
- ✅ Comprehensive verification scripts
- ✅ One-liner bootstrap installation
- ✅ System-wide commands (pve-gpu, pve-gpu-update)

### The Journey
From a collection of numbered scripts to a polished, professional, production-ready GPU setup tool for Proxmox. Every detail was refined for the best possible user experience.

## Support & Updates

- **GitHub**: https://github.com/liquidate/proxmox-setup-scripts
- **Branch**: feature/gpu-detection-improvements
- **Update**: Run `pve-gpu-update` anytime

## Notes

- Scripts are idempotent (safe to re-run)
- Minimal changes to Proxmox host
- Tools installed just-in-time when needed
- All logs available in `/tmp/ollama-lxc-install-*.log`
- Tab completion works in interactive terminals

---

**Built with care for the Proxmox + AMD GPU community.** 🚀

Enjoy your fresh install!

