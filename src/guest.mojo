from std.ffi import external_call


def fib(n: Int) -> Int:
    var a = 0
    var b = 1
    for _ in range(n):
        var t = a + b
        a = b
        b = t
    return a


def write_line(text: StringSpan):
    _ = external_call["write", Int](1, text.unsafe_ptr(), text.byte_length())


@export
def mojo_guest_main() abi("C") -> Int32:
    write_line("hello from Mojo in a RISC-V guest\n")
    # fib(30) = 832040; exit code 0 means the arithmetic came out right.
    if fib(30) == 832040:
        write_line("RESULT: fib(30) == 832040\n")
        return 0
    write_line("RESULT: fib(30) wrong\n")
    return 1
