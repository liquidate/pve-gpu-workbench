
#!/usr/bin/env bash

# Guided installation script for Proxmox GPU setup
# This script provides an interactive menu to run setup scripts in order
# Status checks are performed in real-time against actual system state

# Note: NOT using set -e because we need to handle return codes from functions
# set -e

# Get script directory and source colors (resolve symlinks)
SCRIPT_PATH="${BASH_SOURCE[0]}"
while [ -L "$SCRIPT_PATH" ]; do
    SCRIPT_DIR="$(cd -P "$(dirname "$SCRIPT_PATH")" && pwd)"
    SCRIPT_PATH="$(readlink "$SCRIPT_PATH")"
    [[ $SCRIPT_PATH != /* ]] && SCRIPT_PATH="$SCRIPT_DIR/$SCRIPT_PATH"
done
SCRIPT_DIR="$(cd -P "$(dirname "$SCRIPT_PATH")" && pwd)"
# shellcheck source=includes/colors.sh
source "${SCRIPT_DIR}/includes/colors.sh"

# Associative arrays to store script metadata
declare -A SCRIPT_DESCRIPTIONS
declare -A SCRIPT_CATEGORIES
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
    local desc category
    desc=$(grep '^# SCRIPT_DESC:' "$script_path" 2>/dev/null | sed 's/^# SCRIPT_DESC: //')
    category=$(grep '^# SCRIPT_CATEGORY:' "$script_path" 2>/dev/null | sed 's/^# SCRIPT_CATEGORY: //' | xargs)
    
    # Store in arrays
    SCRIPT_COMMANDS+=("$script_command")
    SCRIPT_DESCRIPTIONS["$script_command"]="$desc"
    SCRIPT_CATEGORIES["$script_command"]="${category:-uncategorized}"
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
check_status_amd-strix-igpu() {
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

check_status_ollama-amd() {
    # Check if Ollama AMD container exists
    if pct list 2>/dev/null | tail -n +2 | awk '{print $3}' | grep -q "^ollama-amd"; then
        local count=$(pct list 2>/dev/null | tail -n +2 | awk '{print $3}' | grep -c "^ollama-amd")
        if [ "$count" -eq 1 ]; then
            echo "INSTALLED"
        else
            echo "${count} CONTAINERS"
        fi
    else
        echo "ACTION"
    fi
}

check_status_ollama-nvidia() {
    # Check if Ollama NVIDIA container exists
    if pct list 2>/dev/null | tail -n +2 | awk '{print $3}' | grep -q "^ollama-nvidia"; then
        local count=$(pct list 2>/dev/null | tail -n +2 | awk '{print $3}' | grep -c "^ollama-nvidia")
        if [ "$count" -eq 1 ]; then
            echo "INSTALLED"
        else
            echo "${count} CONTAINERS"
        fi
    else
        echo "ACTION"
    fi
}

check_status_openwebui() {
    # Check if Open WebUI container exists
    if pct list 2>/dev/null | tail -n +2 | awk '{print $3}' | grep -q "^openwebui"; then
        # Found at least one openwebui container
        local count=$(pct list 2>/dev/null | tail -n +2 | awk '{print $3}' | grep -c "^openwebui")
        if [ "$count" -eq 1 ]; then
            echo "INSTALLED"
        else
            echo "${count} CONTAINERS"
        fi
    else
        echo "ACTION"
    fi
}

check_status_nvidia-upgrade() {
    # Check if NVIDIA driver is installed - try nvidia-smi first, then dpkg
    if command -v nvidia-smi &>/dev/null; then
        local driver_version=$(nvidia-smi --query-gpu=driver_version --format=csv,noheader 2>/dev/null | head -1)
        if [ -n "$driver_version" ]; then
            # Extract major version (e.g., 580.105.08 -> 580)
            local major_version=$(echo "$driver_version" | cut -d'.' -f1)
            echo "v${major_version}"
            return
        fi
    fi
    
    # Fallback: check for old-style nvidia-driver-XXX packages
    local installed_version=$(dpkg -l 2>/dev/null | grep -oP 'nvidia-driver-\K[0-9]+' | head -1)
    
    if [ -n "$installed_version" ]; then
        echo "v${installed_version}"
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

# Function to display script with status (old style, kept for compatibility)
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
    # Total width: 75 chars (safe for Proxmox web UI / noVNC)
    local line_width=75
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

# Function to display numbered menu item with status
display_numbered_script() {
    local number="$1"
    local script_command="$2"
    
    # Get description and status
    local description
    local status
    description=$(get_script_description "$script_command")
    status=$(get_script_status "$script_command")
    
    # Format status with color
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
                status_display="${GREEN}[$status]${NC}"
                ;;
            *"AVAILABLE")
                status_display="${YELLOW}[$status]${NC}"
                ;;
            "UP TO DATE")
                status_display="${GREEN}[$status]${NC}"
                ;;
            v*)
                status_display="${CYAN}[$status]${NC}"
                ;;
            *" UPDATES"|*"CONTAINERS")
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
    # Format: "  N  command-name    - Description...           [STATUS]"
    # Total width: 78 chars for full descriptions, command padded to 15 chars
    local total_width=78
    local cmd_width=15
    local number_str=$(printf "%2s" "$number")
    
    # Pad command name to fixed width for consistent alignment
    local padded_cmd=$(printf "%-${cmd_width}s" "$script_command")
    
    # Calculate space for description
    # "  " + number (2) + "  " + command (15) + " - " = 22 chars
    local prefix_len=22
    local status_len=${#status_plain}
    local available=$((total_width - prefix_len - status_len - 1))
    
    # Truncate description if needed
    if [ ${#description} -gt $available ]; then
        description="${description:0:$((available - 3))}..."
    fi
    
    # Calculate padding to right-align status
    local padding_len=$((available - ${#description}))
    local padding=$(printf "%${padding_len}s" "")
    
    # Display with number, padded command name (dim), description, and right-aligned status
    echo -e "  ${CYAN}${number_str}${NC}  ${DIM}${padded_cmd}${NC} - ${description}${padding} ${status_display}"
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
    
    bash "$script_path" < /dev/tty
    local exit_code=$?
    
    if [ $exit_code -eq 0 ] || [ $exit_code -eq 3 ]; then
        echo ""
        echo -e "${GREEN}✓ Completed: $script_command${NC}"
        echo ""
        return $exit_code
    else
        echo ""
        echo -e "${RED}✗ Failed: $script_command${NC}"
        echo ""
        return 1
    fi
}

# Function to get scripts by category
get_scripts_by_category() {
    local category="$1"
    local gpu_filter="$2"  # "amd", "nvidia", or "all" (optional)
    
    for command in "${SCRIPT_COMMANDS[@]}"; do
        local cmd_category="${SCRIPT_CATEGORIES[$command]}"
        
        if [ "$cmd_category" = "$category" ]; then
            # Apply GPU filter if specified
            if [ -n "$gpu_filter" ] && [ "$gpu_filter" != "all" ]; then
                # Only include scripts that match the GPU filter (prefix or suffix)
                if [[ "$command" == ${gpu_filter}-* ]] || [[ "$command" == *-${gpu_filter} ]]; then
                    echo "$command"
                fi
            else
                echo "$command"
            fi
        fi
    done | sort
}

# Function to get host scripts (filtered by GPU type, in proper execution order)
get_host_scripts() {
    local gpu_type="$1"  # "amd" or "nvidia" or "universal" or "optional"
    local category_filter=""
    
    case "$gpu_type" in
        "amd"|"nvidia")
            # host-setup scripts for specific GPU
            get_scripts_by_category "host-setup" "$gpu_type"
            ;;
        "universal")
            # Scripts that work with any GPU (like gpu-udev)
            for cmd in $(get_scripts_by_category "host-setup" "all"); do
                # Only show if it's GPU-agnostic (no amd/nvidia prefix or suffix)
                if [[ "$cmd" != amd-* && "$cmd" != nvidia-* && "$cmd" != *-amd && "$cmd" != *-nvidia ]]; then
                    echo "$cmd"
                fi
            done
            ;;
        "optional")
            # Maintenance scripts
            get_scripts_by_category "host-maintenance" "all"
            ;;
    esac
}

# Function to get LXC scripts by category and GPU type (using metadata)
get_lxc_scripts() {
    local gpu_type="$1"  # "amd" or "nvidia" or "all"
    
    for command in "${SCRIPT_COMMANDS[@]}"; do
        local category="${SCRIPT_CATEGORIES[$command]}"
        
        # Only LXC scripts (any category starting with "lxc-")
        if [[ "$category" == lxc-* ]]; then
            # Filter by GPU type suffix
            if [ "$gpu_type" = "amd" ] && [[ "$command" == *-amd ]]; then
                echo "$command"
            elif [ "$gpu_type" = "nvidia" ] && [[ "$command" == *-nvidia ]]; then
                echo "$command"
            elif [ "$gpu_type" = "all" ]; then
                echo "$command"
            # GPU-agnostic containers (no -amd or -nvidia suffix)
            elif [[ "$command" != *-amd ]] && [[ "$command" != *-nvidia ]]; then
                echo "$command"
            fi
        fi
    done | sort
}

# Function to get unique LXC categories that have available scripts
get_lxc_categories() {
    local gpu_type="$1"
    local categories=()
    
    for command in $(get_lxc_scripts "$gpu_type"); do
        local category="${SCRIPT_CATEGORIES[$command]}"
        # Add to array if not already present
        if [[ ! " ${categories[@]} " =~ " ${category} " ]]; then
            categories+=("$category")
        fi
    done
    
    # Sort and output
    printf '%s\n' "${categories[@]}" | sort
}

# Function to get category display name
get_category_display_name() {
    local category="$1"
    case "$category" in
        lxc-ai) echo "AI & Machine Learning" ;;
        lxc-media) echo "Media & Photos" ;;
        lxc-dev) echo "Development Tools" ;;
        lxc-productivity) echo "Productivity" ;;
        lxc-monitoring) echo "Monitoring" ;;
        lxc-network) echo "Network Services" ;;
        *) echo "Other" ;;
    esac
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

# Global array to store number-to-command mapping
declare -a MENU_NUMBERS
declare -A MENU_MAP

# Main menu with numbered shortcuts
show_main_menu() {
    clear
    
    # Reset menu mappings
    MENU_NUMBERS=()
    MENU_MAP=()
    local menu_index=1
    
    # Build menu dynamically (78 char width to match menu items)
    echo -e "${GREEN}╔══════════════════════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${GREEN}║${NC}                       PVE GPU Workbench ${DIM}(pve-gpu)${NC}                            ${GREEN}║${NC}"
    echo -e "${GREEN}╚══════════════════════════════════════════════════════════════════════════════╝${NC}"
    echo ""
    
    # Show detected GPU info with emoji
    if [ "$HAS_AMD_GPU" = true ] || [ "$HAS_NVIDIA_GPU" = true ]; then
        if [ "$HAS_NVIDIA_GPU" = true ]; then
            local gpu_model=$(lspci | grep -i "VGA.*NVIDIA\|3D.*NVIDIA" | head -1 | sed -E 's/.*NVIDIA (Corporation )?//' | sed -E 's/ \(rev.*\)//' | sed 's/\[//' | sed 's/\]//')
            echo -e "${CYAN}GPU:${NC} $gpu_model"
        fi
        if [ "$HAS_AMD_GPU" = true ]; then
            local gpu_model=$(lspci | grep -i "VGA.*AMD\|Display.*AMD" | head -1 | sed -E 's/.*\[AMD\/ATI\] //' | sed -E 's/ \(rev.*\)//')
            echo -e "${CYAN}GPU:${NC} $gpu_model"
        fi
        echo ""
    fi
    
    echo -e "${GREEN}QUICK START${NC}"
    echo ""
    echo -e "  ${CYAN}setup${NC}          - Auto-configure GPU (drivers → udev → reboot)"
    echo ""
    
    echo -e "${GREEN}HOST CONFIGURATION${NC}"
    echo ""
    
    # Add AMD setup scripts
    if [ "$HAS_AMD_GPU" = true ]; then
        for cmd in strix-igpu amd-drivers; do
            if [[ " ${SCRIPT_COMMANDS[@]} " =~ " ${cmd} " ]]; then
                display_numbered_script "$menu_index" "$cmd"
                MENU_MAP[$menu_index]="$cmd"
                MENU_NUMBERS+=("$menu_index")
                ((menu_index++))
            fi
        done
    fi
    
    # Add NVIDIA setup scripts
    if [ "$HAS_NVIDIA_GPU" = true ]; then
        if [[ " ${SCRIPT_COMMANDS[@]} " =~ " nvidia-drivers " ]]; then
            display_numbered_script "$menu_index" "nvidia-drivers"
            MENU_MAP[$menu_index]="nvidia-drivers"
            MENU_NUMBERS+=("$menu_index")
            ((menu_index++))
        fi
    fi
    
    # Add universal setup scripts
    for cmd in gpu-udev; do
        if [[ " ${SCRIPT_COMMANDS[@]} " =~ " ${cmd} " ]]; then
            display_numbered_script "$menu_index" "$cmd"
            MENU_MAP[$menu_index]="$cmd"
            MENU_NUMBERS+=("$menu_index")
            ((menu_index++))
        fi
    done
    
    echo ""
    echo -e "${GREEN}DIAGNOSTICS & VERIFICATION${NC}"
    echo ""
    
    # Add verify scripts (host-verify category)
    local verify_gpu_type=""
    [ "$HAS_AMD_GPU" = true ] && verify_gpu_type="amd"
    [ "$HAS_NVIDIA_GPU" = true ] && verify_gpu_type="nvidia"
    [ "$HAS_AMD_GPU" = true ] && [ "$HAS_NVIDIA_GPU" = true ] && verify_gpu_type="all"
    
    for cmd in $(get_scripts_by_category "host-verify" "$verify_gpu_type"); do
        display_numbered_script "$menu_index" "$cmd"
        MENU_MAP[$menu_index]="$cmd"
        MENU_NUMBERS+=("$menu_index")
        ((menu_index++))
    done
    
    # Determine GPU type for container filtering
    local lxc_gpu_type=""
    [ "$HAS_AMD_GPU" = true ] && lxc_gpu_type="amd"
    [ "$HAS_NVIDIA_GPU" = true ] && lxc_gpu_type="nvidia"
    [ "$HAS_AMD_GPU" = true ] && [ "$HAS_NVIDIA_GPU" = true ] && lxc_gpu_type="all"
    
    # Get unique LXC categories that have scripts
    local lxc_categories_list
    lxc_categories_list=$(get_lxc_categories "$lxc_gpu_type")
    
    if [ -n "$lxc_categories_list" ]; then
        # Display each category as a subsection
        while IFS= read -r lxc_category; do
            [ -z "$lxc_category" ] && continue
            
            local display_name
            display_name=$(get_category_display_name "$lxc_category")
            
            echo ""
            echo -e "${GREEN}DEPLOY CONTAINERS${NC} ${DIM}($display_name)${NC}"
            echo ""
            
            # Show scripts in this category
            for cmd in $(get_lxc_scripts "$lxc_gpu_type"); do
                if [ "${SCRIPT_CATEGORIES[$cmd]}" = "$lxc_category" ]; then
                    display_numbered_script "$menu_index" "$cmd"
                    MENU_MAP[$menu_index]="$cmd"
                    MENU_NUMBERS+=("$menu_index")
                    ((menu_index++))
                fi
            done
        done <<< "$lxc_categories_list"
    else
        echo ""
        echo -e "${GREEN}DEPLOY CONTAINERS${NC}"
        echo ""
        echo -e "  ${DIM}No GPU detected - container deployment unavailable${NC}"
    fi
    
    echo ""
    echo -e "${GREEN}MAINTENANCE${NC}"
    echo ""
    
    # Add GPU-specific maintenance scripts (upgrade scripts)
    local maint_gpu_type=""
    [ "$HAS_AMD_GPU" = true ] && maint_gpu_type="amd"
    [ "$HAS_NVIDIA_GPU" = true ] && maint_gpu_type="nvidia"
    [ "$HAS_AMD_GPU" = true ] && [ "$HAS_NVIDIA_GPU" = true ] && maint_gpu_type="all"
    
    for cmd in $(get_scripts_by_category "host-maintenance" "$maint_gpu_type"); do
        display_numbered_script "$menu_index" "$cmd"
        MENU_MAP[$menu_index]="$cmd"
        MENU_NUMBERS+=("$menu_index")
        ((menu_index++))
    done
    
    # Add universal maintenance scripts (like power management)
    for cmd in $(get_scripts_by_category "host-maintenance" "all"); do
        # Only show if GPU-agnostic (no amd/nvidia prefix or suffix)
        if [[ "$cmd" != amd-* && "$cmd" != nvidia-* && "$cmd" != *-amd && "$cmd" != *-nvidia ]]; then
            display_numbered_script "$menu_index" "$cmd"
            MENU_MAP[$menu_index]="$cmd"
            MENU_NUMBERS+=("$menu_index")
            ((menu_index++))
        fi
    done
    
    echo -e "  ${CYAN} u${NC}  ${DIM}$(printf "%-15s" "update")${NC} - Update pve-gpu scripts from GitHub"
    echo -e "  ${CYAN} i${NC}  ${DIM}$(printf "%-15s" "info")${NC} - Show system information"
    echo ""
    
    # Show compact command help
    echo -e "${DIM}───────────────────────────────────────────────────────────────${NC}"
    echo -e "${YELLOW}Enter:${NC} ${CYAN}[number]${NC} ${DIM}or${NC} ${CYAN}<name>${NC} ${DIM}or${NC} ${CYAN}setup${NC} ${DIM}or${NC} ${CYAN}[q]uit${NC}"
    echo ""
}

# Function to show detailed system information
show_system_info() {
    clear
    echo -e "${GREEN}╔══════════════════════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${GREEN}║${NC}                        System Information Dashboard                          ${GREEN}║${NC}"
    echo -e "${GREEN}╚══════════════════════════════════════════════════════════════════════════════╝${NC}"
    echo ""
    
    # Script Version & System Info
    echo -e "${CYAN}═══ SCRIPT VERSION ═══${NC}"
    if [ -d "$SCRIPT_DIR/.git" ]; then
        local git_branch=$(cd "$SCRIPT_DIR" && git rev-parse --abbrev-ref HEAD 2>/dev/null)
        local git_commit=$(cd "$SCRIPT_DIR" && git rev-parse --short HEAD 2>/dev/null)
        local git_date=$(cd "$SCRIPT_DIR" && git log -1 --format=%cd --date=short 2>/dev/null)
        echo -e "  ${GREEN}Branch:${NC} $git_branch"
        echo -e "  ${GREEN}Commit:${NC} $git_commit ($git_date)"
    else
        echo -e "  ${DIM}Git repository not found${NC}"
    fi
    
    echo ""
    echo -e "${CYAN}═══ SYSTEM VERSION ═══${NC}"
    echo -e "  ${GREEN}Proxmox VE:${NC} $(pveversion | head -n1 | cut -d'/' -f2)"
    echo -e "  ${GREEN}Kernel:${NC} $(uname -r)"
    
    echo ""
    
    # GPU Setup Status Summary
    echo -e "${CYAN}═══ GPU SETUP STATUS ═══${NC}"
    if [ "$HAS_AMD_GPU" = true ]; then
        # Extract clean GPU model name
        local gpu_model=$(lspci | grep -i "VGA.*AMD\|Display.*AMD" | head -1 | sed -E 's/.*\[AMD\/ATI\] //' | sed -E 's/ \(rev.*\)//')
        echo -e "${GREEN}AMD GPU:${NC} $gpu_model"
        
        # Quick health check
        local gpu_status="${RED}✗ Not configured${NC}"
        if lsmod | grep -q amdgpu && [ -e /dev/kfd ]; then
            if command -v rocm-smi &>/dev/null && rocm-smi --showproductname 2>&1 | grep -qi "GPU"; then
                gpu_status="${GREEN}✓ Working${NC}"
            else
                gpu_status="${YELLOW}⚠ Partially configured${NC}"
            fi
        elif [ -d "/opt/rocm" ]; then
            gpu_status="${YELLOW}⚠ Reboot needed${NC}"
        fi
        echo -e "  ${GREEN}Status:${NC} $gpu_status"
        
        # ROCm version
        if [ -f "/opt/rocm/.info/version" ]; then
            echo -e "  ${GREEN}ROCm:${NC} $(cat /opt/rocm/.info/version)"
        elif command -v rocm-smi &>/dev/null; then
            local rocm_ver=$(rocm-smi --version 2>/dev/null | grep -oP "ROCM-SMI-LIB version: \K[0-9.]+")
            [ -n "$rocm_ver" ] && echo -e "  ${GREEN}ROCm:${NC} $rocm_ver" || echo -e "  ${DIM}ROCm: Not installed${NC}"
        else
            echo -e "  ${DIM}ROCm: Not installed${NC}"
        fi
        
        # iGPU VRAM allocation
        if grep -q "amdgpu.gttsize=" /proc/cmdline 2>/dev/null; then
            local gtt_size=$(grep -oP 'amdgpu.gttsize=\K[0-9]+' /proc/cmdline)
            local gtt_gb=$((gtt_size / 1024))
            echo -e "  ${GREEN}VRAM (iGPU):${NC} ${gtt_gb}GB allocated"
        else
            echo -e "  ${DIM}VRAM (iGPU): Not configured${NC}"
        fi
    fi
    
    if [ "$HAS_NVIDIA_GPU" = true ]; then
        echo ""
        # Extract clean GPU model name
        local gpu_model=$(lspci | grep -i "VGA.*NVIDIA\|3D.*NVIDIA" | head -1 | sed -E 's/.*NVIDIA (Corporation )?//' | sed -E 's/ \(rev.*\)//')
        echo -e "${GREEN}NVIDIA GPU:${NC} $gpu_model"
        
        # Quick health check
        local gpu_status="${RED}✗ Not configured${NC}"
        if command -v nvidia-smi &>/dev/null; then
            if nvidia-smi &>/dev/null; then
                gpu_status="${GREEN}✓ Working${NC}"
            else
                gpu_status="${YELLOW}⚠ Driver issue${NC}"
            fi
        fi
        echo -e "  ${GREEN}Status:${NC} $gpu_status"
        
        if command -v nvidia-smi &>/dev/null; then
            local cuda_ver=$(nvidia-smi --query-gpu=driver_version --format=csv,noheader 2>/dev/null)
            [ -n "$cuda_ver" ] && echo -e "  ${GREEN}Driver:${NC} $cuda_ver"
        else
            echo -e "  ${DIM}Driver: Not installed${NC}"
        fi
    fi
    
    if [ "$HAS_AMD_GPU" = false ] && [ "$HAS_NVIDIA_GPU" = false ]; then
        echo -e "  ${DIM}No AMD or NVIDIA GPU detected${NC}"
    fi
    
    echo ""
    
    # System Resources
    echo -e "${CYAN}═══ SYSTEM RESOURCES ═══${NC}"
    echo -e "${GREEN}CPU:${NC}"
    lscpu | grep "Model name" | sed 's/Model name: */  /'
    echo -e "  $(nproc) cores"
    
    echo -e "${GREEN}Memory:${NC}"
    free -h | awk '/^Mem:/ {printf "  Total: %s  |  Used: %s  |  Available: %s\n", $2, $3, $7}'
    
    echo -e "${GREEN}Storage Pools:${NC}"
    if command -v pvesm &>/dev/null; then
        pvesm status | tail -n +2 | awk '{
            # pvesm columns: Name Type Status Total Used Available %
            name=$1;
            total=$4;
            used=$5;
            avail=$6;
            if (total > 0) {
                used_pct = (used / total) * 100;
                # Values are in bytes, convert to GB
                printf "  %-15s %8.1f GB used / %8.1f GB total (%5.1f%%)\n", name":", used/1024/1024/1024, total/1024/1024/1024, used_pct;
            }
        }'
    else
        df -h / | awk 'NR==2 {printf "  Root: %s total, %s used, %s free (%s)\n", $2, $3, $4, $5}'
    fi
    
    echo ""
    
    # Network Configuration
    echo -e "${CYAN}═══ NETWORK CONFIGURATION ═══${NC}"
    echo -e "${GREEN}Network Bridges:${NC}"
    ip -br link show type bridge 2>/dev/null | awk '{
        status = ($2 == "UP") ? "UP" : "DOWN";
        printf "  %-10s %s\n", $1, status;
    }'
    
    echo -e "${GREEN}Host IP Addresses:${NC}"
    ip -4 -br addr show | grep -v "^lo" | awk '{printf "  %-15s %s\n", $1":", $3}'
    
    echo ""
    
    # LXC Containers
    echo -e "${CYAN}═══ LXC CONTAINERS ═══${NC}"
    local container_count
    container_count=$(pct list 2>/dev/null | tail -n +2 | wc -l)
    if [ "$container_count" -gt 0 ]; then
        pct list | tail -n +2 | while read -r line; do
            local vmid=$(echo "$line" | awk '{print $1}')
            local status=$(echo "$line" | awk '{print $2}')
            local name=$(echo "$line" | awk '{print $3}')
            
            # Get IP address if container is running
            local ip_addr="N/A"
            local status_colored
            if [ "$status" = "running" ]; then
                ip_addr=$(pct exec "$vmid" -- ip -4 -br addr show 2>/dev/null | grep -v "^lo" | awk '{print $3}' | head -1 | cut -d'/' -f1)
                [ -z "$ip_addr" ] && ip_addr="acquiring..."
                status_colored="\033[0;32mrunning\033[0m"  # Green
            else
                status_colored="\033[2mstopped\033[0m"  # Dim
            fi
            
            # Use echo -e with printf format for proper color rendering
            echo -e "  \033[0;32m[${vmid}]\033[0m $(printf '%-20s' "$name") $status_colored  \033[0;36m${ip_addr}\033[0m"
        done
    else
        echo -e "  ${DIM}No containers found${NC}"
    fi
    
    echo ""
    echo -e "${DIM}Tip: Run 'amd-verify' or 'nvidia-verify' for detailed GPU diagnostics${NC}"
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
    
    # Use read -e for readline support (arrow keys, history)
    read -e -r -p "Choice [setup]: " choice
    choice=${choice:-setup}  # Default to "setup"
    
    # Check if input is a number and map to command
    if [[ "$choice" =~ ^[0-9]+$ ]] && [ -n "${MENU_MAP[$choice]}" ]; then
        choice="${MENU_MAP[$choice]}"
    else
        choice=${choice,,}  # Convert to lowercase for text commands
    fi
    
    case "$choice" in
        "setup"|"all")  # Accept both "setup" and legacy "all"
            # Setup comprehensive logging
            SETUP_LOG="/tmp/pve-gpu-setup-$(date +%Y%m%d-%H%M%S).log"
            
            # Initialize log file
            {
                echo "═══════════════════════════════════════════════════════════"
                echo "PVE GPU Workbench - Setup Log"
                echo "═══════════════════════════════════════════════════════════"
                echo "Started: $(date)"
                echo "Hostname: $(hostname)"
                echo ""
                echo "GPU Detection:"
                echo "  HAS_AMD_GPU: $HAS_AMD_GPU"
                echo "  HAS_NVIDIA_GPU: $HAS_NVIDIA_GPU"
                echo ""
                echo "Detected Hardware:"
                lspci -nn | grep -i "VGA\|3D\|Display"
                echo ""
                echo "AMD scripts queued:"
                get_host_scripts "amd" | sed 's/^/  - /'
                [ -z "$(get_host_scripts "amd")" ] && echo "  (none)"
                echo ""
                echo "NVIDIA scripts queued:"
                get_host_scripts "nvidia" | sed 's/^/  - /'
                [ -z "$(get_host_scripts "nvidia")" ] && echo "  (none)"
                echo ""
                echo "Universal scripts queued:"
                get_host_scripts "universal" | sed 's/^/  - /'
                [ -z "$(get_host_scripts "universal")" ] && echo "  (none)"
                echo ""
                echo "═══════════════════════════════════════════════════════════"
                echo ""
            } > "$SETUP_LOG"
            
            # Function to log to both console and file
            setup_log() {
                echo "$@" | tee -a "$SETUP_LOG"
            }
            
            echo ""
            echo -e "${GREEN}========================================${NC}"
            echo -e "${GREEN}Running GPU Setup scripts...${NC}"
            echo -e "${GREEN}========================================${NC}"
            echo ""
            echo -e "${CYAN}📋 Setup Log:${NC} $SETUP_LOG"
            echo -e "${YELLOW}You will be asked before each script runs.${NC}"
            echo -e "${YELLOW}Press 'y' to run, 'n' to skip, or 'q' to return to main menu.${NC}"
            echo ""
            
            quit_requested=false
            reboot_needed=false
            scripts_run=0
            
            # Run all AMD host scripts
            if [ "$HAS_AMD_GPU" = true ]; then
                echo "[$(date +%H:%M:%S)] Starting AMD host scripts..." >> "$SETUP_LOG"
                for cmd in $(get_host_scripts "amd"); do
                    echo "[$(date +%H:%M:%S)] Prompting: $cmd" >> "$SETUP_LOG"
                    confirm_run_with_info "$cmd"
                    result=$?
                    
                    if [ $result -eq 2 ]; then
                        echo "[$(date +%H:%M:%S)] User quit at: $cmd" >> "$SETUP_LOG"
                        quit_requested=true
                        break
                    elif [ $result -eq 0 ]; then
                        echo "[$(date +%H:%M:%S)] Running: $cmd" >> "$SETUP_LOG"
                        run_script "$cmd"
                        script_exit=$?
                        if [ $script_exit -eq 0 ] || [ $script_exit -eq 3 ]; then
                            echo "[$(date +%H:%M:%S)] SUCCESS: $cmd (exit: $script_exit)" >> "$SETUP_LOG"
                            ((scripts_run++))
                            # Check if script returned exit code 3 (reboot needed)
                            if [ $script_exit -eq 3 ]; then
                                reboot_needed=true
                            fi
                        else
                            echo "[$(date +%H:%M:%S)] FAILED: $cmd (exit: $script_exit)" >> "$SETUP_LOG"
                            read -r -p "Script failed. Continue? [y/N]: " continue_choice < /dev/tty
                            [[ ! "$continue_choice" =~ ^[Yy]$ ]] && break
                        fi
                    else
                        echo "[$(date +%H:%M:%S)] Skipped: $cmd" >> "$SETUP_LOG"
                    fi
                done
            else
                echo "[$(date +%H:%M:%S)] Skipping AMD scripts (no AMD GPU detected)" >> "$SETUP_LOG"
            fi
            
            # Run all NVIDIA host scripts
            if [ "$quit_requested" = false ] && [ "$HAS_NVIDIA_GPU" = true ]; then
                echo "[$(date +%H:%M:%S)] Starting NVIDIA host scripts..." >> "$SETUP_LOG"
                for cmd in $(get_host_scripts "nvidia"); do
                    echo "[$(date +%H:%M:%S)] Prompting: $cmd" >> "$SETUP_LOG"
                    confirm_run_with_info "$cmd"
                    result=$?
                    
                    if [ $result -eq 2 ]; then
                        echo "[$(date +%H:%M:%S)] User quit at: $cmd" >> "$SETUP_LOG"
                        quit_requested=true
                        break
                    elif [ $result -eq 0 ]; then
                        echo "[$(date +%H:%M:%S)] Running: $cmd" >> "$SETUP_LOG"
                        run_script "$cmd"
                        script_exit=$?
                        if [ $script_exit -eq 0 ] || [ $script_exit -eq 3 ]; then
                            echo "[$(date +%H:%M:%S)] SUCCESS: $cmd (exit: $script_exit)" >> "$SETUP_LOG"
                            ((scripts_run++))
                            # Check if script returned exit code 3 (reboot needed)
                            if [ $script_exit -eq 3 ]; then
                                reboot_needed=true
                            fi
                        else
                            echo "[$(date +%H:%M:%S)] FAILED: $cmd (exit: $script_exit)" >> "$SETUP_LOG"
                            read -r -p "Script failed. Continue? [y/N]: " continue_choice < /dev/tty
                            [[ ! "$continue_choice" =~ ^[Yy]$ ]] && break
                        fi
                    else
                        echo "[$(date +%H:%M:%S)] Skipped: $cmd" >> "$SETUP_LOG"
                    fi
                done
            elif [ "$quit_requested" = false ]; then
                echo "[$(date +%H:%M:%S)] Skipping NVIDIA scripts (no NVIDIA GPU detected)" >> "$SETUP_LOG"
            fi
            
            # Run universal host scripts
            if [ "$quit_requested" = false ]; then
                echo "[$(date +%H:%M:%S)] Starting universal host scripts..." >> "$SETUP_LOG"
                for cmd in $(get_host_scripts "universal"); do
                    echo "[$(date +%H:%M:%S)] Prompting: $cmd" >> "$SETUP_LOG"
                    confirm_run_with_info "$cmd"
                    result=$?
                    
                    if [ $result -eq 2 ]; then
                        echo "[$(date +%H:%M:%S)] User quit at: $cmd" >> "$SETUP_LOG"
                        quit_requested=true
                        break
                    elif [ $result -eq 0 ]; then
                        echo "[$(date +%H:%M:%S)] Running: $cmd" >> "$SETUP_LOG"
                        run_script "$cmd"
                        script_exit=$?
                        if [ $script_exit -eq 0 ] || [ $script_exit -eq 3 ]; then
                            echo "[$(date +%H:%M:%S)] SUCCESS: $cmd (exit: $script_exit)" >> "$SETUP_LOG"
                            ((scripts_run++))
                            # Check if script returned exit code 3 (reboot needed)
                            if [ $script_exit -eq 3 ]; then
                                reboot_needed=true
                            fi
                        else
                            echo "[$(date +%H:%M:%S)] FAILED: $cmd (exit: $script_exit)" >> "$SETUP_LOG"
                            read -r -p "Script failed. Continue? [y/N]: " continue_choice < /dev/tty
                            [[ ! "$continue_choice" =~ ^[Yy]$ ]] && break
                        fi
                    else
                        echo "[$(date +%H:%M:%S)] Skipped: $cmd" >> "$SETUP_LOG"
                    fi
                done
            fi
            
            if [ "$quit_requested" = false ]; then
                # Log completion
                {
                    echo ""
                    echo "═══════════════════════════════════════════════════════════"
                    echo "Setup Completed: $(date)"
                    echo "Scripts Run: $scripts_run"
                    echo "Reboot Needed: $reboot_needed"
                    echo "═══════════════════════════════════════════════════════════"
                } >> "$SETUP_LOG"
                
                echo ""
                echo -e "${GREEN}========================================${NC}"
                echo -e "${GREEN}GPU Setup completed!${NC}"
                echo -e "${GREEN}========================================${NC}"
                echo ""
                echo -e "${CYAN}📋 Full setup log: $SETUP_LOG${NC}"
                echo ""
                
                if [ "$scripts_run" -eq 0 ]; then
                    echo -e "${CYAN}No scripts were run (all skipped or already configured)${NC}"
                    echo ""
                elif [ "$reboot_needed" = true ]; then
                    echo -e "${YELLOW}⚠  REBOOT REQUIRED${NC}"
                    echo -e "${CYAN}Kernel modules or parameters were changed and require a reboot.${NC}"
                    echo ""
                    echo -e "${YELLOW}After reboot, run verification:${NC}"
                    if [ "$HAS_AMD_GPU" = true ]; then
                        echo -e "   ${BOLD}pve-gpu → amd-verify${NC}"
                    fi
                    if [ "$HAS_NVIDIA_GPU" = true ]; then
                        echo -e "   ${BOLD}pve-gpu → nvidia-verify${NC}"
                    fi
                    echo ""
                    read -r -p "Reboot now? [Y/n]: " reboot_choice < /dev/tty
                    reboot_choice=${reboot_choice:-Y}
                    
                    if [[ "$reboot_choice" =~ ^[Yy]$ ]]; then
                        echo ""
                        echo -e "${GREEN}Rebooting in 5 seconds... (Ctrl+C to cancel)${NC}"
                        sleep 5
                        reboot
                    else
                        echo ""
                        echo -e "${YELLOW}Remember to reboot manually before proceeding!${NC}"
                        echo -e "${CYAN}Run: ${BOLD}reboot${NC}"
                        echo ""
                    fi
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
            else
                # Log early quit
                {
                    echo ""
                    echo "═══════════════════════════════════════════════════════════"
                    echo "Setup Quit: $(date)"
                    echo "User quit early (scripts run: $scripts_run)"
                    echo "═══════════════════════════════════════════════════════════"
                } >> "$SETUP_LOG"
                
                echo ""
                echo -e "${YELLOW}Setup cancelled by user${NC}"
                echo -e "${CYAN}📋 Partial setup log: $SETUP_LOG${NC}"
                echo ""
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
            echo -e "${GREEN}Thank you for using Proxmox GPU Setup!${NC}"
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
