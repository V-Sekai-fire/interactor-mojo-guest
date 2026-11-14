# interactor-mojo-guest

Want Mojo running inside Godot? Mojo cannot link a RISC-V executable, so this repo does the link step itself. `fib(30)`, async tasks and a host-callable `add_numbers` run from one static guest ELF. Run `pixi run build`, then read `docs/guide.md`.
