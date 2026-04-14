#!/usr/bin/env bash
# TimeToSleep launchd schedule manager

SCRIPT_DIR_SCHED="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR_SCHED/config.sh"

AGENT_LABEL="com.timetosleep.daemon"
PLIST_PATH="$HOME/Library/LaunchAgents/${AGENT_LABEL}.plist"

# Find the daemon script path (installed location)
_daemon_path() {
  local installed="$HOME/.timetosleep/bin/zzz-daemon"
  local dev="$(cd "$SCRIPT_DIR_SCHED/../src" && pwd)/daemon.sh"
  if [ -x "$installed" ]; then
    echo "$installed"
  else
    echo "$dev"
  fi
}

# Calculate wind-down start time from config
_winddown_start() {
  local bedtime
  bedtime=$(config_get "bedtime")
  local winddown
  winddown=$(config_get "winddown_minutes")
  local bed_min
  bed_min=$(time_to_minutes "$bedtime")
  local start_min=$(( bed_min - winddown ))
  # handle wrap-around midnight
  (( start_min < 0 )) && (( start_min += 1440 ))
  minutes_to_time $start_min
}

schedule_install() {
  local daemon_path
  daemon_path=$(_daemon_path)
  local start_time
  start_time=$(_winddown_start)
  local hour="${start_time%%:*}"
  local minute="${start_time##*:}"

  # Remove leading zeros for plist (launchd wants integers)
  hour=$((10#$hour))
  minute=$((10#$minute))

  mkdir -p "$(dirname "$PLIST_PATH")"

  cat > "$PLIST_PATH" << PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key>
  <string>${AGENT_LABEL}</string>

  <key>ProgramArguments</key>
  <array>
    <string>/bin/bash</string>
    <string>${daemon_path}</string>
  </array>

  <key>StartCalendarInterval</key>
  <dict>
    <key>Hour</key>
    <integer>${hour}</integer>
    <key>Minute</key>
    <integer>${minute}</integer>
  </dict>

  <key>StandardOutPath</key>
  <string>${ZZZ_DIR}/daemon.log</string>
  <key>StandardErrorPath</key>
  <string>${ZZZ_DIR}/daemon.log</string>

  <key>EnvironmentVariables</key>
  <dict>
    <key>HOME</key>
    <string>${HOME}</string>
    <key>PATH</key>
    <string>/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin</string>
  </dict>
</dict>
</plist>
PLIST

  # load the agent
  launchctl unload "$PLIST_PATH" 2>/dev/null
  launchctl load "$PLIST_PATH" 2>/dev/null
}

schedule_uninstall() {
  if [ -f "$PLIST_PATH" ]; then
    launchctl unload "$PLIST_PATH" 2>/dev/null
    rm -f "$PLIST_PATH"
  fi
}

schedule_is_installed() {
  [ -f "$PLIST_PATH" ] && launchctl list "$AGENT_LABEL" &>/dev/null
}

# Reinstall schedule (e.g. after config change)
schedule_update() {
  schedule_install
}
