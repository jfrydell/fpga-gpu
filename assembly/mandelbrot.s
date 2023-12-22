# VARIABLES:
# - r1 = y pixel
# - r2 = x pixel of left of block
# - r3-4 = x and y coordinates of center pixel
# - r5 = conversion factor from pixel to coordinate (1/256)
# - r6 = divergence threshold ^ 2 (z^2 > r6 means stop iterations)
# - r7 = how much to divide by for color (used to =number of steps)
# - r14 = number of steps (must be equal to setx, one less than total iteration count, so will reach -1 if never escape)
# - r15 = 1 (for decrementing iteration count)
# - r16 = block index, r16+r2 = actual pixel
# - r17-19 = output
# - r20-21 = initial x and y coordinates (c)
# - r22-23 = current x and y coordinates (z)
# - r24-25 = temporary x and y during calculation
# - r26 = iteration count (starts at MAX_LOOPBACKS, decrements to -1 at end of last iteration (equal to x register))

# SETUP/COORDINATES
add $20, $2, $16 # get x pixel
mul $20, $20, $5 # convert x to coordinate
mul $21, $1, $5 # convert y to coordinate
add $20, $20, $3 # get x pixel relative to origin
sub $21, $4, $21 # get y pixel relative to origin while inverting y axis to match cartesian
add $22, $20, $0 #\ initialize z
add $23, $21, $0 #/
add $26, $0, $14 # initialize iteration count to number of steps

# ITERATION
setx NUMBER_OF_STEPS
loop:
# Calculate z^2 = (x^2 - y^2), 2xy
# Use $24-$25 as temporaries for new x
mul $24, $22, $22 # x^2
mul $25, $23, $23 # y^2
mul $23, $22, $23 #\ y <- 2xy
add $23, $23, $23 #/
sub $22, $24, $25 # x <- x^2 - y^2
# Stop if x^2 + y^2 > r6 (checking divergence of previous iteration to avoid recalculating after +c)
add $31, $24, $25 # x^2 + y^2
sub $31, $6, $31 # r6 - (x^2 + y^2) is negative if we should stop
bltz $31, break # break if negative
# Calculate z^2 + c
add $22, $22, $20 # add Re{c}
add $23, $23, $21 # add Im{c}
# Decrement iteration count and loop
sub $26, $26, $15
loop loop
break:

# COLORS
add $17, $0, $0
add $18, $0, $0
add $19, $0, $0
bltz $26, end # if iteration count is negative, we never escaped, so color black
# Get continuous iteration count using distance (farther = fewer iterations = higher r26)
# - since we have r6 - (x^2 + y^2) in r31, we can just subtract r31/r6^2 (|r31| < r6^2 because previous iteration didn't exceed r6)
div $24, $31, $6
div $24, $24, $6
sub $26, $26, $24 # r24 is r31/r6^2
# Calculate color
div $17, $26, $7 # for red, divide by some constant roughly equal to number of steps i.g. (if number of iterations taken = $14 - $26 < $14 - $7, then $26/$7 > 1)
sub $17, $15, $17 # invert iteration count, so we get brighter color for more iterations (too few iterations based on $7 threshold means $17 < 0 :( )
abs $17, $17 # check for bad zoom where $17 < 0, if so just invert it for OK recovery (NOT IDEAL)
sqrt $18, $17
sqrt $19, $18

# Halt
end: