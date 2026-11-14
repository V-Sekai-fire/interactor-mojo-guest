"""Stand-in for max.algorithm's parallelize on a guest with one worker.

With one worker, max's parallelize runs every item in order on the calling thread: one
chunk, one dispatch, inline. Its multi-item branch enqueues onto a DeviceContext, which
needs the MAX driver and does not build for a guest, so only this path is kept.
"""


def parallelize[
    FuncType: def(Int) -> None,
](func: FuncType, num_work_items: Int):
    for i in range(num_work_items):
        func(i)
