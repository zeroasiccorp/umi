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
 * - This is the bus interconnect for a generic UMI bus
 * - This module only supports 1 host, but multiple devices connected bus
 * - The host facing port is the udev, the device facing port is the uhost
 *
 * - For request, host can request to any devices
 * - For response, any device can response to host
 *
 ****************************************************************************/
module umi_bus
  #(parameter TARGET = "DEFAULT", // technology target
    parameter DW = 32,            // umi packet width
    parameter CW = 32,            // umi command width
    parameter AW = 64,            // address space width
    parameter ND = 5,             // number of devices
    parameter FIFO_DEPTH = 0      // optional pipelining
    )
    (// ctrl
    input              clk,    // main clock signal
    input              nreset, // async active low reset
    input [ND-1:0]     enable_vector,  // enable/ disable specific port
    // decoder interface
    output [AW-1:0]    dec_dstaddr,    // destination address output to decoder
    output             dec_valid,
    input [ND-1:0]     dec_access_req,
    // device port
    input              udev_req_valid,
    input [CW-1:0]     udev_req_cmd,
    input [AW-1:0]     udev_req_dstaddr,
    input [AW-1:0]     udev_req_srcaddr,
    input [DW-1:0]     udev_req_data,
    output             udev_req_ready,
    output             udev_resp_valid,
    output [CW-1:0]    udev_resp_cmd,
    output [AW-1:0]    udev_resp_dstaddr,
    output [AW-1:0]    udev_resp_srcaddr,
    output [DW-1:0]    udev_resp_data,
    input              udev_resp_ready,
    // Host interface
    output [ND-1:0]    uhost_req_valid,
    output [ND*CW-1:0] uhost_req_cmd,
    output [ND*AW-1:0] uhost_req_dstaddr,
    output [ND*AW-1:0] uhost_req_srcaddr,
    output [ND*DW-1:0] uhost_req_data,
    input [ND-1:0]     uhost_req_ready,
    input [ND-1:0]     uhost_resp_valid,
    input [ND*CW-1:0]  uhost_resp_cmd,
    input [ND*AW-1:0]  uhost_resp_dstaddr,
    input [ND*AW-1:0]  uhost_resp_srcaddr,
    input [ND*DW-1:0]  uhost_resp_data,
    output [ND-1:0]    uhost_resp_ready
    );

    // Crossbar for request
    umi_bus_crossbar #(
        .TARGET(TARGET),
        .CW(CW),
        .AW(AW),
        .DW(DW),
        .ND(ND),
        .FIFO_DEPTH(FIFO_DEPTH),
        .RESPONSE(0)
    ) bus_cb_req (
        // ctrl
        .clk(clk),
        .nreset(nreset),
        .enable_vector(enable_vector),
        // decoder interface
        .dec_dstaddr(dec_dstaddr),
        .dec_valid(dec_valid),
        .dec_access_req(dec_access_req),
        // HOST
        .host_in_valid(udev_req_valid),
        .host_in_ready(udev_req_ready),
        .host_in_cmd(udev_req_cmd),
        .host_in_dstaddr(udev_req_dstaddr),
        .host_in_srcaddr(udev_req_srcaddr),
        .host_in_data(udev_req_data),
        .host_out_valid(),
        .host_out_ready(1'b0),
        .host_out_cmd(),
        .host_out_dstaddr(),
        .host_out_srcaddr(),
        .host_out_data(),
        // DEVICES
        .dev_in_valid({ND{1'b0}}),
        .dev_in_ready(),
        .dev_in_cmd({ND*CW{1'b0}}),
        .dev_in_dstaddr({ND*AW{1'b0}}),
        .dev_in_srcaddr({ND*AW{1'b0}}),
        .dev_in_data({ND*DW{1'b0}}),
        .dev_out_valid(uhost_req_valid),
        .dev_out_ready(uhost_req_ready),
        .dev_out_cmd(uhost_req_cmd),
        .dev_out_dstaddr(uhost_req_dstaddr),
        .dev_out_srcaddr(uhost_req_srcaddr),
        .dev_out_data(uhost_req_data)
    );

    umi_bus_crossbar #(
        .TARGET(TARGET),
        .CW(CW),
        .AW(AW),
        .DW(DW),
        .ND(ND),
        .FIFO_DEPTH(FIFO_DEPTH),
        .RESPONSE(1)
    ) bus_cb_resp (
        // ctrl
        .clk(clk),
        .nreset(nreset),
        .enable_vector(enable_vector),
        // decoder interface
        .dec_dstaddr(),
        .dec_valid(),
        .dec_access_req({ND{1'b0}}),
        // HOST
        .host_in_valid(1'b0),
        .host_in_ready(),
        .host_in_cmd({CW{1'b0}}),
        .host_in_dstaddr({AW{1'b0}}),
        .host_in_srcaddr({AW{1'b0}}),
        .host_in_data({DW{1'b0}}),
        .host_out_valid(udev_resp_valid),
        .host_out_ready(udev_resp_ready),
        .host_out_cmd(udev_resp_cmd),
        .host_out_dstaddr(udev_resp_dstaddr),
        .host_out_srcaddr(udev_resp_srcaddr),
        .host_out_data(udev_resp_data),
        // DEVICES
        .dev_in_valid(uhost_resp_valid),
        .dev_in_ready(uhost_resp_ready),
        .dev_in_cmd(uhost_resp_cmd),
        .dev_in_dstaddr(uhost_resp_dstaddr),
        .dev_in_srcaddr(uhost_resp_srcaddr),
        .dev_in_data(uhost_resp_data),
        .dev_out_valid(),
        .dev_out_ready({ND{1'b0}}),
        .dev_out_cmd(),
        .dev_out_dstaddr(),
        .dev_out_srcaddr(),
        .dev_out_data()
    );

endmodule
