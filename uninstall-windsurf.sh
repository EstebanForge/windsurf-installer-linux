#!/bin/bash

# Windsurf Uninstaller for Linux
# Esteban Cuevas <esteban at attitude.cl>
# Licensed under the MIT License, see LICENSE file for details.

# This script uninstalls Windsurf from a Linux system.

set -e

# Colors for output
GREEN='\033[0;32m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Installation directories (will be set based on user privileges)
INSTALL_DIR=""
DESKTOP_FILE=""
BIN_LINK=""

# System-wide installation paths
SYSTEM_INSTALL_DIR="/opt/windsurf"
SYSTEM_DESKTOP_FILE="/usr/share/applications/windsurf.desktop"
SYSTEM_BIN_LINK="/usr/local/bin/windsurf"

# Local installation paths
USER_INSTALL_DIR="$HOME/.local/share/windsurf"
USER_DESKTOP_FILE="$HOME/.local/share/applications/windsurf.desktop"
USER_BIN_LINK="$HOME/.local/bin/windsurf"

echo -e "${GREEN}Windsurf Uninstaller for Linux${NC}"
echo "This script will remove Windsurf from your system."

# Check if system-wide or local installation exists
if [ -d "$SYSTEM_INSTALL_DIR" ] && [ "$EUID" -eq 0 ]; then
    echo -e "${BLUE}System-wide installation found.${NC}"
    INSTALL_DIR="$SYSTEM_INSTALL_DIR"
    DESKTOP_FILE="$SYSTEM_DESKTOP_FILE"
    BIN_LINK="$SYSTEM_BIN_LINK"
elif [ -d "$USER_INSTALL_DIR" ]; then
    echo -e "${BLUE}Local installation found in home directory.${NC}"
    INSTALL_DIR="$USER_INSTALL_DIR"
    DESKTOP_FILE="$USER_DESKTOP_FILE"
    BIN_LINK="$USER_BIN_LINK"
else
    # Check if system-wide exists but we don't have privileges
    if [ -d "$SYSTEM_INSTALL_DIR" ] && [ "$EUID" -ne 0 ]; then
        echo -e "${RED}System-wide installation detected but you need root privileges to uninstall it.${NC}"
        echo "Please run this script with sudo to uninstall the system-wide installation."
        exit 1
    else
        echo -e "${RED}Windsurf installation not found.${NC}"
        exit 1
    fi
fi

# Ask for confirmation
# Read directly from the terminal, not stdin (which is piped from curl)
read -p "Are you sure you want to uninstall Windsurf? (y/N) " -n 1 -r < /dev/tty
echo # Add a newline after the read prompt
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "Uninstallation cancelled."
    exit 0
fi

# Remove files
echo "Removing Windsurf..."

# Remove the symlink
if [ -L "$BIN_LINK" ]; then
    echo "Removing symlink from $BIN_LINK"
    rm -f "$BIN_LINK"
fi

# Remove the desktop file
if [ -f "$DESKTOP_FILE" ]; then
    echo "Removing desktop shortcut from $DESKTOP_FILE"
    rm -f "$DESKTOP_FILE"
fi

# Remove the installation directory
if [ -d "$INSTALL_DIR" ]; then
    echo "Removing installation directory $INSTALL_DIR"
    rm -rf "$INSTALL_DIR"
fi

# Check if the uninstallation was successful
if [ ! -d "$INSTALL_DIR" ] && [ ! -f "$DESKTOP_FILE" ] && [ ! -L "$BIN_LINK" ]; then
    echo -e "${GREEN}Windsurf has been successfully uninstalled!${NC}"

    UPDATE_SCRIPT_USER_DIR="$HOME/.local/bin"
    UPDATE_SCRIPT_FULL_PATH="$UPDATE_SCRIPT_USER_DIR/windsurf-update"

    echo -e "\n${BLUE}--- Removing Update Script ---${NC}"
    if [ -f "$UPDATE_SCRIPT_FULL_PATH" ]; then
        echo "Removing 'windsurf-update' helper script from $UPDATE_SCRIPT_FULL_PATH..."
        rm -f "$UPDATE_SCRIPT_FULL_PATH"
        if [ ! -f "$UPDATE_SCRIPT_FULL_PATH" ]; then
            echo -e "${GREEN}'windsurf-update' script successfully removed.${NC}"
        else
            echo -e "${RED}Failed to remove 'windsurf-update' script. Please remove it manually if desired.${NC}"
        fi
    else
        echo "The 'windsurf-update' helper script was not found at $UPDATE_SCRIPT_FULL_PATH (no action needed)."
    fi
    echo -e "${BLUE}----------------------------${NC}"
else
    echo -e "${RED}Uninstallation may not be complete. Please check manually.${NC}"
    [ -d "$INSTALL_DIR" ] && echo "- Installation directory $INSTALL_DIR still exists."
    [ -f "$DESKTOP_FILE" ] && echo "- Desktop shortcut $DESKTOP_FILE still exists."
    [ -L "$BIN_LINK" ] && echo "- Symlink $BIN_LINK still exists."
fi

