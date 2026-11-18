#!/usr/bin/env bash
# Runs the Infinite Tower test suite inside a disposable copy of the project.
# The copy uses a different project name, so Godot's user:// directory (and
# therefore every save file the tests write) is separate from the real game.
#
# Usage: tests/run_tests.sh [path-to-godot-binary]
set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
GODOT="${1:-${GODOT:-$(command -v godot || echo "$HOME/Downloads/Godot.app/Contents/MacOS/Godot")}}"
if [ ! -x "$GODOT" ]; then
	echo "Godot binary not found. Pass its path as the first argument." >&2
	exit 2
fi

WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/infinite-tower-tests.XXXXXX")"
TEST_NAME="Infinite Tower Test $(basename "$WORK_DIR")"
rsync -a --exclude .git --exclude .godot "$PROJECT_ROOT/" "$WORK_DIR/"
sed -i.orig "s/^config\/name=.*/config\/name=\"$TEST_NAME\"/" "$WORK_DIR/project.godot"

cd "$WORK_DIR"
echo "Importing disposable project copy..."
"$GODOT" --headless --editor --quit >/dev/null 2>&1 || true

echo "Running tests..."
set +e
STATUS=0
# Every tests/test_*.gd script runs in turn, each under its own project name
# so no script sees save data left by another. A script error or a script
# that ran zero checks (for example because it failed to compile) fails the
# run even when Godot itself exits 0.
USER_ROOT="$HOME/Library/Application Support/Godot/app_userdata"
[ "$(uname)" = Darwin ] || USER_ROOT="${XDG_DATA_HOME:-$HOME/.local/share}/godot/app_userdata"
for TEST_SCRIPT in tests/test_*.gd; do
	echo "== $TEST_SCRIPT"
	SCRIPT_NAME="$TEST_NAME $(basename "$TEST_SCRIPT" .gd)"
	sed -i.bak "s/^config\/name=.*/config\/name=\"$SCRIPT_NAME\"/" project.godot
	OUTPUT="$(IT_ALLOW_SAVE_TESTS=1 "$GODOT" --headless -s "$TEST_SCRIPT" 2>&1)"
	RESULT=$?
	echo "$OUTPUT"
	if [ $RESULT -eq 0 ]; then
		if echo "$OUTPUT" | grep -qE "SCRIPT ERROR|Parse Error|Failed to load script"; then
			echo "!! $TEST_SCRIPT reported script errors"
			RESULT=1
		elif echo "$OUTPUT" | grep -qE "\(0 checks\)|PASSED: 0 "; then
			echo "!! $TEST_SCRIPT ran zero checks"
			RESULT=1
		fi
	fi
	[ $RESULT -ne 0 ] && STATUS=$RESULT
	[ -d "$USER_ROOT/$SCRIPT_NAME" ] && rm -rf "$USER_ROOT/$SCRIPT_NAME"
done
set -e

exit $STATUS
