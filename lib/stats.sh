#!/usr/bin/env bash
# TimeToSleep stats tracker

SCRIPT_DIR_STATS="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR_STATS/config.sh"

STATS_FILE="$ZZZ_DIR/stats.json"

stats_ensure() {
  config_ensure_dir
  if [ ! -f "$STATS_FILE" ]; then
    echo '{"records":[],"installed_at":"'"$(date -u +%Y-%m-%dT%H:%M:%SZ)"'"}' > "$STATS_FILE"
  fi
}

# Record a lockdown event
# Usage: stats_record "2025-04-14" "completed" | "skipped:reason"
stats_record() {
  local date="$1" status="$2"
  stats_ensure
  python3 -c "
import json
with open('$STATS_FILE') as f: d = json.load(f)
d['records'] = [r for r in d.get('records', []) if r.get('date') != '$date']
d['records'].append({'date': '$date', 'status': '$status'})
d['records'].sort(key=lambda r: r['date'])
with open('$STATS_FILE', 'w') as f: json.dump(d, f, indent=2, ensure_ascii=False)
"
}

# Get current streak of consecutive "completed" nights
stats_streak() {
  stats_ensure
  python3 -c "
import json
from datetime import datetime, timedelta

with open('$STATS_FILE') as f: d = json.load(f)
records = {r['date']: r['status'] for r in d.get('records', [])}
streak = 0
day = datetime.now().date() - timedelta(days=1)  # start from yesterday
while True:
    ds = day.strftime('%Y-%m-%d')
    if records.get(ds) == 'completed':
        streak += 1
        day -= timedelta(days=1)
    else:
        break
print(streak)
"
}

# Get total stats: total_nights, completed, skipped
stats_summary() {
  stats_ensure
  python3 -c "
import json
with open('$STATS_FILE') as f: d = json.load(f)
records = d.get('records', [])
total = len(records)
completed = sum(1 for r in records if r['status'] == 'completed')
skipped = total - completed
installed = d.get('installed_at', 'unknown')
print(f'{total}|{completed}|{skipped}|{installed}')
"
}

# Get total usage days (since install)
stats_days_since_install() {
  stats_ensure
  python3 -c "
import json
from datetime import datetime
with open('$STATS_FILE') as f: d = json.load(f)
installed = d.get('installed_at', '')
if installed:
    dt = datetime.fromisoformat(installed.replace('Z', '+00:00'))
    days = (datetime.now(dt.tzinfo) - dt).days
    print(max(days, 0))
else:
    print(0)
"
}
