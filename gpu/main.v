`timescale 1ns / 1ps
module main(
    input clock,
    input[15:0] SW,
    input CPU_RESETN,
    inout PS2_CLK,
    inout PS2_DATA,
    output hSync, 		// H Sync Signal
	output vSync, 		// Veritcal Sync Signal
	output[3:0] VGA_R,  // Red Signal Bits
	output[3:0] VGA_G,  // Green Signal Bits
	output[3:0] VGA_B,   // Blue Signal Bits
	output[15:0] LED
);
    //reg clock = 1'b0; always #5 clock = ~clock; // Stupid testing
    localparam INSN_SIZE = 20;
    localparam WORD_SIZE = 16;
    localparam REG_ID_SIZE = 4;
    localparam OPCODE_SIZE = 4;
    localparam WIDTH = 16;

    localparam PROGRAM = "tunnel.mem";

    // Divide clock for core
    wire slow_clock;
    reg[13:0] slow_clock_cntr; initial slow_clock_cntr <= 14'b0;
    always @(posedge clock) slow_clock_cntr <= slow_clock_cntr + 1;
    assign slow_clock = slow_clock_cntr[1];

    // CPU core
    wire cpu_rwe, cpu_mwe;
    wire cpu_reset; assign cpu_reset = ~CPU_RESETN;
	wire[4:0] cpu_rd, cpu_rs1, cpu_rs2;
	wire[31:0] cpu_instAddr, cpu_instData, 
		cpu_rData, cpu_regA, cpu_regB,
		cpu_memAddr, cpu_memDataIn, cpu_memDataOut;
    reg[31:0] cpu_memData;

	// Main Processing Unit (CPU)
	processor CPU(.clock(slow_clock), .reset(cpu_reset), 		
		.address_imem(cpu_instAddr), .q_imem(cpu_instData),
		// Regfile
		.ctrl_writeEnable(cpu_rwe),     .ctrl_writeReg(cpu_rd),
		.ctrl_readRegA(cpu_rs1),     .ctrl_readRegB(cpu_rs2), 
		.data_writeReg(cpu_rData), .data_readRegA(cpu_regA), .data_readRegB(cpu_regB),
		// RAM
		.wren(cpu_mwe), .address_dmem(cpu_memAddr), 
		.data(cpu_memDataIn), .q_dmem(cpu_memData)); 
	
	// CPU Instruction Memory (ROM)
	ROM_B #(.MEMFILE({"cpu_", PROGRAM}))
	CPUInstMem(.clk(slow_clock), 
		.addr(cpu_instAddr[11:0]), 
		.dataOut(cpu_instData));
	
	// CPU Register File
	regfile RegisterFile(.clock(slow_clock), 
		.ctrl_writeEnable(cpu_rwe), .ctrl_reset(cpu_reset), 
		.ctrl_writeReg(cpu_rd),
		.ctrl_readRegA(cpu_rs1), .ctrl_readRegB(cpu_rs2), 
		.data_writeReg(cpu_rData), .data_readRegA(cpu_regA), .data_readRegB(cpu_regB));
						
	// CPU Memory (RAM)
	RAM CPUMem(.clk(slow_clock), 
		.wEn(cpu_mwe), 
		.addr(cpu_memAddr[11:0]), 
		.dataIn(cpu_memDataIn), 
		.dataOut(cpu_memDataOut));
    
    // MMIO
    reg[WORD_SIZE - 1:0] regfile_scalar[15:3]; // forward-declare cpu-writable regs
    wire[15:0] regfile_scalar_input;
    wire[7:0] kb_data;
    reg kb_clear = 1'b0;
    always @(posedge slow_clock) begin
        // Addresses:
        // - 0x1000 (read-only) = keyboard data mask (bit 0 = space, bit 1 = up, bit 2 = down)
        // - 0x1003-0x100f (write-only) = scalar registers 3-15
        if (cpu_memAddr < 32'h1000)
            cpu_memData <= cpu_memDataOut;
        else if (cpu_memAddr == 32'h1000)
            cpu_memData <= {24'b0, kb_data};
        else
            cpu_memData <= 32'b0;
        
        if (cpu_memAddr >= 32'h1003 && cpu_memAddr < 32'h1010 && cpu_mwe == 1'b1)
            regfile_scalar[cpu_memAddr[3:0]] <= regfile_scalar_input;


        if (cpu_mwe == 1'b1 && cpu_memAddr == 32'h1000)
            kb_clear <= 1'b1;
        else
            kb_clear <= 1'b0;
    end
    // Fixed-point memory to float GPU
    wire[31:0] regfile_scalar_input_single;
    fixed_to_single mmio_fts(.s_axis_a_tvalid(1'b1), .s_axis_a_tdata(cpu_memDataIn),
 .m_axis_result_tvalid(), .m_axis_result_tdata(regfile_scalar_input_single));
    single_to_half mmio_sth(.s_axis_a_tvalid(1'b1), .s_axis_a_tdata(regfile_scalar_input_single), .m_axis_result_tvalid(), .m_axis_result_tdata(regfile_scalar_input));
    // Ps2 Interface
    keyboard_input KB(.key(kb_data), .clear(kb_clear), .clk(clock), .ps2_clk(PS2_CLK), .ps2_data(PS2_DATA));
    
    // GPU core
    reg reset = 1;
    wire[15:0] pc;
    wire[INSN_SIZE-1:0] instruction;
    wire[REG_ID_SIZE-1:0] ctrl_rs1, ctrl_rs2;
    wire[WORD_SIZE-1:0] data_rs1, data_rs2;
    wire[WIDTH*WORD_SIZE*3-1:0] frame_out;
    gpu GPU(slow_clock, reset, pc, instruction, ctrl_rs1, ctrl_rs2, data_rs1, data_rs2, frame_out);

    // GPU Register file
    reg[WORD_SIZE-1 : 0] regfile_scalar_y, regfile_scalar_x; // separate from rest to avoid multi-driven net
    integer i;
    initial begin
        for (i = 3; i < 16; i = i + 1)
            regfile_scalar[i] <= 16'd0;
        
        regfile_scalar_y = 16'hdb80;
        regfile_scalar_x = 16'hdd00;
    end
    
    assign data_rs1 = ctrl_rs1 > 2 ? regfile_scalar[ctrl_rs1]
        : ctrl_rs1 == 2 ? regfile_scalar_x : ctrl_rs1 == 1 ? regfile_scalar_y : 16'd0;
    assign data_rs2 = ctrl_rs2 > 2 ? regfile_scalar[ctrl_rs2]
        : ctrl_rs2 == 2 ? regfile_scalar_x : ctrl_rs2 == 1 ? regfile_scalar_y : 16'd0;

    // GPU Instruction Memory (ROM)
	ROM_B #(.MEMFILE(PROGRAM), .DATA_WIDTH(INSN_SIZE))
	InstMem(.clk(slow_clock), 
		.addr(pc[11:0]), 
		.dataOut(instruction));

    // Scheduling logic (pixel coords to registers and outputs to framebuffer)
    reg fb_WE = 1'b0;
    wire[WIDTH*12-1:0] fb_WData; // 12-bit color
    reg[14:0] fb_upcoming_WAddr = 15'd0;
    reg[14:0] fb_WAddr;
    wire[WIDTH-1:0] next_Y, next_X;
    always @(negedge slow_clock) begin
        if (instruction[INSN_SIZE - 1 : INSN_SIZE - OPCODE_SIZE] == 4'b1010 && !fb_WE) begin
            // Update regs
            if (regfile_scalar_x == 16'h5cc0) begin // wait for x=+304
                // End of line, reset x to -320
                regfile_scalar_x <= 16'hdd00;
                if (regfile_scalar_y == 16'h5b78) begin // wait for y=+239
                    // End of frame, reset y to -240 and write-address
                    regfile_scalar_y <= 16'hdb80;
                    fb_upcoming_WAddr <= 15'b0;
                end else begin
                    regfile_scalar_y <= next_Y;
                    fb_upcoming_WAddr <= fb_upcoming_WAddr + 1;
                end
            end else begin
                regfile_scalar_x <= next_X;
                fb_upcoming_WAddr <= fb_upcoming_WAddr + 1;
            end
            // Write to framebuffer and reset
            fb_WE <= 1'b1;
            fb_WAddr <= fb_upcoming_WAddr;
            reset <= 1'b1;
        end else begin
            reset <= 1'b0;
            fb_WE <= 1'b0;
        end
    end

    // Compute fixed-point colors
    // We need a 4-bit fixed-point number, but we first convert to 7-bit fixed (+1 sign), then use random 3-bit threshold to round up (dithering)
    reg[WIDTH*3*3-1:0] dithering_random = 1;
    genvar gidx;
    generate for (gidx = 0; gidx < WIDTH * 3; gidx = gidx + 1) begin
        wire[15:0] float_form;
        wire[7:0] fixed_form;
        assign float_form = frame_out[WORD_SIZE * gidx +: WORD_SIZE];
        assign fb_WData[4 * gidx +: 4] = fixed_form[7] ? 4'b0
            : (fixed_form[2:0] <= dithering_random[3 * gidx +: 3] || fixed_form[6:3] == 4'b1111) ? fixed_form[6:3] : fixed_form[6:3] + 1;
        floating_point_1 to_fixed(.s_axis_a_tvalid(1'b1), .s_axis_a_tdata(float_form), .m_axis_result_tvalid(), .m_axis_result_tdata(fixed_form));
    end endgenerate
    always @(posedge slow_clock) begin
        // LSFR generator (taps from from https://datacipy.cz/lfsr_table.pdf)
        dithering_random <= {dithering_random[WIDTH*3*3-2 : 0], dithering_random[143] ^ dithering_random[141] ^ dithering_random[139] ^ dithering_random[136]};
    end

    // Calculate next X,Y
    fp_unit calc_next_y(.op(4'd0), .in1(regfile_scalar_y), .in2(16'h3c00), .out(next_Y), .clk(slow_clock));
    fp_unit calc_next_x(.op(4'd0), .in1(regfile_scalar_x), .in2(16'h4c00), .out(next_X), .clk(slow_clock));

    // Actual framebuffer output stuff
    framebuffer_output fb_out(clock, 1'b0, fb_WE, fb_WAddr, fb_WData, hSync, vSync, VGA_R, VGA_G, VGA_B);

    // Debugging
    //ila_0 debuggers(.clk(clock), .probe0({1'b0, fb_WAddr}), .probe1(next_X), .probe2(fb_WData[15:0]), .probe3(next_Y), .probe4(fb_WE), .probe5(slow_clock), .probe6(1'b0), .probe7(1'b0));
    assign LED[15:0] = SW[4:0] == 5'd0 ? regfile_scalar[SW[8:5]]
      : SW[15] == 0 ? cpu_rs1 == SW[4:0] ? cpu_regA[15:0] : cpu_rs2 == SW[4:0] ? cpu_regB[15:0] : 16'd0
      : cpu_rs1 == SW[4:0] ? cpu_regA[31:16] : cpu_rs2 == SW[4:0] ? cpu_regB[31:16] : 16'd0;
        
    // Testbench
    // integer actFile, cycles;
    // initial begin
    //     $dumpfile("test.vcd");
    //     $dumpvars(0, main);

    //     #25 reset = 0; // 1 cycle of reset, then start with rising edge at #30
	// 	for (cycles = 0; cycles < 100; cycles = cycles + 1) begin
	// 		// Every rising edge, write to the actual file
	// 		@(posedge clock);
	// 		if (ctrl_rs1 != 0 || ctrl_rs2 != 0) begin
	// 			$display("Cycle %3d: Read from %d and %d", cycles, ctrl_rs1, ctrl_rs2);
	// 		end
	// 	end

	// 	#100;
	// 	$finish;
    // end
    // always @(frame_out) $display("Frame out (cycle %0d): %h", cycles, frame_out);
    // always
	// 	#10 clock = ~clock;

endmodule

// Separate ROM module loading binary memory files (silly but it works I guess)
module ROM_B #(parameter DATA_WIDTH = 32, ADDRESS_WIDTH = 12, DEPTH = 4096, MEMFILE = "") (
    input wire                     clk,
    input wire [ADDRESS_WIDTH-1:0] addr,
    output reg [DATA_WIDTH-1:0]    dataOut = 0);
    
    reg[DATA_WIDTH-1:0] MemoryArray[0:DEPTH-1];
    
    initial begin
        if(MEMFILE > 0) begin
            $readmemb(MEMFILE, MemoryArray);
        end
    end
    
    always @(posedge clk) begin
        dataOut <= MemoryArray[addr];
    end
endmodule
