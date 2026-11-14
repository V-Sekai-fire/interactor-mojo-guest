# interactor-mojo-guest

A Mojo program built into a static RISC-V 64 guest ELF. It prints a line, computes `fib(30)`, and exits with 0 when the result is right.

Mojo cannot link a cross-compiled executable (`--emit exe` fails at the link step), so the build has three steps:

1. `mojo build --emit object` makes an RV64GC object (`lp64d`) from `src/guest.mojo`.
2. `clang` builds `crt/start.c`, a freestanding entry with `_start`, `write` and `exit` as Linux syscalls (`ecall` 64 and 93).
3. `ld.lld -static -nostdlib` links both into `build/guest.elf`. The ELF is `ET_EXEC` with a low entry point, the layout a godot-sandbox guest needs.

## Build and run

    pixi run build
    pixi run test

`test/run_guest.py` loads the ELF into Unicorn, serves the two syscalls, and exits with the guest's exit code. Judge a run by the guest's `RESULT:` line, not by the runner alone. It was checked against a deliberately wrong answer, which exits 1.

## Versions

Mojo is pinned to `1.3.0.dev2026111316`. RISC-V code generation was missing from nightlies `1.0.0b3.dev2026071105` up to at least `1.1.0.dev2026081505` ([modular/modular#6900](https://github.com/modular/modular/issues/6900)) and works again in this one. Re-check it before moving the pin.

## What this does not have

- No Mojo standard library at run time. There is no libc, so `print`, allocation and file I/O are not available. The guest calls `write` through `external_call` and the stub provides it. Only `memcpy` and `memset` are supplied, so code that makes the compiler call other libc symbols fails at link time.
- No godot-sandbox host test. It has not been loaded by Godot's `Sandbox` class, and it registers no public API functions or `.sigs`. Its entry layout matches what the libriscv loader expects, but the run above is in Unicorn.
- No `vmcall` surface: `main` exits instead of suspending, so a host cannot call into it afterwards.

## Licence

MIT. See [LICENSE](LICENSE).
