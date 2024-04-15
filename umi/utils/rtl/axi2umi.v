/*******************************************************************************
 * Copyright 2023 Zero ASIC Corporation
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
 * - AXI4 to UMI converter
 *
 ******************************************************************************/

`default_nettype wire

module axi2umi #(
    parameter CW        = 32,   // command width
    parameter AW        = 64,   // address width
    parameter DW        = 64,   // umi packet width
    parameter IDW       = 16,   // brick ID width
    parameter AXI_IDW   = 8     // AXI ID width
)
(
    input                   clk,
    input                   nreset,
    input  [IDW-1:0]        chipid,
    input  [15:0]           local_routing,

    // AXI4 Interface
    input  [AXI_IDW-1:0]    axi_awid,
    input  [AW-1:0]         axi_awaddr,
    input  [7:0]            axi_awlen,
    input  [2:0]            axi_awsize,
    input  [1:0]            axi_awburst,
    input                   axi_awlock,
    input  [3:0]            axi_awcache,
    input  [2:0]            axi_awprot,
    input  [3:0]            axi_awqos,
    input  [3:0]            axi_awregion,
    input                   axi_awvalid,
    output                  axi_awready,

    input  [AXI_IDW-1:0]    axi_wid,
    input  [DW-1:0]         axi_wdata,
    input  [(DW/8)-1:0]     axi_wstrb,
    input                   axi_wlast,
    input                   axi_wvalid,
    output                  axi_wready,

    output [AXI_IDW-1:0]    axi_bid,
    output [1:0]            axi_bresp,
    output                  axi_bvalid,
    input                   axi_bready,

    input  [AXI_IDW-1:0]    axi_arid,
    input  [AW-1:0]         axi_araddr,
    input  [7:0]            axi_arlen,
    input  [2:0]            axi_arsize,
    input  [1:0]            axi_arburst,
    input                   axi_arlock,
    input  [3:0]            axi_arcache,
    input  [2:0]            axi_arprot,
    input  [3:0]            axi_arqos,
    input  [3:0]            axi_arregion,
    input                   axi_arvalid,
    output                  axi_arready,

    output [AXI_IDW-1:0]    axi_rid,
    output [DW-1:0]         axi_rdata,
    output [1:0]            axi_rresp,
    output                  axi_rlast,
    output                  axi_rvalid,
    input                   axi_rready,

    // Host port
    output                  uhost_req_valid,
    output [CW-1:0]         uhost_req_cmd,
    output [AW-1:0]         uhost_req_dstaddr,
    output [AW-1:0]         uhost_req_srcaddr,
    output [DW-1:0]         uhost_req_data,
    input                   uhost_req_ready,

    input                   uhost_resp_valid,
    input  [CW-1:0]         uhost_resp_cmd,
    input  [AW-1:0]         uhost_resp_dstaddr,
    input  [AW-1:0]         uhost_resp_srcaddr,
    input  [DW-1:0]         uhost_resp_data,
    output                  uhost_resp_ready
);

    `include "umi_messages.vh"

    localparam DWLOG = $clog2(DW/8);
    localparam N     = 3;

    wire    reset_done;

    la_drsync la_drsync_i (
        .clk     (clk),
        .nreset  (nreset),
        .in      (1'b1),
        .out     (reset_done)
    );

    // AXI Write channels (AW, W, B) to UMI
    wire            umi_write_req_valid;
    wire [CW-1:0]   umi_write_req_cmd;
    wire [AW-1:0]   umi_write_req_dstaddr;
    wire [AW-1:0]   umi_write_req_srcaddr;
    wire [DW-1:0]   umi_write_req_data;
    wire            umi_write_req_ready;

    wire            umi_write_resp_valid;
    wire [CW-1:0]   umi_write_resp_cmd;
    wire [AW-1:0]   umi_write_resp_dstaddr;
    wire [AW-1:0]   umi_write_resp_srcaddr;
    wire [DW-1:0]   umi_write_resp_data;
    wire            umi_write_resp_ready;

    axiwrite2umi #(
        .CW         (CW),
        .AW         (AW),
        .DW         (DW),
        .IDW        (16),
        .AXI_IDW    (AXI_IDW)
    ) axiwrite2umi_ (
        .clk                (clk),
        .nreset             (nreset),
        .chipid             (chipid),
        .local_routing      (local_routing),

        // AXI4 Write Interface
        .axi_awid           (axi_awid),
        .axi_awaddr         (axi_awaddr),
        .axi_awlen          (axi_awlen),
        .axi_awsize         (axi_awsize),
        .axi_awburst        (axi_awburst),
        .axi_awlock         (axi_awlock),
        .axi_awcache        (axi_awcache),
        .axi_awprot         (axi_awprot),
        .axi_awqos          (axi_awqos),
        .axi_awregion       (axi_awregion),
        .axi_awvalid        (axi_awvalid),
        .axi_awready        (axi_awready),

        .axi_wid            (axi_wid),
        .axi_wdata          (axi_wdata),
        .axi_wstrb          (axi_wstrb),
        .axi_wlast          (axi_wlast),
        .axi_wvalid         (axi_wvalid),
        .axi_wready         (axi_wready),

        .axi_bid            (axi_bid),
        .axi_bresp          (axi_bresp),
        .axi_bvalid         (axi_bvalid),
        .axi_bready         (axi_bready),

        // UMI Host port
        .uhost_req_valid    (umi_write_req_valid),
        .uhost_req_cmd      (umi_write_req_cmd),
        .uhost_req_dstaddr  (umi_write_req_dstaddr),
        .uhost_req_srcaddr  (umi_write_req_srcaddr),
        .uhost_req_data     (umi_write_req_data),
        .uhost_req_ready    (umi_write_req_ready),

        .uhost_resp_valid   (umi_write_resp_valid),
        .uhost_resp_cmd     (umi_write_resp_cmd),
        .uhost_resp_dstaddr (umi_write_resp_dstaddr),
        .uhost_resp_srcaddr (umi_write_resp_srcaddr),
        .uhost_resp_data    (umi_write_resp_data),
        .uhost_resp_ready   (umi_write_resp_ready)
    );

    // AXI Read channels (AR, R) to UMI
    wire            umi_read_req_valid;
    wire [CW-1:0]   umi_read_req_cmd;
    wire [AW-1:0]   umi_read_req_dstaddr;
    wire [AW-1:0]   umi_read_req_srcaddr;
    wire [DW-1:0]   umi_read_req_data;
    wire            umi_read_req_ready;

    wire            umi_read_resp_valid;
    wire [CW-1:0]   umi_read_resp_cmd;
    wire [AW-1:0]   umi_read_resp_dstaddr;
    wire [AW-1:0]   umi_read_resp_srcaddr;
    wire [DW-1:0]   umi_read_resp_data;
    wire            umi_read_resp_ready;

    axiread2umi #(
        .CW         (CW),
        .AW         (AW),
        .DW         (DW),
        .IDW        (16),
        .AXI_IDW    (AXI_IDW)
    ) axiread2umi_ (
        .clk                (clk),
        .nreset             (nreset),
        .chipid             (chipid),
        .local_routing      (local_routing),

        // AXI4 Read Interface
        .axi_arid           (axi_arid),
        .axi_araddr         (axi_araddr),
        .axi_arlen          (axi_arlen),
        .axi_arsize         (axi_arsize),
        .axi_arburst        (axi_arburst),
        .axi_arlock         (axi_arlock),
        .axi_arcache        (axi_arcache),
        .axi_arprot         (axi_arprot),
        .axi_arqos          (axi_arqos),
        .axi_arregion       (axi_arregion),
        .axi_arvalid        (axi_arvalid),
        .axi_arready        (axi_arready),

        .axi_rid            (axi_rid),
        .axi_rdata          (axi_rdata),
        .axi_rresp          (axi_rresp),
        .axi_rlast          (axi_rlast),
        .axi_rvalid         (axi_rvalid),
        .axi_rready         (axi_rready),

        // UMI Host port
        .uhost_req_valid    (umi_read_req_valid),
        .uhost_req_cmd      (umi_read_req_cmd),
        .uhost_req_dstaddr  (umi_read_req_dstaddr),
        .uhost_req_srcaddr  (umi_read_req_srcaddr),
        .uhost_req_data     (umi_read_req_data),
        .uhost_req_ready    (umi_read_req_ready),

        .uhost_resp_valid   (umi_read_resp_valid),
        .uhost_resp_cmd     (umi_read_resp_cmd),
        .uhost_resp_dstaddr (umi_read_resp_dstaddr),
        .uhost_resp_srcaddr (umi_read_resp_srcaddr),
        .uhost_resp_data    (umi_read_resp_data),
        .uhost_resp_ready   (umi_read_resp_ready)
    );

    // UMI Crossbar
    // Input Port 0  - axiwrite2umi UMI host request
    // Input Port 1  - axiread2umi UMI host request
    // Input Port 2  - Current Module input UMI device response
    // Output Port 0 - axiwrite2umi UMI host response
    // Output Port 1 - axiread2umi UMI host response
    // Output Port 2 - Current Module output UMI device request

    // Mask
    // Size = 3*3 = 9 bits
    // Table:
    // [0]     = axiwrite2umi requesting axiwrite2umi [not allowed]
    // [1]     = axiread2umi  requesting axiwrite2umi [not allowed]
    // [2]     = UMI response requesting axiwrite2umi [allowed]
    //
    // [3]     = axiwrite2umi requesting axiread2umi [not allowed]
    // [4]     = axiread2umi  requesting axiread2umi [not allowed]
    // [5]     = UMI response requesting axiread2umi [allowed]
    //
    // [6]     = axiwrite2umi requesting UMI request [allowed]
    // [7]     = axiread2umi  requesting UMI request [allowed]
    // [8]     = UMI response requesting UMI request [not allowed]
    wire [N*N-1:0]      mask;
    assign mask = {3'b100,
                   3'b011,
                   3'b011};

    wire [N*N-1:0]      umi_crossbar_in_request;
    wire [N*CW-1:0]     umi_crossbar_in_cmd;
    wire [N*AW-1:0]     umi_crossbar_in_dstaddr;
    wire [N*AW-1:0]     umi_crossbar_in_srcaddr;
    wire [N*DW-1:0]     umi_crossbar_in_data;
    wire [N-1:0]        umi_crossbar_in_ready;

    wire [N-1:0]        umi_crossbar_out_valid;
    wire [N*CW-1:0]     umi_crossbar_out_cmd;
    wire [N*AW-1:0]     umi_crossbar_out_dstaddr;
    wire [N*AW-1:0]     umi_crossbar_out_srcaddr;
    wire [N*DW-1:0]     umi_crossbar_out_data;
    wire [N-1:0]        umi_crossbar_out_ready;

    umi_crossbar #(
        .DW         (DW),
        .CW         (CW),
        .AW         (AW),
        .N          (N)
    ) umi_write_read_mux (
        .clk                (clk),
        .nreset             (nreset),
        .mode               (2'b10),
        .mask               (mask),

        // Incoming UMI
        .umi_in_request     (umi_crossbar_in_request),
        .umi_in_cmd         (umi_crossbar_in_cmd),
        .umi_in_dstaddr     (umi_crossbar_in_dstaddr),
        .umi_in_srcaddr     (umi_crossbar_in_srcaddr),
        .umi_in_data        (umi_crossbar_in_data),
        .umi_in_ready       (umi_crossbar_in_ready),

        // Outgoing UMI
        .umi_out_valid      (umi_crossbar_out_valid),
        .umi_out_cmd        (umi_crossbar_out_cmd),
        .umi_out_dstaddr    (umi_crossbar_out_dstaddr),
        .umi_out_srcaddr    (umi_crossbar_out_srcaddr),
        .umi_out_data       (umi_crossbar_out_data),
        .umi_out_ready      (umi_crossbar_out_ready)
    );

    wire    cmd_read_resp;
    wire    cmd_write_resp;

    // Decode Input UMI device response
    umi_decode #(
        .CW     (CW)
    ) uhost_resp_cmd_decode_ (
        // Packet Command
        .command            (uhost_resp_cmd),
        .cmd_invalid        (),

        // request/response/link
        .cmd_request        (),
        .cmd_response       (),

        // requests
        .cmd_read           (),
        .cmd_write          (),
        .cmd_write_posted   (),
        .cmd_rdma           (),
        .cmd_atomic         (),
        .cmd_user0          (),
        .cmd_future0        (),
        .cmd_error          (),
        .cmd_link           (),

        // Response (device -> host)
        .cmd_read_resp      (cmd_read_resp),
        .cmd_write_resp     (cmd_write_resp),
        .cmd_user0_resp     (),
        .cmd_user1_resp     (),
        .cmd_future0_resp   (),
        .cmd_future1_resp   (),
        .cmd_link_resp      (),
        .cmd_atomic_add     (),

        // Atomic operations
        .cmd_atomic_and     (),
        .cmd_atomic_or      (),
        .cmd_atomic_xor     (),
        .cmd_atomic_max     (),
        .cmd_atomic_min     (),
        .cmd_atomic_maxu    (),
        .cmd_atomic_minu    (),
        .cmd_atomic_swap    ()
    );

    assign umi_crossbar_in_request = {{1'b0,
                                      umi_read_req_valid,
                                      umi_write_req_valid},
                                      {(uhost_resp_valid & cmd_read_resp),
                                      1'b0,
                                      1'b0},
                                      {(uhost_resp_valid & cmd_write_resp),
                                      1'b0,
                                      1'b0}};
    assign umi_crossbar_in_cmd = {uhost_resp_cmd,
                                  umi_read_req_cmd,
                                  umi_write_req_cmd};
    assign umi_crossbar_in_dstaddr = {uhost_resp_dstaddr,
                                      umi_read_req_dstaddr,
                                      umi_write_req_dstaddr};
    assign umi_crossbar_in_srcaddr = {uhost_resp_srcaddr,
                                      umi_read_req_srcaddr,
                                      umi_write_req_srcaddr};
    assign umi_crossbar_in_data = {uhost_resp_data,
                                   umi_read_req_data,
                                   umi_write_req_data};
    assign {uhost_resp_ready,
            umi_read_req_ready,
            umi_write_req_ready} = umi_crossbar_in_ready;

    // Crossbar Outputs
    assign {uhost_req_valid,
            umi_read_resp_valid,
            umi_write_resp_valid} = umi_crossbar_out_valid;
    assign {uhost_req_cmd,
            umi_read_resp_cmd,
            umi_write_resp_cmd} = umi_crossbar_out_cmd;
    assign {uhost_req_dstaddr,
            umi_read_resp_dstaddr,
            umi_write_resp_dstaddr} = umi_crossbar_out_dstaddr;
    assign {uhost_req_srcaddr,
            umi_read_resp_srcaddr,
            umi_write_resp_srcaddr} = umi_crossbar_out_srcaddr;
    assign {uhost_req_data,
            umi_read_resp_data,
            umi_write_resp_data} = umi_crossbar_out_data;
    assign umi_crossbar_out_ready = {uhost_req_ready,
                                     umi_read_resp_ready,
                                     umi_write_resp_ready};

endmodule
