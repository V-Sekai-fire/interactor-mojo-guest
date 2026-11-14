/* Freestanding Linux-syscall entry for a Mojo guest: _start, write, exit. */
extern int mojo_guest_main(void);

static long sys3(long n, long a, long b, long c) {
    register long a7 __asm__("a7") = n;
    register long a0 __asm__("a0") = a;
    register long a1 __asm__("a1") = b;
    register long a2 __asm__("a2") = c;
    __asm__ volatile("ecall" : "+r"(a0) : "r"(a7), "r"(a1), "r"(a2) : "memory");
    return a0;
}

long write(int fd, const void *buf, unsigned long n) { return sys3(64, fd, (long)buf, (long)n); }

void *memcpy(void *d, const void *s, unsigned long n) {
    char *dd = d; const char *ss = s;
    while (n--) *dd++ = *ss++;
    return d;
}
void *memset(void *d, int c, unsigned long n) {
    char *dd = d;
    while (n--) *dd++ = (char)c;
    return d;
}

__attribute__((noreturn)) void c_start(void) {
    int rc = mojo_guest_main();
    sys3(93, rc, 0, 0);
    for (;;) {}
}

__asm__(".globl _start\n_start:\n  .option push\n  .option norelax\n  la gp, __global_pointer$\n  .option pop\n  andi sp, sp, -16\n  call c_start\n");
