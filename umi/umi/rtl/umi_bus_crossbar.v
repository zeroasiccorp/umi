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
 *
 * - This is a unidirectional crossbar for a generic UMI bus
 * - This module only supports 1 host, but multiple devices
 *
 * - For request, host can request to any devices
 * - For response, any device can response to host
 *
 * MASK (INPUT -- > OUTPUT PATH ENABLE)
 *
 * [0]  = host transaction to host
 * [1]  = dev0 transaction to host
 * [2]  = dev1 transaction to host
 * [3]  = dev2 transaction to host
 * ...
 * [n+1]= devn transaction to host
 *
 * ...
 *
 * [n*n-n-1] = host transaction to devn
 * [n*n-n]   = dev0 transaction to devn
 * ...
 * [n*n-1]   = devn transaction to devn
 *
 ****************************************************************************/
module umi_bus_crossbar
  #(parameter       TARGET = "DEFAULT", // compiler target
    parameter       CW = 64,            // command width
    parameter       AW = 64,            // address width
    parameter       DW = 32,            // data width
    parameter       ND = 5,             // number of devices
    parameter       FIFO_DEPTH = 0,     // optional pipelining
    parameter [0:0] RESPONSE = 0        // 1 = response, 0 = request
    )
   (
    // ctrl
    input              clk,            // main clock signal
    input              nreset,         // async active low reset
    input [ND-1:0]     enable_vector,  // enable/ disable specific port
    // decoder interface
    output [AW-1:0]    dec_dstaddr,    // destination address output to decoder
    output             dec_valid,
    input [ND-1:0]     dec_access_req,
    // HOST
    input              host_in_valid,
    output             host_in_ready,
    input [CW-1:0]     host_in_cmd,
    input [AW-1:0]     host_in_dstaddr,
    input [AW-1:0]     host_in_srcaddr,
    input [DW-1:0]     host_in_data,
    output             host_out_valid,
    input              host_out_ready,
    output [CW-1:0]    host_out_cmd,
    output [AW-1:0]    host_out_dstaddr,
    output [AW-1:0]    host_out_srcaddr,
    output [DW-1:0]    host_out_data,
    // DEVICES
    input [ND-1:0]     dev_in_valid,
    output [ND-1:0]    dev_in_ready,
    input [ND*CW-1:0]  dev_in_cmd,
    input [ND*AW-1:0]  dev_in_dstaddr,
    input [ND*AW-1:0]  dev_in_srcaddr,
    input [ND*DW-1:0]  dev_in_data,
    output [ND-1:0]    dev_out_valid,
    input [ND-1:0]     dev_out_ready,
    output [ND*CW-1:0] dev_out_cmd,
    output [ND*AW-1:0] dev_out_dstaddr,
    output [ND*AW-1:0] dev_out_srcaddr,
    output [ND*DW-1:0] dev_out_data
    );

    localparam N = ND + 1; // Total ports on the crossbar

    // local wires
    wire [N*N-1:0] request;
    wire [N*N-1:0] enable;
    wire [N*N-1:0] mask = ~enable;

    // Rename buses into a larger vector
    // Inputs
    wire [N-1:0] umi_in_valid = {dev_in_valid, host_in_valid};
    wire [N*CW-1:0] umi_in_cmd = {dev_in_cmd, host_in_cmd};
    wire [N*AW-1:0] umi_in_dstaddr = {dev_in_dstaddr, host_in_dstaddr};
    wire [N*AW-1:0] umi_in_srcaddr = {dev_in_srcaddr, host_in_srcaddr};
    wire [N*DW-1:0] umi_in_data = {dev_in_data, host_in_data};
    wire [N-1:0] umi_out_ready = {dev_out_ready, host_out_ready};
    // Outputs
    wire [N-1:0] umi_in_ready;
    wire [N-1:0] umi_out_valid;
    wire [N*CW-1:0] umi_out_cmd;
    wire [N*AW-1:0] umi_out_dstaddr;
    wire [N*AW-1:0] umi_out_srcaddr;
    wire [N*DW-1:0] umi_out_data;
    assign {dev_in_ready, host_in_ready} = umi_in_ready;
    assign {dev_out_valid, host_out_valid} = umi_out_valid;
    assign {dev_out_cmd, host_out_cmd} = umi_out_cmd;
    assign {dev_out_dstaddr, host_out_dstaddr} = umi_out_dstaddr;
    assign {dev_out_srcaddr, host_out_srcaddr} = umi_out_srcaddr;
    assign {dev_out_data, host_out_data} = umi_out_data;

    // Buffered signal after FIFO
    wire [N*CW-1:0] umi_cmd;
    wire [N*DW-1:0] umi_data;
    wire [N*AW-1:0] umi_dstaddr;
    wire [N*AW-1:0] umi_srcaddr;
    wire [N-1:0] umi_valid;
    wire [N-1:0] umi_ready;

    generate genvar i, j;

    //########################
    //# MASK CROSSBAR OUTPUTS
    //########################

    // safely disable all illegal paths
    if(RESPONSE) begin: gen_umi_resp_enable
        // All devices can and can only response to host
        for (i = 1; i < N; i = i + 1)
            assign enable[i*N+:N] = 'd0; // Disallow device to device
        assign enable[N-1:1] = enable_vector; // Allow device to host
        assign enable[0] = 1'b0; // Disallow host to host
    end
    else begin: gen_umi_req_enable
        for (i = 1; i < N; i = i + 1) begin
            assign enable[(i+1)*N-1:i*N+1] = 'd0; // Disallow device to device
            assign enable[i*N] = enable_vector[i-1]; // Allow host to device
        end
        assign enable[N-1:0] = 'b0; // Disallow host to host
    end

    //####################
    //# pipeline
    //# Optionally easing the timing using a fifo (setting depth to 0 to disable)
    //####################
    for (i = 0; i < N; i = i + 1) begin: gen_umi_fifo
        umi_fifo_flex #(
            .CW(CW),
            .AW(AW),
            .IDW(DW),
            .ODW(DW),
            .ASYNC(0),
            .DEPTH(FIFO_DEPTH))
        umi_fifo_flex_in (
            // Outputs
            .fifo_full      (),
            .fifo_empty     (),
            .umi_in_ready   (umi_in_ready[i]),
            .umi_out_valid  (umi_valid[i]),
            .umi_out_cmd    (umi_cmd[i*CW+:CW]),
            .umi_out_dstaddr(umi_dstaddr[i*AW+:AW]),
            .umi_out_srcaddr(umi_srcaddr[i*AW+:AW]),
            .umi_out_data   (umi_data[i*DW+:DW]),
            // Inputs
            .bypass         (1'b0),
            .chaosmode      (1'b0),
            .umi_in_clk     (clk),
            .umi_in_nreset  (nreset),
            .umi_in_valid   (umi_in_valid[i]),
            .umi_in_cmd     (umi_in_cmd[i*CW+:CW]),
            .umi_in_dstaddr (umi_in_dstaddr[i*AW+:AW]),
            .umi_in_srcaddr (umi_in_srcaddr[i*AW+:AW]),
            .umi_in_data    (umi_in_data[i*DW+:DW]),
            .umi_out_clk    (clk),
            .umi_out_nreset (nreset),
            .umi_out_ready  (umi_ready[i]),
            .vdd            (),
            .vss            ()
        );
    end

    //####################
    //# ADDRESS DECODE
    //####################
    if(RESPONSE) begin: gen_resp_decode
        // Device response always goes back to host
        assign request[0] = 0;
        assign request[N-1:1] = umi_valid[N-1:1];
        assign request[N*N-1:N] = 0;
        // No need to use decoder
        assign dec_dstaddr = {AW{1'b0}};
        assign dec_valid = 1'b0;
    end
    else begin: gen_req_decode
        assign dec_dstaddr = umi_dstaddr[AW-1:0];
        assign dec_valid = umi_valid[0];
        wire [N-1:0] access_request = {dec_access_req, 1'b0};
        for (i = 0; i < N; i = i + 1) begin
            assign request[N*i] = access_request[i];
            assign request[N*i+1+:N-1] = 0;
        end
    end
    endgenerate

   //####################
   //# Crossbar (NxN)
   //####################

    umi_crossbar #(
        .TARGET(TARGET),
        .CW(CW),
        .AW(AW),
        .DW(DW),
        .N(N)
    ) umi_crossbar (
        // Outputs
        .umi_in_ready    (umi_ready),
        .umi_out_valid   (umi_out_valid),
        .umi_out_cmd     (umi_out_cmd),
        .umi_out_srcaddr (umi_out_srcaddr),
        .umi_out_dstaddr (umi_out_dstaddr),
        .umi_out_data    (umi_out_data),
        // Inputs
        .clk             (clk),
        .nreset          (nreset),
        .mode            (2'b00),
        .mask            (mask),
        .umi_in_request  (request),
        .umi_in_cmd      (umi_cmd),
        .umi_in_srcaddr  (umi_srcaddr),
        .umi_in_dstaddr  (umi_dstaddr),
        .umi_in_data     (umi_data),
        .umi_out_ready   (umi_out_ready)
    );

endmodule
