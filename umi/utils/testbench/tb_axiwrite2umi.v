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
 * - AXI4 write channels (AW, W, B) to UMI converter testbench
 *
 ******************************************************************************/

`timescale 1ns / 1ps
`default_nettype wire

module tb_axiwrite2umi #(
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

    // AXI4 Write Interface
    reg  [AXI_IDW-1:0]  axi_awid;
    reg  [AW-1:0]       axi_awaddr;
    reg  [7:0]          num_tx;
    wire [7:0]          axi_awlen;
    reg  [2:0]          axi_awsize;
    reg  [1:0]          axi_awburst;
    reg                 axi_awlock;
    reg  [3:0]          axi_awcache;
    reg  [2:0]          axi_awprot;
    reg  [3:0]          axi_awqos;
    reg  [3:0]          axi_awregion;
    reg                 axi_awvalid;
    wire                axi_awready;

    reg  [AXI_IDW-1:0]  axi_wid;
    reg  [DW-1:0]       axi_wdata;
    reg  [(DW/8)-1:0]   axi_wstrb;
    wire                axi_wlast;
    reg                 axi_wvalid;
    wire                axi_wready;

    wire [AXI_IDW-1:0]  axi_bid;
    wire [1:0]          axi_bresp;
    wire                axi_bvalid;
    reg                 axi_bready;

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

    axiwrite2umi #(
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
    wire [7:0] axi_wstrb_options [0:35];
    reg  [5:0] axi_wstrb_sel_r;
    wire [5:0] axi_wstrb_sel;

    assign axi_wstrb_options[0]  = 8'h01;
    assign axi_wstrb_options[1]  = 8'h02;
    assign axi_wstrb_options[2]  = 8'h04;
    assign axi_wstrb_options[3]  = 8'h08;
    assign axi_wstrb_options[4]  = (DW == 64) ? 8'h10 : 8'h01;
    assign axi_wstrb_options[5]  = (DW == 64) ? 8'h20 : 8'h02;
    assign axi_wstrb_options[6]  = (DW == 64) ? 8'h40 : 8'h04;
    assign axi_wstrb_options[7]  = (DW == 64) ? 8'h80 : 8'h08;
    assign axi_wstrb_options[8]  = 8'h03;
    assign axi_wstrb_options[9]  = 8'h06;
    assign axi_wstrb_options[10] = 8'h0C;
    assign axi_wstrb_options[11] = 8'h18;
    assign axi_wstrb_options[12] = (DW == 64) ? 8'h30 : 8'h03;
    assign axi_wstrb_options[13] = (DW == 64) ? 8'h60 : 8'h06;
    assign axi_wstrb_options[14] = (DW == 64) ? 8'hC0 : 8'h0C;
    assign axi_wstrb_options[15] = 8'h07;
    assign axi_wstrb_options[16] = 8'h0E;
    assign axi_wstrb_options[17] = 8'h1C;
    assign axi_wstrb_options[18] = 8'h38;
    assign axi_wstrb_options[19] = (DW == 64) ? 8'h70 : 8'h07;
    assign axi_wstrb_options[20] = (DW == 64) ? 8'hE0 : 8'h0E;
    assign axi_wstrb_options[21] = 8'h0F;
    assign axi_wstrb_options[22] = 8'h1E;
    assign axi_wstrb_options[23] = 8'h3C;
    assign axi_wstrb_options[24] = 8'h78;
    assign axi_wstrb_options[25] = (DW == 64) ? 8'hF0 : 8'h0F;
    assign axi_wstrb_options[26] = 8'h1F;
    assign axi_wstrb_options[27] = 8'h3E;
    assign axi_wstrb_options[28] = 8'h7C;
    assign axi_wstrb_options[29] = 8'hF8;
    assign axi_wstrb_options[30] = 8'h3F;
    assign axi_wstrb_options[31] = 8'h7E;
    assign axi_wstrb_options[32] = 8'hFC;
    assign axi_wstrb_options[33] = 8'h7F;
    assign axi_wstrb_options[34] = 8'hFE;
    assign axi_wstrb_options[35] = 8'hFF;

    always @(posedge clk) begin
        axi_awid     <= $random;
        axi_awaddr   <= $random & ((RAMDEPTH-1) << $clog2(DW/8)); // DW aligned
        num_tx       <= $random;
        axi_awsize   <= 'b0;
        axi_awburst  <= 2'b01;
        axi_awlock   <= $random;
        axi_awcache  <= $random;
        axi_awprot   <= $random;
        axi_awqos    <= $random;
        axi_awregion <= $random;
        axi_awvalid  <= $random;
    end

    assign axi_awlen = ((axi_awaddr >> $clog2(DW/8)) + num_tx + 1) > RAMDEPTH ?
                       (RAMDEPTH - 1 - (axi_awaddr >> $clog2(DW/8))) :
                       num_tx;

    reg  [8:0]          axi_awlen_r;

    always @(posedge clk) begin
        if (~nreset)
            axi_awlen_r <= 'b0;
        else if (axi_awvalid & axi_awready)
            axi_awlen_r <= axi_awlen + 1;
        else if (axi_wvalid & axi_wready)
            axi_awlen_r <= axi_awlen_r - 1;
    end

    always @(posedge clk) begin
        if (~nreset)
            axi_wid <= 'b0;
        else if (axi_awvalid & axi_awready)
            axi_wid <= axi_awid;
    end

    always @(posedge clk) begin
        axi_wdata   <= {$random, $random};
        axi_wstrb   <= axi_wstrb_options[axi_wstrb_sel];
        axi_wvalid  <= $random;
        axi_bready  <= $random;

        axi_wstrb_sel_r <= $random;
    end

    assign axi_wlast = (axi_awlen_r == 1);

    assign axi_wstrb_sel = (axi_wstrb_sel_r > 35) ?
                           (axi_wstrb_sel_r - 36) :
                           axi_wstrb_sel_r;

    // Scoreboard
    reg  [DW-1:0]   checker_ram [0:RAMDEPTH-1];
    reg  [AW-1:0]   write_addr_golden;

    genvar i;

    always @(posedge clk) begin
        if (axi_awvalid & axi_awready)
            write_addr_golden <= axi_awaddr;
        else if (axi_wvalid & axi_wready)
            write_addr_golden <= write_addr_golden + (DW/8);
    end

    for (i = 0; i < (DW/8); i = i + 1) begin
        always @(posedge clk) begin
            if (axi_wvalid & axi_wready) begin
                if (axi_wstrb[i]) begin
                    checker_ram[write_addr_golden[AW-1:$clog2(DW/8)]][i*8+:8] <= axi_wdata[i*8+:8];
                end
            end
        end
    end

    // Perf Counters
    wire        axi_awcommit;
    wire        axi_wcommit;
    wire        axi_bcommit;
    reg [31:0]  axi_awctr;
    reg [31:0]  axi_wctr;
    reg [31:0]  axi_bctr;

    assign axi_awcommit = axi_awready & axi_awvalid;
    assign axi_wcommit  = axi_wready & axi_wvalid;
    assign axi_bcommit  = axi_bready & axi_bvalid;

    always @(posedge clk or negedge nreset) begin
        if (~nreset) begin
            axi_awctr <= 'b0;
            axi_wctr  <= 'b0;
            axi_bctr  <= 'b0;
        end
        else begin
            if (axi_awcommit) axi_awctr <= axi_awctr + 1;
            if (axi_wcommit)  axi_wctr  <= axi_wctr  + 1;
            if (axi_bcommit)  axi_bctr  <= axi_bctr  + 1;
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
        @(axi_awctr == axi_bctr);
        $display("AXI Write Address Count: %d", axi_awctr);
        $display("AXI Write Data Count: %d", axi_wctr);
        $display("AXI Write Response Count: %d", axi_bctr);
        $display("UMI Req Count: %d", umi_req_ctr);
        $display("UMI Resp Count: %d", umi_resp_ctr);
        $writememh("dutmem.memh", memory_module_.la_spram_i.ram);
        $writememh("goldenmem.memh", checker_ram);
        $finish;
    end

endmodule
