#!/usr/bin/env bash

# Shared utilities for LXC container management

# Detect GPU-enabled LXC containers
detect_gpu_containers() {
    pct list | awk 'NR>1 {print $1}' | while read -r id; do
        if grep -q "lxc.mount.entry.*kfd\|lxc.mount.entry.*nvidia" /etc/pve/lxc/${id}.conf 2>/dev/null; then
            echo "$id"
        fi
    done
}

# Get container info
get_container_info() {
    local id=$1
    local hostname=$(pct config $id 2>/dev/null | grep "hostname:" | cut -d' ' -f2)
    local status=$(pct status $id 2>/dev/null | awk '{print $2}')
    echo "$hostname|$status"
}

# Select a GPU container (interactive)
# Returns container ID or exits
select_gpu_container() {
    local script_name=$1
    local container_id=""
    
    echo -e "${GREEN}>>> Detecting GPU-enabled LXC containers...${NC}"
    
    GPU_CONTAINERS=$(detect_gpu_containers)
    
    if [ -z "$GPU_CONTAINERS" ]; then
        # NO containers found
        echo ""
        echo -e "${YELLOW}⚠️  No GPU-enabled LXC containers found${NC}"
        echo ""
        echo -e "${YELLOW}$script_name requires a GPU-enabled container.${NC}"
        echo ""
        echo "Options:"
        echo "  1) Create one now (run script 031)"
        echo "  2) Exit and create manually"
        echo ""
        read -r -p "Enter choice [1]: " CHOICE
        
        if [ "$CHOICE" = "1" ] || [ -z "$CHOICE" ]; then
            echo ""
            echo -e "${GREEN}>>> Running container creation script...${NC}"
            SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
            bash "${SCRIPT_DIR}/../host/031 - create-gpu-lxc.sh"
            
            # Re-detect after creation
            GPU_CONTAINERS=$(detect_gpu_containers)
            if [ -z "$GPU_CONTAINERS" ]; then
                echo -e "${RED}ERROR: Container creation failed or was cancelled${NC}"
                exit 1
            fi
            
            # Use the newly created container
            container_id=$(echo "$GPU_CONTAINERS" | tail -n1)
        else
            echo "Exiting. Run script 031 first, then run this script again."
            exit 0
        fi
        
    elif [ $(echo "$GPU_CONTAINERS" | wc -w) -eq 1 ]; then
        # ONE container found
        container_id="$GPU_CONTAINERS"
        info=$(get_container_info $container_id)
        hostname=$(echo "$info" | cut -d'|' -f1)
        status=$(echo "$info" | cut -d'|' -f2)
        echo -e "${GREEN}✓ Found GPU container: $container_id ($hostname - $status)${NC}"
        
    else
        # MULTIPLE containers found
        echo ""
        echo -e "${GREEN}Found multiple GPU-enabled containers:${NC}"
        echo ""
        for id in $GPU_CONTAINERS; do
            info=$(get_container_info $id)
            hostname=$(echo "$info" | cut -d'|' -f1)
            status=$(echo "$info" | cut -d'|' -f2)
            echo "  [$id] $hostname ($status)"
        done
        echo ""
        read -r -p "Enter container ID: " container_id
        
        # Validate selection
        if ! echo "$GPU_CONTAINERS" | grep -qw "$container_id"; then
            echo -e "${RED}ERROR: Invalid container ID${NC}"
            exit 1
        fi
    fi
    
    echo "$container_id"
}

# Ensure container is running
ensure_container_running() {
    local container_id=$1
    
    if ! pct status $container_id 2>/dev/null | grep -q "running"; then
        echo -e "${YELLOW}Container $container_id is not running${NC}"
        echo -e "${GREEN}Starting container...${NC}"
        pct start $container_id
        sleep 3
        
        # Verify it started
        if ! pct status $container_id | grep -q "running"; then
            echo -e "${RED}ERROR: Failed to start container $container_id${NC}"
            exit 1
        fi
        echo -e "${GREEN}✓ Container started${NC}"
    fi
}

# Check if Docker is installed in container
check_docker_installed() {
    local container_id=$1
    
    if ! pct exec $container_id -- command -v docker >/dev/null 2>&1; then
        echo -e "${RED}ERROR: Docker not installed in container $container_id${NC}"
        echo ""
        echo "This container needs Docker. Options:"
        echo "  1) Install Docker now"
        echo "  2) Exit"
        echo ""
        read -r -p "Enter choice [1]: " INSTALL_DOCKER
        
        if [ "$INSTALL_DOCKER" = "1" ] || [ -z "$INSTALL_DOCKER" ]; then
            echo ""
            echo -e "${GREEN}>>> Installing Docker in container...${NC}"
            pct exec $container_id -- bash -c "curl -fsSL https://get.docker.com | sh"
            pct exec $container_id -- systemctl enable docker
            pct exec $container_id -- systemctl start docker
            echo -e "${GREEN}✓ Docker installed${NC}"
        else
            echo "Exiting."
            exit 0
        fi
    fi
}

