# interactor-mojo-guest

A Mojo program, with its standard library, built into a static RISC-V 64 guest ELF that runs in a godot-sandbox module build. It prints a line with `print`, computes `fib(30)`, and exits with 0 when the result is right.

Mojo cannot link a cross-compiled executable (`--emit exe` fails at the link step), so `build.sh` does it in steps:

1. `mojo build --emit object` makes an RV64GC object (`lp64d`) from `src/guest.mojo`.
2. `runtime/` is a fork of the parts of Modular's runtime that Mojo's startup code calls (`KGEN_CompilerRT_*`), built for riscv64 (see below).
3. `runtime/sandbox_abi.c` adds the `.sandbox_variant` section, the guest's half of the host contract. It holds the size of a Variant, 40 bytes for a double-precision host, and a host with a different size refuses the program.
4. `clang++` and `lld` link everything statically against the glibc sysroot in `V-Sekai-fire/repository-riscv64-sysroot`.

## Build and run

Clone the sysroot repository beside this one (or set `SYSROOT_REPO`), then:

    pixi run build
    GODOT=<engine binary> pixi run test

`GODOT` is a double-precision editor build with the Sandbox module, for example the `godot.macos.editor.double.arm64` asset of a `V-Sekai-fire/entities-zone` release. The test opens a real window, never `--headless`, loads the ELF into a `Sandbox`, and judges by the guest's own `RESULT: fib(30) == 832040` line and the absence of a Sandbox error. A build without the Sandbox class fails the test.

## The runtime fork

`runtime/upstream/` holds `Globals.cpp`, `Memory.cpp`, `Memory.h` and `System.cpp` verbatim from `Mojo/lib/CompilerRT` in modular/modular at `e6e596ce` (Apache-2.0 with LLVM exceptions). That tree does not build on its own, because it includes headers that are not published (`Support/ADT/GlobalTable.h`, `Support/SymbolExport.h`, `AsyncRT/...`). What changed:

- `Globals.cpp` is used as it is, on top of small stand-ins in `runtime/shim/` for `GlobalTable`, `SymbolExport.h` and `llvm::StringRef`.
- `runtime/Memory.cpp` replaces tcmalloc and logging with `aligned_alloc` and `free`.
- `runtime/System.cpp` keeps `fprintf`, `GetArgV` and `SetArgV`. It reports one core, and drops the config lookup and the stack-trace handler.
- `runtime/AsyncRT.cpp` replaces the thread-pool runtime with the one dummy CPU device that `main()` asks for.

Diff `runtime/*.cpp` against `runtime/upstream/` to see each change.

## Versions

Mojo is pinned to `1.3.0.dev2026111316`. RISC-V code generation was missing from nightlies `1.0.0b3.dev2026071105` up to at least `1.1.0.dev2026081505` ([modular/modular#6900](https://github.com/modular/modular/issues/6900)) and works again in this one. Re-check it before moving the pin.

## What this does not have

- No async runtime. `parallelize`, tasks and coroutines fail to link, because their `KGEN_CompilerRT_AsyncRT_*` entry points are not provided.
- No `vmcall` surface. `main` runs and exits, so a host cannot call into the guest afterwards. It registers no public API functions or `.sigs`.
- No CI run of the Godot test. CI builds the ELF only, because the test needs a window and a Sandbox build.
- Only single-hart behaviour, and only a double-precision host. Build with `SANDBOX_VARIANT_SIZE=24` for a single-precision one, which I did not run.

## Licence

MIT. See [LICENSE](LICENSE).
