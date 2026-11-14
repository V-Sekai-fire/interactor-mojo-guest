#!/bin/sh
# Run build/guest.elf in rvlinux from libriscv/libriscv-rs (safe Rust),
# with no engine and no window. RVLINUX: the built `rvlinux` binary.
# Judge by the guest's RESULT lines and its exit code, not rvlinux's own status.
set -eu
cd "$(dirname "$0")/.."
: "${RVLINUX:?set RVLINUX to the rvlinux binary}"
out=$("$RVLINUX" build/guest.elf 2>&1) || true
printf '%s\n' "$out"
printf '%s\n' "$out" | grep -q "RESULT: fib(30) == 832040" &&
  printf '%s\n' "$out" | grep -q "RESULT: tasks sum == 33" &&
  printf '%s\n' "$out" | grep -q "Program exited, exit code = 0 "
