# VARIABLES:
# - r1 = y pixel
# - r2 = x pixel of left of block
# - r3-r5 = light source vector
# - r6 = sphere y position (x and z are 0)
# - r7 = 0.7 for floor/sky color mix on sphere
# - r8 = 0.5 (used for floor color, could eliminate by doubling fract)
# - r9 = 1/384 (1/256 of specular multiplier (1/256 becuase of stupid clamp ^ 8))
# - r10 = 0.1 (1/2 of diffuse lighting multiplier (1/2 because of stupid clamp = x+abs(x))), also used for ambient lit sphere and upper distance threshold because it's a good constant
# - r11 = threshold distance
# - r12 = pixel -> ray direction conversion multiplier
# - r13 = initial y position
# - r14 = initial z position (likely negative)
# - r15 = constant 1 (used for sphere radius, z coordinate of ray, white floor)
# - r16 = block index, r16+r2 = actual pixel
# - r17-19 = output at end, also used as scratch in middle
# - r20-r22 = current position x,y,z
# - r23-r25 = ray direction x,y, z (z is just 1 at first, but reflection can change it)
# - r26 = raymarching distance (needed whole time to check if we are on sphere at end)
# - r27 = sphere lighting (scratch in raymarch)
# - r28 = floor/sky color of ray (regardless of if reflected or not)
# - r29-r31 = scratch
# SETUP:
add $23, $2, $16 # compute x pixel
mul $23, $23, $12 # compute x direction
mul $24, $1, $12 # compute y direction
sub $24, $0, $24 # negate y (so higher is positive)
add $25, $15, $0 # set z direction to 1 (used if not reflected, initial raymarch implicitly knows it's 1)
add $20, $0, $0 # clear initial x pos
add $21, $13, $0 # set initial y pos
add $22, $14, $0 # set intitial z pos
# RAYMARCH (move position along ray until we hit sphere or floor):
# - r31 = scratch (component squared, distance * ray direction), r28-r30 = new position (because we don't have predication)
setx NUMBER_OF_STEPS
raymarch_loop:
# compute distance to sphere
sub $31, $21, $6 #\ compute (y - sphere_y)^2
mul $26, $31, $31 #/
mul $31, $20, $20 # compute x^2
add $26, $26, $31 # add to distance
mul $31, $22, $22 # compute z^2
add $26, $26, $31 # add to distance
sqrt $26, $26 # compute distance to sphere center
sub $26, $26, $15 # subtract radius
# if we are within threshold (hit sphere) or too far (missed sphere), break
# - want sign = 1 if hit sphere OR too far, XOR works because mutually exclusive
# - so, just calculate (1/r10 - r26) * (r26 - r11), both operands positive if should continue, negative if should break
sub $31, $26, $11 # compute r26 - r11
div $30, $15, $10 #\ compute 1/r10 - r26
sub $30, $30, $26 #/
mul $31, $30, $31 # compute (1/r10 - r26) * (r26 - r11), < 0 if inside sphere (r26 - r11 < 0) or went too far (1/r11 - r26 < 0)
bltz $31, break_raymarch_loop # break if inside sphere or went too far
# update position if we didn't break
mul $31, $26, $23 # x component of distance * ray direction
add $20, $20, $31 # add to x position
mul $31, $26, $24 # y component of distance * ray direction
add $21, $21, $31 # add to y position
add $22, $22, $26 # ray z just 1, so just add distance
# loop back to start with new position
loop raymarch_loop
break_raymarch_loop:

# OUTPUT (generally should go from most to least specific then least to most complex case to optimize overwrites to avoid preserving values to be written later and to ensure we have space for scratch & later-needed values):
# plan: calculate sphere lighting (saved), find reflected ray if hit sphere (with cmov), get floor/sky color (saved), compute overall sphere color with lighting and reflected floor/sky, then replace with floor/sky color if missed sphere
# - r29-r31 free for scratch

# first, subtract distance from threshold, so $26 > 0 if hit sphere, < 0 if missed
sub $26, $11, $26
# if missed sphere, skip reflection and lighting calculation
bltz $26, skip_sphere

# subtract sphere y from our y because next two sections use position as normal
sub $21, $21, $6

# compute reflected ray:
# - ok to be wrong if didn't hit sphere, so (ab)use assumption that unit normal is just position, so (reflected) = (ray) - 2 * dot(ray, position) * position
# - use r17-r19 for reflected ray coordinates before cmov, r31 scratch, r28 dot product result (scratch for now, allocated for floor/sky later)
# - we subtract sphere y from our y for dot product to get position / normal relative to sphere center
mul $28, $20, $23 #\
mul $31, $21, $24 #| dot product (ray, position) in r28 (abuse r25 = z direction = 1, use r31 instead of r21 to get correct relative position)
add $28, $28, $31 #|
add $28, $28, $22 #/
add $28, $28, $28 # multiply by 2
mul $17, $28, $20 #\
mul $18, $28, $21 #|compute 2 * dot(ray, position) * position
mul $19, $28, $22 #/
sub $23, $23, $17 #\
sub $24, $24, $18 #|compute (ray) - 2 * dot(ray, position) * position, setting current ray
sub $25, $25, $19 #/

# compute sphere lighting in r27:
# - first we do diffuse lighting (max(dot(norm,light_direction), 0.) * 0.2), then specular (pow(max(dot(ray, light_direction),0.),8.) / 2.)
# - assume we are on sphere, so normal is just position
# - dot products in r30, r31 scratch
mul $30, $20, $3 #\
mul $31, $21, $4 #|
add $30, $30, $31 #| dot product of norm,light_direction in r30
mul $31, $22, $5 #|
add $30, $30, $31 #/
abs $31, $30      #\ poor man's max(x,0) = x + abs(x) (it's double, so constant in r10 is halved)
add $30, $30, $31 #/
mul $27, $30, $10 # multiply by 0.1 to get total diffuse lighting
#   specular (phong) lighting
mul $30, $23, $3 #\
mul $31, $24, $4 #| dot product of ray,light_direction in r30
add $30, $30, $31 #| (ab)uses fact that z-direction r25 = 1
add $30, $30, $5 #/
abs $31, $30      #\ poor man's max(x,0) = x + abs(x)
add $30, $30, $31 #/
mul $30, $30, $30 #\
mul $30, $30, $30 #| square 3 times to get x^8
mul $30, $30, $30 #/
mul $30, $30, $9  # multiply by 1/256 * 2/3 to get total specular lighting
add $27, $27, $30 # add to total lighting

# undo sphere y subtraction
add $21, $21, $6

# if we missed sphere, we can skip to here for floor/sky
skip_sphere:

# get floor/sky color based on current pos (r20-r22) and reflected ray (r23-r25), result goes in r28:
# first, if ray points upward (r24 > 0), we hit sky, so skip this section
add $28, $0, $0 # set r28 to black in case we skip
sub $29, $0, $24 # check if reflected ray is upward (29 scratch)
bltz $29, skip_floor_sky
# - first compute floor position in r30-r31 (pos.xz + pos.y / (-ray.y) * ray.xz), using r29 for scratch
# - color white if (fract(pos.x)-0.5)*(fract(pos.y)-0.5) < 0. (i.e. if one's frac is < 0.5 and the other is > 0.5), black otherwise. also black if reflected ray is upward (r24 > 0)
# - use r30-r31 for floor coords, r29 for scratch
div $29, $21, $24 #\ pos.y / (-ray.y) in r29
sub $29, $0, $29 #/
mul $30, $29, $23 #\ (pos.y / (-ray.y)) * ray.xz in r30-r31
mul $31, $29, $25 #/
add $30, $30, $20 #\ floor position done! pos.xz + (pos.y / (-ray.y)) * ray.xz in r30-r31
add $31, $31, $22 #/
floor $29, $30    #\
sub $30, $30, $29 #| fract(floor_pos) in r30-r31
floor $29, $31    #|
sub $31, $31, $29 #/
sub $30, $30, $8 #\
sub $31, $31, $8 #| (fract(pos.x)-0.5)*(fract(pos.y)-0.5) in r30, positive/negative corresponds to black/white
mul $30, $30, $31 #/
add $28, $0, $0 # set r28 to black
cmov $28, $15, $30 # if (fract(pos.x)-0.5)*(fract(pos.y)-0.5) < 0., set r28 to white
skip_floor_sky:

# compute overall sphere color with lighting and reflected floor/sky, put it in r17:
# - lighting already in r27, that can just be added
# - reflected color in r28, must multiply by 0.7 (from r7)
# - also add overall ambient light stolen from r10
# - if not sphere, just do floor/sky color
mul $17, $28, $7 # reflected color * 0.7
add $17, $17, $27 # add lighting
add $17, $17, $10 # add ambient light
cmov $17, $28, $26 # if outside sphere ($26 < 0 due to earlier branch logic), just use floor/sky color

# put color in r17-r19 for output
add $18, $17, $0
add $19, $17, $0

# ORIGINAL CODE:
# #define MAX_STEPS 10
# #define MAX_DIST 100.
# #define MIN_DIST 0.01

# vec3 light_direction = normalize(vec3(-1.0, 2.5, -1.0));
# vec3 start_pos = vec3(0., 2.0, -6.5);
# vec3 sphere_pos = vec3(0.2, 1.5, 0.);

# // assumes pos.y > 0 and ray.y < 0
# vec2 floor_pos(vec3 pos, vec3 ray) {
#     return pos.xz + pos.y / (-ray.y) * ray.xz;
# }

# vec4 floor_color(vec2 pos) {
#     //if ((fract(pos.x)-0.5)*(fract(pos.y)-0.5) < 0.)
#     if (((fract(pos.x) - 0.5 < 0.) != (fract(pos.y) - 0.5 < 0.)))
#         return vec4(1.,1.,1.,1.);
#     return vec4(0.,0.,0.,0.);
# }

# float bounce(float t) {
#     return 1. + 2.*abs(sin(t-1.));
# }

# void mainImage( out vec4 fragColor, in vec2 fragCoord )
# {
#     sphere_pos.y = bounce(iTime);
#     //vec2 uv = (fragCoord-.5*iResolution.xy)/iResolution.y;
#     vec2 uv = (fragCoord-iResolution.xy*0.5)/iResolution.y;
#     vec3 col = vec3(0.);
    
#     // current position and ray
#     vec3 pos = start_pos;
#     vec3 ray = normalize(vec3(uv.x,uv.y,1.));
    
#     // initial raymarch for sphere
#     float dist = 0.;
#     float d;
#     for (int i = 0; i < MAX_STEPS; i++) {
#         d = length(pos - sphere_pos) - 1.0;
#         dist += d;
#         pos += ray * d;
#         if (d < MIN_DIST || pos.y < 0. || dist > MAX_DIST) { // stop if hit sphere, floor, or threshold
#             break;
#         }
#     }
#     // if we missed the sphere and are upward, we hit sky
#     if (d >= MIN_DIST && ray.y >= 0.) {
#         fragColor = vec4(0.,0.,0.,1.);
#         return;
#     }
    
#     // if we hit the floor, color checkerboard
#     if (d >= MIN_DIST) {
#         fragColor = floor_color(floor_pos(start_pos, ray));
#         return;
#     }
    
#     // on sphere, calculate unit normal for lighting/reflection
#     // (for now, just position since it's a unit sphere, but more complex SDF and/or interactive position would require determining gradient)
#     vec3 norm = normalize(pos - sphere_pos);
#     float lighting = max(dot(norm,light_direction), 0.) * 0.2;
    
#     // find reflected ray to get floor position / highlights
#     ray -= 2. * dot(ray, norm) * norm;
    
#     // add Phong lighting for specular highlights
#     lighting += pow(max(dot(ray, light_direction),0.),8.) / 1.5;
    
#     // add reflected sky/floor
#     if (ray.y >= 0.) {
#         fragColor = 0.3 * vec4(0.1, 0.1, 0.1, 1.) + 0.7 * vec4(0.,0.,0.,1.) + lighting * vec4(1.,1.,1.,0.);
#         return;
#     }
#     fragColor = 0.3 * vec4(0.1,0.1,0.1,1.) + 0.7 * floor_color(floor_pos(pos, ray)) + lighting * vec4(1.,1.,1.,0.);
# }