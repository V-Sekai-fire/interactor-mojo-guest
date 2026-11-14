from std.runtime._asyncrt import create_task
from std.ffi import external_call
from std.sys import exit


def fib(n: Int) -> Int:
    var a = 0
    var b = 1
    for _ in range(n):
        var t = a + b
        a = b
        b = t
    return a


__async def add[lhs: Int](rhs: Int) -> Int:
    return lhs + rhs


__async def add_two_of_them(a: Int, b: Int) -> Int:
    return __await create_task(add[1](a)) + __await create_task(add[2](b))


@export
def mojo_add_numbers(a: Int, b: Int) abi("C") -> Int:
    return a + b


def main():
    print("hello from Mojo in a RISC-V guest")
    # fib(30) = 832040; exit code 0 means the arithmetic came out right.
    if fib(30) == 832040:
        print("RESULT: fib(30) == 832040")
    else:
        print("RESULT: fib(30) wrong")
        exit(1)
    # (10 + 1) + (20 + 2) = 33, from three tasks on the one-thread async runtime.
    var task = create_task(add_two_of_them(10, 20))
    var sum = task.wait()
    if sum == 33:
        print("RESULT: tasks sum == 33")
    else:
        print("RESULT: tasks sum wrong", sum)
        exit(1)
    # Offer add_numbers to the host. It is callable after main returns.
    external_call["sandbox_register_api", NoneType]()
