/*
 * CoreMark port for the RV32I core.
 * Based on CoreMark's barebones port (Apache 2.0, EEMBC).
 *
 * Time is measured with the memory-mapped cycle counter, so the
 * "ticks" CoreMark prints are clock cycles. Output goes to the
 * memory-mapped UART (see tb/tb_core.sv).
 */
#include "coremark.h"
#include "core_portme.h"

#if VALIDATION_RUN
volatile ee_s32 seed1_volatile = 0x3415;
volatile ee_s32 seed2_volatile = 0x3415;
volatile ee_s32 seed3_volatile = 0x66;
#endif
#if PERFORMANCE_RUN
volatile ee_s32 seed1_volatile = 0x0;
volatile ee_s32 seed2_volatile = 0x0;
volatile ee_s32 seed3_volatile = 0x66;
#endif
#if PROFILE_RUN
volatile ee_s32 seed1_volatile = 0x8;
volatile ee_s32 seed2_volatile = 0x8;
volatile ee_s32 seed3_volatile = 0x8;
#endif
volatile ee_s32 seed4_volatile = ITERATIONS;
volatile ee_s32 seed5_volatile = 0;

#define CYCLE_COUNTER (*(volatile ee_u32 *)0x1000000C)

/* Clock frequency the score is reported against. In simulation only the
   cycle count matters; CoreMark/MHz = iterations * 1e6 / cycles. */
#ifndef CLOCK_HZ
#define CLOCK_HZ 100000000
#endif
#define EE_TICKS_PER_SEC CLOCK_HZ

static CORETIMETYPE start_time_val, stop_time_val;

void start_time(void) { start_time_val = CYCLE_COUNTER; }
void stop_time(void)  { stop_time_val = CYCLE_COUNTER; }

CORE_TICKS get_time(void) { return (CORE_TICKS)(stop_time_val - start_time_val); }

secs_ret time_in_secs(CORE_TICKS ticks)
{
    return ((secs_ret)ticks) / (secs_ret)EE_TICKS_PER_SEC;
}

ee_u32 default_num_contexts = 1;

void portable_init(core_portable *p, int *argc, char *argv[])
{
    (void)argc;
    (void)argv;
    if (sizeof(ee_ptr_int) != sizeof(ee_u8 *))
        ee_printf("ERROR! ee_ptr_int must hold a pointer\n");
    if (sizeof(ee_u32) != 4)
        ee_printf("ERROR! ee_u32 must be 32 bits\n");
    p->portable_id = 1;
}

/* After the run, write the score (iterations per second x 100) in decimal
   to the board's 7-segment display register, e.g. 56.27 shows as 00005627.
   In simulation the write goes nowhere. */
#define DISPLAY (*(volatile ee_u32 *)0x10000010)

void portable_fini(core_portable *p)
{
    p->portable_id = 0;
    unsigned long long ticks = (unsigned long long)(stop_time_val - start_time_val);
    unsigned long long iters = (unsigned long long)seed4_volatile;
    ee_u32 score = ticks ? (ee_u32)(iters * EE_TICKS_PER_SEC * 100ULL / ticks) : 0;
    ee_u32 bcd = 0;
    for (int i = 0; i < 8; i++) {
        bcd |= (score % 10) << (4 * i);
        score /= 10;
    }
    DISPLAY = bcd;
}
