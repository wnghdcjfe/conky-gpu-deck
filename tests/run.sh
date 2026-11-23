#!/bin/sh
# Checks the panel renderer, Conky integration, and install lifecycle.
set -u

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
PANEL="$ROOT/scripts/gpu-panel.sh"
failures=0

check() {
  case "$2" in
    *"$3"*) printf 'ok   - %s\n' "$1" ;;
    *) printf 'FAIL - %s (missing: %s)\n' "$1" "$3"; failures=$((failures + 1)) ;;
  esac
}

refute() {
  case "$2" in
    *"$3"*) printf 'FAIL - %s (found: %s)\n' "$1" "$3"; failures=$((failures + 1)) ;;
    *) printf 'ok   - %s\n' "$1" ;;
  esac
}

truth() {
  label=$1
  shift
  if "$@"; then
    printf 'ok   - %s\n' "$label"
  else
    printf 'FAIL - %s\n' "$label"
    failures=$((failures + 1))
  fi
}

absent() { [ ! -e "$1" ]; }
has_line() { grep -qxF -e "$1" "$2"; }
lacks_line() { ! grep -qxF -e "$1" "$2"; }

as_user() {
  user_home=$1
  shift
  HOME="$user_home" XDG_CONFIG_HOME="$user_home/.config" \
    XDG_STATE_HOME="$user_home/.local/state" sh "$@" >/dev/null 2>&1
}

fails_as_user() { ! as_user "$@"; }

copy_repo() {
  mkdir -p "$1/scripts"
  cp "$ROOT/install.sh" "$ROOT/uninstall.sh" "$ROOT/gpu-deck.conf" "$1/"
  cp "$PANEL" "$ROOT/scripts/install-lib.sh" "$1/scripts/"
}

sample=$(GPU_DECK_SAMPLE="$ROOT/tests/fixtures/sample.csv" sh "$PANEL")
check "renders GPU 0" "$sample" 'GPU 0 ${color}RTX A6000'
check "renders GPU 3" "$sample" 'GPU 3 ${color}RTX A6000'
check "formats VRAM in GiB" "$sample" '40.3 / 48.0 GiB'
check "marks warm GPU as warning" "$sample" '${color3}78°C'
check "rounds power" "$sample" '271 / 300 W'
refute "hides unavailable VRAM temperature" "$sample" '${color5}  VRAM '

spaced=$(GPU_DECK_SAMPLE="$ROOT/tests/fixtures/sample.csv" sh "$PANEL" 13)
check "adds gap between GPUs" "$spaced" '${voffset 13}${font3}${color1}GPU 1'
refute "adds no gap before first GPU" "$spaced" '${voffset 13}${font3}${color1}GPU 0'

edge=$(GPU_DECK_SAMPLE="$ROOT/tests/fixtures/edge.csv" sh "$PANEL")
check "shows VRAM temperature when reported" "$edge" '${color5}  VRAM ${color4}96°C'
check "marks hot GPU as critical" "$edge" '${color4}90°C'
check "handles missing metrics" "$edge" 'GPU 1 ${color}Tesla T4${alignr}${color5}n/a'
check "escapes Conky variables in names" "$edge" 'Vendor $$HOME GPU'
check "reports malformed rows" "$edge" 'Unexpected GPU data'
check "escapes Conky comments in names" "$edge" 'Vendor \#1 GPU'
refute "never prints raw N/A markers" "$edge" '[N/A]'
check "keeps missing values readable" "$edge" '${alignr}${color5}n/a'
refute "omits unit for missing power" "$edge" 'n/a W'
refute "caps displayed utilization" "$edge" '150%'

missing=$(PATH=/nonexistent /bin/sh "$PANEL")
check "reports missing nvidia-smi" "$missing" 'nvidia-smi not found'

empty_file=$(mktemp) || exit 1
empty=$(GPU_DECK_SAMPLE="$empty_file" sh "$PANEL")
rm -f "$empty_file"
check "reports no GPUs" "$empty" 'No NVIDIA GPU detected'

# Runs the real config through Conky from a path that needs shell quoting.
render_from() {
  tmp=$(mktemp -d) || return 1
  theme="$tmp/$1"
  mkdir -p "$theme/scripts"
  cp "$ROOT/gpu-deck.conf" "$theme/"
  cp "$PANEL" "$theme/scripts/"
  cat > "$tmp/headless.conf" <<EOF
dofile([==[$theme/gpu-deck.conf]==])
conky.config.out_to_x = false
conky.config.out_to_console = true
conky.config.background = false
conky.config.total_run_times = 2
EOF
  GPU_DECK_SAMPLE="$ROOT/tests/fixtures/sample.csv" GPU_DECK_SCALE=1 \
    timeout 10 conky -c "$tmp/headless.conf" 2>&1
  rm -rf "$tmp"
}

if command -v conky >/dev/null 2>&1; then
  rendered=$(render_from "theme with space's")
  check "Conky renders first GPU from quoted path" "$rendered" 'GPU 0 RTX A6000'
  check "Conky renders last GPU from quoted path" "$rendered" 'GPU 3 RTX A6000'
  refute "Conky shell command stays valid" "$rendered" 'Syntax error'
  rendered=$(render_from 'theme $HOME x')
  check "Conky renders from path containing a dollar sign" "$rendered" 'GPU 3 RTX A6000'
  rendered=$(render_from 'x}${exec printf IN%sED JECT}')
  check "rejects theme path with braces" "$rendered" 'must not contain { or }'
  refute "does not execute markup from theme path" "$rendered" 'INJECTED'
else
  printf 'FAIL - conky is required for the integration checks\n'
  failures=$((failures + 1))
fi

refute "uses DPI-independent font sizes" "$(cat "$ROOT/gpu-deck.conf")" ':size='

# Edited files survive reinstall and uninstall.
home=$(mktemp -d) || exit 1
installed="$home/.conky/conky-gpu-deck"
autostart="$home/.config/autostart/conky-gpu-deck.desktop"

as_user "$home" "$ROOT/install.sh" --autostart
truth "installs config" test -f "$installed/gpu-deck.conf"
truth "installs executable panel" test -x "$installed/scripts/gpu-panel.sh"
truth "creates autostart entry" has_line 'Name=Conky GPU Deck' "$autostart"

echo '-- local edit' >> "$installed/gpu-deck.conf"
echo '# local edit' >> "$installed/scripts/gpu-panel.sh"
echo '# local edit' >> "$autostart"
as_user "$home" "$ROOT/install.sh" --autostart
truth "reinstall keeps edited config" has_line '-- local edit' "$installed/gpu-deck.conf"
truth "reinstall saves new config beside it" cmp -s "$ROOT/gpu-deck.conf" "$installed/gpu-deck.conf.new"
truth "reinstall keeps edited panel" has_line '# local edit' "$installed/scripts/gpu-panel.sh"
truth "reinstall keeps edited autostart" has_line '# local edit' "$autostart"

echo '-- merge in progress' >> "$installed/gpu-deck.conf.new"
as_user "$home" "$ROOT/install.sh"
truth "reinstall keeps edited .new file" has_line '-- merge in progress' "$installed/gpu-deck.conf.new"

as_user "$home" "$ROOT/uninstall.sh"
truth "uninstall keeps edited config" has_line '-- local edit' "$installed/gpu-deck.conf"
truth "uninstall keeps edited .new file" has_line '-- merge in progress' "$installed/gpu-deck.conf.new"
truth "uninstall keeps edited panel" has_line '# local edit' "$installed/scripts/gpu-panel.sh"
truth "uninstall keeps edited autostart" has_line '# local edit' "$autostart"
truth "uninstall removes manifest" absent "$home/.local/state/conky-gpu-deck/manifest"
rm -rf "$home"

# Unedited files follow updates and are removed cleanly.
home=$(mktemp -d) || exit 1
installed="$home/.conky/conky-gpu-deck"
autostart="$home/.config/autostart/conky-gpu-deck.desktop"
next="$home/next-release"
copy_repo "$next"
echo '-- next release' >> "$next/gpu-deck.conf"
echo '# next release' >> "$next/scripts/gpu-panel.sh"

as_user "$home" "$ROOT/install.sh" --autostart
as_user "$home" "$next/install.sh" --autostart
truth "update replaces unedited config" cmp -s "$next/gpu-deck.conf" "$installed/gpu-deck.conf"
truth "update replaces unedited panel" cmp -s "$next/scripts/gpu-panel.sh" "$installed/scripts/gpu-panel.sh"
truth "update creates no .new file" absent "$installed/gpu-deck.conf.new"
as_user "$home" "$next/uninstall.sh"
truth "uninstall removes updated theme" absent "$installed"
truth "uninstall removes own autostart entry" absent "$autostart"
truth "uninstall removes state directory" absent "$home/.local/state/conky-gpu-deck"

mkdir -p "$(dirname -- "$autostart")"
echo 'Name=Another App' > "$autostart"
as_user "$home" "$ROOT/install.sh" --autostart
truth "keeps foreign autostart entry on install" has_line 'Name=Another App' "$autostart"
truth "does not replace foreign autostart entry" lacks_line 'Name=Conky GPU Deck' "$autostart"
as_user "$home" "$ROOT/uninstall.sh"
truth "keeps foreign autostart entry on uninstall" has_line 'Name=Another App' "$autostart"
rm -rf "$home"

# Unreadable files without a record belong to the user.
home=$(mktemp -d) || exit 1
installed="$home/.conky/conky-gpu-deck"
autostart="$home/.config/autostart/conky-gpu-deck.desktop"
mkdir -p "$installed/scripts" "$(dirname -- "$autostart")"
echo 'private config' > "$installed/gpu-deck.conf"
echo 'private entry' > "$autostart"
chmod 000 "$installed/gpu-deck.conf" "$autostart"
as_user "$home" "$ROOT/uninstall.sh"
truth "uninstall keeps unreadable config" test -e "$installed/gpu-deck.conf"
truth "uninstall keeps unreadable autostart" test -e "$autostart"
as_user "$home" "$ROOT/install.sh"
chmod 644 "$installed/gpu-deck.conf" "$autostart"
truth "install keeps unreadable config" has_line 'private config' "$installed/gpu-deck.conf"
rm -rf "$home"

# An interrupted update leaves the working install intact.
home=$(mktemp -d) || exit 1
installed="$home/.conky/conky-gpu-deck"
next="$home/next-release"
copy_repo "$next"
echo '-- next release' >> "$next/gpu-deck.conf"
as_user "$home" "$ROOT/install.sh"
( ulimit -f 1; as_user "$home" "$next/install.sh" ) 2>/dev/null
truth "interrupted update keeps working config" cmp -s "$ROOT/gpu-deck.conf" "$installed/gpu-deck.conf"
truth "interrupted update leaves no partial file" test -z "$(find "$installed" -name '*.tmp.*')"
as_user "$home" "$next/install.sh"
truth "update recovers after interruption" cmp -s "$next/gpu-deck.conf" "$installed/gpu-deck.conf"
rm -rf "$home"

# Symbolic links are never written through.
home=$(mktemp -d) || exit 1
installed="$home/.conky/conky-gpu-deck"
mkdir -p "$installed" "$home/dotfiles"
echo 'dotfile' > "$home/dotfiles/gpu-deck.conf"
ln -s "$home/dotfiles/gpu-deck.conf" "$installed/gpu-deck.conf"
truth "refuses to install through file symlink" fails_as_user "$home" "$ROOT/install.sh"
truth "leaves file symlink target unchanged" has_line 'dotfile' "$home/dotfiles/gpu-deck.conf"
rm -f "$installed/gpu-deck.conf"

echo 'dotfile' > "$home/dotfiles/gpu-panel.sh"
ln -s "$home/dotfiles" "$installed/scripts"
truth "refuses to install through directory symlink" fails_as_user "$home" "$ROOT/install.sh"
truth "refuses to uninstall through directory symlink" fails_as_user "$home" "$ROOT/uninstall.sh"
truth "leaves directory symlink target unchanged" has_line 'dotfile' "$home/dotfiles/gpu-panel.sh"
rm -rf "$home"

# A checkout at the install path is left alone, whichever copy runs the scripts.
home=$(mktemp -d) || exit 1
clone="$home/.conky/conky-gpu-deck"
copy_repo "$clone"
truth "install succeeds inside install path" as_user "$home" "$clone/install.sh"
as_user "$home" "$clone/uninstall.sh"
truth "uninstall keeps repository config" test -f "$clone/gpu-deck.conf"
truth "uninstall keeps repository script" test -f "$clone/scripts/gpu-panel.sh"

mkdir "$clone/.git"
echo '# uncommitted' >> "$clone/scripts/gpu-panel.sh"
as_user "$home" "$ROOT/install.sh"
truth "other copy does not overwrite checkout" has_line '# uncommitted' "$clone/scripts/gpu-panel.sh"
as_user "$home" "$ROOT/uninstall.sh"
truth "other copy does not delete checkout" has_line '# uncommitted' "$clone/scripts/gpu-panel.sh"
rm -rf "$home"

[ "$failures" -eq 0 ] && printf 'All checks passed\n' || { printf '%d check(s) failed\n' "$failures"; exit 1; }
