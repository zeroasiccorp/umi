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
 * - UMI to AXI4-Lite converter testbench
 *
 ******************************************************************************/


`default_nettype none

module testbench (
    input clk
);

    localparam TIMEOUT  = 500000;
    localparam DW       = 64;
    localparam AW       = 64;
    localparam CW       = 32;
    localparam RAMDEPTH = 4096;  // param specific to testbench
    localparam CTRLW    = 8;

    wire        nreset;
    reg [15:0]  nreset_r = 16'hFFFF;

    assign nreset = ~nreset_r[15];

    always @(negedge clk) begin
        nreset_r <= nreset_r << 1;
    end

    wire            umi_req_valid;
    wire [CW-1:0]   umi_req_cmd;
    wire [AW-1:0]   umi_req_dstaddr;
    wire [AW-1:0]   umi_req_srcaddr;
    wire [DW-1:0]   umi_req_data;
    wire            umi_req_ready;

    // UMI agents
    umi_rx_sim #(
       .VALID_MODE_DEFAULT  (2),
       .DW                  (DW)
    ) umi_rx_i (
        .clk                (clk),
        .valid              (umi_req_valid),
        .cmd                (umi_req_cmd),
        .dstaddr            (umi_req_dstaddr),
        .srcaddr            (umi_req_srcaddr),
        .data               (umi_req_data),
        .ready              (umi_req_ready)
    );

    wire            umi_resp_valid;
    wire [CW-1:0]   umi_resp_cmd;
    wire [AW-1:0]   umi_resp_dstaddr;
    wire [AW-1:0]   umi_resp_srcaddr;
    wire [DW-1:0]   umi_resp_data;
    wire            umi_resp_ready;

    umi_tx_sim #(
        .READY_MODE_DEFAULT (2),
        .DW                 (DW)
    ) umi_tx_i (
        .clk                (clk),
        .valid              (umi_resp_valid),
        .cmd                (umi_resp_cmd),
        .dstaddr            (umi_resp_dstaddr),
        .srcaddr            (umi_resp_srcaddr),
        .data               (umi_resp_data),
        .ready              (umi_resp_ready)
    );

    // Converters
    wire [AW-1:0]       axi_awaddr;
    wire [2:0]          axi_awprot;
    wire                axi_awvalid;
    wire                axi_awready;

    wire [DW-1:0]       axi_wdata;
    wire [(DW/8)-1:0]   axi_wstrb;
    wire                axi_wvalid;
    wire                axi_wready;

    wire [1:0]          axi_bresp;
    wire                axi_bvalid;
    wire                axi_bready;

    wire [AW-1:0]       axi_araddr;
    wire [2:0]          axi_arprot;
    wire                axi_arvalid;
    wire                axi_arready;

    wire [DW-1:0]       axi_rdata;
    wire [1:0]          axi_rresp;
    wire                axi_rvalid;
    wire                axi_rready;

    wire                umi_mem_req_valid;
    wire [CW-1:0]       umi_mem_req_cmd;
    wire [AW-1:0]       umi_mem_req_dstaddr;
    wire [AW-1:0]       umi_mem_req_srcaddr;
    wire [DW-1:0]       umi_mem_req_data;
    wire                umi_mem_req_ready;

    wire                umi_mem_resp_valid;
    wire [CW-1:0]       umi_mem_resp_cmd;
    wire [AW-1:0]       umi_mem_resp_dstaddr;
    wire [AW-1:0]       umi_mem_resp_srcaddr;
    wire [DW-1:0]       umi_mem_resp_data;
    wire                umi_mem_resp_ready;

    // UMI to AXI4-Lite
    umi2axilite #(
        .CW     (CW),
        .AW     (AW),
        .DW     (DW)
    ) umi2axilite_ (
        .clk                (clk),
        .nreset             (nreset),

        // UMI Device port
        .udev_req_valid     (umi_req_valid),
        .udev_req_cmd       (umi_req_cmd),
        .udev_req_dstaddr   (umi_req_dstaddr),
        .udev_req_srcaddr   (umi_req_srcaddr),
        .udev_req_data      (umi_req_data),
        .udev_req_ready     (umi_req_ready),

        .udev_resp_valid    (umi_resp_valid),
        .udev_resp_cmd      (umi_resp_cmd),
        .udev_resp_dstaddr  (umi_resp_dstaddr),
        .udev_resp_srcaddr  (umi_resp_srcaddr),
        .udev_resp_data     (umi_resp_data),
        .udev_resp_ready    (umi_resp_ready),

        // AXI4Lite Interface
        .axi_awaddr         (axi_awaddr),
        .axi_awprot         (axi_awprot),
        .axi_awvalid        (axi_awvalid),
        .axi_awready        (axi_awready),

        .axi_wdata          (axi_wdata),
        .axi_wstrb          (axi_wstrb),
        .axi_wvalid         (axi_wvalid),
        .axi_wready         (axi_wready),

        .axi_bresp          (axi_bresp),
        .axi_bvalid         (axi_bvalid),
        .axi_bready         (axi_bready),

        .axi_araddr         (axi_araddr),
        .axi_arprot         (axi_arprot),
        .axi_arvalid        (axi_arvalid),
        .axi_arready        (axi_arready),

        .axi_rdata          (axi_rdata),
        .axi_rresp          (axi_rresp),
        .axi_rvalid         (axi_rvalid),
        .axi_rready         (axi_rready)
    );

    // AXI4-Lite to UMI
    axilite2umi #(
        .CW     (CW),
        .AW     (AW),
        .DW     (DW),
        .IDW    (16)
    ) axilite2umi_ (
        .clk                (clk),
        .nreset             (nreset),

        // FIXME: The bottom 4 bits of chipid are kept 4'b0001.
        // This hack is to ensure that the memory agent responds on its UMI(0,0)
        // This needs to be fixed either by using a correct address map or
        // enabling all 4 ports. Priority is low.
        .chipid             (16'hAE51),
        .local_routing      (16'hDEAD),

        // AXI4Lite Interface
        .axi_awaddr         (axi_awaddr),
        .axi_awprot         (axi_awprot),
        .axi_awvalid        (axi_awvalid),
        .axi_awready        (axi_awready),

        .axi_wdata          (axi_wdata),
        .axi_wstrb          (axi_wstrb),
        .axi_wvalid         (axi_wvalid),
        .axi_wready         (axi_wready),

        .axi_bresp          (axi_bresp),
        .axi_bvalid         (axi_bvalid),
        .axi_bready         (axi_bready),

        .axi_araddr         (axi_araddr),
        .axi_arprot         (axi_arprot),
        .axi_arvalid        (axi_arvalid),
        .axi_arready        (axi_arready),

        .axi_rdata          (axi_rdata),
        .axi_rresp          (axi_rresp),
        .axi_rvalid         (axi_rvalid),
        .axi_rready         (axi_rready),

        // Host port (per clink)
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

        umi_rx_i.init("host2dut_0.q");
        umi_rx_i.set_valid_mode(valid_mode);

        umi_tx_i.init("dut2host_0.q");
        umi_tx_i.set_ready_mode(ready_mode);
        /* verilator lint_on IGNOREDRETURN */
    end

    // VCD
    initial begin
        if ($test$plusargs("trace")) begin
            $dumpfile("testbench.fst");
            $dumpvars(0, testbench);
        end
    end

    // auto-stop
    auto_stop_sim #(.CYCLES(TIMEOUT)) auto_stop_sim_i (.clk(clk));

endmodule

`default_nettype wire
