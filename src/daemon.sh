#!/usr/bin/env bash
# TimeToSleep daemon — orchestrates wind-down → lockdown → wake-up
# Triggered by launchd at (bedtime - winddown_minutes)

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
source "$ROOT_DIR/lib/config.sh"
source "$ROOT_DIR/lib/stats.sh"
source "$SCRIPT_DIR/media.sh"
source "$SCRIPT_DIR/brightness.sh"

LOG_TAG="[zzz-daemon]"
log() { echo "$(date '+%Y-%m-%d %H:%M:%S') $LOG_TAG $*"; }

# ── Load config ──────────────────────────────────────────────────
BEDTIME=$(config_get "bedtime")
WAKEUP=$(config_get "wakeup")
WINDDOWN=$(config_get "winddown_minutes")
MESSAGE=$(config_get "message")

if [ -z "$BEDTIME" ] || [ -z "$WAKEUP" ]; then
  log "ERROR: Config not found or incomplete. Run 'zzz init' first."
  exit 1
fi

# ── Check if today is an active day ──────────────────────────────
if ! is_active_today; then
  log "Today is not an active day, exiting."
  exit 0
fi

# ── Check for skip ───────────────────────────────────────────────
SKIP_FILE="$ZZZ_DIR/skip_tonight"
if [ -f "$SKIP_FILE" ]; then
  skip_date=$(cat "$SKIP_FILE")
  today=$(date +%Y-%m-%d)
  if [ "$skip_date" = "$today" ]; then
    log "Tonight is skipped by user request."
    stats_record "$today" "skipped"
    rm -f "$SKIP_FILE"
    exit 0
  fi
  rm -f "$SKIP_FILE"
fi

log "Starting wind-down sequence. Bedtime: $BEDTIME, Wake: $WAKEUP, Winddown: ${WINDDOWN}min"

# ── Resolve paths ────────────────────────────────────────────────
OVERLAY_BIN="$HOME/.timetosleep/bin/zzz-overlay"
[ ! -x "$OVERLAY_BIN" ] && OVERLAY_BIN="$ROOT_DIR/bin/zzz-overlay"

# ── Helper: send macOS notification ──────────────────────────────
notify() {
  local title="$1" body="$2"
  osascript -e "display notification \"$body\" with title \"$title\" sound name \"default\"" 2>/dev/null
}

# ── Helper: minutes until a given time (handles midnight wrap) ───
minutes_until() {
  local target_min
  target_min=$(time_to_minutes "$1")
  local now_min
  now_min=$(now_minutes)
  local diff=$(( target_min - now_min ))
  (( diff < 0 )) && (( diff += 1440 ))
  echo $diff
}

# ── Helper: sleep until a given HH:MM ───────────────────────────
sleep_until() {
  local mins
  mins=$(minutes_until "$1")
  if (( mins > 0 && mins < 720 )); then
    log "Sleeping $mins minutes until $1"
    sleep $(( mins * 60 ))
  fi
}

# ── PHASE 1: Wind-down ──────────────────────────────────────────
wind_down() {
  local total_min=$WINDDOWN
  log "Wind-down phase starting ($total_min minutes until lockdown)"

  # Save current state for later restore
  brightness_save
  media_save_volume

  # Notification at start
  notify "TimeToSleep" "还有 ${total_min} 分钟就要锁定了，准备休息吧"

  # Progressive dimming and reminders
  local bed_min
  bed_min=$(time_to_minutes "$BEDTIME")

  # Stage 1: 2/3 of winddown — gentle reminder + slight dim
  local stage1_sleep=$(( total_min * 60 / 3 ))
  sleep $stage1_sleep

  local remaining
  remaining=$(minutes_until "$BEDTIME")
  log "Wind-down stage 2: $remaining minutes remaining"
  notify "TimeToSleep" "还有 ${remaining} 分钟锁定，保存你的工作"
  brightness_fade_to 0.6 10 &

  # Stage 2: another 1/3 — more urgent
  sleep $stage1_sleep

  remaining=$(minutes_until "$BEDTIME")
  log "Wind-down stage 3: $remaining minutes remaining"
  notify "TimeToSleep" "⚠️ ${remaining} 分钟后锁定！"
  media_fade_volume 50 &
  brightness_fade_to 0.3 10 &

  # Stage 3: final stretch — wait until exact bedtime
  sleep_until "$BEDTIME"
}

# ── PHASE 2: Lockdown ───────────────────────────────────────────
lockdown() {
  log "LOCKDOWN activated"
  local today
  today=$(date +%Y-%m-%d)

  # Pause all media
  media_pause_all
  media_mute

  # Set brightness to minimum
  brightness_set 0.05

  # Enable Do Not Disturb (macOS Monterey+)
  shortcuts run "Turn On Focus" 2>/dev/null || true

  # Launch the fullscreen overlay
  if [ -x "$OVERLAY_BIN" ]; then
    log "Launching overlay: $OVERLAY_BIN"

    # Keep overlay alive — if killed, relaunch
    while true; do
      "$OVERLAY_BIN" &
      OVERLAY_PID=$!
      log "Overlay PID: $OVERLAY_PID"
      wait $OVERLAY_PID 2>/dev/null

      # Check if it's wake time
      local remaining
      remaining=$(minutes_until "$WAKEUP")
      if (( remaining <= 1 || remaining > 720 )); then
        log "Wake time reached, stopping overlay"
        break
      fi

      log "Overlay exited unexpectedly, relaunching in 2s..."
      sleep 2
    done
  else
    log "WARNING: Overlay binary not found at $OVERLAY_BIN"
    log "Falling back to terminal lockdown"
    # Fallback: just wait
    sleep_until "$WAKEUP"
  fi

  # Record completion
  stats_record "$today" "completed"
}

# ── PHASE 3: Wake up ────────────────────────────────────────────
wake_up() {
  log "Good morning! Restoring system."

  # Restore brightness
  brightness_restore

  # Restore volume
  media_restore_volume

  # Disable Do Not Disturb
  shortcuts run "Turn Off Focus" 2>/dev/null || true

  # Show streak
  local streak
  streak=$(stats_streak)
  if (( streak > 0 )); then
    notify "TimeToSleep" "早安！你已经连续早睡 ${streak} 天了 🌅"
  else
    notify "TimeToSleep" "早安！新的一天开始了 🌅"
  fi

  log "Daemon complete."
}

# ── Main sequence ────────────────────────────────────────────────
wind_down
lockdown
wake_up
