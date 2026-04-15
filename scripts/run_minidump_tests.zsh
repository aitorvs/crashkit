#!/usr/bin/env zsh
# Build and run Crashpad minidump writer tests on the host (macOS/Linux).
# No Android device or emulator is required — tests use in-memory I/O only.
#
# Usage:
#   scripts/run_minidump_tests.zsh
#   scripts/run_minidump_tests.zsh --filter "MinidumpModuleCrashpadInfoWriter.Allowlist*"
#   scripts/run_minidump_tests.zsh --out out/host --filter "*"
#
# The script:
#   1. Runs `gn gen` for a host build (if not already configured)
#   2. Builds `crashpad_minidump_test` with ninja
#   3. Runs the test binary, optionally with a --gtest_filter
#
# Prerequisites:
#   - gn and ninja on your PATH
#     (Install via `brew install gn ninja` or add depot_tools to PATH)

set -euo pipefail

SCRIPT_DIR="${0:A:h}"
CRASHPAD_DIR="${SCRIPT_DIR}/../external/crashpad"
OUTDIR="out/host"
FILTER=""

usage() {
  cat <<EOF
Usage: $(basename "$0") [--out <dir>] [--filter <gtest_filter>] [--clean]
  --out     GN output dir relative to external/crashpad (default: out/host)
  --filter  gtest filter expression (default: all minidump tests)
  --clean   Remove the output dir before building
EOF
}

CLEAN=false
while [[ $# -gt 0 ]]; do
  case "$1" in
    --out)     OUTDIR="$2"; shift 2 ;;
    --filter)  FILTER="$2"; shift 2 ;;
    --clean)   CLEAN=true; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown argument: $1"; usage; exit 1 ;;
  esac
done

cd "$CRASHPAD_DIR"

if $CLEAN && [[ -d "$OUTDIR" ]]; then
  echo "Removing $OUTDIR"
  rm -rf "$OUTDIR"
fi

# Generate host build if args.gn does not exist yet
if [[ ! -f "$OUTDIR/args.gn" ]]; then
  echo "Configuring host build in $OUTDIR ..."
  gn gen "$OUTDIR" --args='is_debug=true'
fi

echo "Building crashpad_minidump_test ..."
ninja -C "$OUTDIR" crashpad_minidump_test

TEST_BIN="$OUTDIR/crashpad_minidump_test"
[[ -x "$TEST_BIN" ]] || { echo "ERROR: test binary not found at $TEST_BIN"; exit 1; }

# Default filter: run all minidump writer tests (including the allowlist ones)
if [[ -z "$FILTER" ]]; then
  FILTER="MinidumpModuleCrashpadInfoWriter.*:MinidumpCrashpadInfoWriter.*"
fi

echo ""
echo "Running: $TEST_BIN --gtest_filter='$FILTER'"
echo "---"
"$TEST_BIN" --gtest_filter="$FILTER"
