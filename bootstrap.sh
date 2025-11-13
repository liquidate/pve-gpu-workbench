#!/usr/bin/env bash
#
# PVE GPU Workbench - Bootstrap Installer
# 
# Usage:
#   bash -c "$(curl -fsSL https://raw.githubusercontent.com/liquidate/pve-gpu-workbench/main/bootstrap.sh)"
#

set -e

REPO_URL="https://github.com/liquidate/pve-gpu-workbench.git"
REPO_BRANCH="main"
INSTALL_DIR="/root/proxmox-setup-scripts"

# Colors for output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
RED='\033[0;31m'
NC='\033[0m'

echo ""
echo -e "${GREEN}╔══════════════════════════════════════╗${NC}"
echo -e "${GREEN}║  PVE GPU Workbench - Installer      ║${NC}"
echo -e "${GREEN}╚══════════════════════════════════════╝${NC}"
echo ""

# Check if already installed
if [ -d "$INSTALL_DIR" ]; then
    echo -e "${YELLOW}Installation directory already exists: $INSTALL_DIR${NC}"
    read -p "Would you like to update the existing installation? [y/N]: " UPDATE
    UPDATE=${UPDATE:-N}
    
    if [[ "$UPDATE" =~ ^[Yy]$ ]]; then
        echo -e "${CYAN}>>> Updating existing installation...${NC}"
        cd "$INSTALL_DIR"
        git fetch origin
        git checkout "$REPO_BRANCH"
        git pull origin "$REPO_BRANCH"
        echo ""
        echo -e "${GREEN}✓ Updated successfully!${NC}"
        echo ""
        
        # Check if system-wide commands exist, if not offer to create them
        if [ ! -L /usr/local/bin/pve-gpu ]; then
            read -p "Create system-wide 'pve-gpu' commands? [Y/n]: " CREATE_LINKS
            CREATE_LINKS=${CREATE_LINKS:-Y}
            
            if [[ "$CREATE_LINKS" =~ ^[Yy]$ ]]; then
                ln -sf "$INSTALL_DIR/guided-install.sh" /usr/local/bin/pve-gpu
                ln -sf "$INSTALL_DIR/update" /usr/local/bin/pve-gpu-update
                echo -e "${GREEN}✓ Created commands:${NC} pve-gpu, pve-gpu-update"
                echo ""
            fi
        fi
        
        read -p "Launch guided installer? [Y/n]: " LAUNCH
        LAUNCH=${LAUNCH:-Y}
        if [[ "$LAUNCH" =~ ^[Yy]$ ]]; then
            bash "$INSTALL_DIR/guided-install.sh"
        fi
        exit 0
    else
        echo "Installation cancelled."
        exit 0
    fi
fi

# Check if git is installed
echo -e "${CYAN}>>> Checking for git...${NC}"
if ! command -v git &>/dev/null; then
    echo "Git not found. Installing..."
    apt-get update -qq
    apt-get install -y git
    echo -e "${GREEN}✓ Git installed${NC}"
else
    echo -e "${GREEN}✓ Git is already installed${NC}"
fi

# Clone the repository
echo ""
echo -e "${CYAN}>>> Cloning repository...${NC}"
git clone -b "$REPO_BRANCH" "$REPO_URL" "$INSTALL_DIR"

# Make all scripts executable
echo -e "${CYAN}>>> Setting up permissions...${NC}"
chmod +x "$INSTALL_DIR/guided-install.sh"
chmod +x "$INSTALL_DIR/update"
chmod +x "$INSTALL_DIR"/host/*.sh

echo ""
echo -e "${GREEN}╔══════════════════════════════════════╗${NC}"
echo -e "${GREEN}║  Installation Complete!              ║${NC}"
echo -e "${GREEN}╚══════════════════════════════════════╝${NC}"
echo ""
echo -e "${CYAN}Scripts installed to:${NC} $INSTALL_DIR"
echo ""

# Offer to create system-wide commands
read -p "Create system-wide 'pve-gpu' commands (recommended)? [Y/n]: " CREATE_LINKS
CREATE_LINKS=${CREATE_LINKS:-Y}

if [[ "$CREATE_LINKS" =~ ^[Yy]$ ]]; then
    echo -e "${CYAN}>>> Creating system-wide commands...${NC}"
    ln -sf "$INSTALL_DIR/guided-install.sh" /usr/local/bin/pve-gpu
    ln -sf "$INSTALL_DIR/update" /usr/local/bin/pve-gpu-update
    echo -e "${GREEN}✓ Created commands:${NC}"
    echo "  pve-gpu        - Launch guided installer"
    echo "  pve-gpu-update - Update scripts from GitHub"
    echo ""
else
    echo -e "${YELLOW}To get started:${NC}"
    echo "  cd $INSTALL_DIR"
    echo "  ./guided-install.sh"
    echo ""
fi

# Prompt to launch
read -p "Launch guided installer now? [Y/n]: " LAUNCH
LAUNCH=${LAUNCH:-Y}

if [[ "$LAUNCH" =~ ^[Yy]$ ]]; then
    cd "$INSTALL_DIR"
    bash "$INSTALL_DIR/guided-install.sh"
fi

