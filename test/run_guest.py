"""Run build/guest.elf in Unicorn with the two Linux syscalls the guest uses.

Judge by the guest's own RESULT line and its exit code, not by this runner's
status: the runner exits with the guest's code and fails if no RESULT line came out.
"""
import struct
import sys

from unicorn import UC_ARCH_RISCV, UC_MODE_RISCV64, Uc, UcError, UC_HOOK_INTR
from unicorn.riscv_const import UC_RISCV_REG_A0, UC_RISCV_REG_A1, UC_RISCV_REG_A2, UC_RISCV_REG_A7
from unicorn.riscv_const import UC_RISCV_REG_PC, UC_RISCV_REG_SP

path = sys.argv[1] if len(sys.argv) > 1 else "build/guest.elf"
data = open(path, "rb").read()
assert data[:4] == b"\x7fELF" and data[4] == 2, "not an ELF64"
etype, entry = struct.unpack_from("<H", data, 0x10)[0], struct.unpack_from("<Q", data, 0x18)[0]
phoff, phentsize, phnum = (struct.unpack_from("<Q", data, 0x20)[0],
                           struct.unpack_from("<H", data, 0x36)[0],
                           struct.unpack_from("<H", data, 0x38)[0])
assert etype == 2, f"expected ET_EXEC, got {etype}"

PAGE = 0x1000
mu = Uc(UC_ARCH_RISCV, UC_MODE_RISCV64)
exec_ok = False
for i in range(phnum):
    off, = struct.unpack_from("<Q", data, phoff + i * phentsize + 8)
    ptype, flags = struct.unpack_from("<II", data, phoff + i * phentsize)
    _, vaddr, _, filesz, memsz = struct.unpack_from("<QQQQQ", data, phoff + i * phentsize + 8)
    if ptype != 1:
        continue
    lo, hi = vaddr & ~(PAGE - 1), (vaddr + memsz + PAGE - 1) & ~(PAGE - 1)
    try:
        mu.mem_map(lo, hi - lo)
    except UcError:
        pass  # segments sharing a page
    mu.mem_write(vaddr, data[off:off + filesz])
    exec_ok |= bool(flags & 1) and vaddr <= entry < vaddr + memsz
assert exec_ok, "entry point is not inside an executable PT_LOAD"

STACK = 0x7FFF0000
mu.mem_map(STACK - 0x10000, 0x10000)
mu.reg_write(UC_RISCV_REG_SP, STACK - 16)
out = bytearray()
state = {"code": None}

def on_intr(uc, intno, _):
    n = uc.reg_read(UC_RISCV_REG_A7)
    a0, a1, a2 = (uc.reg_read(r) for r in (UC_RISCV_REG_A0, UC_RISCV_REG_A1, UC_RISCV_REG_A2))
    if n == 64:      # write(fd, buf, len)
        out.extend(uc.mem_read(a1, a2))
        uc.reg_write(UC_RISCV_REG_A0, a2)
    elif n == 93:    # exit(code)
        state["code"] = a0
        uc.emu_stop()
    else:
        raise SystemExit(f"unhandled syscall {n}")

mu.hook_add(UC_HOOK_INTR, on_intr)
try:
    mu.emu_start(entry, 0, timeout=20_000_000, count=50_000_000)
except UcError as e:
    raise SystemExit(f"guest faulted at pc={mu.reg_read(UC_RISCV_REG_PC):#x}: {e}")

text = out.decode()
sys.stdout.write(text)
if "RESULT:" not in text or state["code"] is None:
    raise SystemExit("no RESULT line or no exit syscall")
print(f"guest exit code = {state['code']}")
sys.exit(state["code"])
