#!/bin/sh
# Build guest.elf: Mojo -> RV64GC object, a small runtime shim, static link against
# the riscv64 glibc sysroot (V-Sekai-fire/repository-riscv64-sysroot).
set -eu
cd "$(dirname "$0")"
SYSROOT_REPO="${SYSROOT_REPO:-../riscv64-sysroot}"
SYSROOT="$SYSROOT_REPO/sysroot"
GCCLIB="$SYSROOT/lib/gcc-cross/14"
[ -d "$SYSROOT" ] || { echo "no sysroot at $SYSROOT; clone repository-riscv64-sysroot or set SYSROOT_REPO" >&2; exit 1; }
mkdir -p build
TRIPLE=riscv64-unknown-linux-gnu
mojo build src/guest.mojo --target-accelerator=none \
  --target-triple=$TRIPLE --target-cpu=generic-rv64 \
  --target-features=+m,+a,+f,+d,+c --target-abi=lp64d \
  --emit object -o build/guest_mojo.o
CXXFLAGS="--target=$TRIPLE --sysroot=$SYSROOT -march=rv64gc -mabi=lp64d -O2 -std=c++20 \
  -isystem $SYSROOT/include/c++/14 -isystem $SYSROOT/include/c++/14/riscv64-linux-gnu \
  -Iruntime/shim -Iruntime"
for f in runtime/AsyncRT runtime/Memory runtime/System; do
  clang++ $CXXFLAGS -c $f.cpp -o build/$(basename $f).o
done
clang++ $CXXFLAGS -c runtime/upstream/Globals.cpp -o build/Globals.o
# 40 bytes is the Variant of a double-precision host (our engine builds); 24 is single.
clang --target=$TRIPLE --sysroot="$SYSROOT" -march=rv64gc -mabi=lp64d -O2 \
  -DSANDBOX_VARIANT_SIZE="${SANDBOX_VARIANT_SIZE:-40}" -c runtime/sandbox_abi.c -o build/sandbox_abi.o
clang++ --target=$TRIPLE --sysroot="$SYSROOT" -fuse-ld=lld -B"$GCCLIB" -L"$GCCLIB" -static \
  -o build/guest.elf build/guest_mojo.o build/AsyncRT.o build/Memory.o build/System.o build/Globals.o build/sandbox_abi.o
file build/guest.elf
