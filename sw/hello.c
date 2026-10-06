// First test program. Exercises every part of the plumbing:
// .rodata, .data, .bss zeroing, the stack, and libgcc multiply/divide.
// Returns 0 on pass, or a code saying which check failed.

static const int primes[5] = {2, 3, 5, 7, 11};  // .rodata
int counter = 42;                                // .data
int scratch[16];                                 // .bss, must start zeroed

static int fib(int n) { return n < 2 ? n : fib(n - 1) + fib(n - 2); }

int main(void) {
    for (int i = 0; i < 16; i++)
        if (scratch[i] != 0) return 1;            // crt0 failed to zero .bss
    if (counter != 42) return 2;                  // .data not loaded

    int sum = 0;
    for (int i = 0; i < 5; i++) sum += primes[i];
    if (sum != 28) return 3;                      // .rodata wrong

    if (fib(10) != 55) return 4;                  // recursion, so the stack works

    volatile int a = 1234, b = 56;                // volatile: forces real mul/div
    if (a * b != 69104) return 5;                 // libgcc __mulsi3
    if (a / b != 22 || a % b != 2) return 6;      // libgcc __divsi3, __modsi3

    return 0;
}
