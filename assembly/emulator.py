import sys, pygame, numpy as np
pygame.init()

DEBUG_X = -325
DEBUG_Y = -320

# SIMT counter
avg_insn_count = 0

# Run a shader on one row of pixels
def run_row(prog, regs, row):
    global avg_insn_count
    scalar_regs = regs.reshape(-1, 1) @ np.ones(640, dtype=np.half).reshape(1, -1)
    vector_regs = np.zeros((16,640), dtype=np.half)
    x_reg = 0
    for x in range(640):
        xx = x - 320
        scalar_regs[1] = row - 240
        scalar_regs[2,x] = xx - xx % 8
        vector_regs[0,x] = xx % 8
    
    all_regs = np.concatenate((scalar_regs, vector_regs))

    # SIMT
    next_exec_pc = np.zeros(640, dtype=np.uint16)
    
    # run shader
    pc = 0
    insn_count = 0
    while pc < len(prog):
        insn_count += 1
        insn = prog[pc]
        op = (insn & 0xf0000) >> 16
        rd = 16 + ((insn & 0x0f000) >> 12)
        rs1 = (insn & 0x00f80) >> 7
        rs2 = (insn & 0x0007c) >> 2
        if row == DEBUG_Y:
            old_rdval = all_regs[rd, DEBUG_X].tobytes().hex(" ", 2)[2:] + all_regs[rd, DEBUG_X].tobytes().hex(" ", 2)[:2]
        
        new_rdval = None
        try:
            match op:
                case 0:
                    new_rdval = all_regs[rs1] + all_regs[rs2]
                case 1:
                    new_rdval = all_regs[rs1] - all_regs[rs2]
                case 2:
                    new_rdval = all_regs[rs1] * all_regs[rs2]
                case 3:
                    new_rdval = all_regs[rs1] / all_regs[rs2]
                case 4:
                    # all_regs[rd] = np.floor(all_regs[rs1])
                    adj_x = all_regs[rs1]-0.99951171875*(all_regs[rs1]<0)
                    new_rdval = np.floor(np.abs(adj_x))*np.sign(adj_x)
                case 5:
                    new_rdval = np.abs(all_regs[rs1])
                case 6:
                    new_rdval = np.sqrt(all_regs[rs1])
                case 7:
                    new_rdval = np.arctan(all_regs[rs1]) / np.pi
                case 8:
                    new_rdval = np.where(all_regs[rs2] < 0, all_regs[rs1], all_regs[rd])
                case 10:
                    # Halt opcode i added
                    break
                case 13:
                    possible_pc = ((insn & 0x0f000) >> 5) + (insn & 0x0007f)
                    next_exec_pc = np.where((all_regs[rs1] < 0) * (pc >= next_exec_pc), possible_pc, next_exec_pc)
                case 14:
                    x_reg = insn & 0x0ffff
                case 15:
                    if (x_reg > 0):
                        pc = (insn & 0x0ffff) - 1
                    
                    x_reg -= 1
                case 12: # DEBUG
                    if row == 240:
                        print(all_regs[26,321])
                        print(all_regs[20:23,321])
                case _:
                    raise Exception("Unknown instruction")
        except Exception as e:
            print(f"Error executing instruction: {e}")
            print(f"Instruction: {insn:020b}")
            print(f"PC: {pc}")
        
        # SPMD writeback
        if new_rdval is not None:
            all_regs[rd] = np.where(pc >= next_exec_pc, new_rdval, all_regs[rd])
            avg_insn_count += np.sum(pc >= next_exec_pc)
        else:
            avg_insn_count += 640
        
        if row == DEBUG_Y:
            new_rdval = all_regs[rd, DEBUG_X].tobytes().hex(" ", 2)[2:] + all_regs[rd, DEBUG_X].tobytes().hex(" ", 2)[:2]
            print(f"PC {pc}: register {rd} goes from {old_rdval} to {new_rdval}")
        pc += 1
    
    # print(all_regs[24,:])
    if row == 0:
        print(all_regs[:,321])
    if (row == 0):
        print(f"Executed {insn_count} instructions")
    
    return np.clip(all_regs[17:20].T * 256, 0, 255)

# Run the entire shader program, rendering into a framebuffer
def run_program(prog, framebuffer, regs):
    global avg_insn_count
    avg_insn_count = 0
    for y in range(480):
        framebuffer[:,y] = run_row(prog, regs, y)
    
    print(f"Average instructions per pixel: {avg_insn_count / (640 * 480)}")
    

# Load program
if len(sys.argv) != 2:
    print("Usage: python emulator.py <filename>")
    exit(1)
with open(sys.argv[1], "r") as f:
    prog = [int(l, 2) for l in f.readlines()]

print(f"Loaded program of length {len(prog)}")

# Set up the drawing window and framebuffer
screen = pygame.display.set_mode([640, 480])
framebuffer = np.zeros((640,480,3))

# Setup initial regs
regs = np.zeros(16, dtype=np.half)
# Registers for tunnel.mem
regs[3] = 0
regs[4] = 8
regs[5] = 16
regs[6] = 180
regs[9] = 4.0
regs[12] = 900
regs[13] = 200 * 4 / 255
regs[14] = 1000
regs[15] = 0.5
# Registers for gradient.mem
# regs[3] = 1/480
# Registers for spheredemo.mem
regs[3] = -0.348155
regs[4] = 0.870388
regs[5] = -0.348155
regs[6] = 1.5
regs[7] = 0.7
regs[8] = 0.5
regs[9] = 1/6.
regs[10] = 0.08
regs[11] = 0.01
regs[12] = 0.0025
regs[13] = 2.0
regs[14] = -6.5
regs[15] = 1.0
# Registers for mandelbrot.mem
regs[3] = -0.913
regs[4] = 0.267
regs[5] = 1/256
regs[6] = 16
regs[7] = 64 # 64 - (1/regs[5]) // 1024
regs[14] = 64
regs[15] = 1.0

print("Initial regs:")
print("\n".join([x[2:] + x[:2] for x in regs[3:].tobytes().hex("\n", 2).splitlines()]))
print("Fixed-point version:")
print("\n".join(str(2**16 * x) for x in regs[3:]))


# Run until the user asks to quit
running = True
keep_running_program = True
while running:
    # Did the user click the window close button?
    for event in pygame.event.get():
        if event.type == pygame.QUIT:
            running = False

    # Render framebuffer to display
    pygame.surfarray.blit_array(screen, framebuffer)

    # Run the program
    if keep_running_program:
        run_program(prog, framebuffer, regs)

        # Make color bad
        if False: # Basic truncation
            framebuffer = np.floor_divide(framebuffer, 16)
            framebuffer = framebuffer * 16
        else: # Randomness
            framebuffer = 2 * np.floor_divide(framebuffer, 2) # only 7-bits of float-to-fixed in hardware
            fb = np.clip(framebuffer, 0, 240) / 16
            framebuffer = np.floor(fb)
            fb -= np.floor(fb)
            framebuffer += fb > np.random.random((640,480,3))
            framebuffer *= 16
        
        keep_running_program = False

    # Update time
    #regs[3] += 0.5

    # Flip the display
    pygame.display.flip()
    # pygame.image.save(screen, "dithergood.png")

pygame.quit()