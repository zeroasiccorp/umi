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
 * - UMI to AXI4 converter testbench
 *
 ******************************************************************************/


`default_nettype none

`include "switchboard.vh"

module testbench (
    input clk
);

    localparam TIMEOUT  = 500000;
    localparam DW       = 64;
    localparam AW       = 64;
    localparam CW       = 32;
    localparam AXI_IDW  = 8;
    localparam RAMDEPTH = 4096;  // param specific to testbench
    localparam CTRLW    = 8;

    wire        nreset;
    reg [15:0]  nreset_r = 16'hFFFF;

    assign nreset = ~nreset_r[15];

    always @(negedge clk) begin
        nreset_r <= nreset_r << 1;
    end

    // Instantiate switchboard module
    `SB_AXI_WIRES(axi, DW, AW, AXI_IDW);
    `SB_AXI_M(sb_axi_m_i, axi, DW, AW, AXI_IDW);

    // Converters
    `UMI_PORT_WIRES_WIDTHS(umi_mem_req, DW, CW, AW);
    `UMI_PORT_WIRES_WIDTHS(umi_mem_resp, DW, CW, AW);

    // AXI4 to UMI
    axi2umi #(
        .CW         (CW),
        .AW         (AW),
        .DW         (DW),
        .IDW        (16),
        .AXI_IDW    (AXI_IDW)
    ) dut (
        .clk                (clk),
        .nreset             (nreset),

        // FIXME: The bottom 4 bits of chipid are kept 4'b0001.
        // This hack is to ensure that the memory agent responds on its UMI(0,0)
        // This needs to be fixed either by using a correct address map or
        // enabling all 4 ports. Priority is low.
        .chipid             (16'hAE51),
        .local_routing      (16'hDEAD),

        // AXI port
        // AXI4 Write Interface
        .axi_awid           (axi_awid),
        .axi_awaddr         (axi_awaddr),
        .axi_awlen          (axi_awlen),
        .axi_awsize         (axi_awsize),
        .axi_awburst        (axi_awburst),
        .axi_awlock         (axi_awlock),
        .axi_awcache        (axi_awcache),
        .axi_awprot         (axi_awprot),
        .axi_awqos          ('b0),
        .axi_awregion       ('b0),
        .axi_awvalid        (axi_awvalid),
        .axi_awready        (axi_awready),

        .axi_wid            (axi_awid),
        .axi_wdata          (axi_wdata),
        .axi_wstrb          (axi_wstrb),
        .axi_wlast          (axi_wlast),
        .axi_wvalid         (axi_wvalid),
        .axi_wready         (axi_wready),

        .axi_bid            (axi_bid),
        .axi_bresp          (axi_bresp),
        .axi_bvalid         (axi_bvalid),
        .axi_bready         (axi_bready),

        // AXI4 Read Interface
        .axi_arid           (axi_arid),
        .axi_araddr         (axi_araddr),
        .axi_arlen          (axi_arlen),
        .axi_arsize         (axi_arsize),
        .axi_arburst        (axi_arburst),
        .axi_arlock         (axi_arlock),
        .axi_arcache        (axi_arcache),
        .axi_arprot         (axi_arprot),
        .axi_arqos          ('b0),
        .axi_arregion       ('b0),
        .axi_arvalid        (axi_arvalid),
        .axi_arready        (axi_arready),

        .axi_rid            (axi_rid),
        .axi_rdata          (axi_rdata),
        .axi_rresp          (axi_rresp),
        .axi_rlast          (axi_rlast),
        .axi_rvalid         (axi_rvalid),
        .axi_rready         (axi_rready),

        // Host port
        .uhost_req_valid    (umi_mem_req_valid),
        .uhost_req_cmd      (umi_mem_req_cmd),
        .uhost_req_dstaddr  (umi_mem_req_dstaddr),
        .uhost_req_srcaddr  (umi_mem_req_srcaddr),
        .uhost_req_data     (umi_mem_req_data),
        .uhost_req_ready    (umi_mem_req_ready),

        .uhost_resp_valid   (umi_mem_resp_valid),
        .uhost_resp_cmd     (umi_mem_resp_cmd),
        .uhost_resp_dstaddr (umi_mem_resp_dstaddr),
        .uhost_resp_srcaddr (umi_mem_resp_srcaddr),
        .uhost_resp_data    (umi_mem_resp_data),
        .uhost_resp_ready   (umi_mem_resp_ready)
    );

    wire [CTRLW-1:0]    sram_ctrl = 8'b0;

    umi_mem_agent #(
        .DW                 (DW),
        .AW                 (AW),
        .CW                 (CW),
        .CTRLW              (CTRLW),
        .RAMDEPTH           (RAMDEPTH)
    ) memory_module_ (
        .clk                (clk),
        .nreset             (nreset),

        .sram_ctrl          (sram_ctrl),

        .udev_req_valid     (umi_mem_req_valid),
        .udev_req_cmd       (umi_mem_req_cmd),
        .udev_req_dstaddr   (umi_mem_req_dstaddr),
        .udev_req_srcaddr   (umi_mem_req_srcaddr),
        .udev_req_data      (umi_mem_req_data),
        .udev_req_ready     (umi_mem_req_ready),

        .udev_resp_valid    (umi_mem_resp_valid),
        .udev_resp_cmd      (umi_mem_resp_cmd),
        .udev_resp_dstaddr  (umi_mem_resp_dstaddr),
        .udev_resp_srcaddr  (umi_mem_resp_srcaddr),
        .udev_resp_data     (umi_mem_resp_data),
        .udev_resp_ready    (umi_mem_resp_ready)
    );

    initial begin
        /* verilator lint_off IGNOREDRETURN */
        sb_axi_m_i.init("axi");
        /* verilator lint_on IGNOREDRETURN */
    end

    // VCD
    initial begin
        if ($test$plusargs("trace")) begin
            $dumpfile("testbench.fst");
            $dumpvars(0, testbench);
        end
    end

    //// auto-stop
    //auto_stop_sim #(.CYCLES(TIMEOUT)) auto_stop_sim_i (.clk(clk));

endmodule

`default_nettype wire
