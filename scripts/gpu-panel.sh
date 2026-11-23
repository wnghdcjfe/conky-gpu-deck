#!/bin/sh
# Prints one Conky markup block per NVIDIA GPU.
# Usage: gpu-panel.sh [gap-px-between-gpus]
# GPU_DECK_SAMPLE=<csv> reads saved query output instead of nvidia-smi.
set -u

FIELDS=index,name,utilization.gpu,memory.used,memory.total,temperature.gpu,temperature.memory,power.draw,power.limit,fan.speed

notice() {
  printf '${font0}${color3}%s${color}\n' "$1"
  exit 0
}

if [ -n "${GPU_DECK_SAMPLE:-}" ]; then
  data=$(cat -- "$GPU_DECK_SAMPLE" 2>/dev/null) || notice "Cannot read sample data"
elif ! command -v nvidia-smi >/dev/null 2>&1; then
  notice "nvidia-smi not found"
else
  # Conky blocks while this runs, so a hung driver must not freeze the widget.
  data=$(timeout -k 1 3 nvidia-smi --query-gpu="$FIELDS" --format=csv,noheader,nounits 2>/dev/null) \
    || notice "GPU query failed"
fi

[ -n "$data" ] || notice "No NVIDIA GPU detected"

printf '%s\n' "$data" | LC_ALL=C awk -F', *' -v bar_width=26 -v gap="${1:-0}" '
function valid(v) { return v ~ /^[0-9]+(\.[0-9]+)?$/ }
function clamp(v) { return v < 0 ? 0 : (v > 100 ? 100 : v) }
function repeat(s, n,    out) { out = ""; while (n-- > 0) out = out s; return out }
function level(v, warn, crit) { return v >= crit ? "${color4}" : (v >= warn ? "${color3}" : "${color2}") }
function bar(pct, color,    filled) {
  filled = int(clamp(pct) * bar_width / 100 + 0.5)
  return color repeat("━", filled) "${color6}" repeat("━", bar_width - filled)
}
function escape(s) { gsub(/\$/, "$$", s); gsub(/#/, "\\#", s); return s }

NF != 10 { printf "${font0}${color3}Unexpected GPU data${color}\n"; next }
{
  index_id = escape($1)
  name = $2
  sub(/^NVIDIA /, "", name)
  name = escape(substr(name, 1, 22))

  temp_text = "${color5}n/a"
  if (valid($6)) temp_text = level($6, 75, 85) sprintf("%d°C", $6)
  mem_temp = valid($7) ? "${color5}  VRAM " level($7, 85, 95) sprintf("%d°C", $7) : ""

  spacer = (NR > 1 && gap ~ /^[0-9]+$/) ? "${voffset " gap "}" : ""
  printf "%s${font3}${color1}GPU %s ${color}%s${alignr}%s%s\n", spacer, index_id, name, temp_text, mem_temp

  if (valid($3)) {
    printf "${font0}${color5}UTIL %s${alignr}${color}%d%%\n", bar($3, level($3, 70, 90)), clamp($3)
  } else {
    printf "${font0}${color5}UTIL %s${alignr}${color5}n/a\n", bar(0, "${color2}")
  }

  if (valid($4) && valid($5) && $5 > 0) {
    pct = $4 * 100 / $5
    printf "${font0}${color5}VRAM %s${alignr}${color}%.1f / %.1f GiB\n", bar(pct, level(pct, 70, 90)), $4 / 1024, $5 / 1024
  } else {
    printf "${font0}${color5}VRAM %s${alignr}${color5}n/a\n", bar(0, "${color2}")
  }

  limit = valid($9) ? sprintf(" / %d", $9 + 0.5) : ""
  power = valid($8) ? sprintf("%d%s W", $8 + 0.5, limit) : "n/a"
  fan = valid($10) ? sprintf("%d%%", $10) : "n/a"
  printf "${font0}${color5}PWR  ${color}%s${alignr}${color5}FAN ${color}%s\n", power, fan
}
'
