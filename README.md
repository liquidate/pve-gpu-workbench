# PVE GPU Workbench

A guided installation system for GPU passthrough in Proxmox VE, with automated container deployment and a plugin-based architecture.

**Build GPU-accelerated workloads on Proxmox with ease.**

## What This Does

- **Installs GPU drivers** (NVIDIA CUDA or AMD ROCm) on your Proxmox host
- **Configures GPU passthrough** to LXC containers with correct permissions
- **Deploys AI containers** (Ollama, Open WebUI) with GPU acceleration
- **Self-organizing menu** that categorizes containers by purpose
- **Extensible architecture** for adding new services without modifying core code

## Quick Start

On your Proxmox VE host:

```bash
bash -c "$(curl -fsSL https://raw.githubusercontent.com/liquidate/pve-gpu-workbench/main/bootstrap.sh)"
```

This installs the `pve-gpu` command. Run it to launch the interactive workbench.

## Usage

```bash
pve-gpu          # Launch main menu
pve-gpu-update   # Update scripts from GitHub
```

### Interactive Menu

```
╔══════════════════════════════════════════════════════════════════════════════╗
║                    Proxmox GPU Management (pve-gpu)                          ║
╚══════════════════════════════════════════════════════════════════════════════╝

GPU: GB202 GeForce RTX 5090

QUICK START
  setup          - Auto-configure GPU (drivers → verify → reboot)

HOST CONFIGURATION
  1  nvidia-drivers  - Install NVIDIA CUDA drivers and modules      [INSTALLED]
  2  gpu-udev        - Setup udev GPU device permissions           [CONFIGURED]

DIAGNOSTICS & VERIFICATION
  3  nvidia-verify   - Verify NVIDIA GPU setup and drivers             [PASSED]

DEPLOY CONTAINERS (AI & Machine Learning)
  4  ollama-nvidia   - Create Ollama LXC (NVIDIA GPU)               [INSTALLED]
  5  openwebui       - Create Open WebUI LXC                        [INSTALLED]

MAINTENANCE
  6  nvidia-upgrade  - Upgrade NVIDIA driver version                     [v580]
  7  power           - Toggle power management settings               [ENABLED]
  u  update          - Update pve-gpu scripts from GitHub
  i  info            - Show system information

Enter: [number] or <name> or setup or [q]uit
```

**Navigation:**
- Type a number (1-9) for instant access
- Type a command name (e.g., `ollama-nvidia`)
- Type `setup` to run all GPU configuration steps
- Type `i` for system information dashboard

## Typical Workflow

### NVIDIA Setup
1. Run `pve-gpu` → type `setup` (or just press Enter)
2. Follow prompts, reboot when asked
3. After reboot: `pve-gpu` → `3` (nvidia-verify)
4. Deploy Ollama: `pve-gpu` → `4` (ollama-nvidia)
5. Deploy WebUI: `pve-gpu` → `5` (openwebui)

### AMD Setup
1. Run `pve-gpu` → type `setup`
2. Follow prompts, reboot when asked
3. After reboot: `pve-gpu` → verify script
4. Deploy containers as needed

## Key Features

### Plugin Architecture
Scripts self-register using metadata tags:

```bash
#!/usr/bin/env bash
# SCRIPT_DESC: Photo management with AI search
# SCRIPT_CATEGORY: lxc-media
# SCRIPT_DETECT: command -v immich &>/dev/null
```

The menu automatically organizes by category. No menu code changes needed.

### Auto-Organization
Containers group by purpose:
- **AI & Machine Learning** - Ollama, Open WebUI, ComfyUI, Stable Diffusion
- **Media & Photos** - Immich, Jellyfin, Plex, Photoprism  
- **Development Tools** - Code-server, Gitea, GitLab
- *(and more as you add them)*

### Shared Libraries
Modular components eliminate code duplication:
- `includes/progress.sh` - Progress indicators and spinners
- `includes/logging.sh` - Log file management
- `includes/lxc-common.sh` - Common container operations
- `includes/lxc-gpu-nvidia.sh` - NVIDIA GPU passthrough logic

### Container Template
Create new GPU-enabled containers quickly:

```bash
cp templates/lxc-nvidia-template.sh host/mynewapp-nvidia.sh
# Edit: change name, description, and app-specific setup
# Done! Menu auto-discovers and categorizes it
```

## Adding New Containers

1. **Copy template:**
   ```bash
   cp templates/lxc-nvidia-template.sh host/immich-nvidia.sh
   ```

2. **Edit metadata:**
   ```bash
   # SCRIPT_DESC: Photo management with AI search
   # SCRIPT_CATEGORY: lxc-media
   ```

3. **Customize app setup** (lines 80-120 in template)

4. **Done!** Menu automatically shows it under "DEPLOY CONTAINERS (Media & Photos)"

See [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md) and [`PLUGIN_ARCHITECTURE.md`](PLUGIN_ARCHITECTURE.md) for details.

## What Gets Installed

### Proxmox Host
- **NVIDIA**: CUDA drivers, kernel modules, nvidia-smi
- **AMD**: ROCm drivers, rocm-smi, radeontop
- **Both**: udev rules for GPU passthrough

### LXC Containers
- Ubuntu 24.04 LTS base
- Application (Ollama, Open WebUI, etc.)
- GPU passthrough configuration
- Helper scripts (`update`, `gpu-verify`)

## Requirements

- Proxmox VE 8.x or later
- NVIDIA GPU (any CUDA-capable) or AMD GPU (ROCm-supported)
- Root access to Proxmox host
- Internet connection

## Supported Hardware

### NVIDIA
- GeForce RTX series (20xx, 30xx, 40xx, 50xx)
- GeForce GTX series
- Tesla/Quadro/Professional series
- Any CUDA-capable GPU

### AMD  
- Radeon RX series (5000+)
- Radeon Pro series
- Radeon Instinct series
- Strix Halo APU (with configurable iGPU VRAM)

## Troubleshooting

### GPU Not Detected in Container

**NVIDIA:**
```bash
pct exec <container-id> -- nvidia-smi
pct exec <container-id> -- ls -la /dev/nvidia*
```

**AMD:**
```bash
pct exec <container-id> -- rocm-smi
pct exec <container-id> -- ls -la /dev/dri /dev/kfd
```

### Check Logs
All scripts log to `/tmp/` with timestamps:
```bash
ls -lt /tmp/*-install-*.log | head -5
tail -100 /tmp/ollama-nvidia-lxc-install-*.log
```

### Verification Scripts
Run comprehensive diagnostics:
```bash
pve-gpu → nvidia-verify   # or amd-verify
```

## Manual Installation

```bash
apt update && apt install -y git
git clone https://github.com/liquidate/proxmox-setup-scripts.git
cd proxmox-setup-scripts
./guided-install.sh
```

## Project Structure

```
proxmox-setup-scripts/
├── guided-install.sh          # Main menu
├── bootstrap.sh               # One-line installer
├── host/                      # Installation scripts
│   ├── nvidia-drivers.sh
│   ├── ollama-nvidia.sh
│   ├── openwebui.sh
│   └── ...
├── includes/                  # Shared libraries
│   ├── progress.sh
│   ├── logging.sh
│   ├── lxc-common.sh
│   └── lxc-gpu-nvidia.sh
├── templates/                 # Container templates
│   └── lxc-nvidia-template.sh
└── docs/                      # Documentation
    └── ARCHITECTURE.md
```

## Documentation

- [`ARCHITECTURE.md`](docs/ARCHITECTURE.md) - Shared library system
- [`PLUGIN_ARCHITECTURE.md`](PLUGIN_ARCHITECTURE.md) - Plugin design and categories
- [`FORK_ACKNOWLEDGMENT.md`](FORK_ACKNOWLEDGMENT.md) - Project history and divergence

## Acknowledgments

This project was inspired by [jammsen's proxmox-setup-scripts](https://github.com/jammsen/proxmox-setup-scripts), which provided the initial foundation for GPU passthrough in Proxmox LXC containers. 

Over 200+ commits, this fork evolved into a complete rewrite with a plugin architecture, shared library system, and auto-organizing menu. While the core concept of GPU passthrough to LXC originated from jammsen's work, the implementation, architecture, and feature set have diverged significantly.

## License

MIT License - See LICENSE file for details.

## Contributing

Contributions welcome! Please:
1. Test on a fresh Proxmox VE installation
2. Follow the plugin architecture (use `SCRIPT_CATEGORY` tags)
3. Add progress tracking and logging
4. Update documentation if adding new features

## Support

- **Issues**: [GitHub Issues](https://github.com/liquidate/pve-gpu-workbench/issues)
- **Discussions**: [GitHub Discussions](https://github.com/liquidate/pve-gpu-workbench/discussions)
- **Documentation**: [`docs/`](docs/) directory

---

**Note**: This project maintains active development. For the original simpler script collection that inspired this workbench, see [jammsen's proxmox-setup-scripts](https://github.com/jammsen/proxmox-setup-scripts).
