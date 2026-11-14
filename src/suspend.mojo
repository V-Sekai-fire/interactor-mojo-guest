from std.runtime._asyncrt import (
    create_task,
    _Chain,
    _init_asyncrt_chain,
    _del_asyncrt_chain,
    _async_and_then,
    _async_execute,
)
from std.builtin._coroutine import _suspend_async, AnyCoroutine
from std.ffi import external_call


__async def sleep_ns(ns: Int):
    # Suspends this coroutine and arms a host timer. Nothing runs until the timer's timeout.
    var chain = _Chain()
    _init_asyncrt_chain(Pointer(to=chain))
    var p = Pointer(to=chain)

    def body(hdl: AnyCoroutine) {var}:
        external_call["sandbox_wake_chain_after", NoneType](p, ns)
        _async_and_then(hdl, p)

    _suspend_async(body)
    _del_asyncrt_chain(Pointer(to=chain))


__async def waiter(ns: Int):
    external_call["sandbox_note", NoneType](0, external_call["sandbox_ticks_usec", Int64]())
    __await create_task(sleep_ns(ns))
    external_call["sandbox_note", NoneType](1, external_call["sandbox_ticks_usec", Int64]())


@export
def mojo_suspend_start(ns: Int) abi("C") -> Int:
    external_call["sandbox_note", NoneType](0, -1)
    external_call["sandbox_note", NoneType](1, -1)
    # Fire and forget: the frame is not freed, because a Task would free it on return.
    var co = waiter(ns)
    co._set_noop_callback()
    var hdl = co^._take_handle()
    _async_execute[NoneType](hdl, -1)
    external_call["sandbox_drain", NoneType]()
    return 0


@export
def mojo_suspend_elapsed() abi("C") -> Int:
    var start = Int(external_call["sandbox_noted", Int64](0))
    var end = Int(external_call["sandbox_noted", Int64](1))
    if end < 0:
        return -1
    return end - start


def main():
    external_call["sandbox_register_api", NoneType]()
