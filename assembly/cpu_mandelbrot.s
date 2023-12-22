# Just loads the necessary regs
nop
nop
nop
init_gpu_regs:
    # Load static constants into GPU registers (r14, r15 constants)
    addi $1, $0, 64 #\
    sll $1, $1, 16 #| 64 * 2^16 (fixed point)
    sw $1, 4110($0) #/
    sra $1, $1, 6 # 64 >> 6 = 1
    sw $1, 4111($0)

# Initialize other variables
# - r3 = center x coordinate <- -0.913
# - r4 = center y coordinate <- 0.267
# - r5 = zoom level (units per pixel) <- 1/128
# - r6 = divergence threshold (squared) <- 16 (actually a constant for current version)
# - r7 = 64 - min iterations on screen (sets color range, (1/r5)/1024 works OK near boundary) <- 64
    addi $3, $0, -59834
    addi $4, $0, 17498
    addi $5, $0, 512
    addi $6, $0, 16
    sll $6, $6, 16
    sll $7, $6, 2
    sw $3, 4099($0)
    sw $4, 4100($0)
    sw $5, 4101($0)
    sw $6, 4102($0)
    sw $7, 4103($0)
main:
    # General structure: get keyboard input, modify variables and jump out of loop if we were supposed to (otherwise variable gets reset)
    # Get keyboard input
    lw $1, 4096($0)
    # Ignore input since we just processed it
    sw $0, 4096($0)

    # Zoom in on "Z" (26)
    sra $5, $5, 1 # do zoom
    addi $2, $0, 26
    bne $1, $2, skip1
    j break_input
    skip1:
    # Zoom out on "X" (34)
    sll $5, $5, 2 # undo zoom and zoom out
    addi $2, $0, 34
    bne $1, $2, skip2
    j break_input
    skip2:
    sra $5, $5, 1 # undo zoom in/out

    # Calculate amount to move by in $10
    # We move by 256 pixels, so that must be multiplied by r5
    sll $10, $5, 8

    # Move left on "A" (28)
    sub $3, $3, $10 # move left
    addi $2, $0, 28
    bne $1, $2, skip3
    j break_input
    skip3:
    add $3, $3, $10 # undo move left
    # Move right on "D" (35)
    add $3, $3, $10 # move right
    addi $2, $0, 35
    bne $1, $2, skip4
    j break_input
    skip4:
    sub $3, $3, $10 # undo move right
    # Move up on "S" (27)
    sub $4, $4, $10 # move up
    addi $2, $0, 27
    bne $1, $2, skip5
    j break_input
    skip5:
    add $4, $4, $10 # undo move up
    # Move down on "W" (29)
    add $4, $4, $10 # move down
    addi $2, $0, 29
    bne $1, $2, skip6
    j break_input
    skip6:
    sub $4, $4, $10 # undo move down

break_input:
    # Recalculate r7 in case r5 changed
    # want 64 - r7 = 1/1024 // r5, but 1/1024 = 64 in fixed-point, so can just do 64/r5 and then shift by 16 to convert int to fixed
    addi $7, $0, 64
    div $7, $7, $5
    sub $7, $0, $7 #\ invert to 64 - r7
    addi $7, $7, 64 #/
    sll $7, $7, 16

    # Write everything to GPU regs
    sw $3, 4099($0)
    sw $4, 4100($0)
    sw $5, 4101($0)
    sw $6, 4102($0)
    sw $7, 4103($0)

    # Delay loop to allow time for user input
    addi $10, $0, 60000
delay_loop:
    addi $10, $10, -1
    blt $0, $10, delay_loop

    # Loop
    j main