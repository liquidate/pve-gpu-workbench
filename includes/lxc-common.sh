#!/usr/bin/env bash
# LXC container common operations
# Source this file to get consistent container management across scripts

# Ensure Ubuntu template is downloaded
# Usage: ensure_ubuntu_template
ensure_ubuntu_template() {
    local template_name="ubuntu-24.04-standard_24.04-2_amd64.tar.zst"
    local template_path="/var/lib/vz/template/cache/$template_name"
    
    if [ ! -f "$template_path" ]; then
        echo -e "${YELLOW}Downloading Ubuntu 24.04 template (~135MB)...${NC}"
        if pveam download local "$template_name" >> "$LOG_FILE" 2>&1; then
            echo -e "${GREEN}✓ Template downloaded${NC}"
        else
            echo -e "${RED}✗ Failed to download template${NC}"
            echo -e "${YELLOW}Check log: $LOG_FILE${NC}"
            exit 1
        fi
    fi
    
    echo "$template_path"
}

# Create LXC container with standard configuration
# Usage: create_lxc_container <container_id> <hostname> <ip> <memory_gb> <cores> <disk_gb> <storage>
create_lxc_container() {
    local container_id="$1"
    local hostname="$2"
    local ip_address="$3"
    local memory_gb="$4"
    local cores="$5"
    local disk_gb="$6"
    local storage="${7:-local-lvm}"
    local swap_gb="${8:-$((memory_gb / 2))}"
    local bridge_cidr="${9:-24}"
    local gateway="${10:-192.168.111.1}"
    
    local template_path=$(ensure_ubuntu_template)
    
    pct create $container_id \
        "$template_path" \
        --hostname "$hostname" \
        --memory $((memory_gb * 1024)) \
        --cores $cores \
        --swap $((swap_gb * 1024)) \
        --net0 name=eth0,bridge=vmbr0,ip=${ip_address}/${bridge_cidr},gw=${gateway} \
        --storage "$storage" \
        --rootfs "$storage:${disk_gb}" \
        --unprivileged 0 \
        --features nesting=1 \
        --start 0 >> "$LOG_FILE" 2>&1
    
    if [ $? -ne 0 ]; then
        echo -e "${RED}✗ Failed to create container${NC}"
        echo -e "${YELLOW}Check log: $LOG_FILE${NC}"
        exit 1
    fi
}

# Start LXC container with retry logic
# Usage: start_lxc_container <container_id>
start_lxc_container() {
    local container_id="$1"
    
    pct start $container_id >> "$LOG_FILE" 2>&1
    if [ $? -ne 0 ]; then
        echo -e "${RED}✗ Failed to start container${NC}"
        echo -e "${YELLOW}Check log: $LOG_FILE${NC}"
        exit 1
    fi
    
    # Wait for container to be fully started
    local timeout=30
    local elapsed=0
    while ! pct exec $container_id -- test -f /etc/hostname 2>/dev/null; do
        sleep 1
        elapsed=$((elapsed + 1))
        if [ $elapsed -ge $timeout ]; then
            echo -e "${RED}✗ Container failed to start within ${timeout}s${NC}"
            exit 1
        fi
    done
}

# Set root password for container
# Usage: set_root_password <container_id> <password>
set_root_password() {
    local container_id="$1"
    local password="$2"
    
    echo "root:${password}" | pct exec $container_id -- chpasswd >> "$LOG_FILE" 2>&1
    if [ $? -ne 0 ]; then
        echo -e "${YELLOW}⚠ Failed to set root password${NC}"
    fi
}

# Configure SSH for container
# Usage: configure_ssh <container_id>
configure_ssh() {
    local container_id="$1"
    
    pct exec $container_id -- bash -c "
        sed -i 's/#PermitRootLogin prohibit-password/PermitRootLogin yes/' /etc/ssh/sshd_config
        systemctl restart sshd
    " >> "$LOG_FILE" 2>&1
}

# Display container access information
# Usage: show_container_info <hostname> <ip> <port> [<service_name>]
show_container_info() {
    local hostname="$1"
    local ip="$2"
    local port="$3"
    local service_name="${4:-Web Interface}"
    
    echo ""
    echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${GREEN}Installation Complete!${NC}"
    echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
    echo -e "${CYAN}Container Information:${NC}"
    echo "  Hostname: $hostname"
    echo "  IP Address: $ip"
    echo ""
    echo -e "${CYAN}Access:${NC}"
    echo "  ${service_name}: http://${ip}:${port}"
    echo "  SSH: ssh root@${ip}"
    echo ""
}

