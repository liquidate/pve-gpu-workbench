#!/usr/bin/env bash
# SCRIPT_DESC: Install ComfyUI (Stable Diffusion image generation)
# SCRIPT_DETECT:

set -e

# Get script directory and source includes
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/../includes/colors.sh"
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/../includes/container-utils.sh"

echo ""
echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}ComfyUI Installation${NC}"
echo -e "${GREEN}========================================${NC}"
echo ""
echo "ComfyUI is a powerful node-based interface for Stable Diffusion."
echo "Generate images from text prompts using AI with full GPU acceleration."
echo ""
echo -e "${YELLOW}Note: This will download several GB of models on first run.${NC}"
echo ""

# Check if container ID was passed as argument
if [ -n "$1" ]; then
    CONTAINER_ID="$1"
    echo -e "${GREEN}Using container ID: $CONTAINER_ID${NC}"
else
    # Interactive selection
    CONTAINER_ID=$(select_gpu_container "ComfyUI")
fi

# Ensure container is running
ensure_container_running $CONTAINER_ID

# Check if Docker is installed
check_docker_installed $CONTAINER_ID

# Check GPU access
echo ""
echo -e "${GREEN}>>> Verifying GPU access...${NC}"
if ! pct exec $CONTAINER_ID -- test -e /dev/kfd; then
    echo -e "${RED}ERROR: GPU not accessible${NC}"
    exit 1
fi
echo -e "${GREEN}✓ GPU accessible${NC}"

# Check if already installed
echo ""
echo -e "${GREEN}>>> Checking for existing ComfyUI installation...${NC}"
if pct exec $CONTAINER_ID -- docker ps -a --format '{{.Names}}' | grep -q '^comfyui$'; then
    echo -e "${YELLOW}ComfyUI already exists${NC}"
    echo ""
    read -r -p "Reinstall? [y/N]: " REINSTALL
    
    if [[ "$REINSTALL" =~ ^[Yy]$ ]]; then
        pct exec $CONTAINER_ID -- docker stop comfyui 2>/dev/null || true
        pct exec $CONTAINER_ID -- docker rm comfyui 2>/dev/null || true
    else
        CONTAINER_IP=$(pct config $CONTAINER_ID | grep "^net0:" | grep -oP 'ip=\K[\d\.]+' | head -n1)
        echo ""
        echo -e "${GREEN}ComfyUI already installed.${NC}"
        echo ""
        echo -e "${GREEN}Access at: http://$CONTAINER_IP:8188${NC}"
        exit 0
    fi
fi

# Install ComfyUI
echo ""
echo -e "${GREEN}>>> Installing ComfyUI...${NC}"
echo -e "${YELLOW}This may take a few minutes to download the Docker image...${NC}"
echo ""

# Run ComfyUI with ROCm support
pct exec $CONTAINER_ID -- docker run -d \
    --name comfyui \
    --restart always \
    --device /dev/kfd \
    --device /dev/dri \
    -e HSA_OVERRIDE_GFX_VERSION=11.5.1 \
    -e HSA_ENABLE_SDMA=0 \
    --group-add video \
    -p 8188:8188 \
    -v comfyui-models:/home/user/ComfyUI/models \
    -v comfyui-output:/home/user/ComfyUI/output \
    yanwk/comfyui-boot:rocm

# Wait for startup
echo ""
echo -e "${GREEN}>>> Waiting for ComfyUI to start (this may take 30-60 seconds)...${NC}"
echo -e "${YELLOW}ComfyUI is downloading default models on first run...${NC}"
sleep 10

# Show startup logs
echo ""
echo -e "${GREEN}>>> Checking ComfyUI status...${NC}"
pct exec $CONTAINER_ID -- docker logs comfyui --tail 20

# Verify
if pct exec $CONTAINER_ID -- docker ps | grep -q comfyui; then
    echo ""
    echo -e "${GREEN}✓ ComfyUI container started${NC}"
else
    echo -e "${RED}ERROR: ComfyUI failed to start${NC}"
    exit 1
fi

# Get container IP
CONTAINER_IP=$(pct config $CONTAINER_ID | grep "^net0:" | grep -oP 'ip=\K[\d\.]+' | head -n1)

echo ""
echo -e "${GREEN}==========================================${NC}"
echo -e "${GREEN}ComfyUI Installation Complete!${NC}"
echo -e "${GREEN}==========================================${NC}"
echo ""
echo -e "${GREEN}Access ComfyUI at:${NC}"
echo -e "  ${GREEN}http://$CONTAINER_IP:8188${NC}"
echo ""
echo -e "${YELLOW}First-time setup:${NC}"
echo "  1. Wait 30-60 seconds for models to download"
echo "  2. Open http://$CONTAINER_IP:8188 in your browser"
echo "  3. The default workflow will be loaded automatically"
echo "  4. Enter a prompt and click 'Queue Prompt' to generate!"
echo ""
echo -e "${YELLOW}Default models included:${NC}"
echo "  • SD 1.5 checkpoint"
echo "  • VAE"
echo "  • CLIP"
echo ""
echo -e "${YELLOW}To add more models:${NC}"
echo "  1. SSH into container: ssh root@$CONTAINER_IP"
echo "  2. Access model directory: docker exec -it comfyui bash"
echo "  3. Models are in: /home/user/ComfyUI/models/"
echo ""
echo -e "${YELLOW}Monitor GPU usage:${NC}"
echo "  watch -n 0.5 'pct exec $CONTAINER_ID -- rocm-smi --showuse'"
echo ""
echo -e "${GREEN}Container commands:${NC}"
echo "  docker stop comfyui"
echo "  docker start comfyui"
echo "  docker logs -f comfyui"
echo ""

