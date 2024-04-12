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
 * - AXI4 read channel (AR, R) to UMI converter testbench
 *
 ******************************************************************************/

`timescale 1ns / 1ps
`default_nettype wire

module tb_axiread2umi #(
    parameter TARGET     = "DEFAULT",   // pass through variable for hard macro
    parameter TIMEOUT    = 500000,      // timeout value (cycles)
    parameter PERIOD_CLK = 10           // clock period
)
();

    // Local parameters
    localparam CW        = 32;    // UMI command width
    localparam AW        = 64;    // UMI address width
    localparam DW        = 64;    // UMI data width
    localparam RAMDEPTH  = 4096;  // param specific to testbench
    localparam AXI_IDW   = 8;     // AXI ID width

    localparam DWLOG     = $clog2(DW/8);

    // Clock
    reg             clk;

    always
        #(PERIOD_CLK/2) clk = ~clk;

    // SIM Ctrl signals
    reg                     nreset;
    reg [DW*RAMDEPTH-1:0]   memhfile;
    integer                 r;

    // Reset initialization
    initial begin
        #(1)
        nreset   = 1'b0;
        clk      = 1'b0;
        #(PERIOD_CLK * 10)
        nreset   = 1'b1;
    end // initial begin

    // AXI4 Read Interface
    reg  [AXI_IDW-1:0]  axi_arid;
    reg  [AW-1:0]       axi_araddr;
    reg  [7:0]          num_tx;
    wire [7:0]          axi_arlen;
    reg  [2:0]          axi_arsize;
    reg  [1:0]          axi_arburst;
    reg                 axi_arlock;
    reg  [3:0]          axi_arcache;
    reg  [2:0]          axi_arprot;
    reg  [3:0]          axi_arqos;
    reg  [3:0]          axi_arregion;
    reg                 axi_arvalid;
    wire                axi_arready;

    wire [AXI_IDW-1:0]  axi_rid;
    wire [DW-1:0]       axi_rdata;
    wire [1:0]          axi_rresp;
    wire                axi_rlast;
    wire                axi_rvalid;
    reg                 axi_rready;

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

    axiread2umi #(
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

        // Host port (per clink)
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

    // Generate AXI transactions
    always @(posedge clk) begin
        axi_arid     <= $random;
        axi_araddr   <= $random & ((RAMDEPTH*DW/8)-1); // DW aligned
        num_tx       <= $random;
        axi_arsize   <= 'b0;
        axi_arburst  <= 2'b01;
        axi_arlock   <= $random;
        axi_arcache  <= $random;
        axi_arprot   <= $random;
        axi_arqos    <= $random;
        axi_arregion <= $random;
        axi_arvalid  <= $random;
    end

    assign axi_arlen = ((axi_araddr >> DWLOG) + num_tx + 1) > RAMDEPTH ?
                       (RAMDEPTH - 1 - (axi_araddr >> DWLOG)) :
                       num_tx;

    always @(posedge clk) begin
        axi_rready  <= $random;
    end

    // Scoreboard
    reg  [DW-1:0]   checker_ram [0:RAMDEPTH-1];
    reg  [AW-1:0]   read_addr_golden;
    wire [DW-1:0]   read_data_golden;

    always @(posedge clk) begin
        if (axi_arvalid & axi_arready)
            read_addr_golden <= axi_araddr;
        else if (axi_rvalid & axi_rready)
            read_addr_golden <= (read_addr_golden &
                                ((RAMDEPTH-1) << DWLOG)) + (DW/8);
    end

    assign read_data_golden = checker_ram[read_addr_golden[AW-1:DWLOG]] &
                              ({DW{1'b1}} << {read_addr_golden[DWLOG-1:0], 3'b000});

    always @(posedge clk) begin
        if (axi_rvalid & axi_rready) begin
            if (read_data_golden != axi_rdata) begin
                $display("Mismatch! Address: 0x%h, Expected: 0x%h, Actual: 0x%h", read_addr_golden, read_data_golden, axi_rdata);
                $finish;
            end
        end
    end

    //genvar i;

    // Perf Counters
    wire        axi_arcommit;
    wire        axi_rcommit;
    reg [31:0]  axi_arctr;
    reg [31:0]  axi_rctr;

    assign axi_arcommit = axi_arready & axi_arvalid;
    assign axi_rcommit  = axi_rready & axi_rvalid;

    always @(posedge clk or negedge nreset) begin
        if (~nreset) begin
            axi_arctr <= 'b0;
            axi_rctr  <= 'b0;
        end
        else begin
            if (axi_arcommit) axi_arctr <= axi_arctr + 1;
            if (axi_rcommit)  axi_rctr  <= axi_rctr  + 1;
        end
    end

    wire        umi_req_commit;
    wire        umi_resp_commit;
    reg [31:0]  umi_req_ctr;
    reg [31:0]  umi_resp_ctr;

    assign umi_req_commit = uhost_req_ready & uhost_req_valid;
    assign umi_resp_commit = uhost_resp_ready & uhost_resp_valid;

    always @(posedge clk or negedge nreset) begin
        if (~nreset) begin
            umi_req_ctr  <= 'b0;
            umi_resp_ctr <= 'b0;
        end
        else begin
            if (umi_req_commit) umi_req_ctr  <= umi_req_ctr + 1;
            if (umi_resp_commit) umi_resp_ctr <= umi_resp_ctr + 1;
        end
    end

    // control block
    initial begin
        r = $value$plusargs("MEMHFILE=%s", memhfile);
        $readmemh(memhfile, memory_module_.la_spram_i.ram);
        $readmemh(memhfile, checker_ram);
        $timeformat(-9, 0, " ns", 20);
        $dumpfile("waveform.vcd");
        $dumpvars();
        #(TIMEOUT)
        $display("AXI Read Address Count: %d", axi_arctr);
        $display("AXI Read Data Count: %d", axi_rctr);
        $display("UMI Req Count: %d", umi_req_ctr);
        $display("UMI Resp Count: %d", umi_resp_ctr);
        $finish;
    end

endmodule
