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
  PRODUCT_JSON_PATH="$INSTALL_DIR/resources/app/product.json" # Define path to product.json
  if [ -f "$PRODUCT_JSON_PATH" ]; then
    # Extract version using grep and cut.
    # grep -o: print only the matching part.
    # Pattern handles "windsurfVersion": optional_spaces "version_string".
    # cut -d'"' -f4: delimiter " extracts the 4th field (the version).
    # 2>/dev/null for grep: suppress errors if file unreadable/pattern not found.
    # If grep fails/no match, output is empty, cut produces empty, CURRENT_VERSION becomes/remains empty.
    CURRENT_VERSION=$(grep -o '"windsurfVersion":[[:space:]]*"[^"]*"' "$PRODUCT_JSON_PATH" 2>/dev/null | cut -d'"' -f4)
  fi
  # If CURRENT_VERSION is still empty, it means product.json was not found,
  # or it was found but the version could not be extracted.

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

# Parse JSON using grep and cut for consistency and robustness to spacing
# Extracts "url", "windsurfVersion" (as VERSION), and "sha256hash"
DOWNLOAD_URL=$(echo "$JSON_RESPONSE" | grep -o '"url":[[:space:]]*"[^"]*"' | cut -d'"' -f4)
VERSION=$(echo "$JSON_RESPONSE" | grep -o '"windsurfVersion":[[:space:]]*"[^"]*"' | cut -d'"' -f4)
SHA256=$(echo "$JSON_RESPONSE" | grep -o '"sha256hash":[[:space:]]*"[^"]*"' | cut -d'"' -f4)

if [ -z "$DOWNLOAD_URL" ] || [ -z "$VERSION" ] || [ -z "$SHA256" ]; then
  echo -e "${RED}Error: Failed to parse version information${NC}"
  echo "Raw response: $JSON_RESPONSE"
  exit 1
fi

echo -e "${BLUE}Remote available Windsurf version: $VERSION${NC}"

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
LOGO_PATH="$INSTALL_DIR/windsurf-logo-512.png" # Final destination path for the logo
TEMP_LOGO_FILE="$TEMP_DIR/windsurf-logo-512.png" # Temporary download location

MAX_ATTEMPTS=3
ATTEMPT=1
LOGO_DOWNLOADED=false

while [ $ATTEMPT -le $MAX_ATTEMPTS ]; do
  echo "Attempt $ATTEMPT of $MAX_ATTEMPTS to download logo..."
  curl -L -f -s -o "$TEMP_LOGO_FILE" "$LOGO_URL"

  if [ -f "$TEMP_LOGO_FILE" ] && [ $(stat -c%s "$TEMP_LOGO_FILE") -gt 0 ]; then
    echo -e "${GREEN}Logo downloaded successfully from $LOGO_URL.${NC}"
    LOGO_DOWNLOADED=true
    break
  else
    if [ -f "$TEMP_LOGO_FILE" ]; then
      rm "$TEMP_LOGO_FILE"
    fi
    echo -e "${RED}Attempt $ATTEMPT failed or downloaded an empty file from $LOGO_URL.${NC}"
    if [ $ATTEMPT -lt $MAX_ATTEMPTS ]; then
      echo "Retrying in 2 seconds..."
      sleep 2
    fi
  fi
  ATTEMPT=$((ATTEMPT + 1))
done

if [ "$LOGO_DOWNLOADED" = false ]; then
  echo -e "${RED}Failed to download logo from $LOGO_URL after $MAX_ATTEMPTS attempts.${NC}"
  FALLBACK_ICON_FULL_PATH="$INSTALL_DIR/resources/app/resources/linux/code.png"

  echo "Attempting to use fallback icon from existing installation: $FALLBACK_ICON_FULL_PATH"

  if [ -f "$FALLBACK_ICON_FULL_PATH" ] && [ $(stat -c%s "$FALLBACK_ICON_FULL_PATH") -gt 0 ]; then
    echo -e "${GREEN}Fallback icon found. Copying to temporary location...${NC}"
    cp "$FALLBACK_ICON_FULL_PATH" "$TEMP_LOGO_FILE"
    # Verify the copy succeeded and the temp file is not empty
    if [ -f "$TEMP_LOGO_FILE" ] && [ $(stat -c%s "$TEMP_LOGO_FILE") -gt 0 ]; then
      LOGO_DOWNLOADED=true # Mark as successful for subsequent script logic
      echo -e "${GREEN}Fallback icon successfully prepared from $FALLBACK_ICON_FULL_PATH.${NC}"
    else
      echo -e "${RED}Error: Failed to copy or validate fallback icon to $TEMP_LOGO_FILE.${NC}"
      # LOGO_DOWNLOADED remains false, will be caught by the next check
    fi
  else
    echo -e "${RED}Fallback icon not found or is empty at $FALLBACK_ICON_FULL_PATH.${NC}"
  fi
fi

if [ "$LOGO_DOWNLOADED" = false ]; then
  echo -e "${RED}Error: Failed to obtain a valid logo file from $LOGO_URL or as a fallback.${NC}"
  echo "The installation cannot proceed without the logo for the desktop shortcut."
  exit 1
fi

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
cp "$TEMP_LOGO_FILE" "$LOGO_PATH"

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

echo "" # Add a blank line for better separation

# Instructions for running and updating
echo -e "${BLUE}--- Next Steps ---${NC}"
echo "You can run Windsurf from your applications menu or by typing 'windsurf' in the terminal."

# Check if local bin is in PATH for non-root installs
if [ "$EUID" -ne 0 ]; then
  if [[ ":$PATH:" != *":$HOME/.local/bin:"* ]]; then
    echo -e "\n${BLUE}Important: To run 'windsurf' from the terminal, your PATH needs an update.${NC}"
    echo "Please add '$HOME/.local/bin' to your PATH. You can do this by running:"
    if [[ "$CURRENT_SHELL" == "zsh" ]]; then
      echo -e "${GREEN}echo 'export PATH=\"\$HOME/.local/bin:\$PATH\"' >> ~/.zshrc && source ~/.zshrc${NC}"
    elif [[ "$CURRENT_SHELL" == "bash" ]]; then
      echo -e "${GREEN}echo 'export PATH=\"\$HOME/.local/bin:\$PATH\"' >> ~/.bashrc && source ~/.bashrc${NC}"
    else
      echo -e "${GREEN}echo 'export PATH=\"\$HOME/.local/bin:\$PATH\"' >> ~/."$CURRENT_SHELL"rc && source ~/."$CURRENT_SHELL"rc${NC}"
      echo -e "${BLUE}Note: You might need to adjust the shell configuration file path for '$CURRENT_SHELL'.${NC}"
    fi
    echo "You may need to restart your terminal session for this change to take effect."
  fi
fi

# Create windsurf-update helper script
UPDATE_SCRIPT_USER_DIR="$HOME/.local/bin"
UPDATE_SCRIPT_FULL_PATH="$UPDATE_SCRIPT_USER_DIR/windsurf-update"

echo -e "\n${BLUE}Creating a helper script for updates...${NC}"
mkdir -p "$UPDATE_SCRIPT_USER_DIR" # Ensure directory exists

cat > "$UPDATE_SCRIPT_FULL_PATH" << EOF_UPDATE_SCRIPT
#!/bin/bash
# Windsurf Update Script
# This script was generated by the Windsurf installer.
# It allows you to easily update Windsurf by running 'windsurf-update' in your terminal.

echo "Checking for Windsurf updates and reinstalling..."
curl -fsSL https://raw.githubusercontent.com/EstebanForge/windsurf-installer-linux/main/install-windsurf.sh | bash
EOF_UPDATE_SCRIPT

chmod +x "$UPDATE_SCRIPT_FULL_PATH"

echo "A helper script 'windsurf-update' has been created at: $UPDATE_SCRIPT_FULL_PATH"
echo "You can run 'windsurf-update' from your terminal to update Windsurf."
echo "If '$UPDATE_SCRIPT_USER_DIR' was not already in your PATH,"
echo "please ensure you've followed the instructions provided earlier to add it,"
echo "then restart your terminal or source your shell configuration."

echo -e "${BLUE}--------------------${NC}"
