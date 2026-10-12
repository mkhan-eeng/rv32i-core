// Minimal test environment so the official riscv-tests run on this core.
//
// The standard environment sets up CSRs and trap handlers, which an RV32I
// core without Zicsr doesn't have. This one only does what the rv32ui tests
// need: a _start label at 0x80000000, and pass/fail through tohost.
//   pass: tohost = 1
//   fail: tohost = (test number << 1) | 1    (gp holds the test number)
#ifndef RV32I_CORE_RISCV_TEST_H
#define RV32I_CORE_RISCV_TEST_H

#define RVTEST_RV32U .macro init; .endm
#define RVTEST_RV64U RVTEST_RV32U

#define TESTNUM gp

#define RVTEST_CODE_BEGIN                                               \
        .section .text.init;                                            \
        .align  6;                                                      \
        .globl _start;                                                  \
_start:                                                                 \
        init;

#define RVTEST_CODE_END                                                 \
        .word 0x00000000   /* never reached; decodes as illegal */

#define RVTEST_PASS                                                     \
        li      t0, 1;                                                  \
        la      t1, tohost;                                             \
        sw      t0, 0(t1);                                              \
1:      j       1b;

#define RVTEST_FAIL                                                     \
1:      beqz    TESTNUM, 1b;                                            \
        slli    TESTNUM, TESTNUM, 1;                                    \
        ori     TESTNUM, TESTNUM, 1;                                    \
        la      t1, tohost;                                             \
        sw      TESTNUM, 0(t1);                                         \
2:      j       2b;

#define EXTRA_DATA

#define RVTEST_DATA_BEGIN                                               \
        EXTRA_DATA                                                      \
        .pushsection .tohost,"aw",@progbits;                            \
        .align 6; .global tohost; tohost: .dword 0;                     \
        .align 6; .global fromhost; fromhost: .dword 0;                 \
        .popsection;                                                    \
        .align 4; .global begin_signature; begin_signature:

#define RVTEST_DATA_END .align 4; .global end_signature; end_signature:

#endif
