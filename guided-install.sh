
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
declare -A SCRIPT_PATHS
declare -a SCRIPT_COMMANDS

# GPU detection results (set at startup)
HAS_AMD_GPU=false
HAS_NVIDIA_GPU=false

# Function to extract metadata from script header
extract_script_metadata() {
    local script_path="$1"
    local script_command
    script_command=$(basename "$script_path" .sh)
    
    # Read metadata from script header
    local desc
    desc=$(grep '^# SCRIPT_DESC:' "$script_path" 2>/dev/null | sed 's/^# SCRIPT_DESC: //')
    
    # Store in arrays
    SCRIPT_COMMANDS+=("$script_command")
    SCRIPT_DESCRIPTIONS["$script_command"]="$desc"
    SCRIPT_PATHS["$script_command"]="$script_path"
}

# Function to discover and load all scripts
discover_scripts() {
    # Find all scripts in host directory (exclude old numbered scripts and utilities)
    while IFS= read -r script_path; do
        extract_script_metadata "$script_path"
    done < <(find "${SCRIPT_DIR}/host" -maxdepth 1 -name "*.sh" -type f | grep -v "/[0-9]" | sort)
}

# Real-time status check functions (using command names)
check_status_strix-igpu() {
    # Check if Strix Halo iGPU VRAM allocation is configured (amdgpu.gttsize in kernel cmdline)
    if grep -q "amdgpu.gttsize=" /proc/cmdline 2>/dev/null; then
        # Show current allocation
        local gtt_size=$(grep -oP 'amdgpu.gttsize=\K[0-9]+' /proc/cmdline 2>/dev/null)
        local gtt_gb=$((gtt_size / 1024))
        echo "${gtt_gb}GB VRAM"
    else
        echo "NOT CONFIGURED"
    fi
}

check_status_amd-drivers() {
    # Check if AMD ROCm drivers are installed
    if command -v rocm-smi &>/dev/null || [ -d "/opt/rocm" ]; then
        echo "INSTALLED"
    else
        echo "NOT INSTALLED"
    fi
}

check_status_nvidia-drivers() {
    # Check if NVIDIA drivers are installed
    if command -v nvidia-smi &>/dev/null || lsmod | grep -q "^nvidia "; then
        echo "INSTALLED"
    else
        echo "NOT INSTALLED"
    fi
}

check_status_amd-verify() {
    # Comprehensive check: kernel module, ROCm tools, and basic functionality
    if lsmod | grep -q "amdgpu" && \
       command -v rocm-smi &>/dev/null && \
       command -v rocminfo &>/dev/null && \
       [ -e /dev/kfd ]; then
        echo "PASSED"
    else
        echo "NOT VERIFIED"
    fi
}

check_status_nvidia-verify() {
    # Comprehensive check: kernel module and nvidia-smi
    if lsmod | grep -q "^nvidia " && command -v nvidia-smi &>/dev/null; then
        echo "PASSED"
    else
        echo "NOT VERIFIED"
    fi
}

check_status_gpu-udev() {
    # Check if GPU udev rules exist
    if [ -f "/etc/udev/rules.d/99-gpu-passthrough.rules" ]; then
        echo "CONFIGURED"
    else
        echo "NOT CONFIGURED"
    fi
}

check_status_power() {
    # Check if power management services are enabled
    if systemctl is-enabled powertop.service &>/dev/null || \
       systemctl is-enabled autoaspm.service &>/dev/null; then
        echo "ENABLED"
    else
        echo "DISABLED"
    fi
}

check_status_amd-upgrade() {
    # Check if ROCm is installed and check for updates
    if [ -f /etc/apt/sources.list.d/rocm.list ]; then
        local current_version=$(grep -oP 'rocm/apt/\K[0-9]+\.[0-9]+' /etc/apt/sources.list.d/rocm.list | head -1)
        
        if [ -n "$current_version" ]; then
            # Fetch latest version from AMD repository
            local latest_version=$(curl -s https://repo.radeon.com/rocm/apt/ 2>/dev/null | \
                grep -oP 'href="[0-9]+\.[0-9]+/"' | \
                grep -oP '[0-9]+\.[0-9]+' | \
                sort -V | \
                tail -1)
            
            if [ -n "$latest_version" ]; then
                # Compare versions
                if [ "$(printf '%s\n' "$current_version" "$latest_version" | sort -V | tail -1)" = "$latest_version" ] && \
                   [ "$current_version" != "$latest_version" ]; then
                    echo "${latest_version} AVAILABLE"
                else
                    echo "UP TO DATE"
                fi
            else
                # Couldn't fetch, just show current
                echo "v${current_version}"
            fi
        else
            echo "ACTION"
        fi
    else
        echo "NOT INSTALLED"
    fi
}

# Function to check status for a script
get_script_status() {
    local script_command="$1"
    
    # Call appropriate check function if it exists
    if declare -f "check_status_${script_command}" &>/dev/null; then
        "check_status_${script_command}"
    else
        echo ""
    fi
}

# Function to get script description by command
get_script_description() {
    local script_command="$1"
    
    # Try to get from metadata first
    local desc="${SCRIPT_DESCRIPTIONS[$script_command]}"
    
    if [ -n "$desc" ]; then
        echo "$desc"
    else
        echo "Unknown script"
    fi
}

# Function to display script with status
display_script() {
    local script_command="$1"
    
    # Get description and status
    local description
    local status
    description=$(get_script_description "$script_command")
    status=$(get_script_status "$script_command")
    
    # Format status with color (but calculate length without color codes)
    local status_display=""
    local status_plain=""
    if [ -n "$status" ]; then
        status_plain="[$status]"
        case "$status" in
            "INSTALLED"|"CONFIGURED"|"ENABLED"|"PASSED")
                status_display="${GREEN}[$status]${NC}"
                ;;
            "NOT INSTALLED"|"NOT CONFIGURED"|"DISABLED"|"NOT VERIFIED")
                status_display="${YELLOW}[$status]${NC}"
                ;;
            *"GB VRAM")
                # Dynamic VRAM allocation (green = configured)
                status_display="${GREEN}[$status]${NC}"
                ;;
            *"AVAILABLE")
                # Update available (yellow = action recommended)
                status_display="${YELLOW}[$status]${NC}"
                ;;
            "UP TO DATE")
                # No updates needed (green = good)
                status_display="${GREEN}[$status]${NC}"
                ;;
            v*)
                # Version info (cyan = informational)
                status_display="${CYAN}[$status]${NC}"
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
    
    # Calculate padding for right-aligned status
    # Total width: 68 chars (fits standard 80-char terminals with margin)
    local line_width=68
    local prefix_len=$((${#script_command} + 5))  # "  command - "
    local status_len=${#status_plain}
    local desc_max_len=$((line_width - prefix_len - status_len - 1))  # -1 for space before status
    
    # Truncate description if needed
    if [ ${#description} -gt $desc_max_len ]; then
        description="${description:0:$((desc_max_len - 3))}..."
    fi
    
    # Calculate padding
    local padding_len=$((desc_max_len - ${#description}))
    local padding=$(printf "%${padding_len}s" "")
    
    # Display with right-aligned status
    echo -e "  ${CYAN}${script_command}${NC} - ${description}${padding} ${status_display}"
}

# Function to run a script
run_script() {
    local script_command="$1"
    local script_path="${SCRIPT_PATHS[$script_command]}"
    
    if [ -z "$script_path" ]; then
        echo -e "${RED}Error: Unknown command '$script_command'${NC}"
        return 1
    fi
    
    # Clear screen for clean output
    clear
    
    # Determine location context based on command prefix
    local location_tag=""
    local location_desc=""
    if [[ "$script_command" == ollama-* ]] || [[ "$script_command" == comfyui-* ]]; then
        location_tag="${CYAN}[LXC]${NC}"
        location_desc="${CYAN}Location: Creates/manages LXC container${NC}"
    else
        location_tag="${GREEN}[HOST]${NC}"
        location_desc="${CYAN}Location: Proxmox host system (PVE)${NC}"
    fi
    
    echo ""
    echo -e "${GREEN}========================================${NC}"
    echo -e "${GREEN}Running: ${NC}$location_tag ${GREEN}$script_command${NC}"
    echo -e "$location_desc"
    echo -e "${GREEN}========================================${NC}"
    echo ""
    
    if bash "$script_path" < /dev/tty; then
        echo ""
        echo -e "${GREEN}✓ Completed: $script_command${NC}"
        echo ""
        return 0
    else
        echo ""
        echo -e "${RED}✗ Failed: $script_command${NC}"
        echo ""
        return 1
    fi
}

# Function to get host scripts (filtered by GPU type, in proper execution order)
get_host_scripts() {
    local gpu_type="$1"  # "amd" or "nvidia" or "all"
    
    # Detect if Strix Halo is present
    local is_strix_halo=false
    if lspci 2>/dev/null | grep -qi "Strix Halo"; then
        is_strix_halo=true
    fi
    
    # Define execution order (verify scripts excluded - they're diagnostic tools)
    local amd_order=("strix-igpu" "amd-drivers")
    local nvidia_order=("nvidia-drivers")
    local universal_order=("gpu-udev")
    local optional_order=("power" "amd-upgrade")
    
    if [ "$gpu_type" = "amd" ]; then
        for cmd in "${amd_order[@]}"; do
            # Skip strix-igpu if not Strix Halo
            if [[ "$cmd" == "strix-igpu" ]] && [ "$is_strix_halo" = false ]; then
                continue
            fi
            # Only output if script exists
            if [[ " ${SCRIPT_COMMANDS[@]} " =~ " ${cmd} " ]]; then
                echo "$cmd"
            fi
        done
    elif [ "$gpu_type" = "nvidia" ]; then
        for cmd in "${nvidia_order[@]}"; do
            if [[ " ${SCRIPT_COMMANDS[@]} " =~ " ${cmd} " ]]; then
                echo "$cmd"
            fi
        done
    elif [ "$gpu_type" = "universal" ]; then
        for cmd in "${universal_order[@]}"; do
            if [[ " ${SCRIPT_COMMANDS[@]} " =~ " ${cmd} " ]]; then
                echo "$cmd"
            fi
        done
    elif [ "$gpu_type" = "optional" ]; then
        for cmd in "${optional_order[@]}"; do
            if [[ " ${SCRIPT_COMMANDS[@]} " =~ " ${cmd} " ]]; then
                echo "$cmd"
            fi
        done
    fi
}

# Function to get LXC scripts (filtered by GPU type)
get_lxc_scripts() {
    local gpu_type="$1"  # "amd" or "nvidia" or "all"
    
    for command in "${SCRIPT_COMMANDS[@]}"; do
        # Only LXC scripts
        if [[ "$command" == ollama-* ]] || [[ "$command" == comfyui-* ]]; then
            if [ "$gpu_type" = "amd" ] && [[ "$command" == *-amd ]]; then
                echo "$command"
            elif [ "$gpu_type" = "nvidia" ] && [[ "$command" == *-nvidia ]]; then
                echo "$command"
            elif [ "$gpu_type" = "all" ]; then
                echo "$command"
            fi
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
    echo -e "${GREEN}╔══════════════════════════════════════╗${NC}"
    echo -e "${GREEN}║  Proxmox Setup - Guided Installer    ║${NC}"
    echo -e "${GREEN}╚══════════════════════════════════════╝${NC}"
    echo ""
    
    # Show detected GPU info
    if [ "$HAS_AMD_GPU" = true ] || [ "$HAS_NVIDIA_GPU" = true ]; then
        echo -e "${CYAN}Detected GPUs:${NC}"
        [ "$HAS_AMD_GPU" = true ] && echo -e "  ${GREEN}✓${NC} AMD GPU detected"
        [ "$HAS_NVIDIA_GPU" = true ] && echo -e "  ${GREEN}✓${NC} NVIDIA GPU detected"
        echo ""
    fi
    
    echo -e "${GREEN}═══ GPU SETUP ═══${NC}"
    echo ""
    
    # Show AMD host scripts (in logical order for display)
    if [ "$HAS_AMD_GPU" = true ]; then
        # Setup scripts
        for cmd in strix-igpu amd-drivers; do
            [[ " ${SCRIPT_COMMANDS[@]} " =~ " ${cmd} " ]] && display_script "$cmd"
        done
    fi
    
    # Show NVIDIA host scripts
    if [ "$HAS_NVIDIA_GPU" = true ]; then
        [[ " ${SCRIPT_COMMANDS[@]} " =~ " nvidia-drivers " ]] && display_script "nvidia-drivers"
    fi
    
    # Show universal host scripts (gpu-udev)
    for cmd in gpu-udev; do
        [[ " ${SCRIPT_COMMANDS[@]} " =~ " ${cmd} " ]] && display_script "$cmd"
    done
    
    # Show verify scripts separately (not part of "setup")
    echo ""
    echo -e "${GREEN}═══ VERIFICATION ═══${NC}"
    echo ""
    if [ "$HAS_AMD_GPU" = true ]; then
        [[ " ${SCRIPT_COMMANDS[@]} " =~ " amd-verify " ]] && display_script "amd-verify"
    fi
    if [ "$HAS_NVIDIA_GPU" = true ]; then
        [[ " ${SCRIPT_COMMANDS[@]} " =~ " nvidia-verify " ]] && display_script "nvidia-verify"
    fi
    
    # Show optional scripts
    echo ""
    echo -e "${GREEN}═══ OPTIONAL ═══${NC}"
    echo ""
    for cmd in power; do
        [[ " ${SCRIPT_COMMANDS[@]} " =~ " ${cmd} " ]] && display_script "$cmd"
    done
    # AMD-specific optional scripts
    if [ "$HAS_AMD_GPU" = true ]; then
        for cmd in amd-upgrade; do
            [[ " ${SCRIPT_COMMANDS[@]} " =~ " ${cmd} " ]] && display_script "$cmd"
        done
    fi
    
    echo ""
    echo -e "${GREEN}═══ LXC CONTAINERS ═══${NC}"
    echo ""
    
    # Show LXC scripts based on detected GPU
    local lxc_scripts_shown=false
    if [ "$HAS_AMD_GPU" = true ]; then
        for cmd in $(get_lxc_scripts "amd"); do
            display_script "$cmd"
            lxc_scripts_shown=true
        done
    fi
    
    if [ "$HAS_NVIDIA_GPU" = true ]; then
        for cmd in $(get_lxc_scripts "nvidia"); do
            display_script "$cmd"
            lxc_scripts_shown=true
        done
    fi
    
    if [ "$lxc_scripts_shown" = false ]; then
        echo -e "  ${YELLOW}No GPU detected - LXC creation unavailable${NC}"
    fi
    
    echo ""
    echo -e "${YELLOW}Commands:${NC}"
    echo "  setup           - Run all GPU Setup scripts (reboot + verify after)"
    echo "  <command>       - Run specific script (e.g., strix-igpu, ollama-amd)"
    echo "  [u]pdate        - Update scripts from GitHub"
    echo "  [i]nfo          - Show system information"
    echo "  [q]uit          - Exit"
    echo ""
}

# Function to show detailed system information
show_system_info() {
    clear
    echo -e "${GREEN}╔══════════════════════════════════════╗${NC}"
    echo -e "${GREEN}║        System Information            ║${NC}"
    echo -e "${GREEN}╚══════════════════════════════════════╝${NC}"
    echo ""
    
    # GPU Information
    echo -e "${CYAN}═══ GPU INFORMATION ═══${NC}"
    if [ "$HAS_AMD_GPU" = true ]; then
        echo -e "${GREEN}AMD GPU:${NC}"
        lspci | grep -i "VGA.*AMD\|Display.*AMD" | sed 's/^/  /'
        if command -v rocm-smi &>/dev/null || [ -d "/opt/rocm" ]; then
            echo ""
            echo -e "${GREEN}ROCm:${NC}"
            if [ -f "/opt/rocm/.info/version" ]; then
                echo -e "  Version: $(cat /opt/rocm/.info/version)"
            else
                rocm-smi --version 2>/dev/null | grep -i "ROCM-SMI-LIB version" | sed 's/ROCM-SMI-LIB version: /  Version: /' || echo "  Not detected"
            fi
        fi
    fi
    if [ "$HAS_NVIDIA_GPU" = true ]; then
        echo ""
        echo -e "${GREEN}NVIDIA GPU:${NC}"
        lspci | grep -i "VGA.*NVIDIA\|3D.*NVIDIA" | sed 's/^/  /'
        if command -v nvidia-smi &>/dev/null; then
            echo ""
            echo -e "${GREEN}CUDA:${NC}"
            nvidia-smi --query-gpu=driver_version --format=csv,noheader 2>/dev/null | sed 's/^/  Driver: /' || echo "  Not detected"
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
    local script_command="$1"
    
    # Clear screen for clean presentation
    clear
    
    # Get description and status
    local description status
    description=$(get_script_description "$script_command")
    status=$(get_script_status "$script_command")
    
    # Show status info
    local status_msg=""
    if [ -n "$status" ]; then
        status_msg=" ${CYAN}[Current: $status]${NC}"
    fi
    
    echo ""
    echo -e "${GREEN}──────────────────────────────────────${NC}"
    echo -e "${GREEN}[$script_command] $description${NC}${status_msg}"
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
    
    read -r -p "Enter your choice [setup]: " choice
    choice=${choice:-setup}  # Default to "setup"
    choice=${choice,,}  # Convert to lowercase
    
    case "$choice" in
        "setup"|"all")  # Accept both "setup" and legacy "all"
            echo ""
            echo -e "${GREEN}========================================${NC}"
            echo -e "${GREEN}Running GPU Setup scripts...${NC}"
            echo -e "${GREEN}========================================${NC}"
            echo ""
            echo -e "${YELLOW}You will be asked before each script runs.${NC}"
            echo -e "${YELLOW}Press 'y' to run, 'n' to skip, or 'q' to return to main menu.${NC}"
            echo ""
            
            quit_requested=false
            reboot_needed=false
            scripts_run=0
            
            # Run all AMD host scripts
            if [ "$HAS_AMD_GPU" = true ]; then
                for cmd in $(get_host_scripts "amd"); do
                    confirm_run_with_info "$cmd"
                    result=$?
                    
                    if [ $result -eq 2 ]; then
                        quit_requested=true
                        break
                    elif [ $result -eq 0 ]; then
                        if run_script "$cmd"; then
                            ((scripts_run++))
                            # Scripts that require reboot
                            if [[ "$cmd" == "strix-igpu" ]] || [[ "$cmd" == "amd-drivers" ]]; then
                                reboot_needed=true
                            fi
                        else
                            read -r -p "Script failed. Continue? [y/N]: " continue_choice < /dev/tty
                            [[ ! "$continue_choice" =~ ^[Yy]$ ]] && break
                        fi
                    fi
                done
            fi
            
            # Run all NVIDIA host scripts
            if [ "$quit_requested" = false ] && [ "$HAS_NVIDIA_GPU" = true ]; then
                for cmd in $(get_host_scripts "nvidia"); do
                    confirm_run_with_info "$cmd"
                    result=$?
                    
                    if [ $result -eq 2 ]; then
                        quit_requested=true
                        break
                    elif [ $result -eq 0 ]; then
                        if run_script "$cmd"; then
                            ((scripts_run++))
                            # nvidia-drivers requires reboot
                            if [[ "$cmd" == "nvidia-drivers" ]]; then
                                reboot_needed=true
                            fi
                        else
                            read -r -p "Script failed. Continue? [y/N]: " continue_choice < /dev/tty
                            [[ ! "$continue_choice" =~ ^[Yy]$ ]] && break
                        fi
                    fi
                done
            fi
            
            # Run universal host scripts
            if [ "$quit_requested" = false ]; then
                for cmd in $(get_host_scripts "universal"); do
                    confirm_run_with_info "$cmd"
                    result=$?
                    
                    if [ $result -eq 2 ]; then
                        quit_requested=true
                        break
                    elif [ $result -eq 0 ]; then
                        if run_script "$cmd"; then
                            ((scripts_run++))
                        else
                            read -r -p "Script failed. Continue? [y/N]: " continue_choice < /dev/tty
                            [[ ! "$continue_choice" =~ ^[Yy]$ ]] && break
                        fi
                    fi
                done
            fi
            
            if [ "$quit_requested" = false ]; then
                echo ""
                echo -e "${GREEN}========================================${NC}"
                echo -e "${GREEN}GPU Setup completed!${NC}"
                echo -e "${GREEN}========================================${NC}"
                echo ""
                
                if [ "$scripts_run" -eq 0 ]; then
                    echo -e "${CYAN}No scripts were run (all skipped or already configured)${NC}"
                    echo ""
                elif [ "$reboot_needed" = true ]; then
                    echo -e "${YELLOW}⚠  IMPORTANT NEXT STEPS:${NC}"
                    echo -e "${CYAN}1.${NC} ${BOLD}Reboot your system${NC} (kernel parameters/drivers changed)"
                    echo -e "${CYAN}2.${NC} After reboot, run verification:"
                    if [ "$HAS_AMD_GPU" = true ]; then
                        echo -e "   ${BOLD}amd-verify${NC} - Comprehensive verification"
                    fi
                    if [ "$HAS_NVIDIA_GPU" = true ]; then
                        echo -e "   ${BOLD}nvidia-verify${NC} - Comprehensive verification"
                    fi
                    echo ""
                else
                    echo -e "${GREEN}✓ All changes applied successfully!${NC}"
                    echo -e "${CYAN}Note:${NC} You can run verification anytime:"
                    if [ "$HAS_AMD_GPU" = true ]; then
                        echo -e "   ${BOLD}amd-verify${NC} - Comprehensive verification"
                    fi
                    if [ "$HAS_NVIDIA_GPU" = true ]; then
                        echo -e "   ${BOLD}nvidia-verify${NC} - Comprehensive verification"
                    fi
                    echo ""
                fi
                
                read -r -p "Press Enter to continue..." < /dev/tty
            fi
            ;;
            
        "u"|"update")
            clear
            # Run the update script
            if [ -f "${SCRIPT_DIR}/update" ]; then
                exec bash "${SCRIPT_DIR}/update"
            else
                echo -e "${RED}Update script not found${NC}"
                read -r -p "Press Enter to continue..." < /dev/tty
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
            # Try to run as a command
            if [ -n "${SCRIPT_PATHS[$choice]}" ]; then
                run_script "$choice"
                read -r -p "Press Enter to continue..." < /dev/tty
            else
                echo -e "${RED}Invalid choice: $choice${NC}"
                echo -e "${YELLOW}Valid commands: ${CYAN}$(echo "${SCRIPT_COMMANDS[@]}" | tr ' ' ', ')${NC}"
                read -r -p "Press Enter to continue..." < /dev/tty
            fi
            ;;
    esac
done
