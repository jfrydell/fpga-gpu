`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 11/13/2023 12:15:30 AM
// Design Name: 
// Module Name: fp_unit
// Project Name: 
// Target Devices: 
// Tool Versions: 
// Description: 
// 
// Dependencies: 
// 
// Revision:
// Revision 0.01 - File Created
// Additional Comments:
// 
//////////////////////////////////////////////////////////////////////////////////


module fp_unit(
    input [3:0] op,
    input [15:0] in1,
    input [15:0] in2,
    output [15:0] out,
    input clk
    );
    
    // IP-based floating point units
    wire [15:0] add_sub_result, mult_result, div_result, sqrt_result;
    fp_add_sub add_sub(
        .s_axis_a_tvalid(1'b1),
        .s_axis_a_tdata(in1),
        .s_axis_b_tvalid(1'b1),
        .s_axis_b_tdata(in2),
        .s_axis_operation_tvalid(1'b1),
        .s_axis_operation_tdata({7'b0, op[0]}),
        .m_axis_result_tvalid(),
        .m_axis_result_tdata(add_sub_result)
    );
    fp_mult mult(
        .s_axis_a_tvalid(1'b1),
        .s_axis_a_tdata(in1),
        .s_axis_b_tvalid(1'b1),
        .s_axis_b_tdata(in2),
        .m_axis_result_tvalid(),
        .m_axis_result_tdata(mult_result)
    );
    fp_div div(
        .s_axis_a_tvalid(1'b1),
        .s_axis_a_tdata(in1),
        .s_axis_b_tvalid(1'b1),
        .s_axis_b_tdata(in2),
        .m_axis_result_tvalid(),
        .m_axis_result_tdata(div_result)
    );
    fp_sqrt sqrt(
        .s_axis_a_tvalid(1'b1),
        .s_axis_a_tdata(in1),
        .m_axis_result_tvalid(),
        .m_axis_result_tdata(sqrt_result)
    );
    
    // Easy-to-implement abs
    wire [15:0] abs_result;
    assign abs_result = {1'b0, in1[14:0]};
    
    // floor
    wire [15:0] floor_result;
    fp_floor floor(
        .in(in1),
        .out(floor_result)
    );
    
    // arctan LUT
    wire [15:0] arctan_result_unsigned, arctan_result;
    ROM #(.DATA_WIDTH(16), .ADDRESS_WIDTH(11), .DEPTH(2048), .MEMFILE("atan_lut.mem"))
        arctan_lut(clk, in1[14:4], arctan_result_unsigned[15:0]);
    assign arctan_result = {in1[15], arctan_result_unsigned[14:0]};
    
    // Assign output
    assign out = (op[3] == 1) ? in1 : (op[2] == 0) ?
        ((op[1] == 0) ? add_sub_result
            : ((op[0] == 0) ? mult_result : div_result))
        : ((op[1] == 0) ?
            ((op[0] == 0) ? floor_result : abs_result)
            : ((op[0] == 0) ? sqrt_result : arctan_result));
    
endmodule

module fp_floor(
    input [15:0] in,
    output [15:0] out
    );

    // add 0xbbff to negatives (closest number to -1, only incorrect for range (-0.00048828125, 0))
    wire [15:0] add_result, in2;
    fp_add_sub add_1(
        .s_axis_a_tvalid(1'b1),
        .s_axis_a_tdata(in),
        .s_axis_b_tvalid(1'b1),
        .s_axis_b_tdata(16'hbbff),
        .s_axis_operation_tvalid(1'b1),
        .s_axis_operation_tdata(8'd0),
        .m_axis_result_tvalid(),
        .m_axis_result_tdata(add_result)
    );
    assign in2 = (in[15] == 1) ? add_result : in;

    // extract exponent
    wire [4:0] exp;
    assign exp = in2[14:10];

    // zero out relevant bits
    assign out = {in2[15], 
        (exp < 15) ? 5'b0 : exp, // floor to subnormal
        (exp < 16) ? 1'b0 : in2[9],
        (exp < 17) ? 1'b0 : in2[8],
        (exp < 18) ? 1'b0 : in2[7],
        (exp < 19) ? 1'b0 : in2[6],
        (exp < 20) ? 1'b0 : in2[5],
        (exp < 21) ? 1'b0 : in2[4],
        (exp < 22) ? 1'b0 : in2[3],
        (exp < 23) ? 1'b0 : in2[2],
        (exp < 24) ? 1'b0 : in2[1],
        (exp < 25) ? 1'b0 : in2[0]
    };

endmodule

module fp_floor_tb();
    reg[15:0] in;
    wire[15:0] out;
    fp_floor floor(in, out);
    initial begin
        in = 16'h3800;
    end
    always #5 in = in + 1;
    always @(in) begin
        #2 $display("in: %h, out: %h", in, out);
        if (in == 16'h6000)
            $finish;
    end
endmodule