#!/bin/sh
# Run build/guest.elf in a godot-sandbox module build, in a real window (never --headless).
# GODOT: a double-precision editor build with the Sandbox module, e.g. the
# godot.macos.editor.double.arm64 asset of a V-Sekai-fire/entities-zone release.
set -eu
cd "$(dirname "$0")/.."
: "${GODOT:?set GODOT to the engine binary}"
cp build/guest.elf project/guest.elf
"$GODOT" --path project --import --quit-after 5 >/dev/null 2>&1 || true
out=$("$GODOT" --path project --script run.gd --quit-after 300 2>&1) || true
printf '%s\n' "$out" | grep -E "RESULT|ERROR: Sandbox|hello from" || true
printf '%s\n' "$out" | grep -q "RESULT: fib(30) == 832040" && ! printf '%s\n' "$out" | grep -q "ERROR: Sandbox"
