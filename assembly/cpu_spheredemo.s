# CPU program for sphere demo.
# Moves the sphere up and down (y position in GPU register 6 = address 0x1006).
# Sphere position is a 16.16-bit fixed point number (16-bit integer and 16-bit fraction), and should range from 1.0 to 4.0.
nop
nop
nop
init_gpu_regs:
    # Load initial values into GPU registers
    addi $2, $0, 4096
    addi $1, $0, -22816
    sw $1, 3($2)
    addi $1, $0, 57056
    sw $1, 4($2)
    addi $1, $0, -22816
    sw $1, 5($2)
    addi $1, $0, 49152
    sll $1, $1, 1
    sw $1, 6($2)
    addi $1, $0, 45888
    sw $1, 7($2)
    addi $1, $0, 32768
    sw $1, 8($2)
    addi $1, $0, 10920
    sw $1, 9($2)
    addi $1, $0, 5244
    sw $1, 10($2)
    addi $1, $0, 655 # should be 655.5, doesn't matter
    sw $1, 11($2)
    addi $1, $0, 164 # should be 163.875, doesn't matter
    sw $1, 12($2)
    addi $1, $0, 32768
    sll $1, $1, 2
    sw $1, 13($2)
    addi $1, $0, -53248
    sll $1, $1, 3
    sw $1, 14($2)
    addi $1, $0, 32768
    sll $1, $1, 1
    sw $1, 15($2)

init:
    # Load initial sphere position into $1 (only 17 bit immediate, so load 3 and shift left 15)
    addi $1, $0, 3
    sll $1, $1, 15
    # Load sphere memory address into $20 for later use
    addi $20, $0, 4102
    # Load position increment into $2 (use 1/64 of a unit)
    addi $2, $0, 1024
    # Load minimum into $3 and maximum into $4
    sll $3, $2, 6
    sll $4, $3, 2
main_loop:
    # Set sphere position
    sw $1, 0($20)
    # Increment sphere position
    add $1, $1, $2

    # If greater than maximum or less than minimum, reverse direction
    blt $4, $1, flip_direction
    blt $1, $3, flip_direction
    j skip_flip_direction
flip_direction:
    sub $2, $0, $2
skip_flip_direction:

    # Use delay loop to wait about 1/100th of a second
    addi $5, $0, 62500
delay_loop:
    addi $5, $5, -1 # one cycle
    blt $0, $5, delay_loop # three cycles (?)

    j main_loop