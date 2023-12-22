module gpu(clock, reset, pc, instruction, ctrl_rs1, ctrl_rs2, data_rs1, data_rs2, frame_out);
    // Essential parameters for ports
    localparam INSN_SIZE = 20;
    localparam WORD_SIZE = 16;
    localparam REG_ID_SIZE = 4; // Size of register ID (assuming scalar/vector already known; actual reg will be 1 bit bigger)
    localparam OPCODE_SIZE = 4;
    localparam WIDTH = 16;

    // Port definitions
    input clock, reset;
    output reg[15:0] pc = 0;
    input[INSN_SIZE-1:0] instruction;
    output[REG_ID_SIZE-1:0] ctrl_rs1, ctrl_rs2;
    input[WORD_SIZE-1:0] data_rs1, data_rs2;
    output[WIDTH*WORD_SIZE*3-1:0] frame_out;

    // Extra (utility) parameters
    localparam[OPCODE_SIZE-1:0] OPCODE_ADD = 0, OPCODE_SUB = 1, OPCODE_MUL = 2, OPCODE_RECIP = 3, OPCODE_FLOOR = 4, OPCODE_SQRT = 5, OPCODE_CMOV = 8, OPCODE_BLTZ = 13, OPCODE_SETX = 14, OPCODE_LOOP = 15;
    localparam[WIDTH*WORD_SIZE-1:0] R16_VALS = {16'h0, 16'h3c00, 16'h4000, 16'h4200, 16'h4400, 16'h4500, 16'h4600, 16'h4700,
        16'h4800, 16'h4880, 16'h4900, 16'h4980, 16'h4a00, 16'h4a80, 16'h4b00, 16'h4b80};
    integer ii;

    // Next executed PC for each element
    reg[15:0] next_exec_pc[WIDTH-1:0];
    initial for (ii = 0; ii < WIDTH; ii = ii + 1)
        next_exec_pc[ii] <= 0;
    // Find min of all next_exec_pc's for when branch allowed
    wire[15:0] next_exec_pc_min, next_exec_pc_tmp[WIDTH-3:0];
    genvar gidx1;
    generate for (gidx1 = 0; gidx1 < WIDTH/2; gidx1 = gidx1 + 1) begin
        assign next_exec_pc_tmp[gidx1] = (next_exec_pc[2*gidx1] < next_exec_pc[2*gidx1+1]) ? next_exec_pc[2*gidx1] : next_exec_pc[2*gidx1+1];
    end endgenerate
    genvar gidx2;
    generate for (gidx2 = 0; gidx2 < WIDTH/4; gidx2 = gidx2 + 1) begin
        assign next_exec_pc_tmp[WIDTH/2 + gidx2] = (next_exec_pc_tmp[2*gidx2] < next_exec_pc_tmp[2*gidx2+1]) ? next_exec_pc_tmp[2*gidx2] : next_exec_pc_tmp[2*gidx2+1];
    end endgenerate
    genvar gidx3;
    generate for (gidx3 = 0; gidx3 < WIDTH/8; gidx3 = gidx3 + 1) begin
        assign next_exec_pc_tmp[WIDTH/2 + WIDTH/4 + gidx3] = (next_exec_pc_tmp[WIDTH/2 + 2*gidx3] < next_exec_pc_tmp[WIDTH/2 + 2*gidx3+1]) ? next_exec_pc_tmp[WIDTH/2 + 2*gidx3] : next_exec_pc_tmp[WIDTH/2 + 2*gidx3+1];
    end endgenerate
    assign next_exec_pc_min = (next_exec_pc_tmp[WIDTH/2 + WIDTH/4] < next_exec_pc_tmp[WIDTH/2 + WIDTH/4 + 1]) ? next_exec_pc_tmp[WIDTH/2 + WIDTH/4] : next_exec_pc_tmp[WIDTH/2 + WIDTH/4 + 1];

    // === SCALAR PIPELINE (CONTROL SIGNALS, NO DATA) ===
    // Fetch / Branch
    reg[15:0] loop_reg = 16'b0;
    always @(negedge clock) begin
        if (reset)
            pc <= 0;
        else if (instruction[INSN_SIZE - 1 : INSN_SIZE - OPCODE_SIZE] == OPCODE_LOOP && loop_reg > 0)
            pc <= instruction[INSN_SIZE - OPCODE_SIZE - 1 : 0];
        else if (pc + 1 < next_exec_pc_min)
            pc <= next_exec_pc_min;
        else
            pc <= pc + 1;
        
        if (instruction[INSN_SIZE - 1 : INSN_SIZE - OPCODE_SIZE] == OPCODE_LOOP)
            loop_reg <= loop_reg - 1;
        else if (instruction[INSN_SIZE - 1 : INSN_SIZE - OPCODE_SIZE] == OPCODE_SETX)
            loop_reg <= instruction[INSN_SIZE - OPCODE_SIZE - 1 : 0];
    end

    // Decode
    reg[INSN_SIZE-1:0] insn_d = 20'b0;
    reg[15:0] pc_d = 16'd0;
    always @(negedge clock) begin
        if (reset || instruction[INSN_SIZE - 1 : INSN_SIZE - OPCODE_SIZE] == OPCODE_LOOP || instruction[INSN_SIZE - 1 : INSN_SIZE - OPCODE_SIZE] == OPCODE_SETX) begin
            insn_d <= 0;
            pc_d <= 0;
        end else begin
            insn_d <= instruction;
            pc_d <= pc;
        end
    end
    wire[REG_ID_SIZE-1:0] dest_d;
    wire[REG_ID_SIZE:0] src1_d, src2_d;
    assign dest_d = insn_d[INSN_SIZE - OPCODE_SIZE - 1 : INSN_SIZE - OPCODE_SIZE - REG_ID_SIZE];
    assign src1_d = insn_d[INSN_SIZE - OPCODE_SIZE - REG_ID_SIZE - 1 : INSN_SIZE - OPCODE_SIZE - 2 * REG_ID_SIZE - 1];
    assign src2_d = insn_d[INSN_SIZE - OPCODE_SIZE - 2 * REG_ID_SIZE - 2 : INSN_SIZE - OPCODE_SIZE - 3 * REG_ID_SIZE - 2];
    assign ctrl_rs1 = src1_d[REG_ID_SIZE] ? 5'b0 : src1_d[REG_ID_SIZE-1:0]; // Ternary operator not necessary, just prevents superfluous reads
    assign ctrl_rs2 = src2_d[REG_ID_SIZE] ? 5'b0 : src2_d[REG_ID_SIZE-1:0];

    // Execute
    reg[INSN_SIZE-1:0] insn_x = 20'b0;
    reg[15:0] pc_x = 16'd0;
    wire[REG_ID_SIZE-1:0] dest_x_1; // Destination not considering conditional move
    always @(negedge clock) begin
        if (reset) begin
            insn_x <= 0;
            pc_x <= 0;
        end else begin
            insn_x <= insn_d;
            pc_x <= pc_d;
        end
    end
    assign dest_x_1 = insn_x[INSN_SIZE - OPCODE_SIZE - 1 : INSN_SIZE - OPCODE_SIZE - REG_ID_SIZE];

    // Writeback
    reg[INSN_SIZE-1:0] insn_w = 20'b0;
    always @(negedge clock) begin
        if (reset)
            insn_w <= 0;
        else
            insn_w <= insn_x;
    end

    // === VECTOR PIPELINE (ACTUAL DATAFLOW) ===
    genvar gidx;
    generate for (gidx = 0; gidx < WIDTH; gidx = gidx + 1) begin
        // Create register file for each element
        reg[WORD_SIZE - 1:0] regfile[15:0];
        initial regfile[0] <= R16_VALS[WORD_SIZE * (WIDTH - gidx - 1) +: WORD_SIZE];
        initial for (ii = 1; ii < 16; ii = ii + 1) begin
            regfile[ii] <= 0;
        end
        assign frame_out[WORD_SIZE * gidx * 3 +: WORD_SIZE] = regfile[1];
        assign frame_out[WORD_SIZE * gidx * 3 + WORD_SIZE +: WORD_SIZE] = regfile[2];
        assign frame_out[WORD_SIZE * gidx * 3 + 2*WORD_SIZE +: WORD_SIZE] = regfile[3];

        // Decode, reading from vector or scalar regfile
        // Bypassing is done here, so time for mux select bit doesn't add latency to beginning of execute
        wire[WORD_SIZE-1:0] rs1_d, rs2_d;
        wire[REG_ID_SIZE-1:0] dest_x_2; // \ for bypassing
        wire[WORD_SIZE-1:0] rd_x;     // / -------------
        assign rs1_d = src1_d[REG_ID_SIZE] ? ((src1_d[REG_ID_SIZE-1:0] == dest_x_2 && dest_x_2 != 0) ? rd_x : regfile[src1_d[REG_ID_SIZE-1:0]]) : data_rs1;
        assign rs2_d = src2_d[REG_ID_SIZE] ? ((src2_d[REG_ID_SIZE-1:0] == dest_x_2 && dest_x_2 != 0) ? rd_x : regfile[src2_d[REG_ID_SIZE-1:0]]) : data_rs2;

        // Execute
        reg[WORD_SIZE-1:0] rs1_x = 16'b0;
        reg[WORD_SIZE-1:0] rs2_x = 16'b0;
        // don't writeback if it's a CMOV or we've branched forward
        wire should_skip;
        assign should_skip = (pc_x < next_exec_pc[gidx])
            || ((insn_x[INSN_SIZE - 1 : INSN_SIZE - OPCODE_SIZE] == OPCODE_CMOV) && (rs2_x[WORD_SIZE-1] != 1'b1));
        assign dest_x_2 = should_skip ? 5'b0 : dest_x_1;
        always @(negedge clock) begin
            rs1_x <= rs1_d;
            rs2_x <= rs2_d;
        end
        fp_unit fp_unit_x(
            .op(insn_x[INSN_SIZE - 1 : INSN_SIZE - OPCODE_SIZE]),
            .in1(rs1_x),
            .in2(rs2_x),
            .out(rd_x),
            .clk(clock)
        );
        // Branch: if less than 0, set next_exec_pc (technically part of writeback stage). however, must ignore if we've already branched forward (should_skip = 1)
        always @(negedge clock) begin
            if (reset)
                next_exec_pc[gidx] <= 0;
            else if (insn_x[INSN_SIZE - 1 : INSN_SIZE - OPCODE_SIZE] == OPCODE_BLTZ && rs1_x[WORD_SIZE-1] == 1'b1 && !should_skip)
                next_exec_pc[gidx] <= {5'b0, insn_x[INSN_SIZE - OPCODE_SIZE - 1 : INSN_SIZE - OPCODE_SIZE - REG_ID_SIZE], insn_x[6:0]}; // leave gap for src1 lol
        end

        // Writeback
        reg[WORD_SIZE-1:0] rd_w = 16'b0;
        reg[REG_ID_SIZE-1:0] dest_w = 5'b0;
        always @(negedge clock) begin
            rd_w <= rd_x;
            dest_w <= dest_x_2;
        end
        always @(posedge clock) begin
            if (dest_w != 0)
                regfile[dest_w] <= rd_w;
        end
        
        always @(posedge clock) begin
            if (gidx == 0)
                $display("PC(Fetch) %d: register %d goes to %h", pc, 16+dest_w, rd_w);
        end

    end endgenerate


endmodule
