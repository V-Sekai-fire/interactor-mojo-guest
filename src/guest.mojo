from std.sys import exit


def fib(n: Int) -> Int:
    var a = 0
    var b = 1
    for _ in range(n):
        var t = a + b
        a = b
        b = t
    return a


def main():
    print("hello from Mojo in a RISC-V guest")
    # fib(30) = 832040; exit code 0 means the arithmetic came out right.
    if fib(30) == 832040:
        print("RESULT: fib(30) == 832040")
    else:
        print("RESULT: fib(30) wrong")
        exit(1)
