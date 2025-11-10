#!/usr/bin/env bash
# SCRIPT_DESC: Toggle power management (powertop + AutoASPM)
# SCRIPT_DETECT: systemctl is-active --quiet powertop.service && systemctl is-active --quiet autoaspm.service

# Get script directory and source colors
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/../includes/colors.sh"

echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}Power Management Configuration${NC}"
echo -e "${GREEN}========================================${NC}"
echo ""

# Check current status
POWERTOP_ENABLED=false
AUTOASPM_ENABLED=false

if systemctl is-active --quiet powertop.service 2>/dev/null; then
    POWERTOP_ENABLED=true
fi

if systemctl is-active --quiet autoaspm.service 2>/dev/null; then
    AUTOASPM_ENABLED=true
fi

# Show current status with prominent display
echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
if [ "$POWERTOP_ENABLED" = true ] && [ "$AUTOASPM_ENABLED" = true ]; then
    echo -e "${GREEN}       ✓ STATUS: ENABLED${NC}"
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
    echo -e "${CYAN}Power optimizations are active:${NC}"
    echo -e "  ${GREEN}✓${NC} Powertop auto-tune running"
    echo -e "  ${GREEN}✓${NC} PCIe power management active"
    echo -e "  ${GREEN}✓${NC} Persists on reboot"
    echo ""
    echo -e "${CYAN}Your system is saving power and reducing heat.${NC}"
    echo ""
elif [ "$POWERTOP_ENABLED" = true ] || [ "$AUTOASPM_ENABLED" = true ]; then
    echo -e "${YELLOW}       ⚠️  STATUS: PARTIALLY ENABLED${NC}"
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
    echo "  Powertop: $([ "$POWERTOP_ENABLED" = true ] && echo -e "${GREEN}✓ enabled${NC}" || echo -e "${RED}✗ disabled${NC}")"
    echo "  AutoASPM: $([ "$AUTOASPM_ENABLED" = true ] && echo -e "${GREEN}✓ enabled${NC}" || echo -e "${RED}✗ disabled${NC}")"
    echo ""
    echo -e "${YELLOW}Recommendation: Enable both for maximum power savings.${NC}"
    echo ""
else
    echo -e "${YELLOW}       ⊘ STATUS: DISABLED${NC}"
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
    echo -e "${CYAN}Power optimizations are not active.${NC}"
    echo "  • System using default power settings"
    echo "  • Higher idle power consumption (~5-20W more)"
    echo "  • May generate more heat"
    echo ""
    echo -e "${CYAN}Recommendation: Enable for 24/7 servers to reduce costs.${NC}"
    echo ""
fi

# Show menu
echo -e "${CYAN}What would you like to do?${NC}"
echo "  [1] Enable power management (recommended for 24/7 servers)"
echo "  [2] Disable power management"
echo "  [3] Show detailed status"
echo "  [4] Exit without changes"
echo ""

read -r -p "Enter choice [1]: " CHOICE
CHOICE=${CHOICE:-1}

case $CHOICE in
    1)
        echo ""
        echo -e "${GREEN}========================================${NC}"
        echo -e "${GREEN}Enabling Power Management${NC}"
        echo -e "${GREEN}========================================${NC}"
        echo ""
        
        echo -e "${CYAN}What This Does:${NC}"
        echo ""
        echo -e "${GREEN}1. Powertop --auto-tune:${NC}"
        echo "   • Enables CPU frequency scaling for lower idle power"
        echo "   • Enables USB autosuspend (unused USB devices sleep)"
        echo "   • Enables SATA link power management"
        echo "   • Enables audio codec power saving"
        echo "   • Tunes various kernel power parameters"
        echo ""
        echo -e "${GREEN}2. AutoASPM (PCIe Active State Power Management):${NC}"
        echo "   • Allows PCIe devices (GPU, NVMe, etc) to enter low-power states"
        echo "   • Particularly effective for AMD GPUs when idle"
        echo "   • Dynamically manages PCIe link power states"
        echo ""
        echo -e "${CYAN}Expected Benefits:${NC}"
        echo "   • 5-20W lower idle power consumption"
        echo "   • Reduced heat and fan noise"
        echo "   • Lower electricity costs for 24/7 operation"
        echo ""
        echo -e "${YELLOW}Potential Issues (rare):${NC}"
        echo "   ⚠️  USB mice/keyboards may briefly sleep (uncommon)"
        echo "   ⚠️  WiFi may disconnect on laptops (doesn't affect ethernet)"
        echo "   ⚠️  Some PCIe devices may have compatibility issues"
        echo ""
        echo -e "${CYAN}You can easily disable this later by running this script again.${NC}"
        echo ""
        
        read -r -p "Continue with power management setup? [Y/n]: " CONFIRM
        CONFIRM=${CONFIRM:-Y}
        
        if [[ ! "$CONFIRM" =~ ^[Yy]$ ]]; then
            echo "Cancelled."
            exit 0
        fi
        
        echo ""
        echo -e "${GREEN}>>> Step 1/4: Installing powertop...${NC}"
        if ! command -v powertop >/dev/null 2>&1; then
            apt update -qq
            apt install -y powertop
            echo -e "${GREEN}✓ Powertop installed${NC}"
        else
            echo -e "${GREEN}✓ Powertop already installed${NC}"
        fi
        
        echo ""
        echo -e "${GREEN}>>> Step 2/4: Installing AutoASPM...${NC}"
        if [ ! -d "/opt/AutoASPM" ]; then
            git clone https://github.com/notthebee/AutoASPM.git /opt/AutoASPM
            chmod u+x /opt/AutoASPM/pkgs/autoaspm.py
            echo -e "${GREEN}✓ AutoASPM installed${NC}"
        else
            echo -e "${GREEN}✓ AutoASPM already installed${NC}"
        fi
        
        echo ""
        echo -e "${GREEN}>>> Step 3/4: Creating systemd services for persistence...${NC}"
        
        # Create powertop service
        cat > /etc/systemd/system/powertop.service << 'EOF'
[Unit]
Description=Powertop tunings
After=multi-user.target

[Service]
Type=oneshot
ExecStart=/usr/sbin/powertop --auto-tune
RemainAfterExit=true

[Install]
WantedBy=multi-user.target
EOF
        
        # Create AutoASPM service
        cat > /etc/systemd/system/autoaspm.service << 'EOF'
[Unit]
Description=AutoASPM - PCIe Active State Power Management
After=multi-user.target

[Service]
Type=oneshot
ExecStart=/opt/AutoASPM/pkgs/autoaspm.py
RemainAfterExit=true

[Install]
WantedBy=multi-user.target
EOF
        
        echo -e "${GREEN}✓ Systemd services created${NC}"
        
        echo ""
        echo -e "${GREEN}>>> Step 4/4: Enabling and starting services...${NC}"
        systemctl daemon-reload
        systemctl enable powertop.service
        systemctl enable autoaspm.service
        systemctl start powertop.service
        systemctl start autoaspm.service
        
        echo -e "${GREEN}✓ Services enabled and started${NC}"
        
        echo ""
        echo -e "${GREEN}========================================${NC}"
        echo -e "${GREEN}Power Management Enabled!${NC}"
        echo -e "${GREEN}========================================${NC}"
        echo ""
        echo -e "${CYAN}What Just Happened:${NC}"
        echo "  ✓ Powertop auto-tune applied (CPU, USB, SATA optimizations)"
        echo "  ✓ AutoASPM enabled (PCIe power management)"
        echo "  ✓ Services will persist across reboots"
        echo ""
        echo -e "${CYAN}Monitoring Power Savings:${NC}"
        echo "  • Check current power draw with a smart PDU or Kill-a-Watt meter"
        echo "  • Monitor temps: watch -n 1 sensors"
        echo "  • GPU power: rocm-smi --showuse --showmemuse (AMD)"
        echo "  • Run: powertop (interactive TUI to see savings)"
        echo ""
        echo -e "${CYAN}To Disable Later:${NC}"
        echo "  ./guided-install.sh → 8 → Option 2"
        echo ""
        ;;
        
    2)
        echo ""
        echo -e "${YELLOW}========================================${NC}"
        echo -e "${YELLOW}Disabling Power Management${NC}"
        echo -e "${YELLOW}========================================${NC}"
        echo ""
        
        if [ "$POWERTOP_ENABLED" = false ] && [ "$AUTOASPM_ENABLED" = false ]; then
            echo -e "${YELLOW}Power management is already disabled.${NC}"
            exit 0
        fi
        
        echo -e "${YELLOW}This will:${NC}"
        echo "  • Stop powertop and AutoASPM services"
        echo "  • Disable services from running on boot"
        echo "  • Revert system to default power settings"
        echo ""
        echo -e "${CYAN}Note: Services and files will remain installed.${NC}"
        echo -e "${CYAN}      You can re-enable anytime by running this script.${NC}"
        echo ""
        
        read -r -p "Continue with disabling power management? [y/N]: " CONFIRM
        CONFIRM=${CONFIRM:-N}
        
        if [[ ! "$CONFIRM" =~ ^[Yy]$ ]]; then
            echo "Cancelled."
            exit 0
        fi
        
        echo ""
        echo -e "${YELLOW}>>> Stopping and disabling services...${NC}"
        systemctl stop powertop.service 2>/dev/null || true
        systemctl stop autoaspm.service 2>/dev/null || true
        systemctl disable powertop.service 2>/dev/null || true
        systemctl disable autoaspm.service 2>/dev/null || true
        
        echo -e "${GREEN}✓ Services stopped and disabled${NC}"
        
        echo ""
        echo -e "${GREEN}========================================${NC}"
        echo -e "${GREEN}Power Management Disabled${NC}"
        echo -e "${GREEN}========================================${NC}"
        echo ""
        echo -e "${CYAN}System reverted to default power settings.${NC}"
        echo -e "${CYAN}Power consumption may increase.${NC}"
        echo ""
        echo -e "${YELLOW}To completely remove (optional):${NC}"
        echo "  apt remove powertop"
        echo "  rm -rf /opt/AutoASPM"
        echo "  rm /etc/systemd/system/powertop.service"
        echo "  rm /etc/systemd/system/autoaspm.service"
        echo "  systemctl daemon-reload"
        echo ""
        ;;
        
    3)
        echo ""
        echo -e "${CYAN}========================================${NC}"
        echo -e "${CYAN}Power Management Status${NC}"
        echo -e "${CYAN}========================================${NC}"
        echo ""
        
        echo -e "${GREEN}Service Status:${NC}"
        echo ""
        echo "Powertop:"
        if systemctl is-active --quiet powertop.service; then
            echo -e "  Status: ${GREEN}✓ Active (running)${NC}"
            echo -e "  Enabled: $(systemctl is-enabled powertop.service 2>/dev/null || echo 'unknown')"
        else
            echo -e "  Status: ${RED}✗ Inactive${NC}"
        fi
        
        echo ""
        echo "AutoASPM:"
        if systemctl is-active --quiet autoaspm.service; then
            echo -e "  Status: ${GREEN}✓ Active (running)${NC}"
            echo -e "  Enabled: $(systemctl is-enabled autoaspm.service 2>/dev/null || echo 'unknown')"
        else
            echo -e "  Status: ${RED}✗ Inactive${NC}"
        fi
        
        echo ""
        echo -e "${GREEN}Installed Components:${NC}"
        echo "  Powertop: $(command -v powertop >/dev/null && echo '✓ installed' || echo '✗ not installed')"
        echo "  AutoASPM: $([ -d /opt/AutoASPM ] && echo '✓ installed' || echo '✗ not installed')"
        
        if command -v powertop >/dev/null 2>&1; then
            echo ""
            echo -e "${CYAN}Run 'powertop' for interactive power analysis${NC}"
        fi
        
        echo ""
        ;;
        
    4)
        echo "Exiting without changes."
        exit 0
        ;;
        
    *)
        echo -e "${RED}Invalid choice${NC}"
        exit 1
        ;;
esac

