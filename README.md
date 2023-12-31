# FPGA GPU

This is (a subset of) the code for my Duke ECE 350 Digital Systems final project, written in Fall 2023.
The project is described more [here](https://fletchrydell.com/projects/gpu) as well as in the technical report in this repository.

The code here includes only that which I wrote specifically for the final project, and not anything from prior course assignments.
Unfortunately, this means that running this code is impossible if you do not have a working version of the CPU made in the course, along with a few other components needed.
However, I describe below what is included in this repository as well as what the missing files do.

## Verilog

The `gpu` directory includes the Verilog code implementing the GPU core (`gpu_core.v`), keyboard input system (`keuyboard_input.v`), framebuffer/output logic (`framebuffer_output.v`), and a main wrapper for everything (`main.v`).
Additionally, `fp_unit.v` includes the execution unit for the GPU core, and `fp_lookup.c` generates the needed lookup table for the arctan instruction.

The following Verilog modules are missing:
- `processor` is the CPU created throughout the rest of ECE 350. It handles the actual execution of instructions, exposing control and data signals for accessing the register file, data memory, and instruction memory.
- `regfile` is the register file created in another ECE 350 assignment. Implementing it would be fairly easy with Behavioral Verilog (`reg` variables were prohibited for the assignment, making it slightly less trivial).
- `RAM` and `ROM` are modules implementing basic RAMs and ROMs. The `ROM_B` module I implemented in `main.v` is only a few keystrokes away from implementing these, if you're so inclined.
- `Ps2Interface` is a module that gives make/break keycodes from a keyboard plugged into the FPGA. I believe [this](https://github.com/Digilent/Nexys4/blob/master/Projects/User_Demo/src/hdl/Ps2Interface.vhd) is the VHDL module we used, but am too lazy to check.
- `fp_add_sub`, `fp_mult`, `fp_div`, and `fp_sqrt` were generated from the Vivado IP Catalog. They implement non-blocking half-precision floating point operations.
- `fixed_to_single`, `single_to_half`, and `floating_point_1` are likewise Vivado IP blocks for fixed-point (16 bit signed int, 16 bit fraction) to single-precision float, single to half precision float, and half-precision float to 8-bit fixed (1 bit sign, 7 bit fraction) converters, respectively.
  `fixed_to_single` and `single_to_half` are used in tandem because the Vivado IP Catalog has no fixed-point to half-precision converter.

## Assembly

The `assembly` includes all assembly I wrote for this project, along with a (very bad) assembler and emulator for the GPU's ISA. The `cpu_` prefixed files are for the CPU, which follows the architecture specified in the processor assignment.
Because it is course material, I do not include the specification or assembler for the CPU.

## Generated Files

The `generated` directory includes the `.mem` files generated by both the assemblers and the lookup table for arctan. Additionally, it includes generated bitstreams for the 3 demo programs. These can be flashed to the Nexys A7 with OpenOCD (see [Duke's ECE 350 Toolchain](https://github.com/plutothespacedog/ECE350-Toolchain-Mac/blob/master/upload.sh)).

## Technical Report

The `report` directory is a [Typst](https://typst.app/) project for the technical report I wrote describing the project. It also includes the rendered pdf of the report, if you'd like more information about the project.
