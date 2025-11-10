#!/usr/bin/env bash
# SCRIPT_DESC: Install essential tools (curl, git, gpg, htop, iperf3, lshw, mc, s-tui, unzip, wget) and customize bash prompt
# SCRIPT_DETECT: command -v htop &>/dev/null && command -v mc &>/dev/null

apt update
echo ">>> Installing common tools:"
echo ">>> curl, git, gpg, htop, iperf3, iputils-arping, lshw, mc, s-tui, unzip, wget"
apt install -y curl git gpg htop iperf3 iputils-arping lshw mc s-tui unzip wget
echo ">>> Installation of common tools completed."
echo ""
echo "Note: For power management optimizations (reduce power/heat),"
echo "      run script 008 - toggle-power-management.sh"
echo ""

ps1_line="PS1='\${debian_chroot:+(\$debian_chroot)}\\[\\033[01;31m\\]\\u\\[\\033[01;33m\\]@\\[\\033[01;36m\\]\\h \\[\\033[01;33m\\]\\w \\[\\033[01;35m\\]\\\$ \\[\\033[00m\\]'"
while true; do
    read -r -p "Do you want to add a colorful LS and PS1 prompt to ~/.bashrc? [Y/n] " yn
    yn=${yn:-Y}  # Default to 'Y' if input is empty
    case "$yn" in
        [Nn]* )
            echo ">>> PS1 prompt not added."
            break
            ;;
        [Yy]* )
            # Check if the line already exists in ~/.bashrc
            if ! grep -q "LS_OPTIONS='--color=auto'" ~/.bashrc; then
                echo "$ps1_line" >> ~/.bashrc
                echo "export LS_OPTIONS='--color=auto'" >> ~/.bashrc
                echo "alias ls='ls \$LS_OPTIONS'" >> ~/.bashrc
                echo ">>> LS and PS1 prompt added to ~/.bashrc"
            else
                echo ">>> LS and PS1 prompt already in ~/.bashrc, skipping"
            fi
            break
            ;;
        * )
            echo ">>> Please answer yes or no."
            ;;
    esac
done