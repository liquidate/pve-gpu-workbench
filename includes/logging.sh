#!/usr/bin/env bash
# Logging setup and display functions
# Source this file to get consistent logging across all scripts

# Setup logging with timestamped log file
# Usage: setup_logging "script-name" ["custom description"]
setup_logging() {
    local script_name="$1"
    local description="${2:-Installation}"
    
    LOG_FILE="/tmp/${script_name}-$(date +%Y%m%d-%H%M%S).log"
    
    {
        echo "==================================="
        echo "${description} Log"
        echo "Started: $(date)"
        echo "==================================="
        echo ""
    } > "$LOG_FILE"
    
    export LOG_FILE
}

# Display log file location and tail command
# Usage: show_log_info
show_log_info() {
    echo ""
    echo -e "${CYAN}📋 Installation Log:${NC}"
    echo "  File: $LOG_FILE"
    echo -e "  Watch live: ${YELLOW}tail -f $LOG_FILE${NC}"
    echo ""
}

# Show final log location at completion
# Usage: show_log_summary
show_log_summary() {
    echo ""
    echo -e "${CYAN}📋 Full installation log saved to:${NC}"
    echo "  $LOG_FILE"
    echo ""
}

