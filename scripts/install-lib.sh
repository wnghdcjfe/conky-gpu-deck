# Shared by install.sh and uninstall.sh.
# The manifest records each installed file's checksum, which separates files
# left as installed from files the user edited.

TARGET="$HOME/.conky/conky-gpu-deck"
AUTOSTART="${XDG_CONFIG_HOME:-$HOME/.config}/autostart/conky-gpu-deck.desktop"
STATE_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/conky-gpu-deck"
MANIFEST="$STATE_DIR/manifest"
MANAGED="gpu-deck.conf gpu-deck.conf.new scripts/gpu-panel.sh scripts/gpu-panel.sh.new"

sum_of() {
  cksum < "$1" | awk '{ print $1 ":" $2 }'
}

recorded_sum() {
  if [ -f "$MANIFEST" ]; then
    awk -v key="$1" '$2 == key { print $1 }' "$MANIFEST"
  fi
}

record_sum() {
  mkdir -p "$STATE_DIR"
  {
    if [ -f "$MANIFEST" ]; then
      awk -v key="$1" '$2 != key' "$MANIFEST"
    fi
    printf '%s %s\n' "$2" "$1"
  } > "$MANIFEST.tmp"
  mv -- "$MANIFEST.tmp" "$MANIFEST"
}

# True when the file still has the content recorded at install time.
# A file with no record, or one that cannot be read, is treated as the user's.
is_pristine() {
  rec=$(recorded_sum "$2")
  [ -n "$rec" ] && [ -f "$1" ] && [ ! -L "$1" ] && [ "$(sum_of "$1" 2>/dev/null)" = "$rec" ]
}

# Replaces the destination only after a complete copy exists.
install_atomic() {
  tmp="$3.tmp.$$"
  if install -m "$1" -- "$2" "$tmp" && mv -f -- "$tmp" "$3"; then
    return 0
  fi
  rm -f -- "$tmp"
  return 1
}

# A checkout at the install path is the user's working copy, so it is never modified.
target_is_repo() {
  [ -e "$TARGET/.git" ] || [ -e "$TARGET/install.sh" ]
}

refuse_linked_target() {
  for path in "$TARGET" "$TARGET/scripts"; do
    if [ -L "$path" ]; then
      printf 'Refusing to modify symbolic link: %s\n' "$path" >&2
      exit 1
    fi
  done
  for file in $MANAGED; do
    if [ -L "$TARGET/$file" ]; then
      printf 'Refusing to modify symbolic link: %s\n' "$TARGET/$file" >&2
      exit 1
    fi
  done
}
