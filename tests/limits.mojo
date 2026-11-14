# Each documented limit of this guest as a contract-witness-mojo property. A limit is a
# property that does not hold yet, so the red ones are expected. Each turns green the day
# the feature lands; INT round trip is the control that must stay green, which shows the
# harness can pass as well as fail. Built as a guest ELF and run in rvlinux.
from std.atomic import Atomic
from std.ffi import external_call
from std.runtime._asyncrt import TaskGroup, _Chain, _init_asyncrt_chain, _del_asyncrt_chain, _async_wait_timeout
from std.sys import exit
from std.time import perf_counter_ns
from std.utils.lock import BlockingScopedLock, BlockingSpinLock
from witness.check import prop_check_shrink
from witness.ladder import *

from guest_algorithm import parallelize

comptime VARIANT_BYTES = 40  # a Variant of a double-precision host


def new_variant() -> List[UInt8]:
    return List[UInt8](length=VARIANT_BYTES, fill=0)


# ---- Variant types: set a value into a Variant, read it back --------------------------

def show_int(n: Int) -> String:
    return String(n)


def int_roundtrip(x: Int, mut r: Run) -> Bool:
    var v = new_variant()
    var out = Int(0)
    if external_call["sandbox_variant_set_int", Int32](v.unsafe_ptr(), x) != 0:
        return False
    if external_call["sandbox_variant_get_int", Int32](v.unsafe_ptr(), Pointer(to=out)) != 0:
        return False
    return out == x


def show_bool(b: Bool) -> String:
    return String(b)


def bool_roundtrip(x: Bool, mut r: Run) -> Bool:
    var v = new_variant()
    var out = Int32(0)
    if external_call["sandbox_variant_set_bool", Int32](v.unsafe_ptr(), Int32(1) if x else Int32(0)) != 0:
        return False
    if external_call["sandbox_variant_get_bool", Int32](v.unsafe_ptr(), Pointer(to=out)) != 0:
        return False
    return (out != 0) == x


def show_float(f: Float64) -> String:
    return String(f)


def float_roundtrip(x: Float64, mut r: Run) -> Bool:
    var v = new_variant()
    var out = Float64(0)
    if external_call["sandbox_variant_set_float", Int32](v.unsafe_ptr(), x) != 0:
        return False
    if external_call["sandbox_variant_get_float", Int32](v.unsafe_ptr(), Pointer(to=out)) != 0:
        return False
    return out == x or (out != out and x != x)


def show_string(s: String) -> String:
    return String("\"") + s + "\""


def string_roundtrip(x: String, mut r: Run) -> Bool:
    var v = new_variant()
    var buf = List[UInt8](length=4096, fill=0)
    var n = Int(0)
    if external_call["sandbox_variant_set_string", Int32](v.unsafe_ptr(), x.unsafe_ptr(), x.byte_length()) != 0:
        return False
    if external_call["sandbox_variant_get_string", Int32](v.unsafe_ptr(), buf.unsafe_ptr(), 4096, Pointer(to=n)) != 0:
        return False
    if n != x.byte_length():
        return False
    for i in range(n):
        if buf[i] != x.unsafe_ptr()[i]:
            return False
    return True


def object_roundtrip(x: Int, mut r: Run) -> Bool:
    var v = new_variant()
    var out = Int(0)
    if external_call["sandbox_variant_set_object", Int32](v.unsafe_ptr(), x) != 0:
        return False
    if external_call["sandbox_variant_get_object", Int32](v.unsafe_ptr(), Pointer(to=out)) != 0:
        return False
    return out == x


# ---- The one-worker async runtime (n = 1 by decision) ----------------------------------------------------

def one_worker(x: Int, mut r: Run) -> Bool:
    # The decision is n = 1: one worker, so tasks interleave and never run in parallel.
    return external_call["KGEN_CompilerRT_AsyncRT_ParallelismLevel", Int32]() == 1


def parallelize_visits_each_item_once(x: Int, mut r: Run) -> Bool:
    var n = (x if x >= 0 else -x) % 50
    var counts = List[Int](length=n, fill=0)

    def work(i: Int) {mut counts}:
        counts[i] += 1

    parallelize(work, n)
    for i in range(n):
        if counts[i] != 1:
            return False
    return True


def spin_lock_under_tasks(x: Int, mut r: Run) -> Bool:
    # Mojo's spin lock goes through the spin-waiter entry points. Many tasks take
    # one lock, as in the stdlib's test_locks; every increment must be counted.
    var n = 1 + (x if x >= 0 else -x) % 50
    var lock = BlockingSpinLock()
    var counter = Atomic[Int64](0)
    var raw = 0

    __async def inc(mut blockingLock: BlockingSpinLock) {mut}:
        with BlockingScopedLock(blockingLock):
            raw += 1
            _ = counter.fetch_add(1)

    def run_group() {mut}:
        var tg = TaskGroup()
        for _ in range(0, n):
            tg.create_task(inc(lock))
        tg.wait[origin_of(lock)._mlir_origin]()

    run_group()
    _ = lock^
    return raw == n and Int(counter.load()) == n


def ticks_usec() -> Int:
    # Godot's clock through the host; -1 when there is no host to ask.
    return Int(external_call["sandbox_ticks_usec", Int64]())


def timeout_waits_its_deadline(x: Int, mut r: Run) -> Bool:
    # A chain nothing completes, waited on for 2 ms: a real wait takes at least 2 ms of Godot time.
    var chain = _Chain()
    _init_asyncrt_chain(Pointer(to=chain))
    var start = ticks_usec()
    var done = _async_wait_timeout(Pointer(to=chain), 2_000_000)
    var elapsed = ticks_usec() - start
    _del_asyncrt_chain(Pointer(to=chain))
    return (not done) and elapsed >= 2_000


# ---- Runner ---------------------------------------------------------------------------

def run[T: Value](
    name: String,
    gen: def(mut Run, Level) thin -> T,
    pred: def(T, mut Run) thin -> Bool,
    shrinker: def(T) thin -> List[T],
    show: def(T) thin -> String,
) -> Int:
    """Returns 1 for a falsified property, 0 for one that held."""
    try:
        prop_check_shrink[T](name, gen, pred, shrinker, show)
        print("PASS", name)
        return 0
    except e:
        print("FAIL", name, "::", String(e))
        return 1


def main():
    var failed = 0
    failed += run[Int]("int round trip (control)", gen_int, int_roundtrip, shrink_int, show_int)
    failed += run[Bool]("bool round trip", gen_bool, bool_roundtrip, shrink_bool, show_bool)
    failed += run[Float64]("float round trip", gen_float64, float_roundtrip, shrink_float64, show_float)
    var checked = 8
    if external_call["sandbox_host_present", Int32]() != 0:
        failed += run[String]("string round trip", gen_string, string_roundtrip, shrink_string, show_string)
    else:
        checked -= 1
        print("SKIP string round trip :: strings live in the host, and this host has no Sandbox")
    failed += run[Int]("object round trip", gen_int, object_roundtrip, shrink_int, show_int)
    failed += run[Int]("one worker (n = 1)", gen_int, one_worker, shrink_int, show_int)
    failed += run[Int]("parallelize visits each item once", gen_int, parallelize_visits_each_item_once, shrink_int, show_int)
    failed += run[Int]("spin lock under tasks (control)", gen_int, spin_lock_under_tasks, shrink_int, show_int)
    if ticks_usec() >= 0:
        checked += 1
        failed += run[Int]("Wait_Timeout waits its deadline", gen_int, timeout_waits_its_deadline, shrink_int, show_int)
    else:
        print("SKIP Wait_Timeout waits its deadline :: this host has no Godot clock")
    print("RESULT:", failed, "falsified of", checked)
    exit(1 if failed > 0 else 0)
