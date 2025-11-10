
#!/usr/bin/env bash

# Guided installation script for Proxmox GPU setup
# This script provides an interactive menu to run setup scripts in order
# Status checks are performed in real-time against actual system state

# Note: NOT using set -e because we need to handle return codes from functions
# set -e

# Get script directory and source colors
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=includes/colors.sh
source "${SCRIPT_DIR}/includes/colors.sh"

# Associative arrays to store script metadata
declare -A SCRIPT_DESCRIPTIONS
declare -A SCRIPT_STATUS
declare -a SCRIPT_NUMS

# GPU detection results (set at startup)
HAS_AMD_GPU=false
HAS_NVIDIA_GPU=false

# Function to extract metadata from script header
extract_script_metadata() {
    local script_path="$1"
    local script_num
    script_num=$(basename "$script_path" | grep -oP '^\d+')
    
    # Read metadata from script header
    local desc
    desc=$(grep '^# SCRIPT_DESC:' "$script_path" 2>/dev/null | sed 's/^# SCRIPT_DESC: //')
    
    # Store in arrays
    SCRIPT_NUMS+=("$script_num")
    SCRIPT_DESCRIPTIONS["$script_num"]="$desc"
}

# Function to discover and load all scripts
discover_scripts() {
    # Find all scripts in host directory
    while IFS= read -r script_path; do
        extract_script_metadata "$script_path"
    done < <(find "${SCRIPT_DIR}/host" -maxdepth 1 -name "[0-9][0-9][0-9] - *.sh" -type f | sort)
    
    # Sort script numbers (suppress shellcheck warning - we need numeric sort)
    # shellcheck disable=SC2207
    IFS=$'\n' SCRIPT_NUMS=($(printf '%s\n' "${SCRIPT_NUMS[@]}" | sort -n))
    unset IFS
}

# Real-time status check functions
check_status_000() {
    # list-gpus is always available (view-only)
    echo "INFO"
}

check_status_001() {
    # Check if essential tools are installed
    if command -v curl &>/dev/null && command -v wget &>/dev/null && \
       command -v git &>/dev/null && command -v nano &>/dev/null; then
        echo "INSTALLED"
    else
        echo "NOT INSTALLED"
    fi
}

check_status_002() {
    # Check if AMD iGPU VRAM allocation is configured (amdgpu.gttsize in GRUB)
    if grep -q "amdgpu.gttsize=" /etc/default/grub 2>/dev/null; then
        echo "ENABLED"
    else
        echo "NOT ENABLED"
    fi
}

check_status_003() {
    # Check if AMD ROCm drivers are installed
    if command -v rocm-smi &>/dev/null || [ -d "/opt/rocm" ]; then
        echo "INSTALLED"
    else
        echo "NOT INSTALLED"
    fi
}

check_status_004() {
    # Check if NVIDIA drivers are installed
    if command -v nvidia-smi &>/dev/null || lsmod | grep -q "^nvidia "; then
        echo "INSTALLED"
    else
        echo "NOT INSTALLED"
    fi
}

check_status_005() {
    # Check if AMD drivers are verified/loaded
    if lsmod | grep -q "amdgpu"; then
        echo "LOADED"
    else
        echo "NOT LOADED"
    fi
}

check_status_006() {
    # Check if NVIDIA drivers are verified/loaded
    if lsmod | grep -q "^nvidia "; then
        echo "LOADED"
    else
        echo "NOT LOADED"
    fi
}

check_status_007() {
    # Check if GPU udev rules exist
    if [ -f "/etc/udev/rules.d/99-gpu-passthrough.rules" ]; then
        echo "CONFIGURED"
    else
        echo "NOT CONFIGURED"
    fi
}

check_status_008() {
    # Check if power management services are enabled
    if systemctl is-enabled powertop.service &>/dev/null || \
       systemctl is-enabled autoaspm.service &>/dev/null; then
        echo "ENABLED"
    else
        echo "DISABLED"
    fi
}

check_status_999() {
    echo "ACTION"
}

# Function to check status for a script
get_script_status() {
    local script_num="$1"
    
    # Call appropriate check function if it exists
    if declare -f "check_status_${script_num}" &>/dev/null; then
        "check_status_${script_num}"
    else
        echo ""
    fi
}

# Function to get script description by number
get_script_description() {
    local script_num="$1"
    
    # Try to get from metadata first
    local desc="${SCRIPT_DESCRIPTIONS[$script_num]}"
    
    if [ -n "$desc" ]; then
        echo "$desc"
    else
        # Fallback to script filename
        local script_path
        script_path=$(find "${SCRIPT_DIR}/host" -maxdepth 1 -name "${script_num} - *.sh" -type f)
        if [ -n "$script_path" ]; then
            basename "$script_path" | sed 's/^[0-9]\+ - //' | sed 's/\.sh$//'
        else
            echo "Unknown script"
        fi
    fi
}

# Function to display script with status
display_script() {
    local script_path="$1"
    local script_num
    script_num=$(basename "$script_path" | grep -oP '^\d+')
    
    # Get description and status
    local description
    local status
    description=$(get_script_description "$script_num")
    status=$(get_script_status "$script_num")
    
    # Truncate description if too long
    if [ ${#description} -gt 60 ]; then
        description="${description:0:57}..."
    fi
    
    # Format status with color
    local status_display=""
    if [ -n "$status" ]; then
        case "$status" in
            "INSTALLED"|"ENABLED"|"CONFIGURED"|"UP TO DATE")
                status_display="${GREEN}[$status]${NC}"
                ;;
            "NOT INSTALLED"|"NOT ENABLED"|"DEFAULT")
                status_display="${YELLOW}[$status]${NC}"
                ;;
            *" UPDATES")
                status_display="${CYAN}[$status]${NC}"
                ;;
            "INFO"|"ACTION")
                status_display="${DIM}[$status]${NC}"
                ;;
            *)
                status_display="${CYAN}[$status]${NC}"
                ;;
        esac
    fi
    
    # Use echo -e to properly render colors, with padding
    echo -e "  ${BOLD}${script_num}${NC} - ${description} ${status_display}"
}

# Function to run a script
run_script() {
    local script_path="$1"
    local script_num
    local script_name
    script_num=$(basename "$script_path" | grep -oP '^\d+')
    script_name=$(basename "$script_path")
    
    # Determine location context
    local location_tag=""
    local location_desc=""
    if [ "$script_num" -ge 1 ] && [ "$script_num" -le 9 ]; then
        location_tag="${GREEN}[HOST]${NC}"
        location_desc="${CYAN}Location: Proxmox host system (PVE)${NC}"
    elif [ "$script_num" -ge 30 ] && [ "$script_num" -le 99 ]; then
        location_tag="${CYAN}[LXC]${NC}"
        location_desc="${CYAN}Location: Creates/manages LXC container${NC}"
    else
        location_tag="${YELLOW}[UTILITY]${NC}"
        location_desc="${CYAN}Location: Proxmox host system${NC}"
    fi
    
    echo ""
    echo -e "${GREEN}========================================${NC}"
    echo -e "${GREEN}Running: ${NC}$location_tag ${GREEN}$script_name${NC}"
    echo -e "$location_desc"
    echo -e "${GREEN}========================================${NC}"
    echo ""
    
    if bash "$script_path" < /dev/tty; then
        echo ""
        echo -e "${GREEN}✓ Completed: $script_name${NC}"
        echo ""
        return 0
    else
        echo ""
        echo -e "${RED}✗ Failed: $script_name${NC}"
        echo ""
        return 1
    fi
}

# Function to get available scripts in a numeric range
get_scripts_in_range() {
    local start="$1"
    local end="$2"
    
    # Filter scripts by numeric range
    for num in "${SCRIPT_NUMS[@]}"; do
        if [ "$num" -ge "$start" ] && [ "$num" -le "$end" ]; then
            # Find the actual script file
            find "${SCRIPT_DIR}/host" -maxdepth 1 -name "${num} - *.sh" -type f
        fi
    done | sort
}

# Detect GPUs at startup
detect_gpus() {
    # Load GPU detection functions
    # shellcheck source=includes/gpu-detect.sh
    source "${SCRIPT_DIR}/includes/gpu-detect.sh"
    
    # Detect AMD GPUs
    if detect_amd_gpus >/dev/null 2>&1; then
        HAS_AMD_GPU=true
    fi
    
    # Detect NVIDIA GPUs
    if detect_nvidia_gpus >/dev/null 2>&1; then
        HAS_NVIDIA_GPU=true
    fi
}

# Main menu
show_main_menu() {
    clear
    echo -e "${GREEN}╔════════════════════════════════════════╗${NC}"
    echo -e "${GREEN}║  Proxmox Setup - Guided Installer     ║${NC}"
    echo -e "${GREEN}╚════════════════════════════════════════╝${NC}"
    echo ""
    
    # Show detected GPU info
    if [ "$HAS_AMD_GPU" = true ] || [ "$HAS_NVIDIA_GPU" = true ]; then
        echo -e "${CYAN}Detected GPUs:${NC}"
        [ "$HAS_AMD_GPU" = true ] && echo -e "  ${GREEN}✓${NC} AMD GPU detected"
        [ "$HAS_NVIDIA_GPU" = true ] && echo -e "  ${GREEN}✓${NC} NVIDIA GPU detected"
        echo ""
    fi
    
    echo -e "${GREEN}═══ HOST CONFIGURATION ═══${NC}"
    echo ""
    
    # List host setup scripts (001-008), filtering by GPU
    while IFS= read -r script; do
        local script_num
        script_num=$(basename "$script" | grep -oP '^\d+')
        
        # Skip script 000 (GPU list - redundant, shown at top)
        [ "$script_num" = "000" ] && continue
        
        # Filter GPU-specific scripts
        case "$script_num" in
            002|003|005)
                # AMD-specific scripts
                [ "$HAS_AMD_GPU" = true ] && display_script "$script"
                ;;
            004|006)
                # NVIDIA-specific scripts
                [ "$HAS_NVIDIA_GPU" = true ] && display_script "$script"
                ;;
            *)
                # Universal scripts (001, 007, 008)
                display_script "$script"
                ;;
        esac
    done < <(get_scripts_in_range 0 8)
    
    echo ""
    echo -e "${GREEN}═══ LXC CONTAINERS ═══${NC}"
    echo ""
    
    # Show LXC scripts based on detected GPU
    local lxc_scripts_shown=false
    if [ "$HAS_AMD_GPU" = true ]; then
        while IFS= read -r script; do
            display_script "$script"
            lxc_scripts_shown=true
        done < <(get_scripts_in_range 30 39)
    fi
    
    if [ "$HAS_NVIDIA_GPU" = true ]; then
        while IFS= read -r script; do
            display_script "$script"
            lxc_scripts_shown=true
        done < <(get_scripts_in_range 40 49)
    fi
    
    if [ "$lxc_scripts_shown" = false ]; then
        echo -e "  ${YELLOW}No GPU detected - LXC creation unavailable${NC}"
        echo -e "  ${GRAY}Run script 004 to detect GPUs${NC}"
    fi
    
    echo ""
    echo -e "${GREEN}═══ UTILITIES ═══${NC}"
    echo ""
    
    # List utility scripts (999)
    while IFS= read -r script; do
        display_script "$script"
    done < <(get_scripts_in_range 999 999)
    
    echo ""
    echo -e "${YELLOW}Commands:${NC}"
    echo "  all          - Run all Host Configuration scripts with confirmations"
    echo "  <number>     - Run specific script by number (e.g., 1, 30, 999)"
    echo "  i/info       - Show detailed system information"
    echo "  q/quit       - Exit installer"
    echo ""
}

# Function to show detailed system information
show_system_info() {
    clear
    echo -e "${GREEN}╔════════════════════════════════════════╗${NC}"
    echo -e "${GREEN}║      System Information                ║${NC}"
    echo -e "${GREEN}╚════════════════════════════════════════╝${NC}"
    echo ""
    
    # GPU Information
    echo -e "${CYAN}═══ GPU INFORMATION ═══${NC}"
    if [ "$HAS_AMD_GPU" = true ]; then
        echo -e "${GREEN}AMD GPU:${NC}"
        lspci | grep -i "VGA.*AMD\|Display.*AMD" | sed 's/^/  /'
        if command -v rocm-smi &>/dev/null; then
            echo -e "\n${DIM}ROCm Version:${NC}"
            rocm-smi --version 2>/dev/null | grep "ROCm" | sed 's/^/  /' || echo "  Not available"
        fi
    fi
    if [ "$HAS_NVIDIA_GPU" = true ]; then
        echo -e "${GREEN}NVIDIA GPU:${NC}"
        lspci | grep -i "VGA.*NVIDIA\|3D.*NVIDIA" | sed 's/^/  /'
        if command -v nvidia-smi &>/dev/null; then
            echo -e "\n${DIM}Driver Version:${NC}"
            nvidia-smi --query-gpu=driver_version --format=csv,noheader 2>/dev/null | sed 's/^/  /' || echo "  Not available"
        fi
    fi
    echo ""
    
    # System Resources
    echo -e "${CYAN}═══ SYSTEM RESOURCES ═══${NC}"
    echo -e "${GREEN}CPU:${NC}"
    lscpu | grep "Model name" | sed 's/Model name: */  /'
    echo -e "${GREEN}Cores:${NC} $(nproc) cores"
    
    echo -e "${GREEN}Memory:${NC}"
    free -h | awk '/^Mem:/ {printf "  Total: %s  |  Used: %s  |  Free: %s\n", $2, $3, $4}'
    
    echo -e "${GREEN}Storage:${NC}"
    df -h / | awk 'NR==2 {printf "  Root: %s total, %s used, %s free (%s used)\n", $2, $3, $4, $5}'
    echo ""
    
    # LXC Containers
    echo -e "${CYAN}═══ LXC CONTAINERS ═══${NC}"
    local container_count
    container_count=$(pct list 2>/dev/null | tail -n +2 | wc -l)
    if [ "$container_count" -gt 0 ]; then
        echo -e "${GREEN}Running Containers:${NC}"
        pct list | tail -n +2 | awk '{printf "  [%s] %s - %s\n", $1, $3, $2}'
    else
        echo -e "${DIM}  No containers found${NC}"
    fi
    echo ""
    
    # Network
    echo -e "${CYAN}═══ NETWORK ═══${NC}"
    ip -br addr show | grep -v "^lo" | awk '{printf "  %s: %s\n", $1, $3}'
    echo ""
    
    read -r -p "Press Enter to return to main menu..." < /dev/tty
}

# Function to prompt user before running script with detailed info
confirm_run_with_info() {
    local script_path="$1"
    local script_num
    script_num=$(basename "$script_path" | grep -oP '^\d+')
    
    # Get description and status
    local description status
    description=$(get_script_description "$script_num")
    status=$(get_script_status "$script_num")
    
    # Show status info
    local status_msg=""
    if [ -n "$status" ]; then
        status_msg=" ${CYAN}[Current: $status]${NC}"
    fi
    
    echo ""
    echo -e "${GREEN}──────────────────────────────────────${NC}"
    echo -e "${GREEN}[$script_num] $description${NC}${status_msg}"
    echo -e "${GREEN}──────────────────────────────────────${NC}"
    read -r -p "Run this script? [Y/n/q]: " choice < /dev/tty
    choice=${choice:-Y}
    echo ""  # Add blank line after input
    
    case "$choice" in
        [Qq]|[Qq][Uu][Ii][Tt])
            return 2  # Special return code for quit
            ;;
        [Yy]|[Yy][Ee][Ss])
            return 0  # Run the script
            ;;
        *)
            return 1  # Skip the script
            ;;
    esac
}

# Initialize: discover all scripts and detect GPUs
discover_scripts
detect_gpus

# Main loop
while true; do
    show_main_menu
    
    read -r -p "Enter your choice [all]: " choice
    choice=${choice:-all}  # Default to "all"
    choice=${choice,,}  # Convert to lowercase
    
    case "$choice" in
        "all")
            echo ""
            echo -e "${GREEN}========================================${NC}"
            echo -e "${GREEN}Running all Host Configuration scripts...${NC}"
            echo -e "${GREEN}========================================${NC}"
            echo ""
            echo -e "${YELLOW}You will be asked before each script runs.${NC}"
            echo -e "${YELLOW}Press 'y' to run, 'n' to skip, or 'q' to return to main menu.${NC}"
            echo ""
            
            quit_requested=false
            while IFS= read -r script; do
                local script_num
                script_num=$(basename "$script" | grep -oP '^\d+')
                
                # Skip script 000 (GPU list - redundant)
                if [ "$script_num" = "000" ]; then
                    continue
                fi
                
                # Filter GPU-specific scripts (skip if hardware not present)
                case "$script_num" in
                    002|003|005)
                        # AMD-specific scripts
                        if [ "$HAS_AMD_GPU" = false ]; then
                            echo -e "${DIM}Skipping $(basename "$script") - No AMD GPU detected${NC}"
                            sleep 0.3
                            continue
                        fi
                        ;;
                    004|006)
                        # NVIDIA-specific scripts
                        if [ "$HAS_NVIDIA_GPU" = false ]; then
                            echo -e "${DIM}Skipping $(basename "$script") - No NVIDIA GPU detected${NC}"
                            sleep 0.3
                            continue
                        fi
                        ;;
                esac
                
                # Always ask user with detailed information
                confirm_run_with_info "$script"
                result=$?
                
                if [ $result -eq 2 ]; then
                    # User chose to quit back to main menu
                    echo -e "${YELLOW}Returning to main menu...${NC}"
                    quit_requested=true
                    break
                elif [ $result -eq 0 ]; then
                    # User chose to run the script
                    if ! run_script "$script"; then
                        echo ""
                        read -r -p "Script failed. Continue with next script? [y/N]: " continue_choice < /dev/tty
                        continue_choice=${continue_choice:-N}
                        if [[ ! "$continue_choice" =~ ^[Yy]$ ]]; then
                            break
                        fi
                    fi
                    # Small delay to ensure clean terminal state
                    sleep 0.5
                else
                    # User chose to skip
                    echo -e "${YELLOW}Skipped by user: $(basename "$script")${NC}"
                    # Small delay to ensure clean terminal state
                    sleep 0.5
                fi
            done < <(get_scripts_in_range 0 8)
            
            if [ "$quit_requested" = false ]; then
                echo ""
                echo -e "${GREEN}========================================${NC}"
                echo -e "${GREEN}Host Configuration process completed!${NC}"
                echo -e "${GREEN}========================================${NC}"
                read -r -p "Press Enter to continue..." < /dev/tty
            fi
            ;;
            
        [0-9]|[0-9][0-9]|[0-9][0-9][0-9])
            # Run specific script - pad to 3 digits
            padded_choice=$(printf "%03d" "$choice" 2>/dev/null)
            
            if [ -z "$padded_choice" ]; then
                echo -e "${RED}Invalid script number: $choice${NC}"
                read -r -p "Press Enter to continue..."
            else
                script_path=$(find "${SCRIPT_DIR}/host" -maxdepth 1 -name "${padded_choice} - *.sh" -type f)
                
                if [ -z "$script_path" ]; then
                    echo -e "${RED}Script $padded_choice not found!${NC}"
                    read -r -p "Press Enter to continue..."
                else
                    run_script "$script_path"
                    read -r -p "Press Enter to continue..."
                fi
            fi
            ;;
            
        "i"|"info")
            show_system_info
            ;;
            
        "q"|"quit")
            echo ""
            echo -e "${GREEN}Thank you for using Proxmox Setup Scripts${NC}"
            echo ""
            exit 0
            ;;
            
        *)
            echo -e "${RED}Invalid choice!${NC}"
            read -r -p "Press Enter to continue..."
            ;;
    esac
done
