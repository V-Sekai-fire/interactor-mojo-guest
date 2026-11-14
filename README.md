# interactor-mojo-guest

A Mojo program, with its standard library, built into a static RISC-V 64 guest ELF that runs in a godot-sandbox module build. It prints a line with `print`, computes `fib(30)`, adds up three async tasks, and offers `add_numbers` to the host, which can `vmcall` it after `main` returns.

Mojo cannot link a cross-compiled executable (`--emit exe` fails at the link step), so `build.sh` does it in steps:

1. `mojo build --emit object` makes an RV64GC object (`lp64d`) from `src/guest.mojo`.
2. `runtime/` is a fork of the parts of Modular's runtime that Mojo's startup code calls (`KGEN_CompilerRT_*`), built for riscv64 (see below).
3. `runtime/sandbox_abi.c` is the guest's half of the host contract: the `.sandbox_variant` section (the size of a Variant, 40 bytes for a double-precision host, and a host with a different size refuses the program), `fast_exit` (where a finished `vmcall` returns to), and `sandbox_register_api`, which registers `add_numbers` through `ecall` 547 while `main` runs. The function's logic is Mojo (`mojo_add_numbers`, exported with `abi("C")`). The C part only unpacks the boxed Variants.
4. `clang++` and `lld` link everything statically against the glibc sysroot in `V-Sekai-fire/repository-riscv64-sysroot`.

## Public API

`sigs/interactor-mojo-guest.sigs` lists what a host can call. Keep it in step with `sandbox_register_api`. Today that is `MojoGuest.add_numbers(int a, int b) -> int`. The host must set `unboxed_arguments = false`, because the C glue reads Variant pointers, not native registers. Registration is only legal during the host's initialization, which is when `main` runs.

## Build and run

In a workspace checkout the sysroot is found at `../../5-repository/riscv64-sysroot`. Standalone, clone the sysroot repository beside this one (or set `SYSROOT_REPO`). Then:

    pixi run build
    GODOT=<engine binary> pixi run test

`GODOT` is a double-precision editor build with the Sandbox module, for example the `godot.macos.editor.double.arm64` asset of a `V-Sekai-fire/entities-zone` release. The test opens a real window, never `--headless`, loads the ELF into a `Sandbox`, and judges by the guest's own `RESULT: fib(30) == 832040` and `RESULT: tasks sum == 33` lines and by `vmcall("add_numbers", 3, 4)` returning 7 and the absence of a Sandbox error. A build without the Sandbox class fails the test.

For a run with no engine and no window, build `rvlinux` from [libriscv/libriscv-rs](https://github.com/libriscv/libriscv-rs) (safe Rust, BSD-3-Clause, pinned nightly) and run `RVLINUX=<binary> pixi run test-rvlinux`. It runs the same ELF as a Linux userspace guest in under a millisecond and judges by the same `RESULT` lines and the guest's exit code. It does not provide the Sandbox host API, so it reports `Unhandled system call: 547` for the registration and cannot check the `.sandbox_variant` contract or the `vmcall`.

## The runtime fork

`runtime/upstream/` holds `Globals.cpp`, `Memory.cpp`, `Memory.h` and `System.cpp` verbatim from `Mojo/lib/CompilerRT` in modular/modular at `e6e596ce` (Apache-2.0 with LLVM exceptions). That tree does not build on its own, because it includes headers that are not published (`Support/ADT/GlobalTable.h`, `Support/SymbolExport.h`, `AsyncRT/...`). What changed:

- `Globals.cpp` is used as it is, on top of small stand-ins in `runtime/shim/` for `GlobalTable`, `SymbolExport.h` and `llvm::StringRef`.
- `runtime/Memory.cpp` replaces tcmalloc and logging with `aligned_alloc` and `free`.
- `runtime/System.cpp` keeps `fprintf`, `GetArgV` and `SetArgV`. It reports one core, and drops the config lookup and the stack-trace handler.
- `runtime/AsyncRT.cpp` is the thread-pool runtime with a pool of one worker, because a guest has no threads. `Execute` and `AndThen` queue the coroutine, and the queue runs in order when the program waits on a chain or the runtime is released at exit. `Complete` moves a chain's continuations onto the queue. `Wait_Timeout` does not sleep, because with one worker only queued work can complete a chain. A `Wait` that nothing can complete aborts instead of hanging.

Diff `runtime/*.cpp` against `runtime/upstream/` to see each change.

## Versions

Mojo is pinned to `1.3.0.dev2026111316`. RISC-V code generation was missing from nightlies `1.0.0b3.dev2026071105` up to at least `1.1.0.dev2026081505` ([modular/modular#6900](https://github.com/modular/modular/issues/6900)) and works again in this one. Re-check it before moving the pin.

## What this does not have

- One worker, so tasks interleave but never run in parallel. The test exercises `create_task` and `__await` from `std.runtime._asyncrt` (the stdlib marks async unfinished). `parallelize` is in `max.algorithm`, and I did not try it.
- One public function, `add_numbers`, taking and returning ints. Other Variant types, strings and objects are not handled. It has not been called from a second `vmcall` after a reset, or with native (unboxed) arguments.
- No CI run of the Godot test. CI builds the ELF only, because the test needs a window and a Sandbox build.
- Only single-hart behaviour, and only a double-precision host. Build with `SANDBOX_VARIANT_SIZE=24` for a single-precision one, which I did not run.

## The limits as tests

Each limit below is a test that does not pass yet, so it can go green when the limit is lifted. `pixi run test-limits` runs the witness properties in rvlinux (needs `RVLINUX` and a `contract-witness-mojo` checkout at `../contract-witness-mojo`, or `WITNESS_REPO`; in a workspace it is `../../2-contract/witness-mojo`). It exits 1 while any limit is red, so it is not part of `pixi run test`, and CI does not run it. It exits 2 if a control goes red.

| Limit | Test | Result today |
|---|---|---|
| INT Variants only (control) | `tests/limits.mojo` int round trip | passes |
| bool Variants | bool round trip | red |
| float Variants | float round trip | red |
| string Variants | string round trip | red |
| object Variants | object round trip | red |
| One worker, no parallelism | more than one worker | red |
| `Wait_Timeout` does not sleep | `Wait_Timeout` waits its deadline | skipped: the clock does not advance in rvlinux or in the Sandbox build |
| Spin locks use a stand-in waiter (control) | spin lock under tasks | passes, 100 tasks on one lock |
| Native (unboxed) arguments | `project/limits_host.gd` unboxed vmcall | red |
| A second `vmcall` after the first (control) | `project/limits_host.gd` repeated vmcall | passes |

The bool, float, string and object glue is declared in `runtime/sandbox_abi.c` and returns `-ENOSYS`, so each of those tests fails for that reason. The two GDScript checks are not witness properties, because a property runs in the guest and cannot choose how the host passes its arguments. Run them with `godot --path project --script limits_host.gd`.

Not written as tests, and why:

- A single-precision host (`SANDBOX_VARIANT_SIZE=24`) needs a single-precision engine build, which I do not have.
- A `Wait` on a chain nothing can complete aborts the whole guest, so a property cannot catch it.
- `parallelize` is in `max.algorithm`. Importing it is a build error, not a failing property.
- CI does not run the Godot test, and rvlinux has no Sandbox host. These are about where tests run, not about the guest.

## Licence

MIT. See [LICENSE](LICENSE).
