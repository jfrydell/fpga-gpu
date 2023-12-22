import sys

# Get filename from argument
if len(sys.argv) != 2:
    print("Usage: python assembler.py <filename>")
    exit(1)
filename = sys.argv[1]
with open(filename, "r") as f:
    lines = f.readlines()

# Loop through lines, assembling instruction-by-instruction into strings of 20 bits
prog = []
for l in lines:
    # Remove comments and blank lines
    line = l.partition("#")[0].strip()
    if line == "":
        continue
    
    try:
        insn = "" # Ugly hack: 21-bit instruction, then remove 5th bit later because rd is 4 bits
        # Split line into tokens
        op, args = line.partition(" ")[::2]
        args = args.split(",")
        try:
            regs = [f"{int(arg.strip()[1:]):05b}" for arg in args]
        except Exception as e:
            regs = None
        match op:
            case "add":
                insn = "0000" + regs[0] + regs[1] + regs[2] + "00"
            case "sub":
                insn = "0001" + regs[0] + regs[1] + regs[2] + "00"
            case "mul":
                insn = "0010" + regs[0] + regs[1] + regs[2] + "00"
            case "div":
                insn = "0011" + regs[0] + regs[1] + regs[2] + "00"
            case "floor":
                insn = "0100" + regs[0] + regs[1] + "0000000"
            case "abs":
                insn = "0101" + regs[0] + regs[1] + "0000000"
            case "sqrt":
                insn = "0110" + regs[0] + regs[1] + "0000000"
            case "atan":
                insn = "0111" + regs[0] + regs[1] + "0000000"
            case "cmov":
                insn = "1000" + regs[0] + regs[1] + regs[2] + "00"
            case "done":
                insn = "101010000000000000000"
            case "bltz":
                insn = "11011" + "XXXX" + f"{int(args[0].strip()[1:]):05b}" + "XXXXXXX " + ",".join(args)
            case "setx":
                # TODO: implement setx if argument is a number
                insn = "11101" + " XX " + ",".join(args) + " XX"
            case "loop":
                insn = "11111 XX " + ",".join(args) + " XX"
            case _:
                raise Exception("Unknown instruction")
        if insn[4] != "1":
            raise Exception("rd must be a vector register")
        insn = insn[:4] + insn[5:]
        prog.append(insn)
    except Exception as e:
        prog.append(f"ERROR: {l.strip()}")
        print(f"Error parsing line: {e}\nLine: {l}")

print("\n".join(prog))
print("00000000000000000000\n00000000000000000000\n00000000000000000000\n10100000000000000000")