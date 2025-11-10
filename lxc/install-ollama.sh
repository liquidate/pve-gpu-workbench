#!/usr/bin/env bash
# SCRIPT_DESC: Install Ollama and test GPU access inside LXC container

set -e

# Get script directory and source colors
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/../includes/colors.sh"

echo -e "${GREEN}==========================================${NC}"
echo -e "${GREEN}Ollama Installation for GPU-enabled LXC${NC}"
echo -e "${GREEN}==========================================${NC}"
echo ""

# Check if running inside container
if [ ! -e /dev/kfd ]; then
    echo -e "${RED}ERROR: This script must be run inside the LXC container${NC}"
    echo -e "${YELLOW}SSH into your container first:${NC}"
    echo "  ssh root@<container-ip>"
    exit 1
fi

# Check if GPU is accessible
echo -e "${GREEN}>>> Checking GPU access...${NC}"
if [ -e /dev/kfd ] && [ -e /dev/dri/card0 ]; then
    echo -e "${GREEN}✓ GPU devices accessible${NC}"
else
    echo -e "${RED}ERROR: GPU devices not accessible${NC}"
    exit 1
fi

# Check installation method
echo ""
echo -e "${YELLOW}Choose installation method:${NC}"
echo "  1) Docker Ollama (recommended - managed via Portainer)"
echo "  2) Native Ollama (alternative - runs as systemd service)"
echo ""
echo -e "${CYAN}Note: Both work equally well with GPU. Docker is easier to manage.${NC}"
echo ""
read -r -p "Enter choice [1]: " INSTALL_METHOD
INSTALL_METHOD=${INSTALL_METHOD:-1}

if [ "$INSTALL_METHOD" = "1" ]; then
    echo ""
    echo -e "${GREEN}>>> Installing Ollama in Docker...${NC}"
    
    # Check if Docker is installed
    if ! command -v docker >/dev/null 2>&1; then
        echo -e "${RED}ERROR: Docker not installed${NC}"
        echo "Run the AMD driver installation script first"
        exit 1
    fi
    
    # Check if container already exists
    if docker ps -a --format '{{.Names}}' | grep -q '^ollama$'; then
        echo -e "${YELLOW}Ollama container already exists${NC}"
        echo ""
        read -r -p "Remove and recreate? [y/N]: " RECREATE
        if [[ "$RECREATE" =~ ^[Yy]$ ]]; then
            docker stop ollama 2>/dev/null || true
            docker rm ollama 2>/dev/null || true
        else
            echo "Starting existing container..."
            docker start ollama
            echo -e "${GREEN}✓ Ollama container started${NC}"
            echo ""
            echo -e "${YELLOW}To use:${NC}"
            echo "  docker exec -it ollama ollama run llama3.2:3b"
            exit 0
        fi
    fi
    
    # Create Ollama container
    echo ""
    echo -e "${GREEN}>>> Creating Ollama Docker container...${NC}"
    docker run -d --device /dev/kfd --device /dev/dri \
        -e HSA_OVERRIDE_GFX_VERSION=11.5.1 -e HSA_ENABLE_SDMA=0 \
        --group-add video --name ollama \
        -v ollama:/root/.ollama -p 11434:11434 \
        ollama/ollama
    
    echo -e "${GREEN}✓ Ollama container created${NC}"
    sleep 2
    
    # Test
    echo ""
    echo -e "${YELLOW}=== Test Ollama with GPU ===${NC}"
    echo ""
    read -r -p "Download and test llama3.2:3b (~2GB)? [Y/n]: " RUN_TEST
    RUN_TEST=${RUN_TEST:-Y}
    
    if [[ "$RUN_TEST" =~ ^[Yy]$ ]]; then
        echo ""
        echo -e "${GREEN}>>> Testing Ollama...${NC}"
        echo -e "${YELLOW}Open another terminal and run: docker exec ollama rocm-smi --showuse --showmemuse${NC}"
        echo ""
        sleep 2
        
        echo "Testing with prompt: 'Why is the sky blue? Answer in one sentence.'"
        echo ""
        docker exec ollama ollama run llama3.2:3b "Why is the sky blue? Answer in one sentence."
        
        echo ""
        echo -e "${GREEN}✓ Ollama test complete!${NC}"
    fi
    
    echo ""
    echo -e "${YELLOW}To use Ollama:${NC}"
    echo "  docker exec -it ollama ollama run llama3.2:3b"
    echo ""
    echo -e "${YELLOW}Monitor GPU:${NC}"
    echo "  docker exec ollama rocm-smi --showuse --showmemuse"
    echo ""
    echo -e "${YELLOW}Access Ollama API:${NC}"
    echo "  curl http://localhost:11434/api/generate -d '{\"model\":\"llama3.2:3b\",\"prompt\":\"Hello\"}'"
    echo ""
    echo -e "${YELLOW}Manage container:${NC}"
    echo "  docker stop ollama"
    echo "  docker start ollama"
    echo "  docker logs -f ollama"
    echo ""

elif [ "$INSTALL_METHOD" = "2" ]; then
    echo ""
    echo -e "${GREEN}>>> Installing Ollama natively...${NC}"
    
    # Check if already installed
    if command -v ollama >/dev/null 2>&1; then
        echo -e "${YELLOW}Ollama is already installed${NC}"
        ollama --version
    else
        curl -fsSL https://ollama.com/install.sh | sh
        echo -e "${GREEN}✓ Ollama installed${NC}"
    fi
    
    # Start Ollama service
    echo ""
    echo -e "${GREEN}>>> Starting Ollama service...${NC}"
    systemctl enable ollama 2>/dev/null || true
    systemctl start ollama 2>/dev/null || true
    sleep 2
    
    # Test with a model
    echo ""
    echo -e "${YELLOW}=== Test Ollama with GPU ===${NC}"
    echo ""
    echo -e "${GREEN}Available test models:${NC}"
    echo "  1) llama3.2:3b     - Fastest, 3B parameters (~2GB)"
    echo "  2) llama3.2:1b     - Smallest, 1B parameters (~1GB)"
    echo "  3) qwen2.5:3b      - Alternative 3B model"
    echo "  4) Skip test"
    echo ""
    read -r -p "Enter choice [1]: " MODEL_CHOICE
    MODEL_CHOICE=${MODEL_CHOICE:-1}
    
    case $MODEL_CHOICE in
        1) MODEL="llama3.2:3b" ;;
        2) MODEL="llama3.2:1b" ;;
        3) MODEL="qwen2.5:3b" ;;
        4) 
            echo ""
            echo -e "${GREEN}✓ Ollama installed successfully${NC}"
            echo ""
            echo -e "${YELLOW}To use Ollama:${NC}"
            echo "  ollama run llama3.2:3b"
            echo ""
            echo -e "${YELLOW}Monitor GPU usage:${NC}"
            echo "  watch -n 0.5 rocm-smi --showuse --showmemuse"
            exit 0
            ;;
        *) MODEL="llama3.2:3b" ;;
    esac
    
    echo ""
    echo -e "${GREEN}>>> Downloading and running $MODEL...${NC}"
    echo -e "${YELLOW}This will download the model (~2GB) and test it.${NC}"
    echo -e "${YELLOW}Open another terminal and run: watch -n 0.5 rocm-smi --showuse --showmemuse${NC}"
    echo ""
    sleep 2
    
    # Run test
    echo "Testing with prompt: 'Why is the sky blue? Answer in one sentence.'"
    echo ""
    echo "quit" | ollama run $MODEL "Why is the sky blue? Answer in one sentence."
    
    echo ""
    echo -e "${GREEN}✓ Ollama test complete!${NC}"
    echo ""
    echo -e "${YELLOW}To continue chatting:${NC}"
    echo "  ollama run $MODEL"
    echo ""
    echo -e "${YELLOW}To try other models:${NC}"
    echo "  ollama list                    # List downloaded models"
    echo "  ollama pull <model>            # Download a model"
    echo "  ollama rm <model>              # Remove a model"
    echo ""
    
else
    echo -e "${RED}Invalid choice${NC}"
    exit 1
fi

echo ""
echo -e "${GREEN}==========================================${NC}"
echo -e "${GREEN}Ollama Installation Complete!${NC}"
echo -e "${GREEN}==========================================${NC}"
echo ""

