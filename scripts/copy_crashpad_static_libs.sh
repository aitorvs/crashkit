#!/usr/bin/env bash
set -euo pipefail

# copy_crashpad_artifacts.sh
# Copies Crashpad static libs + handler per ABI under:
#   <DST>/lib/<abi>/base/libbase.a
#   <DST>/lib/<abi>/client/libclient.a
#   <DST>/lib/<abi>/client/libcommon.a   (from obj/client)
#   <DST>/lib/<abi>/util/libutil.a
#   <DST>/lib/<abi>/crashpad_handler.so  (ELF, chmod +x)
#
# Optionally copies headers (from Crashpad *source* tree) into:
#   <DST>/include/...
#
# Usage example:
#   $0 --src out --dst ./crashkit/src/main/cpp/crashpad --abis "arm64-v8a x86 x86_64" --hdr-src /path/to/crashpad

SRC=""       # Crashpad *out* dir (where built artifacts are)
DST=""       # Destination root (e.g., ./crashkit/src/main/cpp/crashpad)
HDR_SRC=""   # Crashpad *source* root (optional; used to copy headers)
ABIS="arm64-v8a"

usage() {
  cat <<EOF
Usage: $0 --src <crashpad_out_dir> --dst <dest_root_dir> [--abis "arm64-v8a x86_64 x86 armeabi-v7a"] [--hdr-src <crashpad_src_root>]

Layout produced:
  <DST>/lib/<abi>/base/libbase.a
  <DST>/lib/<abi>/client/libclient.a
  <DST>/lib/<abi>/client/libcommon.a
  <DST>/lib/<abi>/util/libutil.a
  <DST>/lib/<abi>/crashpad_handler.so
  <DST>/include/...                 (only if --hdr-src given)

Expected Crashpad out subdirs per ABI (first existing is used):
  arm64-v8a    -> android-arm64  android_arm64  arm64
  armeabi-v7a  -> android-arm    android_arm    arm
  x86_64       -> android-x64    android_x64    x64    android-x86_64
  x86          -> android-x86    android_x86    x86

Examples:
  # Copy libs/handler only:
  $0 --src out --dst ./crashkit/src/main/cpp/crashpad --abis "arm64-v8a x86 x86_64"

  # Copy libs/handler + public headers (rsync-like include of *.h):
  $0 --src out --dst ./crashkit/src/main/cpp/crashpad --abis "arm64-v8a x86 x86_64" --hdr-src /path/to/crashpad
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --src)      SRC="$2"; shift 2 ;;
    --dst)      DST="$2"; shift 2 ;;
    --abis)     ABIS="$2"; shift 2 ;;
    --hdr-src)  HDR_SRC="$2"; shift 2 ;;
    -h|--help)  usage; exit 0 ;;
    *) echo "Unknown arg: $1" >&2; usage; exit 1 ;;
  esac
done

[[ -z "${SRC}" || -z "${DST}" ]] && { echo "Error: --src and --dst are required"; usage; exit 1; }
[[ -d "$SRC" ]] || { echo "Error: src dir not found: $SRC" >&2; exit 1; }
mkdir -p "$DST"

LIB_DST="$DST/lib"
INC_DST="$DST/include"

# Candidate out subdirs per ABI (ordered)
abi_dirs() {
  case "$1" in
    arm64-v8a)   echo "android-arm64 android_arm64 arm64" ;;
    armeabi-v7a) echo "android-arm android_arm arm" ;;
    x86_64)      echo "android-x64 android_x64 x64 android-x86_64" ;;
    x86)         echo "android-x86 android_x86 x86" ;;
    *)           echo "$1" ;;
  esac
}

# Find pattern inside ABI roots, first preferring paths that contain $4 (if given)
find_in_abi() {
  local base="$1" abi="$2" pattern="$3" prefer="${4:-}"
  local cand root hit

  for cand in $(abi_dirs "$abi"); do
    root="$base/$cand"
    [[ -d "$root" ]] || continue

    if [[ -n "$prefer" ]]; then
      hit="$(find "$root" -type f -name "$pattern" -path "*$prefer*" 2>/dev/null | head -n 1 || true)"
      [[ -n "$hit" ]] && { echo "$hit"; return 0; }
    fi

    hit="$(find "$root" -type f -name "$pattern" 2>/dev/null | head -n 1 || true)"
    [[ -n "$hit" ]] && { echo "$hit"; return 0; }
  done
  return 1
}

copy_lib() {
  local abi="$1" pattern="$2" out_subdir="$3" prefer_subpath="${4:-}"
  local srcpath
  if srcpath="$(find_in_abi "$SRC" "$abi" "$pattern" "$prefer_subpath")"; then
    local outdir="$LIB_DST/$abi/$out_subdir"; mkdir -p "$outdir"
    cp -f "$srcpath" "$outdir/$pattern"
    echo "[$abi] Copied $srcpath -> $outdir/$pattern"
  else
    echo "[$abi] ERROR: $pattern not found under any of: $(abi_dirs "$abi" | sed "s|^|$SRC/|g")" >&2
    return 1
  fi
}

copy_handler() {
  local abi="$1"
  local srcpath=""
  # Prefer anything named crashpad_handler in the ABI tree
  if ! srcpath="$(find_in_abi "$SRC" "$abi" "crashpad_handler" "")"; then
    srcpath="$(find_in_abi "$SRC" "$abi" "crashpad_handler.so" "")" || true
  fi
  if [[ -n "$srcpath" ]]; then
    local outdir="$LIB_DST/$abi"; mkdir -p "$outdir"
    cp -f "$srcpath" "$outdir/crashpad_handler.so"
    chmod +x "$outdir/crashpad_handler.so"
    echo "[$abi] Copied $srcpath -> $outdir/crashpad_handler.so (chmod +x)"
  else
    echo "[$abi] ERROR: crashpad_handler not found under any of: $(abi_dirs "$abi" | sed "s|^|$SRC/|g")" >&2
    return 1
  fi
}

copy_headers() {
  local src="$1"
  [[ -z "$src" ]] && { echo "[headers] Skipping (no --hdr-src provided)"; return 0; }
  [[ -d "$src" ]] || { echo "[headers] ERROR: hdr-src dir not found: $src" >&2; return 1; }

  mkdir -p "$INC_DST"
  if command -v rsync >/dev/null 2>&1; then
    # Mirror your previous approach: only *.h, keep dirs, prune empties.
    rsync -avh --include='*/' --include='*.h' --exclude='*' --prune-empty-dirs "$src/" "$INC_DST/"
  else
    # Fallback without rsync: replicate directory structure and copy *.h files.
    while IFS= read -r -d '' h; do
      rel="${h#$src/}"
      mkdir -p "$INC_DST/$(dirname "$rel")"
      cp -f "$h" "$INC_DST/$rel"
    done < <(find "$src" -type f -name "*.h" -print0)
  fi
  echo "[headers] Copied headers from $src -> $INC_DST"
}

# pattern : output-subdir : preferred-subpath-fragment
declare -a SPECS=(
  "libbase.a:base:obj/*mini_chromium*/base"
  "libclient.a:client:obj/client"
  "libcommon.a:client:obj/client"   # prefer client, not handler
  "libutil.a:util:obj/util"
)

# Copy per-ABI libs/handler
# shellcheck disable=SC2086
for abi in $ABIS; do
  ok=0
  for spec in "${SPECS[@]}"; do
    IFS=":" read -r lib outdir prefer <<<"$spec"
    if copy_lib "$abi" "$lib" "$outdir" "$prefer"; then ok=$((ok+1)); fi
  done
  if copy_handler "$abi"; then ok=$((ok+1)); fi

  expected=$(( ${#SPECS[@]} + 1 ))
  if [[ $ok -lt $expected ]]; then
    echo "[$abi] Some artifacts missing. Expected: $expected, copied: $ok" >&2
  fi
done

# Copy headers (arch-independent)
copy_headers "$HDR_SRC"

echo "Done. Output at: $DST"
