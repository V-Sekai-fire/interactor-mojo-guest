/* The guest-side half of the godot-sandbox host contract: the size of this
 * program's Variant, in a .sandbox_variant section. A host whose own Variant
 * differs (24 bytes single precision, 40 bytes double) refuses the program at
 * load. Same layout as program/cpp/docker/api/api.cpp in godot-sandbox. */
#include <stdint.h>

struct SandboxVariantSize {
    char magic[4];
    uint32_t size;
};

__attribute__((used, retain, section(".sandbox_variant")))
const struct SandboxVariantSize sandbox_variant_size = { { 'S', 'B', 'X', 'V' }, SANDBOX_VARIANT_SIZE };

/* ---- Public API: what the host can vmcall -------------------------------- */

#include <stddef.h>

#define ECALL_SANDBOX_ADD 547
#define VARIANT_INT 2

/* The guest's Variant: a 32-bit type, then the payload at offset 8. The scalar types fit
 * there. A string is an index into the host's scoped variants. The rest of the 24 or 40
 * bytes is never touched. */
struct GuestVariant {
    int32_t type;
    int32_t pad;
    union {
        int64_t i;
        double f;
    };
};

struct GuestFunctionExtra {
    const char *desc; size_t desc_len;
    const char *ret;  size_t ret_len;
    const char *args; size_t args_len;
};

/* Registers a public function while the host is initializing the guest (main runs
 * then). Same ecall the C++ guest API's add_sandbox_api_function makes. */
static void sandbox_add_function(const char *name, size_t name_len, void *address,
                                 const char *ret, const char *args) {
    size_t ret_len = 0, args_len = 0;
    while (ret[ret_len]) ret_len++;
    while (args[args_len]) args_len++;
    struct GuestFunctionExtra extra = { "", 0, ret, ret_len, args, args_len };
    register long a0 __asm__("a0") = 1;
    register const char *a1 __asm__("a1") = name;
    register size_t a2 __asm__("a2") = name_len;
    register void *a3 __asm__("a3") = address;
    register void *a4 __asm__("a4") = &extra;
    register long a7 __asm__("a7") = ECALL_SANDBOX_ADD;
    __asm__ volatile("ecall" : "+r"(a0) : "r"(a1), "r"(a2), "r"(a3), "r"(a4), "r"(a7) : "memory");
}

/* fast_exit: where every vmcall returns to. The host resolves it by name and
 * uses its address as the return address, so a finished call stops the machine
 * with the guest's state intact. Same code as the C++ guest API. */
__attribute__((used, retain, noreturn)) void fast_exit(void) {
    __asm__ volatile("1: .insn i SYSTEM, 0, x0, x0, 0x7ff\n j 1b");
    __builtin_unreachable();
}

/* ---- Variant conversions -------------------------------------------------
 * Each returns 0 on success, -EINVAL_ for a Variant of another type, -ENOSYS_ when the
 * host does not answer (no Sandbox host, as under rvlinux), and -ERANGE_ for a string
 * longer than the caller's buffer. */
#define EINVAL_ 22
#define ERANGE_ 34
#define ENOSYS_ 38
#define ECALL_IS_EDITOR 512
#define ECALL_VCREATE 517
#define ECALL_VFETCH 519
#define ECALL_ARENA_FREE 483
enum { VARIANT_NIL = 0, VARIANT_BOOL = 1, VARIANT_FLOAT = 3, VARIANT_STRING = 4, VARIANT_OBJECT = 24 };

static long ecall4(long n, long a0v, long a1v, long a2v, long a3v) {
    register long a0 __asm__("a0") = a0v;
    register long a1 __asm__("a1") = a1v;
    register long a2 __asm__("a2") = a2v;
    register long a3 __asm__("a3") = a3v;
    register long a7 __asm__("a7") = n;
    __asm__ volatile("ecall" : "+r"(a0) : "r"(a1), "r"(a2), "r"(a3), "r"(a7) : "memory");
    return a0;
}

/* The host answers ECALL_IS_EDITOR with 0 or 1. Anything else, including the -1 an
 * unhandled call leaves in a0, is no Sandbox host. */
int sandbox_host_present(void) {
    long r = ecall4(ECALL_IS_EDITOR, -1, 0, 0, 0);
    return r == 0 || r == 1;
}

/* Godot's clock: the Time singleton's get_ticks_usec, through GET_OBJ and OBJ_CALLP.
 * Returns -1 when the host does not answer, as under rvlinux. */
#define ECALL_GET_OBJ 504
#define ECALL_OBJ_CALLP 506
static long ecall7(long n, long a0v, long a1v, long a2v, long a3v, long a4v, long a5v, long a6v) {
    register long a0 __asm__("a0") = a0v;
    register long a1 __asm__("a1") = a1v;
    register long a2 __asm__("a2") = a2v;
    register long a3 __asm__("a3") = a3v;
    register long a4 __asm__("a4") = a4v;
    register long a5 __asm__("a5") = a5v;
    register long a6 __asm__("a6") = a6v;
    register long a7 __asm__("a7") = n;
    __asm__ volatile("ecall" : "+r"(a0) : "r"(a1), "r"(a2), "r"(a3), "r"(a4), "r"(a5), "r"(a6), "r"(a7) : "memory");
    return a0;
}

long sandbox_ticks_usec(void) {
    static long time_obj = 0;
    struct GuestVariant ret;
    if (!sandbox_host_present()) return -1;
    if (time_obj == 0) time_obj = ecall4(ECALL_GET_OBJ, (long)"Time", 4, 0, 0);
    if (time_obj == 0) return -1;
    ret.type = VARIANT_NIL;
    ecall7(ECALL_OBJ_CALLP, time_obj, (long)"get_ticks_usec", 14, 0, (long)&ret, 0, 0);
    return ret.type == VARIANT_INT ? (long)ret.i : -1;
}

/* A one-shot Godot Timer whose timeout calls `callback` in the guest. The callback is boxed:
 * (return Variant*, timer Variant*, capture Variant*). */
#define ECALL_TIMER_PERIODIC 530
void sandbox_timer_oneshot(double seconds, void *callback) {
    struct GuestVariant ret;
    unsigned char capture[32] = { 0 };
    register double f0 __asm__("fa0") = seconds;
    register long a0 __asm__("a0") = 1;
    register void *a1 __asm__("a1") = callback;
    register void *a2 __asm__("a2") = capture;
    register void *a3 __asm__("a3") = &ret;
    register long a7 __asm__("a7") = ECALL_TIMER_PERIODIC;
    __asm__ volatile("ecall" : "+r"(a0) : "f"(f0), "r"(a1), "r"(a2), "r"(a3), "r"(a7) : "memory");
}

extern void sandbox_timer_fired(void);
static void timer_callback(struct GuestVariant *ret, struct GuestVariant *timer, struct GuestVariant *capture) {
    (void)timer; (void)capture;
    ret->type = VARIANT_NIL;
    sandbox_timer_fired();
}
void sandbox_arm_timer_ns(long ns) { sandbox_timer_oneshot((double)ns / 1e9, (void *)timer_callback); }

/* Two numbers the guest leaves for the host to read: when a suspended wait began and ended. */
static long noted[2] = { -1, -1 };
void sandbox_note(long i, long v) { noted[i] = v; }
long sandbox_noted(long i) { return noted[i]; }

int sandbox_variant_set_int(struct GuestVariant *v, long x) { v->type = VARIANT_INT; v->i = x; return 0; }
int sandbox_variant_get_int(const struct GuestVariant *v, long *x) {
    if (v->type != VARIANT_INT) return -EINVAL_;
    *x = v->i;
    return 0;
}
int sandbox_variant_set_bool(struct GuestVariant *v, int b) { v->type = VARIANT_BOOL; v->i = b != 0; return 0; }
int sandbox_variant_get_bool(const struct GuestVariant *v, int *b) {
    if (v->type != VARIANT_BOOL) return -EINVAL_;
    *b = (v->i & 0xff) != 0;
    return 0;
}
int sandbox_variant_set_float(struct GuestVariant *v, double f) { v->type = VARIANT_FLOAT; v->f = f; return 0; }
int sandbox_variant_get_float(const struct GuestVariant *v, double *f) {
    if (v->type != VARIANT_FLOAT) return -EINVAL_;
    *f = v->f;
    return 0;
}
int sandbox_variant_set_object(struct GuestVariant *v, long handle) { v->type = VARIANT_OBJECT; v->i = handle; return 0; }
int sandbox_variant_get_object(const struct GuestVariant *v, long *handle) {
    if (v->type != VARIANT_OBJECT) return -EINVAL_;
    *handle = v->i;
    return 0;
}

/* VCREATE method 1 takes a pointer and a length and makes a scoped String on the host. */
int sandbox_variant_set_string(struct GuestVariant *v, const char *s, size_t n) {
    struct { const char *data; size_t size; } in = { s, n };
    v->type = VARIANT_NIL;
    ecall4(ECALL_VCREATE, (long)v, VARIANT_STRING, 1, (long)&in);
    return v->type == VARIANT_STRING ? 0 : -ENOSYS_;
}

/* VFETCH method 1 copies the string into the host's arena; it is copied out and freed. */
int sandbox_variant_get_string(const struct GuestVariant *v, char *buf, size_t cap, size_t *n) {
    struct { char *data; size_t size; } out = { 0, 0 };
    if (v->type != VARIANT_STRING) return -EINVAL_;
    ecall4(ECALL_VFETCH, (long)(unsigned)v->i, (long)&out, 1, 0);
    if (out.data == 0 && out.size == 0) return -ENOSYS_;
    int rc = out.size > cap ? -ERANGE_ : 0;
    if (rc == 0) for (size_t i = 0; i < out.size; i++) buf[i] = out.data[i];
    *n = out.size;
    if (out.data) ecall4(ECALL_ARENA_FREE, (long)out.data, 0, 0, 0);
    return rc;
}

/* The logic is Mojo; this is the boxed-Variant calling convention: a0 is the
 * return Variant, a1 and a2 point at the arguments. A non-int argument gives a
 * NIL return. */
extern long mojo_add_numbers(long a, long b) __attribute__((weak));

static void add_numbers(struct GuestVariant *ret, const struct GuestVariant *a, const struct GuestVariant *b) {
    long x, y;
    if (sandbox_variant_get_int(a, &x) || sandbox_variant_get_int(b, &y)) { ret->type = VARIANT_NIL; return; }
    sandbox_variant_set_int(ret, mojo_add_numbers(x, y));
}

/* echo returns its argument by going through every conversion above, so a host
 * round trip exercises the same code as the tests. A string longer than the buffer,
 * or a type not handled, gives NIL. */
static void echo(struct GuestVariant *ret, const struct GuestVariant *a) {
    long l; int b; double f; size_t n; char buf[4096];
    ret->type = VARIANT_NIL;
    if (!sandbox_variant_get_int(a, &l)) sandbox_variant_set_int(ret, l);
    else if (!sandbox_variant_get_bool(a, &b)) sandbox_variant_set_bool(ret, b);
    else if (!sandbox_variant_get_float(a, &f)) sandbox_variant_set_float(ret, f);
    else if (!sandbox_variant_get_object(a, &l)) sandbox_variant_set_object(ret, l);
    else if (!sandbox_variant_get_string(a, buf, sizeof buf, &n)) sandbox_variant_set_string(ret, buf, n);
}

/* The same function for a host with unboxed_arguments = true: a0 is the return Variant and
 * ints arrive raw in a1 and a2, not as Variant pointers. One sandbox uses one ABI, so this
 * is a second name. */
static void add_numbers_native(struct GuestVariant *ret, long a, long b) {
    sandbox_variant_set_int(ret, mojo_add_numbers(a, b));
}

extern long mojo_suspend_start(long ns) __attribute__((weak));
extern long mojo_suspend_elapsed(void) __attribute__((weak));
static void suspend_start(struct GuestVariant *ret, const struct GuestVariant *ns) {
    long n;
    if (sandbox_variant_get_int(ns, &n)) { ret->type = VARIANT_NIL; return; }
    sandbox_variant_set_int(ret, mojo_suspend_start(n));
}
static void suspend_elapsed(struct GuestVariant *ret) { sandbox_variant_set_int(ret, mojo_suspend_elapsed()); }

void sandbox_register_api(void) {
    if (mojo_suspend_start) {
        sandbox_add_function("suspend_start", 13, (void *)suspend_start, "int", "int ns");
        sandbox_add_function("suspend_elapsed", 15, (void *)suspend_elapsed, "int", "");
        return;
    }
    sandbox_add_function("add_numbers_native", 18, (void *)add_numbers_native, "int", "int a, int b");
    sandbox_add_function("add_numbers", 11, (void *)add_numbers, "int", "int a, int b");
    sandbox_add_function("echo", 4, (void *)echo, "Variant", "Variant value");
}
