# void mainImage( out vec4 fragColor, in vec2 fragCoord )
# {
#     float time = 6. * iTime;
#     vec2 coord = fragCoord - iResolution.xy / 2.0;
#     float d = 1000.0 / length(coord);
#     float theta = atan(coord.y / coord.x) / 3.14159265;
    
#     // Color given position
#     float p = fract(d * 1. + theta * 1.0 + time);
#     if (p < 0.5) {
#         fragColor = vec4(2.0/d,0.0,0.0, 1.0);
#     } else {
#         fragColor = vec4(0.0,2.0/d,0.0, 1.0);
#     }
    
#     if (abs(d - (15. - time)) < 0.5) {
#         fragColor = vec4(0.,0.,2.5/d,0.);
#     }
    
#     if (d < max(2.5, 30. - 2. * time)) {
#         fragColor = vec4(0.,0.,0.,0.);
# }

# VARIABLES:
# - r1 = y pixel
# - r2 = x pixel of left of block
# - r3 = time
# - r4-r5 = next ring times (NOTE: these represent time to hit d=0, not visible front of tunnel)
# - r6 = current player y position
# - r9 = min rendered tunnel distance (2.5 in shadertoy, could make cool intro by gradually reducing)
# - r10-11 = UNUSED (was color)
# - r12 = player radius ^ 2
# - r13 = max color constant, corresponding to d=1.0
# - r14 = 1000.0 (should be tunnel_radius / slope_per_pixel, will be less with lower resolution)
# - r15 = constant 0.5
# - r16 = block index, r16+r2 = actual pixel
# - r17-19 = output
# - r20 = x pixel
# - r21 = distance along tunnel
# - r22 = angle
# - r25 = desired color, already faded by distance
# - r31 = temp
# SETUP/COORDINATES:
add $20, $2, $16 # compute x pixel
mul $21, $20, $20 # \ compute length
mul $31, $1, $1 # |
add $21, $21, $31 # |
sqrt $21, $21 # /
div $21, $14, $21 # get distance along tunnel
div $22, $1, $20 # \ atan(y/x) / PI
atan $22, $22 # /
div $25, $13, $21 # get color magnitude
add $19, $0, $0 # zero out blue to start (others handled below to avoid black band)

# CALCULATE COLOR:
# get color coordinate `fract(distance + theta + time) - 0.5` for spiral
add $23, $21, $22
add $23, $23, $3
floor $31, $23
sub $23, $23, $31
sub $23, $23, $15
# load two colors (reg and green) in based on $23 < 0 and $23 > 0
add $17, $0, $0
add $18, $25, $0
cmov $17, $25, $23
cmov $18, $0, $23
# load color 3 for the incoming rings (r23 is distance + time, r24 checks if within 0.5 of desired hit time)
add $23, $21, $3
sub $24, $23, $4
abs $24, $24
sub $24, $24, $15
cmov $19, $25, $24 # TODO: find a way to combine cmovs (maybe need min function of two r24 values, or multiply since they won't overlap?)
cmov $17, $0, $24
cmov $18, $0, $24
sub $24, $23, $5
abs $24, $24
sub $24, $24, $15
cmov $19, $25, $24
cmov $17, $0, $24
cmov $18, $0, $24
# black out closest part of tunnel to give visible boundary
sub $24, $21, $9
cmov $17, $0, $24
cmov $18, $0, $24
cmov $19, $0, $24
# draw player (ball) in gray
sub $31, $1, $6 #\ (y - y_0) ^ 2
mul $31, $31, $31 #/
mul $30, $20, $20 #\ add x^2 to get r^2
add $31, $31, $30 #/
sub $31, $31, $12 # subtract desired r^2 so we can draw if < 0
cmov $17, $15, $31
cmov $18, $15, $31
cmov $19, $15, $31