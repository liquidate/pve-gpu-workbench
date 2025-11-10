#!/usr/bin/env bash
# SCRIPT_DESC: Install Open WebUI (ChatGPT-like interface for Ollama)
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
echo -e "${GREEN}Open WebUI Installation${NC}"
echo -e "${GREEN}========================================${NC}"
echo ""
echo "Open WebUI provides a ChatGPT-like interface for Ollama."
echo "Features: Chat history, model switching, markdown support, and more."
echo ""

# Check if container ID was passed as argument
if [ -n "$1" ]; then
    CONTAINER_ID="$1"
    echo -e "${GREEN}Using container ID: $CONTAINER_ID${NC}"
else
    # Interactive selection
    CONTAINER_ID=$(select_gpu_container "Open WebUI")
fi

# Ensure container is running
ensure_container_running $CONTAINER_ID

# Check if Docker is installed
check_docker_installed $CONTAINER_ID

# Check if Ollama is running
echo ""
echo -e "${GREEN}>>> Checking for Ollama...${NC}"
OLLAMA_INSTALLED=false

# Check for native Ollama in common locations
if pct exec $CONTAINER_ID -- test -f /usr/local/bin/ollama 2>/dev/null || \
   pct exec $CONTAINER_ID -- test -f /usr/bin/ollama 2>/dev/null || \
   pct exec $CONTAINER_ID -- systemctl is-active --quiet ollama 2>/dev/null; then
    OLLAMA_INSTALLED=true
    OLLAMA_URL="http://localhost:11434"
    echo -e "${GREEN}✓ Ollama installed natively${NC}"
# Check for Docker Ollama
elif pct exec $CONTAINER_ID -- docker ps --format '{{.Names}}' 2>/dev/null | grep -q '^ollama$'; then
    OLLAMA_INSTALLED=true
    OLLAMA_URL="http://ollama:11434"
    echo -e "${GREEN}✓ Ollama running in Docker${NC}"
fi

if [ "$OLLAMA_INSTALLED" = false ]; then
    echo -e "${YELLOW}⚠️  Ollama not found${NC}"
    echo ""
    echo "Open WebUI requires Ollama to be installed first."
    echo ""
    echo "Options:"
    echo "  1) Install Ollama now (recommended)"
    echo "  2) Continue anyway (you can install Ollama later)"
    echo "  3) Exit"
    echo ""
    read -r -p "Enter choice [1]: " CHOICE
    CHOICE=${CHOICE:-1}
    
    if [ "$CHOICE" = "1" ]; then
        echo ""
        bash "${SCRIPT_DIR}/033 - install-ollama.sh" "$CONTAINER_ID"
        # Check if Docker or native
        if pct exec $CONTAINER_ID -- docker ps --format '{{.Names}}' | grep -q '^ollama$'; then
            OLLAMA_URL="http://ollama:11434"
        else
            OLLAMA_URL="http://localhost:11434"
        fi
    elif [ "$CHOICE" = "2" ]; then
        OLLAMA_URL="http://localhost:11434"
    else
        exit 0
    fi
fi

# Check if Open WebUI already exists
echo ""
echo -e "${GREEN}>>> Checking for existing Open WebUI installation...${NC}"
if pct exec $CONTAINER_ID -- docker ps -a --format '{{.Names}}' | grep -q '^open-webui$'; then
    echo -e "${YELLOW}Open WebUI already exists${NC}"
    echo ""
    read -r -p "Reinstall? [y/N]: " REINSTALL
    
    if [[ "$REINSTALL" =~ ^[Yy]$ ]]; then
        pct exec $CONTAINER_ID -- docker stop open-webui 2>/dev/null || true
        pct exec $CONTAINER_ID -- docker rm open-webui 2>/dev/null || true
        pct exec $CONTAINER_ID -- docker volume rm open-webui 2>/dev/null || true
    else
        CONTAINER_IP=$(pct config $CONTAINER_ID | grep "^net0:" | grep -oP 'ip=\K[\d\.]+' | head -n1)
        echo ""
        echo -e "${GREEN}Open WebUI already installed.${NC}"
        echo ""
        echo -e "${GREEN}Access at: http://$CONTAINER_IP:3000${NC}"
        exit 0
    fi
fi

# Install Open WebUI
echo ""
echo -e "${GREEN}>>> Installing Open WebUI...${NC}"
echo ""

# Create volume
pct exec $CONTAINER_ID -- docker volume create open-webui

# Determine network mode based on Ollama installation
if echo "$OLLAMA_URL" | grep -q "ollama:11434"; then
    # Ollama in Docker - use Docker network
    NETWORK_MODE="--network container:ollama"
else
    # Ollama native - use host network
    NETWORK_MODE="--add-host=host.docker.internal:host-gateway"
fi

# Run Open WebUI
pct exec $CONTAINER_ID -- docker run -d \
    --name open-webui \
    --restart always \
    -p 3000:8080 \
    $NETWORK_MODE \
    -v open-webui:/app/backend/data \
    -e OLLAMA_BASE_URL="$OLLAMA_URL" \
    ghcr.io/open-webui/open-webui:main

# Wait for it to start
echo ""
echo -e "${GREEN}>>> Waiting for Open WebUI to start...${NC}"
sleep 5

# Verify
if pct exec $CONTAINER_ID -- docker ps | grep -q open-webui; then
    echo -e "${GREEN}✓ Open WebUI installed successfully${NC}"
else
    echo -e "${RED}ERROR: Open WebUI failed to start${NC}"
    echo "Check logs: pct exec $CONTAINER_ID -- docker logs open-webui"
    exit 1
fi

# Get container IP
CONTAINER_IP=$(pct config $CONTAINER_ID | grep "^net0:" | grep -oP 'ip=\K[\d\.]+' | head -n1)

echo ""
echo -e "${GREEN}==========================================${NC}"
echo -e "${GREEN}Open WebUI Installation Complete!${NC}"
echo -e "${GREEN}==========================================${NC}"
echo ""
echo -e "${GREEN}Access Open WebUI at:${NC}"
echo -e "  ${GREEN}http://$CONTAINER_IP:3000${NC}"
echo ""
echo -e "${YELLOW}First-time setup:${NC}"
echo "  1. Open http://$CONTAINER_IP:3000 in your browser"
echo "  2. Create an account (first user becomes admin)"
echo "  3. Start chatting with your models!"
echo ""
echo -e "${YELLOW}Features:${NC}"
echo "  • ChatGPT-like interface"
echo "  • Multiple conversations"
echo "  • Model switching"
echo "  • Markdown & code syntax highlighting"
echo "  • Image generation support (with appropriate models)"
echo ""
echo -e "${GREEN}Container commands:${NC}"
echo "  docker stop open-webui"
echo "  docker start open-webui"
echo "  docker logs open-webui"
echo ""

