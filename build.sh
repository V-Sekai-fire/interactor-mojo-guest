#!/bin/sh
# Build guest.elf: Mojo -> RV64GC object, C entry stub, static link with lld.
set -eu
cd "$(dirname "$0")"
mkdir -p build
mojo build src/guest.mojo --target-accelerator=none \
  --target-triple=riscv64-unknown-linux-gnu --target-cpu=generic-rv64 \
  --target-features=+m,+a,+f,+d,+c --target-abi=lp64d \
  --emit object -o build/guest_mojo.o
clang --target=riscv64-unknown-linux-gnu -march=rv64gc -mabi=lp64d -O2 \
  -ffreestanding -fno-builtin -c crt/start.c -o build/start.o
ld.lld -static -nostdlib --no-dynamic-linker -o build/guest.elf build/start.o build/guest_mojo.o
file build/guest.elf
