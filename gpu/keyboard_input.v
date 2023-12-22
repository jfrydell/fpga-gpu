/* Tracks the currently held key (inaccurate for overlapping keypresses) */
module keyboard_input(
    output reg[7:0] key,
    input clear,
    input clk,
    inout ps2_clk,
	inout ps2_data
);

    // Handle keyboard input for sprite
    wire [7:0] ps2_rx_data;
    wire ps2_read_data;
    reg break_code = 0; // 1 if last data was break code 8'hf0, so next press should be ignored
    always @(negedge ps2_read_data, posedge clear) begin
        // Latch in ps2 data
        if (clear) key <= 0;
        else begin
            if (ps2_rx_data == 8'hf0) begin
                break_code <= 1;
                key <= 8'h00;
            end else begin
                if (break_code == 0)
                    key <= ps2_rx_data;
                else
                    break_code <= 0;
            end
        end
    end
    Ps2Interface ps2(
        .ps2_clk(ps2_clk),
        .ps2_data(ps2_data),
        .clk(clk),
        .rst(0),
        .tx_data(0),
        .write_data(0),
        .rx_data(ps2_rx_data),
        .read_data(ps2_read_data)
    );

endmodule