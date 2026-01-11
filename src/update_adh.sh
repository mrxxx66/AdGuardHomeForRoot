#!/sbin/sh
# Script to update AdGuardHome binary and filters automatically
# This script can be used both manually and in GitHub Actions

set -eu

# Get the directory of the script
SCRIPT_DIR="$(dirname "$(readlink -f "$0")")"
. "$SCRIPT_DIR/settings.conf"

# Base URLs for AdGuardHome assets
ADGH_REPO_URL="https://api.github.com/repos/AdguardTeam/AdGuardHome/releases/latest"
FILTER_RULES_URL="https://raw.githubusercontent.com/TG-Twilight/AWAvenue-Ads-Rule/release/rules/ads-filter.txt"

# Function to get latest release info
get_latest_release_info() {
  local api_url="$1"
  local asset_name="$2"
  
  if command -v curl >/dev/null 2>&1; then
    curl -s "$api_url" | grep '"tag_name":' | sed -E 's/.*"([^"]+)".*/\1/'
  elif command -v wget >/dev/null 2>&1; then
    wget -qO- "$api_url" | grep '"tag_name":' | sed -E 's/.*"([^"]+)".*/\1/'
  else
    echo "Error: Neither curl nor wget found"
    exit 1
  fi
}

# Function to download a file
download_file() {
  local url="$1"
  local dest="$2"
  
  if command -v curl >/dev/null 2>&1; then
    curl -L -o "$dest" "$url"
  elif command -v wget >/dev/null 2>&1; then
    wget -O "$dest" "$url"
  else
    echo "Error: Neither curl nor wget found"
    exit 1
  fi
}

# Determine the architecture
detect_architecture() {
  local arch=$(uname -m)
  case "$arch" in
    aarch64|arm64)
      echo "arm64"
      ;;
    armv7l|arm)
      echo "armv7"
      ;;
    *)
      echo "Unsupported architecture: $arch" >&2
      exit 1
      ;;
  esac
}

# Main update function
update_adh() {
  echo "Detecting architecture..."
  local arch
  arch=$(detect_architecture)
  echo "Detected architecture: $arch"
  
  echo "Getting latest AdGuardHome release info..."
  local version_tag
  version_tag=$(get_latest_release_info "$ADGH_REPO_URL")
  echo "Latest version: $version_tag"
  
  # Update version in module.prop
  local temp_module_prop="$TMPDIR/module.prop.tmp"
  cp "$MOD_PATH/module.prop" "$temp_module_prop"
  
  # Replace version and versionCode in module.prop
  sed -i "s/^version=.*/version=${version_tag#v}/" "$temp_module_prop"
  sed -i "s/^versionCode=.*/versionCode=$(date +%Y%m%d)/" "$temp_module_prop"
  
  # Move the updated file back
  mv "$temp_module_prop" "$MOD_PATH/module.prop"
  
  # Download the appropriate binary
  local binary_url="https://github.com/AdguardTeam/AdGuardHome/releases/latest/download/AdGuardHome_linux_${arch}.tar.gz"
  local temp_archive="/tmp/AdGuardHome.tar.gz"
  
  echo "Downloading AdGuardHome for $arch from $binary_url..."
  download_file "$binary_url" "$temp_archive"
  
  # Extract the binary
  local temp_extract_dir="/tmp/agh-update"
  mkdir -p "$temp_extract_dir"
  tar -xzf "$temp_archive" -C "$temp_extract_dir"
  
  # Stop AdGuardHome if running
  if [ -f "$PID_FILE" ]; then
    local pid=$(cat "$PID_FILE" 2>/dev/null || echo "")
    if [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null; then
      echo "Stopping AdGuardHome..."
      kill "$pid"
      sleep 3
    fi
  fi
  
  # Backup current binary if exists
  if [ -f "$BIN_DIR/AdGuardHome" ]; then
    echo "Backing up current binary..."
    cp "$BIN_DIR/AdGuardHome" "$BIN_DIR/AdGuardHome.bak"
  fi
  
  # Copy new binary
  echo "Installing new AdGuardHome binary..."
  mv "$temp_extract_dir/AdGuardHome" "$BIN_DIR/AdGuardHome"
  chmod +x "$BIN_DIR/AdGuardHome"
  
  # Cleanup
  rm -rf "$temp_archive" "$temp_extract_dir"
  
  echo "AdGuardHome updated successfully to $version_tag for $arch architecture"
  
  # Update filter rules
  echo "Updating filter rules..."
  local filter_file="$BIN_DIR/filter.txt"
  download_file "$FILTER_RULES_URL" "$filter_file"
  echo "Filter rules updated successfully"
}

# Run update
update_adh