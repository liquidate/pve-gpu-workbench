#!/usr/bin/env bash
# SCRIPT_DESC: Install Ollama LLM runner in GPU-enabled LXC
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
echo -e "${GREEN}Ollama Installation${NC}"
echo -e "${GREEN}========================================${NC}"
echo ""
echo "Ollama lets you run large language models (LLMs) locally with GPU acceleration."
echo "Supported models: Llama, Mistral, Qwen, Gemma, and many more."
echo ""

# Check if container ID was passed as argument (from script 031)
if [ -n "$1" ]; then
    CONTAINER_ID="$1"
    echo -e "${GREEN}Using container ID: $CONTAINER_ID${NC}"
else
    # Interactive selection
    CONTAINER_ID=$(select_gpu_container "Ollama")
fi

# Ensure container is running
ensure_container_running $CONTAINER_ID

# Check if GPU devices are accessible
echo ""
echo -e "${GREEN}>>> Verifying GPU access in container...${NC}"
if ! pct exec $CONTAINER_ID -- test -e /dev/kfd; then
    echo -e "${RED}ERROR: GPU not accessible in container $CONTAINER_ID${NC}"
    echo "Make sure this container was created with script 031."
    exit 1
fi
echo -e "${GREEN}✓ GPU accessible${NC}"

# Run the Ollama installation script inside the container
echo ""
echo -e "${GREEN}>>> Running Ollama installation script...${NC}"
echo ""

# Make sure the script exists and is executable
pct exec $CONTAINER_ID -- chmod +x /root/proxmox-setup-scripts/lxc/install-ollama.sh 2>/dev/null || true

# Run the installation
pct exec $CONTAINER_ID -- bash /root/proxmox-setup-scripts/lxc/install-ollama.sh

# Get container IP
CONTAINER_IP=$(pct config $CONTAINER_ID | grep "^net0:" | grep -oP 'ip=\K[\d\.]+' | head -n1)

echo ""
echo -e "${GREEN}==========================================${NC}"
echo -e "${GREEN}Ollama Installation Complete!${NC}"
echo -e "${GREEN}==========================================${NC}"
echo ""
echo -e "${YELLOW}To use Ollama:${NC}"
echo "  ssh root@$CONTAINER_IP"
echo "  ollama run llama3.2:3b"
echo ""
echo -e "${YELLOW}Or access the API:${NC}"
echo "  curl http://$CONTAINER_IP:11434/api/generate -d '{\"model\":\"llama3.2:3b\",\"prompt\":\"Hello\"}'"
echo ""

