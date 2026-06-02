#!/bin/bash

# Devin Desktop Installer for Linux
# Esteban Cuevas <esteban at attitude.cl>
# Licensed under the MIT License, see LICENSE file for details.

# This script installs Devin Desktop (formerly Windsurf) on a Linux system, using the tarball provided by the upstream API.

set -e

# Colors for output
GREEN='\033[0;32m'
BLUE='\033[0;34m'
RED='\033[0;31m'
NC='\033[0m' # No Color

# Check if system is x64
if [ "$(uname -m)" != "x86_64" ]; then
  echo -e "${RED}Error: Devin Desktop is only compatible with x64 systems.${NC}"
  echo "Your system architecture: $(uname -m)"
  echo "Devin Desktop doesn't work with 32-bit or ARM CPUs."
  exit 1
fi

# Installation directories (will be set based on user privileges)
INSTALL_DIR=""
DESKTOP_FILE=""
BIN_LINK=""

# System-wide installation paths
SYSTEM_INSTALL_DIR="/opt/devin-desktop"
SYSTEM_DESKTOP_FILE="/usr/share/applications/devin-desktop.desktop"
SYSTEM_BIN_LINK="/usr/local/bin/devin-desktop"

# Local installation paths
USER_INSTALL_DIR="$HOME/.local/share/devin-desktop"
USER_DESKTOP_FILE="$HOME/.local/share/applications/devin-desktop.desktop"
USER_BIN_LINK="$HOME/.local/bin/devin-desktop"

# Temp directory for download
# Use XDG_RUNTIME_DIR if available, fall back to /tmp
TEMP_DIR="${XDG_RUNTIME_DIR:-/tmp}/devin-desktop-installer-$$"
mkdir -p "$TEMP_DIR"
trap 'rm -rf "$TEMP_DIR"' EXIT

echo -e "${GREEN}Devin Desktop Installer for Linux${NC}"
echo "This script will install Devin Desktop (formerly Windsurf) on your system."

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
    echo -e "${BLUE}Note: Add ~/.local/bin to your PATH to run devin-desktop from terminal${NC}"
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
    # Note: upstream API still uses "windsurfVersion" field name even after Devin Desktop rebrand
  fi
  # If CURRENT_VERSION is still empty, it means product.json was not found,
  # or it was found but the version could not be extracted.

  if [ -n "$CURRENT_VERSION" ]; then
    echo -e "${BLUE}Found existing Devin Desktop installation (version $CURRENT_VERSION)${NC}"
    UPGRADE_MODE=true
  else
    echo -e "${BLUE}Found existing Devin Desktop installation (unknown version)${NC}"
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

echo -e "${BLUE}Remote available Devin Desktop version: $VERSION${NC}"

# Check if we already have the latest version
if [ "$UPGRADE_MODE" = true ] && [ "$CURRENT_VERSION" = "$VERSION" ]; then
  echo -e "${BLUE}You already have Devin Desktop version $VERSION installed.${NC}"
  # Read directly from the terminal, not stdin (which is piped from curl)
  read -p "Do you want to reinstall the same version? (y/N) " -n 1 -r < /dev/tty
  echo # Add a newline after the read prompt
  if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "Installation cancelled."
    exit 0
  fi
  echo "Proceeding with reinstallation of Devin Desktop version $VERSION..."
fi

if [ "$UPGRADE_MODE" = true ]; then
  echo -e "${BLUE}Upgrading Devin Desktop from version $CURRENT_VERSION to $VERSION${NC}"
else
  echo -e "${BLUE}Installing Devin Desktop version $VERSION${NC}"
fi

echo "Download URL: $DOWNLOAD_URL"

# Download the tarball
TARBALL="$TEMP_DIR/devin-desktop.tar.gz"
echo "Downloading Devin Desktop..."
curl -L "$DOWNLOAD_URL" -o "$TARBALL"

# Icon will be extracted from the tarball after extraction (see below).
LOGO_PATH="$INSTALL_DIR/devin-desktop-logo.svg"

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
echo "Extracting Devin Desktop..."
tar -xzf "$TARBALL" -C "$TEMP_DIR"

# Find the chrome-sandbox file to locate the correct application directory
CHROME_SANDBOX=$(find "$TEMP_DIR" -type f -name "chrome-sandbox" | head -n 1)

if [ -z "$CHROME_SANDBOX" ]; then
  echo -e "${RED}Error: Could not find chrome-sandbox in the extracted files${NC}"
  echo "This might indicate a change in the Devin Desktop package structure."
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
if [ ! -f "$INSTALL_DIR/devin-desktop" ]; then
  echo -e "${RED}Error: Installation failed, binary not found at expected location${NC}"
  echo "Contents of source directory ($APP_DIR):"
  ls -la "$APP_DIR"
  echo "Contents of install directory ($INSTALL_DIR):"
  ls -la "$INSTALL_DIR"
  exit 1
fi

# Extract the Devin logo from the tarball
# Primary: out/media/code-icon.svg, Fallback: resources/linux/code.png
TARBALL_LOGO_PATH=$(tar -tzf "$TARBALL" | grep -E 'out/media/code-icon\.svg$' | head -n 1)
if [ -z "$TARBALL_LOGO_PATH" ]; then
  echo -e "${RED}SVG icon not found in tarball, falling back to PNG...${NC}"
  TARBALL_LOGO_PATH=$(tar -tzf "$TARBALL" | grep -E 'resources/linux/code\.png$' | head -n 1)
  LOGO_PATH="$INSTALL_DIR/devin-desktop-logo.png"
fi
if [ -n "$TARBALL_LOGO_PATH" ]; then
  echo "Extracting Devin Desktop logo..."
  tar -xzf "$TARBALL" -C "$TEMP_DIR" "$TARBALL_LOGO_PATH"
  cp "$TEMP_DIR/$TARBALL_LOGO_PATH" "$LOGO_PATH"
  echo -e "${GREEN}Logo extracted successfully.${NC}"
else
  echo -e "${RED}Warning: Could not find logo in tarball. Desktop shortcut will have no icon.${NC}"
fi

# Make the binary executable
chmod +x "$INSTALL_DIR/devin-desktop"

# Create a symlink in bin directory
echo "Creating symlink..."
mkdir -p "$(dirname "$BIN_LINK")"
ln -sf "$INSTALL_DIR/devin-desktop" "$BIN_LINK"

# Create desktop entry
echo "Creating desktop shortcut..."
mkdir -p "$(dirname "$DESKTOP_FILE")"
cat > "$DESKTOP_FILE" << EOF
[Desktop Entry]
Name=Devin Desktop
GenericName=Code Editor
Comment=AI-powered code editor, formerly Windsurf
Exec=$INSTALL_DIR/devin-desktop %F
Icon=$LOGO_PATH
Type=Application
Actions=new-empty-window;
MimeType=application/x-code-workspace;
Categories=Development;TextEditor;
Keywords=devin;windsurf;code;editor;
Version=$VERSION
StartupWMClass=devin-desktop

[Desktop Action new-empty-window]
Name=New Empty Window
Exec=$INSTALL_DIR/devin-desktop --new-window %F
EOF

if [ "$UPGRADE_MODE" = true ]; then
  echo -e "${GREEN}Devin Desktop has been successfully upgraded to version $VERSION!${NC}"
else
  echo -e "${GREEN}Devin Desktop $VERSION has been successfully installed!${NC}"
fi

# Detect user's shell
CURRENT_SHELL=$(basename "$SHELL")

echo "" # Add a blank line for better separation

# Instructions for running and updating
echo -e "${BLUE}--- Next Steps ---${NC}"
echo "You can run Devin Desktop from your applications menu or by typing 'devin-desktop' in the terminal."

# Check if local bin is in PATH for non-root installs
if [ "$EUID" -ne 0 ]; then
  if [[ ":$PATH:" != *":$HOME/.local/bin:"* ]]; then
    echo -e "\n${BLUE}Important: To run 'devin-desktop' from the terminal, your PATH needs an update.${NC}"
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

# Create devin-desktop-update helper script
UPDATE_SCRIPT_USER_DIR="$HOME/.local/bin"
UPDATE_SCRIPT_FULL_PATH="$UPDATE_SCRIPT_USER_DIR/devin-desktop-update"

echo -e "\n${BLUE}Creating a helper script for updates...${NC}"
mkdir -p "$UPDATE_SCRIPT_USER_DIR" # Ensure directory exists

cat > "$UPDATE_SCRIPT_FULL_PATH" << EOF_UPDATE_SCRIPT
#!/bin/bash
# Devin Desktop Update Script
# This script was generated by the Devin Desktop installer.
# It allows you to easily update Devin Desktop by running 'devin-desktop-update' in your terminal.

echo "Checking for Devin Desktop updates and reinstalling..."
curl -fsSL https://raw.githubusercontent.com/EstebanForge/windsurf-installer-linux/main/install-devin-desktop.sh | bash
EOF_UPDATE_SCRIPT

chmod +x "$UPDATE_SCRIPT_FULL_PATH"

echo "A helper script 'devin-desktop-update' has been created at: $UPDATE_SCRIPT_FULL_PATH"
echo "You can run 'devin-desktop-update' from your terminal to update Devin Desktop."
echo "If '$UPDATE_SCRIPT_USER_DIR' was not already in your PATH,"
echo "please ensure you've followed the instructions provided earlier to add it,"
echo "then restart your terminal or source your shell configuration."

# Clean up old Windsurf paths if they exist (migration from previous install)
if [ "$EUID" -eq 0 ]; then
  OLD_INSTALL_DIR="/opt/windsurf"
  OLD_DESKTOP_FILE="/usr/share/applications/windsurf.desktop"
  OLD_BIN_LINK="/usr/local/bin/windsurf"
else
  OLD_INSTALL_DIR="$HOME/.local/share/windsurf"
  OLD_DESKTOP_FILE="$HOME/.local/share/applications/windsurf.desktop"
  OLD_BIN_LINK="$HOME/.local/bin/windsurf"
fi
OLD_UPDATE_SCRIPT="$HOME/.local/bin/windsurf-update"

MIGRATION_NEEDED=false
for old_path in "$OLD_INSTALL_DIR" "$OLD_DESKTOP_FILE" "$OLD_BIN_LINK" "$OLD_UPDATE_SCRIPT"; do
  if [ -e "$old_path" ]; then
    MIGRATION_NEEDED=true
    break
  fi
done

if [ "$MIGRATION_NEEDED" = true ]; then
  echo -e "\n${BLUE}--- Migrating from Windsurf to Devin Desktop ---${NC}"
  echo "Found old Windsurf installation paths. Cleaning up..."

  [ -L "$OLD_BIN_LINK" ] && echo "Removing old symlink $OLD_BIN_LINK" && rm -f "$OLD_BIN_LINK"
  [ -f "$OLD_DESKTOP_FILE" ] && echo "Removing old desktop entry $OLD_DESKTOP_FILE" && rm -f "$OLD_DESKTOP_FILE"
  [ -f "$OLD_UPDATE_SCRIPT" ] && echo "Removing old update script $OLD_UPDATE_SCRIPT" && rm -f "$OLD_UPDATE_SCRIPT"
  [ -d "$OLD_INSTALL_DIR" ] && echo "Removing old installation directory $OLD_INSTALL_DIR" && rm -rf "$OLD_INSTALL_DIR"

  echo -e "${GREEN}Old Windsurf paths cleaned up.${NC}"
fi

echo -e "${BLUE}--------------------${NC}"
