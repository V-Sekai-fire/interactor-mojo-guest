# interactor-mojo-guest

A Mojo program, with its standard library, built into a static RISC-V 64 guest ELF that runs in a godot-sandbox module build. It prints a line with `print`, computes `fib(30)`, adds up three async tasks, and offers `add_numbers` to the host, which can `vmcall` it after `main` returns.

Mojo cannot link a cross-compiled executable (`--emit exe` fails at the link step), so `tools/build.exs` does it in steps:

1. `mojo build --emit object` makes an RV64GC object (`lp64d`) from `src/guest.mojo`.
2. `runtime/` is a fork of the parts of Modular's runtime that Mojo's startup code calls (`KGEN_CompilerRT_*`), built for riscv64 (see below).
3. `runtime/sandbox_abi.c` is the guest's half of the host contract: the `.sandbox_variant` section (the size of a Variant, 40 bytes for a double-precision host, and a host with a different size refuses the program), `fast_exit` (where a finished `vmcall` returns to), and `sandbox_register_api`, which registers `add_numbers` through `ecall` 547 while `main` runs. The function's logic is Mojo (`mojo_add_numbers`, exported with `abi("C")`). The C part only unpacks the boxed Variants.
4. `clang++` and `lld` link everything statically against the glibc sysroot in `V-Sekai-fire/repository-riscv64-sysroot`.

## Public API

`sigs/interactor-mojo-guest.sigs` lists what a host can call. Keep it in step with `sandbox_register_api`. Today that is `MojoGuest.add_numbers(int a, int b) -> int` and `MojoGuest.echo(Variant value) -> Variant`, which takes int, bool, float, string or object back out unchanged. `add_numbers` and `echo` need `unboxed_arguments = false`, because their glue reads Variant pointers. `add_numbers_native` needs it true: ints arrive raw in `a1` and `a2`. Registration is only legal during the host's initialization, which is when `main` runs.

## Build and run

Tools are Elixir scripts in `tools/` and gates are GDScript in `project/`, as the workspace's rules for guests say. `pixi run build`, `test`, `test-rvlinux` and `test-limits` call them.

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

- One worker by decision (n = 1), so tasks interleave but never run in parallel. `max.algorithm`'s `parallelize` does not build for a guest, because its multi-item branch enqueues onto a DeviceContext from the MAX driver. `src/guest_algorithm.mojo` is its one-worker path, which runs every item in order on the calling thread.
- One ABI per sandbox. `add_numbers` and `echo` take boxed Variant pointers, so the host sets `unboxed_arguments = false`. `add_numbers_native` is the same function for a host with it set to true. Only that one function has a native form.
- A `Wait_Timeout` that sleeps. It drains the queue, then polls Godot's `Time.get_ticks_usec` until the deadline, and every poll is charged to the instruction budget. The engine test sets `execution_timeout` to 0 (no limit) for that reason. Without a Sandbox host, as in rvlinux, it answers at once.
- A CI run of the Godot test. CI builds the ELF only, because the test needs a window and a Sandbox build.
- A single-precision host. Build with `SANDBOX_VARIANT_SIZE=24` for one; I did not run it. The double host refuses that build, which I did run.

## The limits as tests

`pixi run test-limits` runs contract-witness-mojo properties in rvlinux (needs `RVLINUX` and a `contract-witness-mojo` checkout, `../../2-contract/witness-mojo` in a workspace or `WITNESS_REPO`). `pixi run test-hostlimits` runs GDScript checks in the Sandbox build, and the same witness properties inside it. A test that fails is a limit that still stands.

| Limit | Test | Result today |
|---|---|---|
| Variant types: int | int round trip (control) | passes |
| Variant types: bool, float, object | round trip of each | pass |
| Variant types: string | string round trip, needs the host | passes in the Sandbox build, skipped in rvlinux, which has no host |
| The same types through a real `vmcall` | `echo` of int, bool, float, string, object | pass in the Sandbox build |
| One worker, n = 1 | worker count is one | passes |
| `parallelize` on one worker | visits each item once | passes |
| Spin locks use a stand-in waiter (control) | spin lock under tasks | passes, up to 50 tasks on one lock |
| A second `vmcall` after the first (control) | repeated vmcall | passes |
| `Wait_Timeout` waits its deadline on Godot's clock | waits its deadline | passes in the Sandbox build, skipped in rvlinux, which has no host clock |
| Native (unboxed) arguments | unboxed vmcall of `add_numbers_native` | passes |

The Variant glue is in `runtime/sandbox_abi.c`. Bool, float and object travel in the payload. A string is created and fetched through the host's `ECALL_VCREATE` and `ECALL_VFETCH`. The string test needs `references_max` raised in the host, because each trial scopes one host variant and the default allows 100. `project/limits_run.gd` sets 20,000.

Not written as tests, and why:

- A single-precision host needs a single-precision engine build, which I do not have.
- A `Wait` on a chain nothing can complete aborts the whole guest, so a property cannot catch it.
- CI does not run the Godot test, and rvlinux has no Sandbox host. These are about where tests run, not about the guest.

## Licence

MIT. See [LICENSE](LICENSE).
