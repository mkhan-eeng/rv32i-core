# Small program for the pipeline diagram (make pipeview).
# Sums a 4-element array. The loop shows:
#   - a load-use stall (lw then add uses the loaded value)
#   - forwarding (addi results used by the next instruction)
#   - a branch mispredict + flush on the first iteration (BTB is cold),
#     correct predictions after that, and a mispredict when the loop exits
    .section .text.init
    .globl _start
_start:
    la    a0, data
    li    t0, 4            # loop count
    li    t2, 0            # sum
loop:
    lw    t1, 0(a0)
    add   t2, t2, t1       # needs t1 straight from the load: 1-cycle stall
    addi  a0, a0, 4
    addi  t0, t0, -1
    bnez  t0, loop
    li    t3, 100          # 10+20+30+40
    bne   t2, t3, fail
    li    t4, 1
    la    t5, tohost
    sw    t4, 0(t5)        # pass
1:  j     1b
fail:
    li    t4, 3
    la    t5, tohost
    sw    t4, 0(t5)
2:  j     2b

    .data
data: .word 10, 20, 30, 40

    .section .tohost, "aw", @progbits
    .align 6
    .globl tohost
tohost: .dword 0
