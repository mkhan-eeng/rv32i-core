# Startup code: runs before main().
# 1. Set up the stack pointer.
# 2. Zero the .bss section (C requires uninitialized globals to start at 0).
# 3. Call main().
# 4. Report main's return value through tohost and halt.

    .section .text.init
    .globl _start
_start:
    la    sp, _stack_top

    la    t0, _bss_start
    la    t1, _bss_end
1:  bgeu  t0, t1, 2f
    sw    zero, 0(t0)
    addi  t0, t0, 4
    j     1b

2:  call  main

    # tohost = (return value << 1) | 1
    # Spike treats this as "exit with code = return value". 0 means pass.
    slli  a0, a0, 1
    ori   a0, a0, 1
    la    t0, tohost
    sw    a0, 0(t0)
3:  j     3b

    .section .tohost, "aw", @progbits
    .align 6
    .globl tohost
tohost:   .dword 0
    .align 6
    .globl fromhost
fromhost: .dword 0
