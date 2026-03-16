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
 * - TL-UH to UMI converter cocotb testbench
 *
 ******************************************************************************/

`timescale 1ns / 1ps
`default_nettype wire

module testbench #(
    parameter CW       = 32,          // UMI command width
    parameter AW       = 64,          // UMI address width
    parameter DW       = 64,          // UMI data width
    parameter IDW      = 48,          // umi global chip ID width
    parameter RAMDEPTH = 512          // Memory depth
)
(
    input               clk,
    input               nreset,
    input  [IDW-1:0]    globalid,

    // TileLink A channel
    output              tl_a_ready,
    input               tl_a_valid,
    input  [2:0]        tl_a_opcode,
    input  [2:0]        tl_a_param,
    input  [2:0]        tl_a_size,
    input  [4:0]        tl_a_source,
    input  [55:0]       tl_a_address,
    input  [7:0]        tl_a_mask,
    input  [63:0]       tl_a_data,
    input               tl_a_corrupt,

    // TileLink D channel
    input               tl_d_ready,
    output              tl_d_valid,
    output [2:0]        tl_d_opcode,
    output [1:0]        tl_d_param,
    output [2:0]        tl_d_size,
    output [4:0]        tl_d_source,
    output              tl_d_sink,
    output              tl_d_denied,
    output [63:0]       tl_d_data,
    output              tl_d_corrupt
);

    // Internal UMI signals between tl2umi and umi_memagent
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

    // TL2UMI adapter
    tl2umi #(
        .CW         (CW),
        .AW         (AW),
        .DW         (DW),
        .IDW        (IDW)
    ) dut (
        .clk                (clk),
        .nreset             (nreset),
        .globalid           (globalid),

        .tl_a_ready         (tl_a_ready),
        .tl_a_valid         (tl_a_valid),
        .tl_a_opcode        (tl_a_opcode),
        .tl_a_param         (tl_a_param),
        .tl_a_size          (tl_a_size),
        .tl_a_source        (tl_a_source),
        .tl_a_address       (tl_a_address),
        .tl_a_mask          (tl_a_mask),
        .tl_a_data          (tl_a_data),
        .tl_a_corrupt       (tl_a_corrupt),

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

    // UMI memory agent (handles UMI requests and generates responses)
    umi_memagent #(
        .DW         (DW),
        .AW         (AW),
        .CW         (CW),
        .RAMDEPTH   (RAMDEPTH)
    ) mem_agent (
        .clk                (clk),
        .nreset             (nreset),
        .sram_ctrl          (8'b0),

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

endmodule
