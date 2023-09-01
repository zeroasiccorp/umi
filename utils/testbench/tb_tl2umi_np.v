/******************************************************************************
 * Function:  TL-UH to UMI converter testbench
 * Author:    Aliasger Zaidy
 * Copyright: 2023 Zero ASIC Corporation. All rights reserved.
 * License: This file contains confidential and proprietary information of
 * Zero ASIC. This file may only be used in accordance with the terms and
 * conditions of a signed license agreement with Zero ASIC. All other use,
 * reproduction, or distribution of this software is strictly prohibited.
 *
 * Documentation:
 *
 ****************************************************************************/

`timescale 1ns / 1ps
`default_nettype wire
`include "tl-uh.vh"

module tb_tl2umi_np #(
    parameter TARGET     = "DEFAULT",   // pass through variable for hard macro
    parameter TIMEOUT    = 5000,        // timeout value (cycles)
    parameter PERIOD_CLK = 10           // clock period
)
();

    // Local parameters
    localparam STIMDEPTH = 1024;
    localparam TCW       = 8;
    localparam CW        = 32;          // UMI width
    localparam AW        = 64;          // UMI width
    localparam DW        = 512;
    localparam RAMDEPTH  = 512;  // param specific to testbench

    // Clock
    reg             clk;

    always
        #(PERIOD_CLK/2) clk = ~clk;

    // SIM Ctrl signals
    reg                     nreset;
    reg [DW*RAMDEPTH-1:0]   memhfile;
    reg                     load;
    reg                     go;
    integer                 r;

    // Reset initialization
    initial begin
        #(1)
        nreset   = 1'b0;
        clk      = 1'b0;
        load     = 1'b0;
        go       = 1'b0;
        #(PERIOD_CLK * 10)
        nreset   = 1'b1;
        #(PERIOD_CLK * 10)
        go       = 1'b1;
    end // initial begin

    // TileLink signals
    wire            tl_a_ready;
    reg             tl_a_valid;
    reg [2:0]       tl_a_opcode;
    reg [2:0]       tl_a_param;
    reg [2:0]       tl_a_size;
    reg [4:0]       tl_a_source;
    reg [55:0]      tl_a_address;
    reg [7:0]       tl_a_mask;
    reg [63:0]      tl_a_data;

    reg             tl_d_ready;
    wire            tl_d_valid;
    wire [2:0]      tl_d_opcode;
    wire [1:0]      tl_d_param;
    wire [2:0]      tl_d_size;
    wire [4:0]      tl_d_source;
    wire            tl_d_sink;
    wire            tl_d_denied;
    wire [63:0]     tl_d_data;
    wire            tl_d_corrupt;

    // Host UMI signals
    wire            uhost_req_valid;
    wire [CW-1:0]   uhost_req_cmd;
    wire [AW-1:0]   uhost_req_dstaddr;
    wire [AW-1:0]   uhost_req_srcaddr;
    wire [DW-1:0]   uhost_req_data;
    wire            uhost_req_ready;

    wire            uhost_resp_valid;
    wire [CW-1:0]   uhost_resp_cmd;
    wire [AW-1:0]   uhost_resp_dstaddr;
    wire [AW-1:0]   uhost_resp_srcaddr;
    wire [DW-1:0]   uhost_resp_data;
    wire            uhost_resp_ready;

    tl2umi_np #(
        .CW         (CW),
        .AW         (AW),
        .DW         (DW)
    ) dut (
        .clk                (clk),
        .nreset             (nreset),


        // FIXME: The bottom 4 bits of chipid are kept 4'b0001.
        // This hack is to ensure that the memory agent responds on its UMI(0,0)
        // This needs to be fixed either by using a correct address map or
        // enabling all 4 ports. Priority is low.
        .chipid             (16'hAE51),

        .tl_a_ready         (tl_a_ready),
        .tl_a_valid         (tl_a_valid),
        .tl_a_opcode        (tl_a_opcode),
        .tl_a_param         (tl_a_param),
        .tl_a_size          (tl_a_size),
        .tl_a_source        (tl_a_source),
        .tl_a_address       (tl_a_address),
        .tl_a_mask          (tl_a_mask),
        .tl_a_data          (tl_a_data),
        .tl_a_corrupt       (1'b0),

        .tl_d_ready         (tl_d_ready),
        .tl_d_valid         (tl_d_valid),
        .tl_d_opcode        (tl_d_opcode),
        .tl_d_param         (tl_d_param),
        .tl_d_size          (tl_d_size),
        .tl_d_source        (tl_d_source),
        .tl_d_sink          (tl_d_sink),
        .tl_d_denied        (tl_d_denied),
        .tl_d_data          (tl_d_data),
        .tl_d_corrupt       (tl_d_corrupt),

        .uhost_req_valid    (uhost_req_valid),
        .uhost_req_cmd      (uhost_req_cmd),
        .uhost_req_dstaddr  (uhost_req_dstaddr),
        .uhost_req_srcaddr  (uhost_req_srcaddr),
        .uhost_req_data     (uhost_req_data),
        .uhost_req_ready    (uhost_req_ready),

        .uhost_resp_valid   (uhost_resp_valid),
        .uhost_resp_cmd     (uhost_resp_cmd),
        .uhost_resp_dstaddr (uhost_resp_dstaddr),
        .uhost_resp_srcaddr (uhost_resp_srcaddr),
        .uhost_resp_data    (uhost_resp_data),
        .uhost_resp_ready   (uhost_resp_ready)
    );

    umi_mem_agent #(
        .DW         (DW),
        .AW         (AW),
        .CW         (CW),
        .RAMDEPTH   (RAMDEPTH)
    ) memory_module_ (
        .clk                (clk),
        .nreset             (nreset),

        .udev_req_valid     (uhost_req_valid),
        .udev_req_cmd       (uhost_req_cmd),
        .udev_req_dstaddr   (uhost_req_dstaddr),
        .udev_req_srcaddr   (uhost_req_srcaddr),
        .udev_req_data      (uhost_req_data),
        .udev_req_ready     (uhost_req_ready),

        .udev_resp_valid    (uhost_resp_valid),
        .udev_resp_cmd      (uhost_resp_cmd),
        .udev_resp_dstaddr  (uhost_resp_dstaddr),
        .udev_resp_srcaddr  (uhost_resp_srcaddr),
        .udev_resp_data     (uhost_resp_data),
        .udev_resp_ready    (uhost_resp_ready)
    );

    // control block
    initial begin
        r = $value$plusargs("MEMHFILE=%s", memhfile);
        $readmemh(memhfile, memory_module_.la_spram_i.ram);
        $timeformat(-9, 0, " ns", 20);
        $dumpfile("waveform.vcd");
        $dumpvars();
        #(TIMEOUT)
        $finish;
    end

/*
    // Test case from Steven:
    // Issue a TL Get command that requires multiple response beats
    // Respond with partial data then wait then respond with the remaining
    // data. Trying to emulate valid deassertion on UMI response bus.
    initial begin
        if (!nreset) @(posedge nreset);
        @(negedge clk);

        tl_a_valid      = 1'b1;
        tl_a_opcode     = `TL_OP_Get;
        tl_a_param      = 3'b0;
        tl_a_size       = 3'd7;
        tl_a_source     = 5'h15;
        tl_a_address    = 64'hDEADBEEF;
        tl_a_mask       = 8'd255;

        if (!tl_a_ready) @(posedge tl_a_ready);

        @(negedge clk);
        tl_a_valid  = 1'b0;
    end

    initial begin
        @(posedge (uhost_req_valid & uhost_req_ready));
        uhost_resp_valid    = 1'b1;
        uhost_resp_cmd      = 32'h00003F02;
        uhost_resp_dstaddr  = 64'h0000000007150000;
        uhost_resp_srcaddr  = 64'hDEADBEEF;
        uhost_resp_data     = $random;
        if (!uhost_resp_ready) @(posedge uhost_resp_ready);
        @(negedge clk);
        @(negedge clk);
        uhost_resp_valid    = 1'b0;
        repeat (10) @(negedge clk);
        uhost_resp_valid    = 1'b1;
        uhost_resp_cmd      = 32'h00403F02;
        uhost_resp_dstaddr  = 64'h0000000007150000 + 64;
        uhost_resp_srcaddr  = 64'hDEADBEEF + 64;
        if (!uhost_resp_ready) @(posedge uhost_resp_ready);
        @(negedge clk);
        @(negedge clk);
        uhost_resp_valid    = 1'b0;
    end
*/

    // Generate TileLink transactions
    reg  [2:0]      tl_random_opcode;
    reg  [2:0]      tl_random_size;
    reg  [6:0]      tl_random_address;
    reg  [7:0]      tl_byte_counter;
    reg             tl_a_ready_for_random;
    wire [3:0]      tl_arth_logic_alignment;
    wire [2:0]      tl_opcodes_under_test [0:2];

    assign tl_opcodes_under_test[0] = 3'd0;
    assign tl_opcodes_under_test[1] = 3'd1;
    assign tl_opcodes_under_test[2] = 3'd4;

    assign tl_arth_logic_alignment = 1 << tl_random_size[1:0];

    always @(posedge clk) begin
        tl_random_opcode <= tl_opcodes_under_test[$random % 3];
        tl_random_size <= $random % 8;
        tl_random_address <= $random % 128;
    end

    always @(posedge clk) begin
        if (~nreset) begin
            tl_a_ready_for_random <= 1'b1;
        end
        else begin
            if (tl_a_ready_for_random) begin
                tl_a_ready_for_random <= 1'b0;
                tl_a_opcode <= tl_random_opcode;
                tl_byte_counter <= 1 << tl_random_size;
                if (tl_random_size > 2)
                    tl_a_mask <= 8'd255;
                else if (tl_random_size == 2)
                    tl_a_mask <= 8'd15 << 4;
                else if (tl_random_size == 1)
                    tl_a_mask <= 8'd3 << 2;
                else if (tl_random_size == 0)
                    tl_a_mask <= 8'd1;

                case (tl_random_opcode)
                    `TL_OP_PutFullData: begin
                        tl_a_valid <= 1'b1;
                        tl_a_param <= 3'b0;
                        tl_a_size <= tl_random_size;
                        tl_a_source <= $random % 32;
                        if (tl_random_size < 'd3)
                            tl_a_address <= {tl_random_address, tl_arth_logic_alignment[2:0]};
                        else
                            tl_a_address <= {tl_random_address, 3'b000};
                    end
                    `TL_OP_PutPartialData: begin
                        tl_a_valid <= 1'b1;
                        tl_a_param <= 3'b0;
                        tl_a_size <= 6;
                        tl_byte_counter <= 1 << 6;
                        tl_a_source <= $random % 32;
                        if (tl_random_size < 'd3)
                            tl_a_address <= {tl_random_address, tl_arth_logic_alignment[2:0]};
                        else
                            tl_a_address <= {tl_random_address, 3'b000};
                        if (tl_random_size > 2)
                            tl_a_mask <= 8'd0;
                        else if (tl_random_size == 2)
                            tl_a_mask <= 8'd0;
                        else if (tl_random_size == 1)
                            tl_a_mask <= 8'd0;
                        else if (tl_random_size == 0)
                            tl_a_mask <= 8'd0;
                    end
                    `TL_OP_ArithmeticData: begin
                        tl_a_valid <= 1'b1;
                        tl_a_param <= $random % 5;
                        tl_a_size <= tl_random_size[1:0];
                        tl_a_source <= $random % 32;
                        tl_a_address <= {tl_random_address, tl_arth_logic_alignment[2:0]};
                        if (tl_random_size[1:0] == 3)
                            tl_a_mask <= 8'd255;
                        else if (tl_random_size[1:0] == 2)
                            tl_a_mask <= 8'd15 << 4;
                        else if (tl_random_size[1:0] == 1)
                            tl_a_mask <= 8'd3 << 2;
                        else if (tl_random_size[1:0] == 0)
                            tl_a_mask <= 8'd1;
                    end
                    `TL_OP_LogicalData: begin
                        tl_a_valid <= 1'b1;
                        tl_a_param <= $random % 4;
                        tl_a_size <= tl_random_size[1:0];
                        tl_a_source <= $random % 32;
                        tl_a_address <= {tl_random_address, tl_arth_logic_alignment[2:0]};
                        if (tl_random_size[1:0] == 3)
                            tl_a_mask <= 8'd255;
                        else if (tl_random_size[1:0] == 2)
                            tl_a_mask <= 8'd15 << 4;
                        else if (tl_random_size[1:0] == 1)
                            tl_a_mask <= 8'd3 << 2;
                        else if (tl_random_size[1:0] == 0)
                            tl_a_mask <= 8'd1;
                    end
                    `TL_OP_Get: begin
                        tl_a_valid <= 1'b1;
                        tl_a_param <= 3'b0;
                        tl_a_size <= tl_random_size;
                        tl_a_source <= $random % 32;
                        if (tl_random_size < 'd3)
                            tl_a_address <= {tl_random_address, tl_arth_logic_alignment[2:0]};
                        else
                            tl_a_address <= {tl_random_address, 3'b000};
                    end
                endcase
            end
            else begin
                if (tl_a_ready) begin
                    if (tl_a_opcode == `TL_OP_PutFullData) begin
                        if (tl_byte_counter <= 8'd8) begin
                            tl_a_ready_for_random <= 1'b1;
                            tl_a_valid <= 1'b0;
                        end
                        tl_byte_counter <= tl_byte_counter - 8'd8;
                        tl_a_mask <= 8'd255;
                    end
                    else if (tl_a_opcode == `TL_OP_PutPartialData) begin
                        if (tl_byte_counter <= 8'd8) begin
                            tl_a_ready_for_random <= 1'b1;
                            tl_a_valid <= 1'b0;
                        end
                        tl_byte_counter <= tl_byte_counter - 8'd8;
                        tl_a_mask <= (tl_byte_counter <= 8'd16) ? 8'd0 : 8'd255;
                    end
                    else begin
                        tl_a_ready_for_random <= 1'b1;
                        tl_a_valid <= 1'b0;
                    end
                end
            end
        end
    end

    always @(posedge clk) begin
        tl_a_data <= {$random, $random, $random, $random};
        // tl_d_ready <= $random % 2;
        tl_d_ready <= 1'b1;
    end

endmodule
