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

/* The guest's Variant: a 32-bit type, then the value at offset 8. Only INT is
 * read or written here, so the rest of the 24 or 40 bytes is never touched. */
struct GuestVariant {
    int32_t type;
    int32_t pad;
    int64_t i;
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
 * Each returns 0 on success and -ENOSYS_ for a type the glue does not handle yet.
 * Only INT is handled. The rest are declared so tests/limits.mojo can call them:
 * they are the red side of a test-first list, and each one's test passes the day
 * the stub is replaced. */
#define ENOSYS_ 38
enum { VARIANT_NIL = 0, VARIANT_BOOL = 1, VARIANT_FLOAT = 3, VARIANT_STRING = 4, VARIANT_OBJECT = 24 };

int sandbox_variant_set_int(struct GuestVariant *v, long x) { v->type = VARIANT_INT; v->i = x; return 0; }
int sandbox_variant_get_int(const struct GuestVariant *v, long *x) {
    if (v->type != VARIANT_INT) return -ENOSYS_;
    *x = v->i;
    return 0;
}
int sandbox_variant_set_bool(struct GuestVariant *v, int b) { (void)b; v->type = VARIANT_NIL; return -ENOSYS_; }
int sandbox_variant_get_bool(const struct GuestVariant *v, int *b) { (void)v; (void)b; return -ENOSYS_; }
int sandbox_variant_set_float(struct GuestVariant *v, double f) { (void)f; v->type = VARIANT_NIL; return -ENOSYS_; }
int sandbox_variant_get_float(const struct GuestVariant *v, double *f) { (void)v; (void)f; return -ENOSYS_; }
int sandbox_variant_set_string(struct GuestVariant *v, const char *s, size_t n) { (void)s; (void)n; v->type = VARIANT_NIL; return -ENOSYS_; }
int sandbox_variant_get_string(const struct GuestVariant *v, char *buf, size_t cap, size_t *n) { (void)v; (void)buf; (void)cap; (void)n; return -ENOSYS_; }
int sandbox_variant_set_object(struct GuestVariant *v, long handle) { (void)handle; v->type = VARIANT_NIL; return -ENOSYS_; }
int sandbox_variant_get_object(const struct GuestVariant *v, long *handle) { (void)v; (void)handle; return -ENOSYS_; }

/* The logic is Mojo; this is the boxed-Variant calling convention: a0 is the
 * return Variant, a1 and a2 point at the arguments. A non-int argument gives a
 * NIL return. */
extern long mojo_add_numbers(long a, long b) __attribute__((weak));

static void add_numbers(struct GuestVariant *ret, const struct GuestVariant *a, const struct GuestVariant *b) {
    long x, y;
    if (sandbox_variant_get_int(a, &x) || sandbox_variant_get_int(b, &y)) { ret->type = VARIANT_NIL; return; }
    sandbox_variant_set_int(ret, mojo_add_numbers(x, y));
}

void sandbox_register_api(void) {
    sandbox_add_function("add_numbers", 11, (void *)add_numbers, "int", "int a, int b");
}
