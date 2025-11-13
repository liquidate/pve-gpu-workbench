# Fork Acknowledgment

## Origins

This project started as a fork of [jammsen/proxmox-setup-scripts](https://github.com/jammsen/proxmox-setup-scripts), which provided the initial foundation for GPU passthrough in Proxmox LXC containers.

## Evolution

Over the course of 200+ commits, this project has evolved significantly beyond the original scope:

### Architectural Changes
- **Shared Library System**: Created modular `includes/` directory with reusable components
- **Plugin Architecture**: Metadata-driven script discovery and categorization
- **Template System**: Reusable templates for rapid container creation
- **Modern Menu**: Numbered shortcuts, auto-categorization, real-time status

### New Features
- **LXC Containers**: Ollama (NVIDIA/AMD), Open WebUI
- **Progress Tracking**: Unified progress indicators and spinners
- **Logging Infrastructure**: Comprehensive logging with upfront display
- **GPU Detection**: Enhanced detection for NVIDIA and AMD GPUs
- **Container Notes**: Automatic notes with access URLs and commands

### Critical Fixes
- **GPU Detection**: Fixed NVIDIA GPU detection in LXC (correct cgroup permissions: 195, 511, 236)
- **CUDA Paths**: Proper LD_LIBRARY_PATH handling for CUDA libraries
- **AppArmor**: Workarounds for Proxmox 9 compatibility
- **Strix Halo**: iGPU VRAM allocation support

## Scope Comparison

**Original (jammsen):**
- Collection of setup scripts
- Focus on initial GPU passthrough
- Manual script execution

**This Fork:**
- Self-organizing platform
- Plugin-based architecture  
- Guided installation with real-time status
- Scalable to 50+ containers
- Template-driven development

## Statistics

- **204 commits** beyond original fork point
- **52 files changed**
- **+9,993 lines added, -2,359 deleted** (net +7,600 lines)
- **10 new architectural files** (includes/, templates/, docs/)

## Recognition

While this project has diverged significantly, we acknowledge jammsen's original work as the inspiration and starting point. The core concepts of GPU passthrough to LXC containers originated from his research and implementation.

## License

This project maintains the same license as the original (if applicable), with all modifications and additions available under the same terms.

## Contact

For questions about this fork's unique features (plugin system, templates, menu redesign), please use this repository's issue tracker.

For questions about the original GPU passthrough concepts, please refer to [jammsen's repository](https://github.com/jammsen/proxmox-setup-scripts).

