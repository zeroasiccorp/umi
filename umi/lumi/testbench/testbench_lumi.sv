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
 ******************************************************************************/

`default_nettype none

module testbench (
                  input clk
                  );

   parameter integer RW=32;
   parameter integer DW=256;
   parameter integer AW=64;
   parameter integer CW=32;
   parameter integer PERIOD_CLK = 10;
   parameter integer TCW = 8;
   parameter integer IOW = 128;
   parameter integer NUMI = 2;

   /*AUTOWIRE*/
   // Beginning of automatic wires (for undeclared instantiated-module outputs)
   wire [CW-1:0]        phy_in_cmd;
   wire [RW-1:0]        phy_in_data;
   wire [AW-1:0]        phy_in_dstaddr;
   wire                 phy_in_ready;
   wire [AW-1:0]        phy_in_srcaddr;
   wire                 phy_in_valid;
   wire [CW-1:0]        phy_out_cmd;
   wire [RW-1:0]        phy_out_data;
   wire [AW-1:0]        phy_out_dstaddr;
   wire                 phy_out_ready;
   wire [AW-1:0]        phy_out_srcaddr;
   wire                 phy_out_valid;
   wire [IOW-1:0]       phy_rxdata;
   wire                 phy_rxvld;
   wire [IOW-1:0]       phy_txdata;
   wire                 phy_txvld;
   wire [CW-1:0]        udev_req_cmd;
   wire [DW-1:0]        udev_req_data;
   wire [AW-1:0]        udev_req_dstaddr;
   wire                 udev_req_ready;
   wire [AW-1:0]        udev_req_srcaddr;
   wire                 udev_req_valid;
   wire [CW-1:0]        udev_resp_cmd;
   wire [DW-1:0]        udev_resp_data;
   wire [AW-1:0]        udev_resp_dstaddr;
   wire                 udev_resp_ready;
   wire [AW-1:0]        udev_resp_srcaddr;
   wire                 udev_resp_valid;
   // End of automatics
   reg                  nreset;
   reg                  go;

   wire                 host_sb_req_ready;
   wire [CW-1:0]        host_sb_req_cmd;
   wire [RW-1:0]        host_sb_req_data;
   wire [AW-1:0]        host_sb_req_dstaddr;
   wire [AW-1:0]        host_sb_req_srcaddr;
   wire                 host_sb_req_valid;

   wire                 host_sb_resp_ready;
   wire [CW-1:0]        host_sb_resp_cmd;
   wire [RW-1:0]        host_sb_resp_data;
   wire [AW-1:0]        host_sb_resp_dstaddr;
   wire [AW-1:0]        host_sb_resp_srcaddr;
   wire                 host_sb_resp_valid;

   wire                 host_req_ready;
   wire [CW-1:0]        host_req_cmd;
   wire [DW-1:0]        host_req_data;
   wire [AW-1:0]        host_req_dstaddr;
   wire [AW-1:0]        host_req_srcaddr;
   wire                 host_req_valid;

   wire                 host_resp_ready;
   wire [CW-1:0]        host_resp_cmd;
   wire [DW-1:0]        host_resp_data;
   wire [AW-1:0]        host_resp_dstaddr;
   wire [AW-1:0]        host_resp_srcaddr;
   wire                 host_resp_valid;

   ///////////////////////////////////////////
   // Host side umi agents
   ///////////////////////////////////////////
   queue_to_umi_sim #(
                .VALID_MODE_DEFAULT(2),
                .DW(RW)
                )
   host_sb_rx_i (
                 .clk(clk),
                 .reset(~nreset),
                 .data(host_sb_req_data),
                 .srcaddr(host_sb_req_srcaddr),
                 .dstaddr(host_sb_req_dstaddr),
                 .cmd(host_sb_req_cmd),
                 .ready(host_sb_req_ready),
                 .valid(host_sb_req_valid)
                 );

   umi_to_queue_sim #(
                .READY_MODE_DEFAULT(2),
                .DW(RW)
                )
   host_sb_tx_i (
                 .clk(clk),
                 .reset(~nreset),
                 .data(host_sb_resp_data),
                 .srcaddr(host_sb_resp_srcaddr),
                 .dstaddr(host_sb_resp_dstaddr),
                 .cmd(host_sb_resp_cmd),
                 .ready(host_sb_resp_ready),
                 .valid(host_sb_resp_valid)
                 );

   queue_to_umi_sim #(
                .VALID_MODE_DEFAULT(2),
                .DW(256)
                )
   host_umi_rx_i (
             .clk(clk),
             .reset(~nreset),
             .data(host_req_data[255:0]),
             .srcaddr(host_req_srcaddr),
             .dstaddr(host_req_dstaddr),
             .cmd(host_req_cmd),
             .ready(host_req_ready),
             .valid(host_req_valid)
             );

//   assign host_req_data[511:256] = 'h0;

   umi_to_queue_sim #(
                .READY_MODE_DEFAULT(2),
                .DW(256)
                )
   host_umi_tx_i (
             .clk(clk),
             .reset(~nreset),
             .data(host_resp_data[255:0]),
             .srcaddr(host_resp_srcaddr),
             .dstaddr(host_resp_dstaddr),
             .cmd(host_resp_cmd),
             .ready(host_resp_ready),
             .valid(host_resp_valid)
             );

   // No clink so driving all clock from the tb
   wire rxclk = clk;
   wire txclk = clk;
   wire phy_clk = clk;
   wire rxnreset = nreset;
   wire txnreset = nreset;
   wire phy_nreset = nreset;
   reg  linkactive_host;
   reg  linkactive_device;
   integer host_delay;
   integer device_delay;
   reg [31:0] delay_cnt;

   always @(posedge clk or negedge nreset)
     if (~nreset)
       delay_cnt <= 'd0;
     else
       delay_cnt <= delay_cnt + 1;
   initial
     begin
        if (!$value$plusargs("hostdly=%d",host_delay))
          host_delay = $urandom%500;
        if (!$value$plusargs("devdly=%d",device_delay))
          device_delay = $urandom%500;
     end

   always @(posedge clk or negedge nreset)
     if (~nreset)
       begin
          linkactive_host <= 1'b0;
          linkactive_device <= 1'b0;
       end
     else
       begin
          if (delay_cnt == host_delay)
            linkactive_host <= 1'b1;
          if (delay_cnt == device_delay)
            linkactive_device <= 1'b1;
       end

   // instantiate dut with UMI ports
   /* lumi AUTO_TEMPLATE(
    .udev_\(.*\)      (host_\1[]),
    .uhost_req_ready  ('0),
    .uhost_req_.*     (),
    .uhost_resp_ready (),
    .uhost_resp_.*    ('0),
    .phy_in_\(.*\)    (phy_out_\1[]),
    .phy_out_\(.*\)   (phy_in_\1[]),
    .sb_in_\(.*\)     (host_sb_req_\1[]),
    .sb_out_\(.*\)    (host_sb_resp_\1[]),
    .phy_rx\(.*\)     (phy_tx\1[]),
    .phy_tx\(.*\)     (phy_rx\1[]),
    .devicemode       (1'b0),
    .deviceready      (1'b1),
    .phy_linkactive   (linkactive_host),
    .phy_iow          (8'h0),
    .host_linkactive  (),
    .vss              (),
    .vdd.*            (),
    );*/
   lumi #(.IOW(IOW),
          .RW(RW),
          .CW(CW),
          .AW(AW),
          .DW(DW),
          .GRPID(8'h70))
   lumi_host_i(/*AUTOINST*/
               // Outputs
               .uhost_req_valid (),                      // Templated
               .uhost_req_cmd   (),                      // Templated
               .uhost_req_dstaddr(),                     // Templated
               .uhost_req_srcaddr(),                     // Templated
               .uhost_req_data  (),                      // Templated
               .uhost_resp_ready(),                      // Templated
               .udev_req_ready  (host_req_ready),        // Templated
               .udev_resp_valid (host_resp_valid),       // Templated
               .udev_resp_cmd   (host_resp_cmd[CW-1:0]), // Templated
               .udev_resp_dstaddr(host_resp_dstaddr[AW-1:0]), // Templated
               .udev_resp_srcaddr(host_resp_srcaddr[AW-1:0]), // Templated
               .udev_resp_data  (host_resp_data[DW-1:0]), // Templated
               .sb_in_ready     (host_sb_req_ready),     // Templated
               .sb_out_valid    (host_sb_resp_valid),    // Templated
               .sb_out_cmd      (host_sb_resp_cmd[CW-1:0]), // Templated
               .sb_out_dstaddr  (host_sb_resp_dstaddr[AW-1:0]), // Templated
               .sb_out_srcaddr  (host_sb_resp_srcaddr[AW-1:0]), // Templated
               .sb_out_data     (host_sb_resp_data[RW-1:0]), // Templated
               .phy_in_ready    (phy_out_ready),         // Templated
               .phy_out_valid   (phy_in_valid),          // Templated
               .phy_out_cmd     (phy_in_cmd[CW-1:0]),    // Templated
               .phy_out_dstaddr (phy_in_dstaddr[AW-1:0]), // Templated
               .phy_out_srcaddr (phy_in_srcaddr[AW-1:0]), // Templated
               .phy_out_data    (phy_in_data[RW-1:0]),   // Templated
               .phy_txdata      (phy_rxdata[IOW-1:0]),   // Templated
               .phy_txvld       (phy_rxvld),             // Templated
               .host_linkactive (),                      // Templated
               // Inputs
               .devicemode      (1'b0),                  // Templated
               .uhost_req_ready ('0),                    // Templated
               .uhost_resp_valid('0),                    // Templated
               .uhost_resp_cmd  ('0),                    // Templated
               .uhost_resp_dstaddr('0),                  // Templated
               .uhost_resp_srcaddr('0),                  // Templated
               .uhost_resp_data ('0),                    // Templated
               .udev_req_valid  (host_req_valid),        // Templated
               .udev_req_cmd    (host_req_cmd[CW-1:0]),  // Templated
               .udev_req_dstaddr(host_req_dstaddr[AW-1:0]), // Templated
               .udev_req_srcaddr(host_req_srcaddr[AW-1:0]), // Templated
               .udev_req_data   (host_req_data[DW-1:0]), // Templated
               .udev_resp_ready (host_resp_ready),       // Templated
               .sb_in_valid     (host_sb_req_valid),     // Templated
               .sb_in_cmd       (host_sb_req_cmd[CW-1:0]), // Templated
               .sb_in_dstaddr   (host_sb_req_dstaddr[AW-1:0]), // Templated
               .sb_in_srcaddr   (host_sb_req_srcaddr[AW-1:0]), // Templated
               .sb_in_data      (host_sb_req_data[RW-1:0]), // Templated
               .sb_out_ready    (host_sb_resp_ready),    // Templated
               .phy_clk         (phy_clk),
               .phy_nreset      (phy_nreset),
               .phy_in_valid    (phy_out_valid),         // Templated
               .phy_in_cmd      (phy_out_cmd[CW-1:0]),   // Templated
               .phy_in_dstaddr  (phy_out_dstaddr[AW-1:0]), // Templated
               .phy_in_srcaddr  (phy_out_srcaddr[AW-1:0]), // Templated
               .phy_in_data     (phy_out_data[RW-1:0]),  // Templated
               .phy_out_ready   (phy_in_ready),          // Templated
               .phy_rxdata      (phy_txdata[IOW-1:0]),   // Templated
               .phy_rxvld       (phy_txvld),             // Templated
               .rxclk           (rxclk),
               .rxnreset        (rxnreset),
               .txclk           (txclk),
               .txnreset        (txnreset),
               .phy_linkactive  (linkactive_host),       // Templated
               .phy_iow         (8'h0),                  // Templated
               .nreset          (nreset),
               .clk             (clk),
               .deviceready     (1'b1),                  // Templated
               .vss             (),                      // Templated
               .vdd             ());                     // Templated

   /* lumi AUTO_TEMPLATE(
    .uhost_req_\(.*\)  (udev_req_\1[]),
    .uhost_resp_\(.*\) (udev_resp_\1[]),
    .udev_req_ready    (),
    .udev_req_.*       ('h0),
    .udev_resp_ready   (1'b0),
    .udev_resp_.*      (),
    .sb_in_ready       (),
    .sb_in_.*          ('h0),
    .sb_out_ready      (1'b0),
    .sb_out.*          (),
    .devicemode        (1'b1),
    .deviceready       (1'b1),
    .phy_linkactive    (linkactive_device),
    .phy_iow           (8'h0),
    .host_linkactive   (),
    .vss               (),
    .vdd.*             (),
    );*/
   lumi #(.IOW(IOW),
          .RW(RW),
          .CW(CW),
          .AW(AW),
          .DW(DW),
          .GRPID(8'h60))
   lumi_dev_i(/*AUTOINST*/
              // Outputs
              .uhost_req_valid  (udev_req_valid),        // Templated
              .uhost_req_cmd    (udev_req_cmd[CW-1:0]),  // Templated
              .uhost_req_dstaddr(udev_req_dstaddr[AW-1:0]), // Templated
              .uhost_req_srcaddr(udev_req_srcaddr[AW-1:0]), // Templated
              .uhost_req_data   (udev_req_data[DW-1:0]), // Templated
              .uhost_resp_ready (udev_resp_ready),       // Templated
              .udev_req_ready   (),                      // Templated
              .udev_resp_valid  (),                      // Templated
              .udev_resp_cmd    (),                      // Templated
              .udev_resp_dstaddr(),                      // Templated
              .udev_resp_srcaddr(),                      // Templated
              .udev_resp_data   (),                      // Templated
              .sb_in_ready      (),                      // Templated
              .sb_out_valid     (),                      // Templated
              .sb_out_cmd       (),                      // Templated
              .sb_out_dstaddr   (),                      // Templated
              .sb_out_srcaddr   (),                      // Templated
              .sb_out_data      (),                      // Templated
              .phy_in_ready     (phy_in_ready),
              .phy_out_valid    (phy_out_valid),
              .phy_out_cmd      (phy_out_cmd[CW-1:0]),
              .phy_out_dstaddr  (phy_out_dstaddr[AW-1:0]),
              .phy_out_srcaddr  (phy_out_srcaddr[AW-1:0]),
              .phy_out_data     (phy_out_data[RW-1:0]),
              .phy_txdata       (phy_txdata[IOW-1:0]),
              .phy_txvld        (phy_txvld),
              .host_linkactive  (),                      // Templated
              // Inputs
              .devicemode       (1'b1),                  // Templated
              .uhost_req_ready  (udev_req_ready),        // Templated
              .uhost_resp_valid (udev_resp_valid),       // Templated
              .uhost_resp_cmd   (udev_resp_cmd[CW-1:0]), // Templated
              .uhost_resp_dstaddr(udev_resp_dstaddr[AW-1:0]), // Templated
              .uhost_resp_srcaddr(udev_resp_srcaddr[AW-1:0]), // Templated
              .uhost_resp_data  (udev_resp_data[DW-1:0]), // Templated
              .udev_req_valid   ('h0),                   // Templated
              .udev_req_cmd     ('h0),                   // Templated
              .udev_req_dstaddr ('h0),                   // Templated
              .udev_req_srcaddr ('h0),                   // Templated
              .udev_req_data    ('h0),                   // Templated
              .udev_resp_ready  (1'b0),                  // Templated
              .sb_in_valid      ('h0),                   // Templated
              .sb_in_cmd        ('h0),                   // Templated
              .sb_in_dstaddr    ('h0),                   // Templated
              .sb_in_srcaddr    ('h0),                   // Templated
              .sb_in_data       ('h0),                   // Templated
              .sb_out_ready     (1'b0),                  // Templated
              .phy_clk          (phy_clk),
              .phy_nreset       (phy_nreset),
              .phy_in_valid     (phy_in_valid),
              .phy_in_cmd       (phy_in_cmd[CW-1:0]),
              .phy_in_dstaddr   (phy_in_dstaddr[AW-1:0]),
              .phy_in_srcaddr   (phy_in_srcaddr[AW-1:0]),
              .phy_in_data      (phy_in_data[RW-1:0]),
              .phy_out_ready    (phy_out_ready),
              .phy_rxdata       (phy_rxdata[IOW-1:0]),
              .phy_rxvld        (phy_rxvld),
              .rxclk            (rxclk),
              .rxnreset         (rxnreset),
              .txclk            (txclk),
              .txnreset         (txnreset),
              .phy_linkactive   (linkactive_device),     // Templated
              .phy_iow          (8'h0),                  // Templated
              .nreset           (nreset),
              .clk              (clk),
              .deviceready      (1'b1),                  // Templated
              .vss              (),                      // Templated
              .vdd              ());                     // Templated

   umi_memagent #(.DW(DW),
                   .AW(AW),
                   .CW(CW),
                   .CTRLW(8))
   umi_memagent_i(.sram_ctrl           (8'b010_01_0_0_0),
                   /*AUTOINST*/
                   // Outputs
                   .udev_req_ready      (udev_req_ready),
                   .udev_resp_valid     (udev_resp_valid),
                   .udev_resp_cmd       (udev_resp_cmd[CW-1:0]),
                   .udev_resp_dstaddr   (udev_resp_dstaddr[AW-1:0]),
                   .udev_resp_srcaddr   (udev_resp_srcaddr[AW-1:0]),
                   .udev_resp_data      (udev_resp_data[DW-1:0]),
                   // Inputs
                   .clk                 (clk),
                   .nreset              (nreset),
                   .udev_req_valid      (udev_req_valid),
                   .udev_req_cmd        (udev_req_cmd[CW-1:0]),
                   .udev_req_dstaddr    (udev_req_dstaddr[AW-1:0]),
                   .udev_req_srcaddr    (udev_req_srcaddr[AW-1:0]),
                   .udev_req_data       (udev_req_data[DW-1:0]),
                   .udev_resp_ready     (udev_resp_ready));

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

      host_umi_rx_i.init("host2dut_0.q");
      host_umi_rx_i.set_valid_mode(valid_mode);

      host_umi_tx_i.init("dut2host_0.q");
      host_umi_tx_i.set_ready_mode(ready_mode);

      host_sb_rx_i.init("sb2dut_0.q");
      host_sb_rx_i.set_valid_mode(valid_mode);

      host_sb_tx_i.init("dut2sb_0.q");
      host_sb_tx_i.set_ready_mode(ready_mode);

      /* verilator lint_on IGNOREDRETURN */
   end

   // FST

   initial
     begin
        nreset   = 1'b0;
        go       = 1'b0;
     end // initial begin

   // Bring up reset and the go signal on the first clock cycle
   always @(negedge clk)
     begin
        nreset <= nreset | 1'b1;
        go <= 1'b1;
     end

   // control block
   initial
     begin
        if ($test$plusargs("trace"))
          begin
             $dumpfile("testbench.vcd");
             $dumpvars(0, testbench);
          end
     end

   // auto-stop

   auto_stop_sim auto_stop_sim_i (.clk(clk));

endmodule
// Local Variables:
// verilog-library-directories:("../rtl" "../../umi/rtl" )
// End:

`default_nettype wire
