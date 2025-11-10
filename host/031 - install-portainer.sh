#!/usr/bin/env bash
# SCRIPT_DESC: Install Portainer Docker management UI in GPU-enabled LXC
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
echo -e "${GREEN}Portainer Installation${NC}"
echo -e "${GREEN}========================================${NC}"
echo ""
echo "Portainer provides a web UI for managing Docker containers, images, networks, and volumes."
echo ""

# Check if container ID was passed as argument (from script 031)
if [ -n "$1" ]; then
    CONTAINER_ID="$1"
    echo -e "${GREEN}Using container ID: $CONTAINER_ID${NC}"
else
    # Interactive selection
    CONTAINER_ID=$(select_gpu_container "Portainer")
fi

# Ensure container is running
ensure_container_running $CONTAINER_ID

# Check if Docker is installed
check_docker_installed $CONTAINER_ID

# Check if Portainer already running
echo ""
echo -e "${GREEN}>>> Checking for existing Portainer installation...${NC}"
if pct exec $CONTAINER_ID -- docker ps -a --format '{{.Names}}' | grep -q '^portainer$'; then
    echo -e "${YELLOW}Portainer container already exists in container $CONTAINER_ID${NC}"
    echo ""
    read -r -p "Reinstall Portainer? [y/N]: " REINSTALL
    
    if [[ "$REINSTALL" =~ ^[Yy]$ ]]; then
        echo -e "${GREEN}Removing existing Portainer...${NC}"
        pct exec $CONTAINER_ID -- docker stop portainer 2>/dev/null || true
        pct exec $CONTAINER_ID -- docker rm portainer 2>/dev/null || true
        pct exec $CONTAINER_ID -- docker volume rm portainer_data 2>/dev/null || true
    else
        echo ""
        echo -e "${GREEN}Portainer is already installed.${NC}"
        
        # Get container IP from net0 config line
        CONTAINER_IP=$(pct config $CONTAINER_ID | grep "^net0:" | grep -oP 'ip=\K[\d\.]+' | head -n1)
        
        echo ""
        echo -e "${GREEN}Access Portainer at:${NC}"
        echo "  https://$CONTAINER_IP:9443"
        echo ""
        echo -e "${YELLOW}Default admin password setup required on first login.${NC}"
        exit 0
    fi
fi

# Install Portainer
echo ""
echo -e "${GREEN}>>> Installing Portainer in container $CONTAINER_ID...${NC}"
echo ""

# Create Portainer volume and container
pct exec $CONTAINER_ID -- docker volume create portainer_data

pct exec $CONTAINER_ID -- docker run -d \
    --name=portainer \
    --restart=always \
    -p 8000:8000 \
    -p 9443:9443 \
    -v /var/run/docker.sock:/var/run/docker.sock \
    -v portainer_data:/data \
    portainer/portainer-ce:latest

# Wait for Portainer to start
echo ""
echo -e "${GREEN}>>> Waiting for Portainer to start...${NC}"
sleep 5

# Verify it's running
if pct exec $CONTAINER_ID -- docker ps | grep -q portainer; then
    echo -e "${GREEN}✓ Portainer installed successfully${NC}"
else
    echo -e "${RED}ERROR: Portainer failed to start${NC}"
    echo "Check logs: pct exec $CONTAINER_ID -- docker logs portainer"
    exit 1
fi

# Get container IP from net0 config line
CONTAINER_IP=$(pct config $CONTAINER_ID | grep "^net0:" | grep -oP 'ip=\K[\d\.]+' | head -n1)

echo ""
echo -e "${GREEN}==========================================${NC}"
echo -e "${GREEN}Portainer Installation Complete!${NC}"
echo -e "${GREEN}==========================================${NC}"
echo ""
echo -e "${GREEN}Access Portainer at:${NC}"
echo -e "  ${GREEN}https://$CONTAINER_IP:9443${NC}"
echo ""
echo -e "${YELLOW}First-time setup:${NC}"
echo "  1. Open https://$CONTAINER_IP:9443 in your browser"
echo "  2. Create an admin username and password"
echo "  3. Select 'Get Started' to manage the local Docker environment"
echo ""
echo -e "${YELLOW}Note:${NC} Your browser may warn about the self-signed certificate - this is normal."
echo "      Click 'Advanced' and 'Proceed' to continue."
echo ""
echo -e "${GREEN}Container commands:${NC}"
echo "  docker stop portainer    # Stop Portainer"
echo "  docker start portainer   # Start Portainer"
echo "  docker logs portainer    # View logs"
echo ""

