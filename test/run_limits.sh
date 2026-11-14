#!/bin/sh
# The documented limits as contract-witness-mojo properties, run in rvlinux. They are
# expected to be red where a limit exists: this script exits 1 while any property is
# falsified, so it is not part of `pixi run test`. A control that is falsified, or a
# property that is expected to stay red going green, is the news.
# RVLINUX: the libriscv-rs binary. WITNESS_REPO: a contract-witness-mojo checkout.
set -eu
cd "$(dirname "$0")/.."
: "${RVLINUX:?set RVLINUX to the rvlinux binary}"
if [ -z "${WITNESS_REPO:-}" ]; then
  if [ -d ../../2-contract/witness-mojo ]; then WITNESS_REPO=../../2-contract/witness-mojo
  else WITNESS_REPO=../contract-witness-mojo; fi
fi
MOJO_FLAGS="-I $WITNESS_REPO/src" ./build.sh tests/limits.mojo limits >/dev/null
out=$("$RVLINUX" build/limits.elf 2>&1) || true
printf '%s\n' "$out" | cut -c1-120
printf '%s\n' "$out" | grep -q "^PASS int round trip (control)" || { echo "control failed" >&2; exit 2; }
printf '%s\n' "$out" | grep -q "^PASS spin lock under tasks (control)" || { echo "control failed" >&2; exit 2; }
printf '%s\n' "$out" | grep -q "exit code = 0 "
