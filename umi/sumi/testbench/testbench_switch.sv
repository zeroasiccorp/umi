/*******************************************************************************
 * Copyright 2024 Zero ASIC Corporation
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *     http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 *
 * ----
 *
 * Documentation:
 * - Simple umi switch testbench
 *
 ******************************************************************************/

module testbench (
`ifdef VERILATOR
    input clk
`endif
);

`include "switchboard.vh"

    parameter integer N     = 4;
    parameter integer M     = 4;
    parameter integer DW    = 256;
    parameter integer AW    = 64;
    parameter integer CW    = 32;

    localparam PERIOD_CLK   = 10;
    localparam RST_CYCLES   = 16;

`ifndef VERILATOR
    // Generate clock for non verilator sim tools
    reg clk;

    initial
        clk  = 1'b0;
    always #(PERIOD_CLK/2) clk = ~clk;
`endif

    // Reset control
    reg [RST_CYCLES:0]      nreset_vec;
    wire                    nreset;
    wire                    initdone;

    assign nreset = nreset_vec[RST_CYCLES-1];
    assign initdone = nreset_vec[RST_CYCLES];

    initial
        nreset_vec = 'b1;
    always @(negedge clk) nreset_vec <= {nreset_vec[RST_CYCLES-1:0], 1'b1};

    wire [N*M-1:0]  umi_in_valid;
    wire [N*CW-1:0] umi_in_cmd;
    wire [N*AW-1:0] umi_in_dstaddr;
    wire [N*AW-1:0] umi_in_srcaddr;
    wire [N*DW-1:0] umi_in_data;
    wire [N-1:0]    umi_in_ready;

    wire [M-1:0]    umi_out_valid;
    wire [M*CW-1:0] umi_out_cmd;
    wire [M*AW-1:0] umi_out_dstaddr;
    wire [M*AW-1:0] umi_out_srcaddr;
    wire [M*DW-1:0] umi_out_data;
    wire [M-1:0]    umi_out_ready;

    // Initialize UMI
    integer valid_mode, ready_mode;

    initial begin
        /* verilator lint_off IGNOREDRETURN */
        if (!$value$plusargs("valid_mode=%d", valid_mode)) begin
            valid_mode = 2;  // default if not provided as a plusarg
        end

        if (!$value$plusargs("ready_mode=%d", ready_mode)) begin
            ready_mode = 2;  // default if not provided as a plusarg
        end
        /* verilator lint_on IGNOREDRETURN */
    end

    ///////////////////////////////////////////
    // Host side umi agents
    ///////////////////////////////////////////
    genvar  i, j;

    generate
    for(i = 0; i < N; i = i + 1) begin: switch_in

        wire umi_valid;

        umi_rx_sim #(
            .VALID_MODE_DEFAULT (2),
            .DW                 (DW)
        ) umi_rx_i (
            .clk        (clk),

            .valid      (umi_valid),
            .cmd        (umi_in_cmd[i*CW+:CW]),
            .dstaddr    (umi_in_dstaddr[i*AW+:AW]),
            .srcaddr    (umi_in_srcaddr[i*AW+:AW]),
            .data       (umi_in_data[i*DW+:DW]),
            .ready      (umi_in_ready[i] & initdone)
        );

        for (j = 0; j < M; j = j + 1) begin: request
            assign umi_in_valid[j*N + i] = umi_valid &
                                           (umi_in_dstaddr[i*AW+40+:16] == j);
        end

        initial begin
            `ifndef VERILATOR
                #1;
            `endif
            switch_in[i].umi_rx_i.init($sformatf("client2rtl_%0d.q", i));
            switch_in[i].umi_rx_i.set_valid_mode(valid_mode);
        end
    end
    endgenerate

    generate
    for(i = 0; i < M; i = i + 1) begin: switch_out
        umi_tx_sim #(
            .READY_MODE_DEFAULT (2),
            .DW                 (DW)
        ) umi_tx_i (
            .clk        (clk),

            .valid      (umi_out_valid[i] & initdone),
            .cmd        (umi_out_cmd[i*CW+:CW]),
            .dstaddr    (umi_out_dstaddr[i*AW+:AW]),
            .srcaddr    (umi_out_srcaddr[i*AW+:AW]),
            .data       (umi_out_data[i*DW+:DW]),
            .ready      (umi_out_ready[i])
        );

        initial begin
            `ifndef VERILATOR
                #1;
            `endif
            switch_out[i].umi_tx_i.init($sformatf("rtl2client_%0d.q", i));
            switch_out[i].umi_tx_i.set_ready_mode(ready_mode);
        end
    end
    endgenerate

    // instantiate dut with UMI ports
    umi_switch #(
        .N      (N),
        .M      (M),
        .MASK   (0),
        .DW     (DW),
        .CW     (CW),
        .AW     (AW)
    ) umi_switch_i (
        .clk                (clk),
        .nreset             (nreset),
        .arbmode            (2'b00),
        .arbmask            ('b0),

        .umi_in_valid       (umi_in_valid & {(N*M){initdone}}),
        .umi_in_cmd         (umi_in_cmd),
        .umi_in_dstaddr     (umi_in_dstaddr),
        .umi_in_srcaddr     (umi_in_srcaddr),
        .umi_in_data        (umi_in_data),
        .umi_in_ready       (umi_in_ready),

        .umi_out_valid      (umi_out_valid),
        .umi_out_cmd        (umi_out_cmd),
        .umi_out_dstaddr    (umi_out_dstaddr),
        .umi_out_srcaddr    (umi_out_srcaddr),
        .umi_out_data       (umi_out_data),
        .umi_out_ready      (umi_out_ready & {M{initdone}})
    );

    // waveform dump
    `SB_SETUP_PROBES

    // auto-stop
    auto_stop_sim auto_stop_sim_i (.clk(clk));

endmodule
