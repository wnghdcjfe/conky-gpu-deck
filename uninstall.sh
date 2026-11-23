#!/bin/sh
# Stops the theme and removes installed files. Files the user edited are kept.
set -eu

SOURCE=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd -P)
. "$SOURCE/scripts/install-lib.sh"

if ! target_is_repo; then
  refuse_linked_target
fi

kept=0

# Matching whole arguments covers every launch form without touching other programs.
conf="$TARGET/gpu-deck.conf"
for pid in $(pgrep -u "$(id -u)" -x conky || true); do
  if tr '\0' '\n' < "/proc/$pid/cmdline" 2>/dev/null \
    | grep -qxF -e "$conf" -e "--config=$conf" -e "-c$conf"; then
    kill "$pid" 2>/dev/null || true
  fi
done

if [ -e "$AUTOSTART" ] || [ -L "$AUTOSTART" ]; then
  if is_pristine "$AUTOSTART" autostart; then
    rm -f -- "$AUTOSTART"
  else
    printf 'Kept autostart entry: %s\n' "$AUTOSTART"
    kept=1
  fi
fi

if target_is_repo; then
  echo "Repository is at the install path; keeping its files"
  kept=1
else
  for file in $MANAGED; do
    path="$TARGET/$file"
    if is_pristine "$path" "$file"; then
      rm -f -- "$path"
    elif [ -e "$path" ]; then
      printf 'Kept your edited file: %s\n' "$path"
      kept=1
    fi
  done
  rmdir "$TARGET/scripts" "$TARGET" 2>/dev/null || true
fi

rm -f -- "$MANIFEST"
rmdir "$STATE_DIR" 2>/dev/null || true

if [ "$kept" -eq 1 ]; then
  echo "Partially removed conky-gpu-deck; the files listed above were kept"
else
  echo "Removed conky-gpu-deck"
fi
