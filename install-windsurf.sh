#!/bin/bash

# Windsurf Installer for Linux
# Esteban Cuevas <esteban at attitude.cl>
# Licensed under the MIT License, see LICENSE file for details.

# This script installs the Windsurf on a Linux system, using the tarball provided by Windsurf itself.

set -e

# Colors for output
GREEN='\033[0;32m'
BLUE='\033[0;34m'
RED='\033[0;31m'
NC='\033[0m' # No Color

# Check if system is x64
if [ "$(uname -m)" != "x86_64" ]; then
  echo -e "${RED}Error: Windsurf is only compatible with x64 systems.${NC}"
  echo "Your system architecture: $(uname -m)"
  echo "Windsurf doesn't work with 32-bit or ARM CPUs."
  exit 1
fi

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

# Temp directory for download
# Use XDG_RUNTIME_DIR if available, fall back to /tmp
TEMP_DIR="${XDG_RUNTIME_DIR:-/tmp}/windsurf-installer-$$"
mkdir -p "$TEMP_DIR"
trap 'rm -rf "$TEMP_DIR"' EXIT

echo -e "${GREEN}Windsurf Installer for Linux${NC}"
echo "This script will install Windsurf on your system."

# Set installation paths based on privileges
if [ "$EUID" -eq 0 ]; then
  echo -e "${BLUE}Installing system-wide as root${NC}"
  INSTALL_DIR="$SYSTEM_INSTALL_DIR"
  DESKTOP_FILE="$SYSTEM_DESKTOP_FILE"
  BIN_LINK="$SYSTEM_BIN_LINK"
else
  echo -e "${BLUE}Installing locally in your home directory${NC}"
  INSTALL_DIR="$USER_INSTALL_DIR"
  DESKTOP_FILE="$USER_DESKTOP_FILE"
  BIN_LINK="$USER_BIN_LINK"

  # Ensure local directories exist
  mkdir -p "$HOME/.local/bin"
  mkdir -p "$HOME/.local/share/applications"

  # Add ~/.local/bin to PATH if not already there
  if [[ ":$PATH:" != *":$HOME/.local/bin:"* ]]; then
    echo -e "${BLUE}Note: Add ~/.local/bin to your PATH to run windsurf from terminal${NC}"
    echo "export PATH=\"\$HOME/.local/bin:\$PATH\""
  fi
fi

# Check for existing installation
UPGRADE_MODE=false
if [ -d "$INSTALL_DIR" ]; then
  # Try to get currently installed version
  CURRENT_VERSION=""
  if [ -f "$DESKTOP_FILE" ]; then
    CURRENT_VERSION=$(grep -o "Version=.*" "$DESKTOP_FILE" | cut -d= -f2)
  fi

  if [ -n "$CURRENT_VERSION" ]; then
    echo -e "${BLUE}Found existing Windsurf installation (version $CURRENT_VERSION)${NC}"
    UPGRADE_MODE=true
  else
    echo -e "${BLUE}Found existing Windsurf installation (unknown version)${NC}"
    UPGRADE_MODE=true
  fi
fi

# Get the latest version information
echo "Fetching latest version information..."
JSON_RESPONSE=$(curl -s https://windsurf-stable.codeium.com/api/update/linux-x64/stable/latest)

# Parse JSON using pure Bash regex - more reliable than grep for complex JSON
if [[ "$JSON_RESPONSE" =~ \"url\":\"([^\"]+)\" ]]; then
  DOWNLOAD_URL="${BASH_REMATCH[1]}"
else
  DOWNLOAD_URL=""
fi

if [[ "$JSON_RESPONSE" =~ \"windsurfVersion\":\"([^\"]+)\" ]]; then
  VERSION="${BASH_REMATCH[1]}"
else
  VERSION=""
fi

if [[ "$JSON_RESPONSE" =~ \"sha256hash\":\"([^\"]+)\" ]]; then
  SHA256="${BASH_REMATCH[1]}"
else
  SHA256=""
fi

if [ -z "$DOWNLOAD_URL" ] || [ -z "$VERSION" ] || [ -z "$SHA256" ]; then
  echo -e "${RED}Error: Failed to parse version information${NC}"
  echo "Raw response: $JSON_RESPONSE"
  exit 1
fi

echo "Found Windsurf version $VERSION"

# Check if we already have the latest version
if [ "$UPGRADE_MODE" = true ] && [ "$CURRENT_VERSION" = "$VERSION" ]; then
  echo -e "${BLUE}You already have Windsurf version $VERSION installed.${NC}"
  # Read directly from the terminal, not stdin (which is piped from curl)
  read -p "Do you want to reinstall the same version? (y/N) " -n 1 -r < /dev/tty
  echo # Add a newline after the read prompt
  if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "Installation cancelled."
    exit 0
  fi
  echo "Proceeding with reinstallation of Windsurf version $VERSION..."
fi

if [ "$UPGRADE_MODE" = true ]; then
  echo -e "${BLUE}Upgrading Windsurf from version $CURRENT_VERSION to $VERSION${NC}"
else
  echo -e "${BLUE}Installing Windsurf version $VERSION${NC}"
fi

echo "Download URL: $DOWNLOAD_URL"

# Download the tarball
TARBALL="$TEMP_DIR/windsurf.tar.gz"
echo "Downloading Windsurf..."
curl -L "$DOWNLOAD_URL" -o "$TARBALL"

# Download the icon-logo from GitHub
echo "Downloading Windsurf logo..."
LOGO_URL="https://raw.githubusercontent.com/EstebanForge/windsurf-installer-linux/main/windsurf-logo-512.png"
LOGO_PATH="$INSTALL_DIR/windsurf-logo-512.png"
curl -L "$LOGO_URL" -o "$TEMP_DIR/windsurf-logo-512.png"

# Verify checksum
echo "Verifying download integrity..."
CALCULATED_SHA256=$(sha256sum "$TARBALL" | cut -d' ' -f1)
if [ "$CALCULATED_SHA256" != "$SHA256" ]; then
  echo -e "${RED}Error: Checksum verification failed${NC}"
  echo "Expected: $SHA256"
  echo "Got: $CALCULATED_SHA256"
  exit 1
fi
echo -e "${GREEN}Checksum verification passed!${NC}"

# Extract the tarball
echo "Extracting Windsurf..."
tar -xzf "$TARBALL" -C "$TEMP_DIR"

# Find the chrome-sandbox file to locate the correct application directory
CHROME_SANDBOX=$(find "$TEMP_DIR" -type f -name "chrome-sandbox" | head -n 1)

if [ -z "$CHROME_SANDBOX" ]; then
  echo -e "${RED}Error: Could not find chrome-sandbox in the extracted files${NC}"
  echo "This might indicate a change in the Windsurf package structure."
  echo "Extracted contents:"
  find "$TEMP_DIR" -type f | sort | grep -v "node_modules" | head -20
  exit 1
fi

# Use the directory containing chrome-sandbox
APP_DIR=$(dirname "$CHROME_SANDBOX")
echo "Found application directory on extracted tarball: $APP_DIR"

# Create installation directory
mkdir -p "$INSTALL_DIR"

# Use rsync to copy all files including hidden ones
if command -v rsync &>/dev/null; then
  echo "Copying application files..."
  rsync -a "$APP_DIR/" "$INSTALL_DIR/"
else
  echo -e "${RED}Error: rsync is required but not installed on your system${NC}"
  echo "Please install rsync using your distribution's package manager:"
  echo "  - Debian/Ubuntu: sudo apt-get install rsync"
  echo "  - Fedora/RHEL:   sudo dnf install rsync"
  echo "  - Arch Linux:    sudo pacman -S rsync"
  exit 1
fi

# Verify installation succeeded
if [ ! -f "$INSTALL_DIR/windsurf" ]; then
  echo -e "${RED}Error: Installation failed, binary not found at expected location${NC}"
  echo "Contents of source directory ($APP_DIR):"
  ls -la "$APP_DIR"
  echo "Contents of install directory ($INSTALL_DIR):"
  ls -la "$INSTALL_DIR"
  exit 1
fi

# Save the logo to the installation directory
cp "$TEMP_DIR/windsurf-logo-512.png" "$LOGO_PATH"

# Make the binary executable
chmod +x "$INSTALL_DIR/windsurf"

# Create a symlink in bin directory
echo "Creating symlink..."
mkdir -p "$(dirname "$BIN_LINK")"
ln -sf "$INSTALL_DIR/windsurf" "$BIN_LINK"

# Create desktop entry
echo "Creating desktop shortcut..."
mkdir -p "$(dirname "$DESKTOP_FILE")"
cat > "$DESKTOP_FILE" << EOF
[Desktop Entry]
Name=Windsurf
GenericName=Code Editor
Comment=IDE built to keep you in flow state. Instant, invaluable AI developer assistance where you want it, when you want it
Exec=$INSTALL_DIR/windsurf %F
Icon=$LOGO_PATH
Type=Application
Actions=new-empty-window;
MimeType=application/x-code-workspace;
Categories=Development;TextEditor;
Keywords=windsurf;code;editor;
Version=$VERSION
StartupWMClass=windsurf-url-handler

[Desktop Action new-empty-window]
Name=New Empty Window
Exec=$INSTALL_DIR/windsurf --new-window %F
EOF

if [ "$UPGRADE_MODE" = true ]; then
  echo -e "${GREEN}Windsurf has been successfully upgraded to version $VERSION!${NC}"
else
  echo -e "${GREEN}Windsurf $VERSION has been successfully installed!${NC}"
fi

# Detect user's shell
CURRENT_SHELL=$(basename "$SHELL")

echo "You can run it from your applications menu or by typing 'windsurf' in terminal."

if [ "$EUID" -ne 0 ]; then
  echo -e "${BLUE}If '$HOME/.local/bin/' is not in your PATH, you may need to restart your session${NC}"
  echo -e "or add it manually, running on your terminal:\n"

  if [[ "$CURRENT_SHELL" == "zsh" ]]; then
    echo -e "${GREEN}echo 'export PATH=\"\$HOME/.local/bin:\$PATH\"' >> ~/.zshrc${NC}"
  else
    echo -e "${GREEN}echo 'export PATH=\"\$HOME/.local/bin:\$PATH\"' >> ~/.bashrc${NC}"
  fi

  echo -e "\n"
fi
