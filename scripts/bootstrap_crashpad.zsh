#!/usr/bin/env zsh
# Bootstraps Crashpad sources (and depot_tools) so your other build scripts can run.
#
# Examples:
#   scripts/bootstrap_crashpad.zsh --dest external/crashpad
#   scripts/bootstrap_crashpad.zsh --dest ~/src/crashpad --ndk "$HOME/Library/Android/sdk/ndk/28.2.13676358"
#
# What it does:
#   - Clones (or reuses) depot_tools
#   - Fetches Crashpad with all Chromium deps via gclient
#   - Prints next-step commands to build with scripts/crashpad_all.zsh
#
# Notes:
#   - Safe to re-run; it won’t reclone if dirs already exist.
#   - Works on macOS/Linux.

set -euo pipefail

print_usage() {
  cat <<EOF
Usage: $(basename "$0") --dest <crashpad_dir> [--depot-tools <dir>] [--branch <ref>] [--ndk <path>]
  --dest         Where to put the Crashpad checkout (e.g. external/crashpad)
  --depot-tools  Optional path for depot_tools (default: <dest>/../depot_tools)
  --branch       Crashpad git ref to checkout (default: origin/main)
  --ndk          Optional ANDROID NDK path; just exported for your convenience
EOF
}

DEST=""
DEPOT_TOOLS=""
BRANCH="origin/main"
NDK_PATH="${NDK:-${ANDROID_NDK_ROOT:-}}"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --dest) DEST="$2"; shift 2 ;;
    --depot-tools) DEPOT_TOOLS="$2"; shift 2 ;;
    --branch) BRANCH="$2"; shift 2 ;;
    --ndk) NDK_PATH="$2"; shift 2 ;;
    -h|--help) print_usage; exit 0 ;;
    *) echo "Unknown arg: $1"; print_usage; exit 1 ;;
  esac
done

[[ -z "$DEST" ]] && { echo "ERROR: --dest is required"; print_usage; exit 1; }

# Resolve absolute paths
mkdir -p "$DEST"
DEST="$(cd "$DEST" && pwd -P)"

if [[ -z "${DEPOT_TOOLS:-}" ]]; then
  # put depot_tools next to the crashpad dir by default
  DEPOT_TOOLS="$(cd "$DEST/.." && pwd -P)/depot_tools"
fi

# 1) depot_tools
if [[ ! -d "$DEPOT_TOOLS/.git" ]]; then
  echo "Cloning depot_tools into: $DEPOT_TOOLS"
  mkdir -p "$DEPOT_TOOLS"
  git clone https://chromium.googlesource.com/chromium/tools/depot_tools.git "$DEPOT_TOOLS"
else
  echo "depot_tools already present: $DEPOT_TOOLS (pulling)"
  git -C "$DEPOT_TOOLS" pull --ff-only || true
fi

FETCH="$DEPOT_TOOLS/fetch"
GCLIENT="$DEPOT_TOOLS/gclient"

[[ -x "$FETCH" && -x "$GCLIENT" ]] || { echo "ERROR: fetch/gclient not found in $DEPOT_TOOLS"; exit 1; }

# 2) Crashpad
if [[ ! -d "$DEST/.git" ]]; then
  echo "Fetching Crashpad (this may take a while)..."
  # 'fetch crashpad' creates the directory itself; run from parent
  pushd "$(dirname "$DEST")" >/dev/null
  "$FETCH" crashpad
  popd >/dev/null
else
  echo "Crashpad repo already exists: $DEST"
fi

# Ensure we're at the requested branch/ref
git -C "$DEST" fetch origin
git -C "$DEST" checkout "$BRANCH" || true

# gclient config/sync (guard for unmanaged checkouts)
if [[ ! -f "$DEST/.gclient" && ! -f "$(dirname "$DEST")/.gclient" ]]; then
  echo "Configuring gclient for Crashpad..."
  pushd "$(dirname "$DEST")" >/dev/null
  "$GCLIENT" config --name="$(basename "$DEST")" --unmanaged https://chromium.googlesource.com/crashpad/crashpad
  popd >/dev/null
fi

echo "Syncing dependencies via gclient..."
pushd "$(dirname "$DEST")" >/dev/null
"$GCLIENT" sync -D
popd >/dev/null

# Optional: export NDK to help your next commands
if [[ -n "$NDK_PATH" ]]; then
  echo "NDK path detected/provided:"
  echo "  $NDK_PATH"
else
  echo "NOTE: No NDK path provided. You can export one later as NDK=/path/to/android-ndk"
fi

cat <<EOS

✅ Crashpad checkout ready at:
  $DEST

Next steps:

1) Export NDK (if not already):
   export NDK="${NDK_PATH:-/path/to/android-ndk}"

2) Build Crashpad for your ABIs (example):
   scripts/crashpad_all.zsh --abis "arm64-v8a x86 x86_64 armeabi-v7a" --api 26 --out "$DEST/out"

3) Copy artifacts into your Android library (example):
   scripts/copy_crashpad_static_libs.sh --src "$DEST/out" --dst ./crashkit/src/main/cpp/crashpad/lib/ --abis "arm64-v8a x86 x86_64 armeabi-v7a"

4) Build the Android project:
   ./gradlew clean assembleDebug

EOS

