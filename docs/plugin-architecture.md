# Plugin Architecture Proposal

## Problem
Current menu hardcodes script patterns (`ollama-*`, `comfyui-*`). Won't scale as we add more LXC containers.

## Solution: Metadata-Driven Auto-Discovery

### Script Header Format
```bash
#!/usr/bin/env bash
# SCRIPT_DESC: Create Ollama LXC (NVIDIA GPU)
# SCRIPT_CATEGORY: lxc-ai
# SCRIPT_PRIORITY: 10
# SCRIPT_DETECT: nvidia-smi
```

### Supported Categories

#### Host Scripts
- `host-setup` - Driver installation, udev rules
- `host-verify` - Diagnostic and verification tools
- `host-maintenance` - Updates, power management

#### LXC Containers
- `lxc-ai` - AI & Machine Learning (Ollama, ComfyUI, Stable Diffusion)
- `lxc-media` - Media Servers (Jellyfin, Plex, Immich, Photoprism)
- `lxc-dev` - Development Tools (code-server, gitea)
- `lxc-productivity` - Productivity (Nextcloud, Paperless-ngx)
- `lxc-monitoring` - Monitoring (Grafana, Prometheus)
- `lxc-network` - Network Services (Pi-hole, AdGuard, Nginx Proxy Manager)

### Menu Organization

**Option A: Grouped Categories** (Current approach)
```
DEPLOY CONTAINERS (AI & Machine Learning)
  4  ollama-nvidia      [INSTALLED]
  5  openwebui          [INSTALLED]
  6  comfyui-nvidia     [ACTION]

DEPLOY CONTAINERS (Media & Photos)
  7  immich-nvidia      [ACTION]
  8  jellyfin-nvidia    [ACTION]
```

**Option B: Submenu Navigation** (Better for 20+ scripts)
```
DEPLOY CONTAINERS
  4  AI & Machine Learning...     (3 available, 2 installed)
  5  Media & Photos...            (2 available, 0 installed)
  6  Development Tools...         (4 available, 1 installed)
  
→ Selecting "4" opens submenu:
  AI & MACHINE LEARNING
   4a  ollama-nvidia      [INSTALLED]
   4b  openwebui          [INSTALLED]
   4c  comfyui-nvidia     [ACTION]
   4d  stable-diffusion   [ACTION]
   [b]ack to main menu
```

**Option C: Hybrid** (Best UX)
- Show top 5 most common containers directly (ollama, openwebui, comfyui, immich, jellyfin)
- Add "More containers..." option for rest
- Auto-promote frequently used containers to main menu

### Implementation Priority

1. **Phase 1** (Now): Add SCRIPT_CATEGORY to existing scripts
2. **Phase 2**: Update menu to use categories instead of hardcoded patterns
3. **Phase 3**: Add submenu support when we have 10+ LXC scripts
4. **Phase 4**: Smart ordering based on usage/popularity

### Benefits

✅ **Scalable** - Add new scripts without touching menu code
✅ **Organized** - Auto-grouped by category
✅ **Flexible** - Easy to reorganize
✅ **Maintainable** - Script metadata is self-contained
✅ **Discoverable** - Users see all available options

### Breaking Changes

None! Backward compatible:
- Scripts without SCRIPT_CATEGORY default to "uncategorized"
- Current pattern matching stays as fallback
- Menu numbering adjusts automatically

## Next Steps

1. Add SCRIPT_CATEGORY to existing scripts?
2. Implement category-based grouping?
3. Wait until we have more LXC scripts?

**Recommendation**: Add categories now (future-proof), implement grouping later (when needed).

