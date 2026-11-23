#!/bin/sh
# Installs or updates the theme for the current user. Use --autostart to launch at login.
# Edited files are kept, and the new version is saved beside them as .new.
set -eu

SOURCE=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd -P)
. "$SOURCE/scripts/install-lib.sh"

case "${1:-}" in
  "" | --autostart) ;;
  *) printf 'Usage: %s [--autostart]\n' "$0" >&2; exit 2 ;;
esac

command -v conky >/dev/null 2>&1 || { echo "conky is not installed" >&2; exit 1; }

place_file() {
  src=$1 dest=$2 key=$3 mode=$4

  if [ ! -e "$dest" ] || is_pristine "$dest" "$key" || cmp -s "$src" "$dest"; then
    install_atomic "$mode" "$src" "$dest"
    record_sum "$key" "$(sum_of "$dest")"
  elif [ ! -e "$dest.new" ] || is_pristine "$dest.new" "$key.new" || cmp -s "$src" "$dest.new"; then
    install_atomic "$mode" "$src" "$dest.new"
    record_sum "$key.new" "$(sum_of "$dest.new")"
    printf 'Kept your edited file. New version: %s\n' "$dest.new"
  else
    printf 'Kept your edited files: %s and %s\n' "$dest" "$dest.new"
  fi
}

if target_is_repo; then
  echo "Repository is already at the install path; skipping file copy"
else
  refuse_linked_target
  mkdir -p "$STATE_DIR" "$TARGET/scripts"
  place_file "$SOURCE/gpu-deck.conf" "$TARGET/gpu-deck.conf" gpu-deck.conf 644
  place_file "$SOURCE/scripts/gpu-panel.sh" "$TARGET/scripts/gpu-panel.sh" scripts/gpu-panel.sh 755
fi

if [ "${1:-}" = "--autostart" ]; then
  mkdir -p "$STATE_DIR"
  entry="$STATE_DIR/autostart.desktop.tmp"
  cat > "$entry" <<'EOF'
[Desktop Entry]
Type=Application
Name=Conky GPU Deck
Exec=sh -c "sleep 5; exec conky -c \\"\\$HOME/.conky/conky-gpu-deck/gpu-deck.conf\\""
X-GNOME-Autostart-enabled=true
EOF

  if [ ! -L "$AUTOSTART" ] && { [ ! -e "$AUTOSTART" ] || is_pristine "$AUTOSTART" autostart || cmp -s "$entry" "$AUTOSTART"; }; then
    mkdir -p "$(dirname -- "$AUTOSTART")"
    install_atomic 644 "$entry" "$AUTOSTART"
    record_sum autostart "$(sum_of "$AUTOSTART")"
  else
    printf 'Kept existing autostart entry: %s\n' "$AUTOSTART" >&2
  fi
  rm -f -- "$entry"
fi

printf 'Installed to %s\nRun: conky -c "%s/gpu-deck.conf"\n' "$TARGET" "$TARGET"
