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
 * - Simple umi mux testbench
 *
 ******************************************************************************/

module testbench (
`ifdef VERILATOR
    input clk
`endif
);

`include "switchboard.vh"

    localparam N  = 4;
    localparam DW = 256;
    localparam CW = 32;
    localparam AW = 64;

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

    wire [N-1:0]    umi_in_valid;
    wire [N*CW-1:0] umi_in_cmd;
    wire [N*AW-1:0] umi_in_dstaddr;
    wire [N*AW-1:0] umi_in_srcaddr;
    wire [N*DW-1:0] umi_in_data;
    wire [N-1:0]    umi_in_ready;

    wire            umi_out_valid;
    wire [CW-1:0]   umi_out_cmd;
    wire [AW-1:0]   umi_out_dstaddr;
    wire [AW-1:0]   umi_out_srcaddr;
    wire [DW-1:0]   umi_out_data;
    wire            umi_out_ready;

    ///////////////////////////////////////////
    // Host side umi agents
    ///////////////////////////////////////////

    genvar          i;

    generate
    for(i = 0; i < N; i = i + 1) begin: mux_in
        queue_to_umi_sim #(
            .VALID_MODE_DEFAULT (2),
            .DW                 (DW)
        ) umi_rx_i (
            .clk        (clk),

            .valid      (umi_in_valid[i]),
            .cmd        (umi_in_cmd[i*CW+:CW]),
            .dstaddr    (umi_in_dstaddr[i*AW+:AW]),
            .srcaddr    (umi_in_srcaddr[i*AW+:AW]),
            .data       (umi_in_data[i*DW+:DW]),
            .ready      (umi_in_ready[i] & initdone)
        );

        initial begin
            `ifndef VERILATOR
                #1;
            `endif
            mux_in[i].umi_rx_i.init($sformatf("client2rtl_%0d.q", i));
            mux_in[i].umi_rx_i.set_valid_mode(valid_mode);
        end
    end
    endgenerate

    umi_to_queue_sim #(
        .READY_MODE_DEFAULT (2),
        .DW                 (DW)
    ) umi_tx_i (
        .clk        (clk),

        .valid      (umi_out_valid & initdone),
        .cmd        (umi_out_cmd),
        .dstaddr    (umi_out_dstaddr),
        .srcaddr    (umi_out_srcaddr),
        .data       (umi_out_data),
        .ready      (umi_out_ready)
    );

    initial begin
        `ifndef VERILATOR
            #1;
        `endif
        umi_tx_i.init("rtl2client_0.q");
        umi_tx_i.set_ready_mode(ready_mode);
    end

    // UMI Demux
    umi_mux #(
        .N  (N),
        .DW (DW),
        .CW (CW),
        .AW (AW)
    ) umi_mux_i (
        .clk                (clk),
        .nreset             (nreset),
        .arbmode            (2'b10),
        .arbmask            ({N{1'b0}}),

        .umi_in_valid       (umi_in_valid & {N{initdone}}),
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
        .umi_out_ready      (umi_out_ready & initdone)
    );

    // waveform dump
    `SB_SETUP_PROBES

    // auto-stop
    auto_stop_sim auto_stop_sim_i (.clk(clk));

endmodule
