. /data/adb/agh/settings.conf
. /data/adb/agh/scripts/base.sh

start_adguardhome() {
  # check if AdGuardHome is already running
  if [ -f "$PID_FILE" ] && ps | grep -w "$adg_pid" | grep -q "AdGuardHome"; then
    log "AdGuardHome is already running" "AdGuardHome 已经在运行"
    exit 0
  fi

  # to fix https://github.com/AdguardTeam/AdGuardHome/issues/7002
  export SSL_CERT_DIR="/system/etc/security/cacerts/"
  # set timezone to Shanghai
  export TZ="Asia/Shanghai"

  # backup old log and overwrite new log
  if [ -f "$AGH_DIR/bin.log" ]; then
    mv "$AGH_DIR/bin.log" "$AGH_DIR/bin.log.bak"
  fi

  # run binary
  busybox setuidgid "$adg_user:$adg_group" "$BIN_DIR/AdGuardHome" >"$AGH_DIR/bin.log" 2>&1 &
  adg_pid=$!

  # check if AdGuardHome started successfully
  if ps | grep -w "$adg_pid" | grep -q "AdGuardHome"; then
    echo "$adg_pid" >"$PID_FILE"
    # check if iptables is enabled
    if [ "$enable_iptables" = true ]; then
      $SCRIPT_DIR/iptables.sh enable
      log "🥰 started PID: $adg_pid iptables: enabled" "🥰 启动成功 PID: $adg_pid iptables 已启用"
      update_description "🥰 Started PID: $adg_pid iptables: enabled" "🥰 启动成功 PID: $adg_pid iptables 已启用"
    else
      log "🥰 started PID: $adg_pid iptables: disabled" "🥰 启动成功 PID: $adg_pid iptables 已禁用"
      update_description "🥰 Started PID: $adg_pid iptables: disabled" "🥰 启动成功 PID: $adg_pid iptables 已禁用"
    fi
  else
    log "😭 Error occurred, check logs for details" "😭 出现错误，请检查日志以获取详细信息"
    update_description "😭 Error occurred, check logs for details" "😭 出现错误，请检查日志以获取详细信息"
    $SCRIPT_DIR/debug.sh
    exit 1
  fi
}

stop_adguardhome() {
  if [ -f "$PID_FILE" ]; then
    pid=$(cat "$PID_FILE")
    kill $pid || kill -9 $pid
    rm "$PID_FILE"
    log "AdGuardHome stopped (PID: $pid)" "AdGuardHome 已停止 (PID: $pid)"
  else
    pkill -f "AdGuardHome" || pkill -9 -f "AdGuardHome"
    log "AdGuardHome force stopped" "AdGuardHome 强制停止"
  fi
  update_description "❌ Stopped" "❌ 已停止"
  $SCRIPT_DIR/iptables.sh disable
}

toggle_adguardhome() {
  if [ -f "$PID_FILE" ] && ps | grep -w "$(cat $PID_FILE)" | grep -q "AdGuardHome"; then
    stop_adguardhome
  else
    start_adguardhome
  fi
}

# Function to update AdGuardHome binary and filters
update_adh_core() {
  local arch
  arch=$(uname -m)
  case "$arch" in
    aarch64|arm64)
      ARCH="arm64"
      ;;
    armv7l|arm)
      ARCH="armv7"
      ;;
    *)
      log "Unsupported architecture: $arch" "不支持的架构: $arch"
      return 1
      ;;
  esac

  log "Starting AdGuardHome core update for $ARCH..." "开始更新 AdGuardHome 核心 ($ARCH)..."

  # Get latest release info
  local api_response
  api_response=$(curl -s https://api.github.com/repos/AdguardTeam/AdGuardHome/releases/latest)
  local version_tag
  version_tag=$(echo "$api_response" | grep '"tag_name":' | sed -E 's/.*"([^"]+)".*/\1/')
  
  if [ -z "$version_tag" ]; then
    log "Failed to get latest version info" "获取最新版本信息失败"
    return 1
  fi

  log "Found latest version: $version_tag" "发现最新版本: $version_tag"

  # Update module.prop with new version
  sed -i "s/^version=.*/version=${version_tag#v}/" "$MOD_PATH/module.prop"
  sed -i "s/^versionCode=.*/versionCode=$(date +%Y%m%d)/" "$MOD_PATH/module.prop"

  # Download new binary
  local binary_url="https://github.com/AdguardTeam/AdGuardHome/releases/latest/download/AdGuardHome_linux_${ARCH}.tar.gz"
  local temp_archive="/tmp/AdGuardHome.tar.gz"
  
  if ! curl -L -o "$temp_archive" "$binary_url"; then
    log "Failed to download new binary" "下载新二进制文件失败"
    return 1
  fi

  # Stop AdGuardHome if running
  if [ -f "$PID_FILE" ]; then
    local pid=$(cat "$PID_FILE" 2>/dev/null || echo "")
    if [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null; then
      log "Stopping AdGuardHome..." "正在停止 AdGuardHome..."
      kill "$pid"
      sleep 3
    fi
  fi

  # Extract and replace binary
  local temp_dir="/tmp/agh-update"
  mkdir -p "$temp_dir"
  tar -xzf "$temp_archive" -C "$temp_dir"
  
  # Backup current binary
  if [ -f "$BIN_DIR/AdGuardHome" ]; then
    cp "$BIN_DIR/AdGuardHome" "$BIN_DIR/AdGuardHome.bak"
  fi
  
  mv "$temp_dir/AdGuardHome" "$BIN_DIR/AdGuardHome"
  chmod +x "$BIN_DIR/AdGuardHome"
  
  # Cleanup
  rm -rf "$temp_archive" "$temp_dir"

  log "AdGuardHome core updated successfully to $version_tag" "AdGuardHome 核心成功更新到 $version_tag"

  # Update filter rules
  update_filter_rules
}

# Function to update filter rules only
update_filter_rules() {
  log "Updating filter rules..." "正在更新过滤规则..."
  
  if ! curl -o "$BIN_DIR/filter.txt" "https://raw.githubusercontent.com/TG-Twilight/AWAvenue-Ads-Rule/release/rules/ads-filter.txt"; then
    log "Failed to update filter rules" "更新过滤规则失败"
    return 1
  fi
  
  log "Filter rules updated successfully" "过滤规则更新成功"
}

case "$1" in
start)
  start_adguardhome
  ;;
stop)
  stop_adguardhome
  ;;
toggle)
  toggle_adguardhome
  ;;
*)
  echo "Usage: $0 {start|stop|toggle}"
  exit 1
  ;;
esac
