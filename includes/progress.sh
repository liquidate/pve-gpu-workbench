#!/usr/bin/env bash
# Progress tracking and UI functions
# Source this file to get consistent progress tracking across all scripts

# Display step progress with counter
# Usage: show_progress <step> <total> "message"
show_progress() {
    local step=$1
    local total=$2
    local message=$3
    echo -ne "\r\033[K${CYAN}[Step $step/$total]${NC} $message..."
}

# Display completion message
# Usage: complete_progress "message"
complete_progress() {
    echo -e "\r\033[K${GREEN}✓${NC} $1"
}

# Spinner for long-running commands
SPINNER_PID=""

# Start animated spinner with message
# Usage: start_spinner "message"
start_spinner() {
    local message="$1"
    local spinner_chars="⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏"
    
    tput civis  # Hide cursor
    
    (
        local i=0
        while true; do
            local char="${spinner_chars:$i:1}"
            echo -ne "\r\033[K${CYAN}${char}${NC} ${message}"
            i=$(( (i + 1) % ${#spinner_chars} ))
            sleep 0.1
        done
    ) &
    SPINNER_PID=$!
}

# Stop spinner and clear line
# Usage: stop_spinner
stop_spinner() {
    if [ -n "$SPINNER_PID" ]; then
        kill "$SPINNER_PID" 2>/dev/null || true
        wait "$SPINNER_PID" 2>/dev/null || true
        SPINNER_PID=""
    fi
    echo -ne "\r\033[K"
    tput cnorm  # Show cursor
}

# Cleanup spinner on script exit
trap stop_spinner EXIT

