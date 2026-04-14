#!/usr/bin/env bash
# TimeToSleep onboarding — zzz init

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
source "$ROOT_DIR/lib/ui.sh"
source "$ROOT_DIR/lib/config.sh"
source "$ROOT_DIR/lib/stats.sh"

run_init() {
  clear 2>/dev/null || true

  ui_moon

  ui_box "$(printf '%b\n' \
    "${BOLD}你即将和自己签一份早睡契约。${RESET}" \
    "" \
    "从今天起，到了约定的时间，" \
    "电脑会替你守住这份约定。" \
    "" \
    "${DIM}锁定后到起床前，无法解锁。${RESET}")"

  sleep 1

  # ── bedtime ──
  local bedtime
  ui_input_time "你想几点睡觉？" bedtime "23:00"

  # ── wakeup ──
  local wakeup
  ui_input_time "你想几点起床？" wakeup "07:00"

  # ── active days ──
  local days_csv
  ui_multiselect "哪几天启用？" days_csv \
    "周一:1:selected" \
    "周二:2:selected" \
    "周三:3:selected" \
    "周四:4:selected" \
    "周五:5:selected" \
    "周六:6" \
    "周日:7"

  # ── wind-down ──
  local winddown
  ui_select "提前多久开始提醒？" winddown \
    "15 分钟:15" \
    "30 分钟:30" \
    "45 分钟:45" \
    "60 分钟:60"

  # ── show contract ──
  ui_blank

  local days_display=""
  local day_names=("" "周一" "周二" "周三" "周四" "周五" "周六" "周日")
  IFS=',' read -ra day_arr <<< "$days_csv"
  for d in "${day_arr[@]}"; do
    [ -n "$days_display" ] && days_display+="、"
    days_display+="${day_names[$d]}"
  done

  ui_box "$(printf '%b\n' \
    "${BOLD}${C_PURPLE}你的早睡契约${RESET}" \
    "" \
    "  睡觉：${BOLD}$bedtime${RESET}    起床：${BOLD}$wakeup${RESET}" \
    "  启用：${BOLD}$days_display${RESET}" \
    "  提前 ${BOLD}$winddown 分钟${RESET}开始提醒" \
    "" \
    "  ${C_RED}锁定后到起床前，无法解锁。${RESET}")"

  ui_blank

  # ── activation phrase (type-to-confirm) ──
  if ! ui_type_confirm "最后一步：请键入下面这句以激活：" "和晚睡说再见"; then
    ui_blank
    ui_error "未正确输入，设置已取消。"
    ui_dim "想好了再来：zzz init"
    ui_blank
    return 1
  fi

  ui_blank
  ui_success "已确认！"

  # ── save config ──
  config_ensure_dir

  # convert days_csv to JSON array
  local days_json="["
  local first=true
  IFS=',' read -ra day_arr <<< "$days_csv"
  for d in "${day_arr[@]}"; do
    $first || days_json+=","
    days_json+="\"$d\""
    first=false
  done
  days_json+="]"

  cat > "$ZZZ_CONFIG" << ENDJSON
{
  "bedtime": "$bedtime",
  "wakeup": "$wakeup",
  "days": $days_json,
  "winddown_minutes": $winddown,
  "activated_at": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "version": "1.0.0"
}
ENDJSON

  # init stats
  stats_ensure

  # ── setup schedule ──
  source "$ROOT_DIR/lib/schedule.sh"
  schedule_install
  ui_success "定时任务已激活"

  ui_blank
  ui_box "$(printf '%b\n' \
    "${C_GREEN}${BOLD}设置完成！${RESET}" \
    "" \
    "今晚 ${BOLD}$bedtime${RESET} 你的电脑将开始锁定。" \
    "提前 ${BOLD}$winddown 分钟${RESET}会收到提醒。" \
    "" \
    "${DIM}输入 zzz 查看今晚状态${RESET}")"
  ui_blank
}

run_init
