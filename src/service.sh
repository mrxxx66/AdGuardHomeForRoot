#!/system/bin/sh
# This script is called by Magisk's service.d

# Load configuration
. $MODDIR/settings.conf

# Function to check for module updates
check_module_updates() {
  # Only check based on configured interval
  local last_check_file="$AGH_DIR/last_update_check"
  local current_time=$(date +%s)
  local last_check=0
  
  if [ -f "$last_check_file" ]; then
    last_check=$(cat "$last_check_file")
  fi
  
  local time_diff=$((current_time - last_check))
  
  if [ $time_diff -gt $AUTO_UPDATE_INTERVAL ]; then
    log "Checking for updates..." "正在检查更新..."
    
    # Get remote version info
    local remote_info=$(curl -s "$UPDATE_JSON_URL")
    local remote_version=$(echo "$remote_info" | grep -o '"version":"[^"]*' | cut -d'"' -f4)
    local current_version=$(grep "^version=" "$MODDIR/module.prop" | cut -d'=' -f2)
    
    if [ "$remote_version" != "$current_version" ]; then
      log "New module version available: $remote_version" "发现新版本: $remote_version"
      # Here could implement auto-download feature or just notify user
    fi
    
    echo $current_time > "$last_check_file"
  fi
}

# Function to check for AdGuardHome core updates
check_adh_updates() {
  # Check for AdGuardHome updates based on configuration
  if [ "$AUTO_UPDATE_AGGRESSIVE_CHECK" = "true" ]; then
    # More frequent checks if aggressive mode is enabled
    local check_interval=43200  # 12 hours
  else
    local check_interval=$AUTO_UPDATE_INTERVAL
  fi
  
  local last_check_file="$AGH_DIR/last_adh_update_check"
  local current_time=$(date +%s)
  local last_check=0
  
  if [ -f "$last_check_file" ]; then
    last_check=$(cat "$last_check_file")
  fi
  
  local time_diff=$((current_time -last_check))
  
  if [ $time_diff -gt $check_interval ]; then
    log "Checking for AdGuardHome updates..." "正在检查AdGuardHome更新..."
    
    # Get latest AdGuardHome version
    local api_response
    api_response=$(curl -s https://api.github.com/repos/AdguardTeam/AdGuardHome/releases/latest)
    local latest_version
    latest_version=$(echo "$api_response" | grep '"tag_name":' | sed -E 's/.*"([^"]+)".*/\1/')
    
    # Get current version from binary or config
    local current_version
    current_version=$(cd "$BIN_DIR" && ./AdGuardHome -v | cut -d' ' -f2)
    
    if [ "$latest_version" != "$current_version" ]; then
      log "New AdGuardHome version available: $latest_version" "AdGuardHome新版本可用: $latest_version"
      
      if [ "$AUTO_UPDATE_FILTER_ONLY" = "false" ]; then
        # Update both binary and filters
        log "Updating AdGuardHome core..." "正在更新AdGuardHome核心..."
        # Call update function
        update_adh_core
      else
        # Update only filters
        log "Updating filters only..." "仅更新过滤器..."
        update_filter_rules
      fi
    fi
    
    echo $current_time > "$last_check_file"
  fi
}

# Main service logic
log "Starting AdGuardHome service..." "正在启动AdGuardHome服务..."

# Start AdGuardHome
"$BIN_DIR/AdGuardHome" -c "$BIN_DIR/AdGuardHome.yaml" -w "$BIN_DIR" --no-check-update > /dev/null 2>&1 &

# Save PID
echo $! > "$PID_FILE"

# Perform update checks in background
(
  sleep 300  # Wait 5 minutes after boot before checking updates
  check_module_updates &
  check_adh_updates &
) &

until [ $(getprop init.svc.bootanim) = "stopped" ]; do
  sleep 12
done

/data/adb/agh/scripts/tool.sh start

inotifyd /data/adb/agh/scripts/inotify.sh /data/adb/modules/AdGuardHome:d,n &
