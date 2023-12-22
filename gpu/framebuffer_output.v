`timescale 1ns / 1ps

module framebuffer_output(
	input clk, 			// 100 MHz System Clock
	input reset, 		// Reset Signal
    input fb_WE,
    input[14:0] fb_WAddr,
    input[191:0] fb_WData,
	output hSync, 		// H Sync Signal
	output vSync, 		// Veritcal Sync Signal
	output[3:0] VGA_R,  // Red Signal Bits
	output[3:0] VGA_G,  // Green Signal Bits
	output[3:0] VGA_B   // Blue Signal Bits
	);
	
	// Clock divider 100 MHz -> 25 MHz
	wire clk25; // 25MHz clock

	reg[1:0] pixCounter = 0;      // Pixel counter to divide the clock
    assign clk25 = pixCounter[1]; // Set the clock high whenever the second bit (2) is high
	always @(posedge clk) begin
		pixCounter <= pixCounter + 1; // Since the reg is only 3 bits, it will reset every 8 cycles
	end

	// VGA Timing Generation for a Standard VGA Screen
	localparam 
		VIDEO_WIDTH = 640,  // Standard VGA Width
		VIDEO_HEIGHT = 480; // Standard VGA Height
	wire active, screenEnd;
	wire[9:0] x;
	wire[8:0] y;
	VGATimingGenerator #(
		.HEIGHT(VIDEO_HEIGHT), // Use the standard VGA Values
		.WIDTH(VIDEO_WIDTH))
	Display( 
		.clk25(clk25),  	   // 25MHz Pixel Clock
		.reset(reset),		   // Reset Signal
		.screenEnd(screenEnd), // High for one cycle when between two frames
		.active(active),	   // High when drawing pixels
		.hSync(hSync),  	   // Set Generated H Signal
		.vSync(vSync),		   // Set Generated V Signal
		.x(x), 				   // X Coordinate (from left)
		.y(y)); 			   // Y Coordinate (from top)	   
    
    // Framebuffer reading
    wire [14:0] fb_RAddr;
    wire [191:0] fb_RData;
    reg [191:0] current_block;
    assign fb_RAddr = (y << 5) + (y << 3) + (x >> 4) + 1; // Prepare to read the next block
    always @(posedge clk25) begin
        if ((x & 9'd15) == 9'd15)
            current_block <= fb_RData;
        else
            current_block <= current_block >> 12;
    end
    
    // Framebuffer
    framebuffer fb(clk, fb_WE, fb_WAddr, fb_WData, fb_RAddr, fb_RData);
    
    // Load current color from block
    assign {VGA_B, VGA_G, VGA_R} = active ? current_block[11:0] : 12'b0;
	
endmodule

module framebuffer #(parameter DATA_WIDTH = 192, ADDRESS_WIDTH = 15, DEPTH = 19200, INITIAL_DATA = 192'hffff000f000fffff000f000fffff000f000fffff000f000f)(
    input clock,
    input writeEnable,
    input [ADDRESS_WIDTH-1:0] writeAddr,
    input [DATA_WIDTH-1:0] writeData,
    input [ADDRESS_WIDTH-1:0] readAddr,
    output [DATA_WIDTH-1:0] readData
    );
    
    localparam MAIN_DEPTH = 16384;
    
    wire [DATA_WIDTH-1:0] readDataMain, readDataSecondary;
    framebuffer_part #(.DEPTH(MAIN_DEPTH), .ADDRESS_WIDTH(ADDRESS_WIDTH-1)) main_fb(
        .clock(clock), 
        .writeEnable(writeEnable && (writeAddr[ADDRESS_WIDTH-1] == 0)),
        .writeAddr(writeAddr[ADDRESS_WIDTH-2:0]),
        .writeData(writeData),
        .readAddr(readAddr[ADDRESS_WIDTH-2:0]),
        .readData(readDataMain)
    );
    framebuffer_part #(.DEPTH(DEPTH-MAIN_DEPTH), .ADDRESS_WIDTH(ADDRESS_WIDTH-1)) secondary_fb(
        .clock(clock), 
        .writeEnable(writeEnable && (writeAddr[ADDRESS_WIDTH-1] == 1)),
        .writeAddr(writeAddr[ADDRESS_WIDTH-2:0]),
        .writeData(writeData),
        .readAddr(readAddr[ADDRESS_WIDTH-2:0]),
        .readData(readDataSecondary)
    );
    assign readData = (readAddr[ADDRESS_WIDTH-1] == 0) ? readDataMain : readDataSecondary;
    
endmodule

module framebuffer_part #(parameter DATA_WIDTH = 192, ADDRESS_WIDTH = 15, DEPTH = 16384, INITIAL_DATA = 192'hffff000f000fffff000f000fffff000f000fffff000f000f)(
    input clock,
    input writeEnable,
    input [ADDRESS_WIDTH-1:0] writeAddr,
    input [DATA_WIDTH-1:0] writeData,
    input [ADDRESS_WIDTH-1:0] readAddr,
    output reg [DATA_WIDTH-1:0] readData
    );
    
    reg[DATA_WIDTH-1:0] data[0:DEPTH-1];
    
    integer i;
    initial begin
        for (i = 0; i < DEPTH; i = i + 1)
            data[i] <= INITIAL_DATA;
    end
    
    always @(posedge clock) begin
        if(writeEnable)
            data[writeAddr] <= writeData;
        
        readData <= data[readAddr];
    end
endmodule


`timescale 1 ns/ 1 ps
module VGATimingGenerator #(parameter HEIGHT=480, WIDTH=640) (
	input clk25, 		// 25 MHz clock
	input reset, 		// Reset the Frame
	output active, 		// In the visible area
	output screenEnd,	// High for one cycle between frames
	output hSync,		// Horizontal sync, active high, marks the end of a horizontal line
	output vSync,		// Vertical sync, active high, marks the end of a vertical line
	output[9:0] x,		// X coordinate from left
	output[8:0] y);		// Y coordinate from top
	
	/*///////////////////////////////////////////
	--          		VGA Timing
	--  Horizontal:
	--                   ___________             _____________
	--                  |           |           |
	--__________________|  VIDEO    |___________|  VIDEO (next line)

	--___________   _____________________   ______________________
	--           |_|                     |_|
	--            B <-C-><----D----><-E->
	--           <------------A--------->
	--  The Units used below are pixels;  
	--      B->Sync_cycle                   : H_SYNC_WIDTH
	--      C->Back_porch                   : H_BACK_PORCH
	--      D->Visable Area					: WIDTH
	--      E->Front porch                  : H_FRONT_PORCH
	--      A->horizontal line total length : H_LINE
	--	
	--	
	--	Vertical:
	--                   __________             _____________
	--                  |          |           |          
	--__________________|  VIDEO   |___________|  VIDEO (next frame)
	--
	--__________   _____________________   ______________________
	--          |_|                     |_|
	--           P <-Q-><----R----><-S->
	--          <-----------O---------->
	--	The Unit used below are horizontal lines;  
	--  	P->Sync_cycle                   : V_SYNC_WIDTH
	--  	Q->Back_porch                   : V_BACK_PORCH
	--  	R->Visable Area					: HEIGHT
	--  	S->Front porch                  : V_FRONT_PORCH
	--  	O->vertical line total length   : V_LINE
	///////////////////////////////////////////*/

	localparam 
		H_FRONT_PORCH = 16,
		H_SYNC_WIDTH  = 96,
		H_BACK_PORCH  = 48,

		H_SYNC_START = WIDTH + H_FRONT_PORCH,
		H_SYNC_END   = H_SYNC_START + H_SYNC_WIDTH,
		H_LINE       = H_SYNC_END + H_BACK_PORCH,

		V_FRONT_PORCH = 11,
		V_SYNC_WIDTH  = 2,
		V_BACK_PORCH  = 31,

		V_SYNC_START = HEIGHT + V_FRONT_PORCH,
		V_SYNC_END   = V_SYNC_START + V_SYNC_WIDTH,
		V_LINE       = V_SYNC_END + V_BACK_PORCH;

	// Count the position on the screen to decide the VGA regions
	reg[9:0] hPos = 0;
	reg[9:0] vPos = 0;
	always @(posedge clk25 or posedge reset) begin
		if(reset) begin
			hPos <= 0;
			vPos <= 0;
		end else begin
			if(hPos == H_LINE - 1) begin // End of horizontal line
				hPos <= 0;
				if(vPos == V_LINE - 1)   // End of vertical line
					vPos <= 0;
				else begin
					vPos <= vPos + 1;
				end
			end else 
				hPos <= hPos + 1;
		end
	end

	// Determine active regions
	wire activeX, activeY;
	assign activeX = (hPos < WIDTH);   // Active for the first 640 pixels of each line
	assign activeY = (vPos < HEIGHT);  // Active for the first 480 horizontal lines 
	assign active = activeX & activeY; // Active when both x and y are active      

	// Only output the x and y coordinates 
	assign x = activeX ? hPos : 0; // Output x coordinate when x is active. Otherwise 0
	assign y = activeY ? vPos : 0; // Output y coordinate when x is active. Otherwise 0

	// Screen ends when x and y reach their ends 
	assign screenEnd = (vPos == (V_LINE - 1)) & (hPos == (H_LINE - 1)); 

	// Generate the sync signals based on the parameters
	assign hSync = (hPos < H_SYNC_START) | (hPos >= H_SYNC_END);
	assign vSync = (vPos < V_SYNC_START) | (vPos >= V_SYNC_END);
endmodule