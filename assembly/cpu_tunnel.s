# CPU program for tunnel game.
# Increments time (GPU r3 = 0x1003) and sets current and next ring positions (GPU r4,r5 = 0x1004,0x1005)
# At start, do intro effect by gradually decreasing draw theshold (GPU r9 = 0x1009, ends at 4.0)
nop
nop
nop
init_gpu_regs:
    # Load initial values into GPU registers (r13, r14, r15 constants)
    addi $20, $0, 4096
    addi $1, $0, 51392
    sll $1, $1, 2
    sw $1, 13($20)
    addi $1, $0, 64000
    sll $1, $1, 10
    sw $1, 14($20)
    addi $1, $0, 32768
    sw $1, 15($20)
    # Zero out 3, 4, 5, 6, and 9 (for after reset)
    addi $1, $0, 0
    sw $1, 3($20)
    sw $1, 4($20)
    sw $1, 5($20)
    sw $1, 6($20)
    sw $1, 9($20)
    sw $1, 12($20)

startup_animation:
    # Move GPU r9 from 64.0 to 4.0 (only visible at about 32, but want to give time for VGA to start)
    # Store current value in $1, end in $9
    addi $1, $0, 64
    sll $1, $1, 16
    addi $9, $0, 4
    sll $9, $9, 16
startup_loop:
    addi $1, $1, -1 # Decrement value
    # addi $1, $9, 0 # SKIP STARTUP FOR DEBUGGING
    sw $1, 9($20) # Store in GPU register
    # This loop runs ~4,000,000 times and we want it to take ~5 seconds = 125,000,000 cycles, so loop should take ~30 cycles. We just add a 5-time delay loop
    addi $3, $0, 5
startup_delay_loop:
    addi $3, $3, -1
    blt $0, $3, startup_delay_loop
    blt $9, $1, startup_loop # Loop until $1 <= $2

# Main program begins here
# Variables:
# - $1: Current time within wave (wave ends at 0)
# - $2: Current wave speed (delay at end of main), divided by 1.2 each wave
# - $3: Incoming ring time
# - $4: Next ring time
# - $5: Incoming ring address (for setting next next)
# - $6: Current player y position (180 * 2^16 is floor, goes in GPU 6 = 4102)
# - $7: Current ball velocity (y)
# - $8: Physics counter (apply gravity/velocity after 
# - $9: Draw threshold (4.0)
# - $10: Input (>0 if jump)
# - $11: Random number state (for randomizing next ring)
    addi $1, $0, 0 #\ Initialize to wave 0 done, so start by resetting at wave 1 (delay 833)
    addi $2, $0, 1000 #/
    addi $5, $0, 4100 # Incoming ring address
    addi $6, $0, 180 #\
    sll $6, $6, 16 #| Initialize player y and set in GPU
    sw $6, 4102($0) #/
    addi $11, $0, 100 # RNG seed
    addi $29, $0, 900 #\
    sll $29, $29, 16 #| Ball radius ^ 2 in GPU 12
    sw $29, 4108($0) #/
main:
    # Increment time
    addi $1, $1, 32 # SHOULD BE ABOUT BASE_DELAY_TIME / 25
    sw $1, 4099($0)
    # Check if wave is over
    blt $1, $0, new_wave_skip

    # New wave
    # Speed up wave $2 <- $2/1.2, reset $1 to -75 * 2^16
    addi $31, $0, 5
    mul $2, $2, $31
    addi $31, $0, 6
    div $2, $2, $31
    addi $1, $0, -75
    sll $1, $1, 16
    # Set incoming ring to already be passed (so it will be randomized)
    addi $3, $1, 0
    # Set next ring to be at TIME + 20 * 2^16
    addi $4, $0, 20
    sll $4, $4, 16
    add $4, $1, $4
    # Draw next at incoming pointer, then swap incoming to other address (to be overwritten by randomized ring)
    sw $4, 0($5)
    sub $5, $0, $5
    addi $5, $5, 8201
    # Reset physics / position
    addi $6, $0, 180
    sll $6, $6, 16
    addi $7, $0, 0
    addi $8, $0, 0
    sw $6, 4102($0)
new_wave_skip:

    # Check if incoming ring has passed
    sub $31, $3, $1 #\ $31 = ring time - current time = where ring is
    blt $9, $31, new_ring_skip #/ incoming ring has passed if where ring is <= min visible ==> skip if min visible < ring time - current time
    blt $0, $4, new_ring_skip # Skipped last time (undrawn next after wave end)

    # New incoming ring
    addi $3, $4, 0 # Set incoming to next
    # Generate a random delay in r30, using the LCG state in r11. We use ZX81 parameters a=75, c=74, m=65537 from Wikipedia
    # first, do the multiplication and addition without mod
    addi $31, $0, 75
    mul $11, $11, $31
    addi $11, $11, 74
    # now, do the mod: (65536A + B) mod 65537 = -A + B mod 65537 = (B > A) ? (B - A) : (B - A + 65537 = B - A + 1 with two's complement after masking)
    addi $31, $0, 65535 # mask
    sra $30, $11, 16 # r30 = A
    and $11, $11, $31 # r11 = B
    sub $11, $11, $30 # r11 = B - A
    sra $30, $11, 31 # r30 = (B - A) < 0 ? -1 : 0
    sub $11, $11, $30 # r11 = (B - A) < 0 ? B - A + 1 : B - A
    and $11, $11, $31 # mask off high bits to complete mod
    # now, scale to (5*2^16, 13*2^16) by multiplying by 8 and adding 5*2^16
    sll $30, $11, 3
    addi $31, $0, 5
    sll $31, $31, 16
    add $30, $30, $31
    # now, add to incoming to get next
    add $4, $3, $30 # New next is incoming + random
    # If next is after wave ends, don't draw it
    blt $0, $4, new_ring_skip
    # Draw next (where incoming was), swap pointer
    sw $4, 0($5)
    sub $5, $0, $5
    addi $5, $5, 8201
new_ring_skip:

    # If on ground, skip physics and do input check
    addi $29, $0, 180 #\
    sll $29, $29, 16 #| 180 * 2^16 = 180 fixed, need r29 < r6 ==> 180 <= r6 ==> r6 >= 180
    addi $29, $29, -1 #/
    blt $29, $6, on_ground

    # Apply physics (velocity / gravity) to ball
    addi $7, $7, 1 # Apply gravity
    add $6, $6, $7 # Apply velocity
    sw $6, 4102($0) # Set ball position in GPU

    # Check if ball is still off floor, skipping rest of main (ground snap and input check) if so
    addi $29, $29, 1 # previously held 180 * 2^16 - 1, now 180 * 2^16, need r6 < r29 ==> r6 < 180 for branch (above floor, on or below means snap)
    blt $6, $29, main_done

    # Snap to floor (in case we are below); MAYBE UNNECESSARY DUE TO INTEGER GRAVITY ALGORITHM
    addi $6, $0, 180 #\ set position to 180 * 2^16
    sll $6, $6, 16 #/
    addi $7, $0, 0 # zero out velocity
    sw $6, 4102($0)

on_ground:
    # We are on the ground, either from snapping or because we haven't jumped. Check input and handle jump
    # Put input in $10, if nonzero then jump
    lw $10, 4096($0)
    addi $29, $0, 1
    blt $10, $29, check_loss # no input, don't jump
    # Need $7 = -3500 (velocity), $6 < 180 (physics skipped if on ground)
    addi $7, $0, -3500
    addi $6, $6, -1

check_loss:
    # trigger loss if ring is under ball (ring pos = r3 - r1 in (4.5,5.5))
    addi $29, $0, 9 #\ r29 = 4.5*2^16
    sll $29, $29, 15 #/
    add $29, $1, $29 # r29 = r1 + 4.5*2^16 (equivalent ring position of back of ball)
    blt $3, $29, main_done # if ring is before ball, ring has passed ==> no loss
    addi $29, $29, 65535 # r29 = r1 + 5.5*2^16 (equivalent ring position of front of ball)
    blt $29, $3, main_done # if ring is after ball, still have time to jump ==> no loss
    # If we get here, we have lost ==> wait ~1 second in sadness and restart game 
    addi $29, $0, 1
    sll $29, $29, 22
loser_loop:
    addi $29, $29, -1
    blt $0, $29, loser_loop
    j init_gpu_regs

main_done:

    add $29, $0, $2
main_delay_loop:
    addi $29, $29, -1
    blt $0, $29, main_delay_loop

    j main