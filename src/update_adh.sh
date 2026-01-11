#!/usr/bin/env sh
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
  
  if command -v curl >/dev/null 2>&1; then
    local response
    response=$(curl -s "$api_url")
    if [ -z "$response" ]; then
      echo "Error: Empty response from GitHub API" >&2
      return 1
    fi
    echo "$response" | grep '"tag_name":' | sed -E 's/.*"([^"]+)".*/\1/'
  elif command -v wget >/dev/null 2>&1; then
    local response
    response=$(wget -qO- "$api_url")
    if [ -z "$response" ]; then
      echo "Error: Empty response from GitHub API" >&2
      return 1
    fi
    echo "$response" | grep '"tag_name":' | sed -E 's/.*"([^"]+)".*/\1/'
  else
    echo "Error: Neither curl nor wget found" >&2
    return 1
  fi
}

# Function to download a file
download_file() {
  local url="$1"
  local dest="$2"
  
  if [ -z "$url" ] || [ "$url" = "http://" ] || [ "$url" = "https://" ]; then
    echo "Error: Invalid URL provided: '$url'" >&2
    return 1
  fi
  
  if command -v curl >/dev/null 2>&1; then
    curl -L -o "$dest" "$url"
  elif command -v wget >/dev/null 2>&1; then
    wget -O "$dest" "$url"
  else
    echo "Error: Neither curl nor wget found" >&2
    return 1
  fi
}

# Determine the architecture for Android devices
detect_android_architecture() {
  local arch=$(uname -m)
  case "$arch" in
    aarch64|arm64)
      echo "arm64"
      ;;
    armv7l|arm)
      echo "armv7"
      ;;
    *)
      # For CI/CD environments, default to arm64 (most common Android architecture)
      echo "arm64"
      ;;
  esac
}

# Main update function
update_adh() {
  echo "Detecting architecture for Android device..."
  local arch
  arch=$(detect_android_architecture)
  echo "Target Android architecture: $arch"
  
  echo "Getting latest AdGuardHome release info..."
  local version_tag
  version_tag=$(get_latest_release_info "$ADGH_REPO_URL") || {
    echo "Failed to get latest release info from GitHub API" >&2
    echo "This might be due to network issues, API rate limits, or missing tools" >&2
    echo "Please ensure you have internet connectivity and either curl or wget installed" >&2
    exit 1
  }
  
  # Validate version tag
  if [ -z "$version_tag" ]; then
    echo "Error: Received empty version tag from GitHub API" >&2
    exit 1
  fi
  
  echo "Latest version: $version_tag"
  
  # Update version in module.prop
  if [ -n "$TMPDIR" ] && [ -d "$TMPDIR" ] && [ -f "$SCRIPT_DIR/../module.prop" ]; then
    # If running in CI/CD, update local file directly
    local temp_module_prop="$TMPDIR/module.prop.tmp"
    cp "$SCRIPT_DIR/../module.prop" "$temp_module_prop"
  else
    local temp_module_prop="$TMPDIR/module.prop.tmp"
    cp "$MOD_PATH/module.prop" "$temp_module_prop"
  fi
  
  # Replace version and versionCode in module.prop
  sed -i "s/^version=.*/version=${version_tag#v}/" "$temp_module_prop"
  sed -i "s/^versionCode=.*/versionCode=$(date +%Y%m%d)/" "$temp_module_prop"
  
  # Move the updated file back
  if [ -n "$TMPDIR" ] && [ -d "$TMPDIR" ] && [ -f "$SCRIPT_DIR/../module.prop" ]; then
    # If running in CI/CD, move to local path
    mv "$temp_module_prop" "$SCRIPT_DIR/../module.prop"
  else
    mv "$temp_module_prop" "$MOD_PATH/module.prop"
  fi
  
  # Download the appropriate binary
  local binary_url="https://github.com/AdguardTeam/AdGuardHome/releases/download/${version_tag}/AdGuardHome_linux_${arch}.tar.gz"
  local temp_archive="/tmp/AdGuardHome.tar.gz"
  
  echo "Downloading AdGuardHome for Android $arch from $binary_url..."
  download_file "$binary_url" "$temp_archive" || {
    echo "Failed to download AdGuardHome binary" >&2
    echo "Please check your internet connection and try again" >&2
    exit 1
  }
  
  # Extract the binary
  local temp_extract_dir="/tmp/agh-update"
  mkdir -p "$temp_extract_dir"
  tar -xzf "$temp_archive" -C "$temp_extract_dir"
  
  # Determine target binary directory based on environment
  local target_bin_dir
  if [ -n "$TMPDIR" ] && [ -d "$TMPDIR" ] && [ -d "$SCRIPT_DIR/../bin" ]; then
    # Running in CI/CD
    target_bin_dir="$SCRIPT_DIR/../bin"
  else
    # Running on device
    target_bin_dir="$BIN_DIR"
    
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
    if [ -f "$target_bin_dir/AdGuardHome" ]; then
      echo "Backing up current binary..."
      cp "$target_bin_dir/AdGuardHome" "$target_bin_dir/AdGuardHome.bak"
    fi
  fi
  
  # Copy new binary to the appropriate location
  echo "Installing new AdGuardHome binary..."
  mv "$temp_extract_dir/AdGuardHome" "$target_bin_dir/AdGuardHome"
  chmod +x "$target_bin_dir/AdGuardHome"
  
  # Cleanup
  rm -rf "$temp_archive" "$temp_extract_dir"
  
  echo "AdGuardHome updated successfully to $version_tag for $arch architecture"
  
  # Update filter rules
  echo "Updating filter rules..."
  local filter_file
  if [ -n "$TMPDIR" ] && [ -d "$TMPDIR" ] && [ -d "$SCRIPT_DIR/../bin" ]; then
    # Running in CI/CD
    filter_file="$SCRIPT_DIR/../bin/filter.txt"
  else
    # Running on device
    filter_file="$BIN_DIR/filter.txt"
  fi
  
  if download_file "$FILTER_RULES_URL" "$filter_file"; then
    echo "Filter rules updated successfully"
  else
    echo "Warning: Failed to update filter rules, but AdGuardHome core was updated successfully" >&2
  fi
}

# Run update
update_adh