#!/usr/bin/env bash
# EVERAFTER verification entry point.
#
#   bash tools/run_checks.sh            # static checks (+ engine tests if Godot exists)
#   GODOT=/path/to/godot bash tools/run_checks.sh
#
# Static checks always run: they only need Python 3 and (optionally) gdtoolkit.
# The headless engine test suite runs only when a Godot 4 executable is found,
# and the script says so explicitly instead of pretending it ran.

set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

FAILED=0

section() {
  echo ""
  echo "=============================================================="
  echo "$1"
  echo "=============================================================="
}

section "1/5 Static project consistency (tools/check_project.py)"
if command -v python3 >/dev/null 2>&1; then
  python3 tools/check_project.py "$@" || FAILED=1
else
  echo "python3 not found: skipped (this check cannot run here)."
fi

section "2/5 GDScript syntax (gdparse, from the gdtoolkit package)"
if command -v gdparse >/dev/null 2>&1; then
  GD_FILES=$(find src tests -name '*.gd' | sort)
  # shellcheck disable=SC2086
  if gdparse $GD_FILES; then
    echo "gdparse: OK ($(echo "$GD_FILES" | wc -l) files parsed)"
  else
    echo "gdparse: FAILED"
    FAILED=1
  fi
else
  echo "gdparse not found: skipped."
  echo "  install with: pip install gdtoolkit"
fi

section "3/5 GDScript style (gdlint)"
if command -v gdlint >/dev/null 2>&1; then
  gdlint src tests || FAILED=1
else
  echo "gdlint not found: skipped."
  echo "  install with: pip install gdtoolkit"
fi

GODOT_BIN="${GODOT:-}"
if [ -z "$GODOT_BIN" ]; then
  for candidate in godot4 godot Godot godot-4; do
    if command -v "$candidate" >/dev/null 2>&1; then
      GODOT_BIN="$candidate"
      break
    fi
  done
fi

section "4/5 Headless unit tests (tests/run_tests.gd)"
if [ -n "$GODOT_BIN" ]; then
  echo "using: $GODOT_BIN"
  "$GODOT_BIN" --headless --path . --script res://tests/run_tests.gd || FAILED=1
else
  echo "No Godot executable found: the unit suite DID NOT RUN."
  echo "  Windows: download a stable Godot 4 build, then run"
  echo "    Godot_v4.x-stable_win64.exe --headless --path . --script res://tests/run_tests.gd"
fi

section "5/5 Headless world integration tests (tests/run_world_tests.gd)"
if [ -n "$GODOT_BIN" ]; then
  echo "using: $GODOT_BIN"
  "$GODOT_BIN" --headless --path . --script res://tests/run_world_tests.gd || FAILED=1
else
  echo "No Godot executable found: the world integration suite DID NOT RUN."
  echo "  Windows: download a stable Godot 4 build, then run"
  echo "    Godot_v4.x-stable_win64.exe --headless --path . --script res://tests/run_world_tests.gd"
fi

section "Summary"
if [ "$FAILED" -eq 0 ]; then
  echo "All executed checks passed."
else
  echo "At least one executed check failed."
fi
exit "$FAILED"
