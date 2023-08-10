`default_nettype none

module testbench (
                  input clk
                  );

   parameter integer RW=32;
   parameter integer DW=512;
   parameter integer AW=64;
   parameter integer CW=32;
   parameter integer PERIOD_CLK = 10;
   parameter integer TCW = 8;
   parameter integer IOW = 64;
   parameter integer NUMI = 2;

   /*AUTOWIRE*/
   // Beginning of automatic wires (for undeclared instantiated-module outputs)
   wire                 host_linkactive;
   wire                 phy_in_ready;
   wire [CW-1:0]        phy_int_cmd;
   wire [RW-1:0]        phy_int_data;
   wire [AW-1:0]        phy_int_dstaddr;
   wire [AW-1:0]        phy_int_srcaddr;
   wire                 phy_int_valid;
   wire [CW-1:0]        phy_out_cmd;
   wire [RW-1:0]        phy_out_data;
   wire [AW-1:0]        phy_out_dstaddr;
   wire                 phy_out_ready;
   wire [AW-1:0]        phy_out_srcaddr;
   wire                 phy_out_valid;
   wire [IOW-1:0]       phy_rxdata;
   wire                 phy_rxrdy;
   wire                 phy_rxvld;
   wire [IOW-1:0]       phy_txdata;
   wire                 phy_txrdy;
   wire                 phy_txvld;
   wire                 sb_in_ready;
   wire [CW-1:0]        sb_out_cmd;
   wire [RW-1:0]        sb_out_data;
   wire [AW-1:0]        sb_out_dstaddr;
   wire [AW-1:0]        sb_out_srcaddr;
   wire                 sb_out_valid;
   wire [CW-1:0]        udev_req_cmd;
   wire [DW-1:0]        udev_req_data;
   wire [AW-1:0]        udev_req_dstaddr;
   wire                 udev_req_ready;
   wire [AW-1:0]        udev_req_srcaddr;
   wire                 udev_req_valid;
   wire                 udev_resp_cmd;
   wire                 udev_resp_data;
   wire                 udev_resp_dstaddr;
   wire                 udev_resp_ready;
   wire                 udev_resp_srcaddr;
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
   wire [255:0]         host_resp_unused;
   wire [AW-1:0]        host_resp_dstaddr;
   wire [AW-1:0]        host_resp_srcaddr;
   wire                 host_resp_valid;

   ///////////////////////////////////////////
   // Host side umi agents
   ///////////////////////////////////////////
   umi_rx_sim #(
                .VALID_MODE_DEFAULT(2),
                .DW(RW)
                )
   host_sb_rx_i (
                 .clk(clk),
                 .data(host_sb_req_data),
                 .srcaddr(host_sb_req_srcaddr),
                 .dstaddr(host_sb_req_dstaddr),
                 .cmd(host_sb_req_cmd),
                 .ready(host_sb_req_ready),
                 .valid(host_sb_req_valid)
                 );

   umi_tx_sim #(
                .READY_MODE_DEFAULT(2),
                .DW(RW)
                )
   host_sb_tx_i (
                 .clk(clk),
                 .data(host_sb_resp_data),
                 .srcaddr(host_sb_resp_srcaddr),
                 .dstaddr(host_sb_resp_dstaddr),
                 .cmd(host_sb_resp_cmd),
                 .ready(host_sb_resp_ready),
                 .valid(host_sb_resp_valid)
                 );

   umi_rx_sim #(
                .VALID_MODE_DEFAULT(2),
                .DW(256)
                )
   host_umi_rx_i (
             .clk(clk),
             .data(host_req_data[255:0]),
             .srcaddr(host_req_srcaddr),
             .dstaddr(host_req_dstaddr),
             .cmd(host_req_cmd),
             .ready(host_req_ready),
             .valid(host_req_valid)
             );

   assign uhost_req_data[511:256] = 'h0;

   umi_tx_sim #(
                .READY_MODE_DEFAULT(2),
                .DW(256)
                )
   host_umi_tx_i (
             .clk(clk),
             .data(host_resp_data[255:0]),
             .srcaddr(host_resp_srcaddr),
             .dstaddr(host_resp_dstaddr),
             .cmd(host_resp_cmd),
             .ready(host_resp_ready),
             .valid(host_resp_valid)
             );

   // instantiate dut with UMI ports
   /* lumi AUTO_TEMPLATE(
    .udev_\(.*\)      (host_\1[]),
    .uhost_req_ready  ('0),
    .uhost_req_.*     (),
    .uhost_resp_ready (),
    .uhost_resp_.*    ('0),
    .phy_in_\(.*\)    (phy_out_\1[]),
    .phy_out_\(.*\)   (phy_int_\1[]),
    .sb_in_\(.*\)     (host_sb_req_\1[]),
    .sb_out_\(.*\)    (host_sb_resp_\1[]),
    .phy_rx\(.*\)     (phy_tx\1[]),
    .phy_tx\(.*\)     (phy_rx\1[]),
    .devicemode       (1'b0),
    .phy_linkactive   (1'b1),
    );*/
   lumi #(.RW(RW),
          .CW(CW),
          .AW(AW),
          .DW(DW))
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
               .phy_out_valid   (phy_int_valid),         // Templated
               .phy_out_cmd     (phy_int_cmd[CW-1:0]),   // Templated
               .phy_out_dstaddr (phy_int_dstaddr[AW-1:0]), // Templated
               .phy_out_srcaddr (phy_int_srcaddr[AW-1:0]), // Templated
               .phy_out_data    (phy_int_data[RW-1:0]),  // Templated
               .phy_rxrdy       (phy_txrdy),             // Templated
               .phy_txdata      (phy_rxdata[IOW-1:0]),   // Templated
               .phy_txvld       (phy_rxvld),             // Templated
               .host_linkactive (host_linkactive),
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
               .phy_in_valid    (phy_out_valid),         // Templated
               .phy_in_cmd      (phy_out_cmd[CW-1:0]),   // Templated
               .phy_in_dstaddr  (phy_out_dstaddr[AW-1:0]), // Templated
               .phy_in_srcaddr  (phy_out_srcaddr[AW-1:0]), // Templated
               .phy_in_data     (phy_out_data[RW-1:0]),  // Templated
               .phy_out_ready   (phy_int_ready),         // Templated
               .phy_rxdata      (phy_txdata[IOW-1:0]),   // Templated
               .phy_rxvld       (phy_txvld),             // Templated
               .phy_txrdy       (phy_rxrdy),             // Templated
               .phy_linkactive  (1'b1),                  // Templated
               .nreset          (nreset),
               .clk             (clk),
               .devicready      (devicready),
               .vss             (vss),
               .vdd             (vdd),
               .vddio           (vddio));

   /* lumi AUTO_TEMPLATE(
    .uhost_req_\(.*\)  (udev_req_\1[]),
    .uhost_resp_\(.*\) (udev_resp_\1[]),
    .udev_req_ready    (),
    .udev_req_.*       ('h0),
    .udev_resp_ready   (1'b0),
    .udev_resp_.*      (),
    .devicemode        (1'b0),
    .phy_linkactive    (1'b1),
    );*/
   lumi #(.RW(RW),
          .CW(CW),
          .AW(AW),
          .DW(DW))
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
              .sb_in_ready      (sb_in_ready),
              .sb_out_valid     (sb_out_valid),
              .sb_out_cmd       (sb_out_cmd[CW-1:0]),
              .sb_out_dstaddr   (sb_out_dstaddr[AW-1:0]),
              .sb_out_srcaddr   (sb_out_srcaddr[AW-1:0]),
              .sb_out_data      (sb_out_data[RW-1:0]),
              .phy_in_ready     (phy_in_ready),
              .phy_out_valid    (phy_out_valid),
              .phy_out_cmd      (phy_out_cmd[CW-1:0]),
              .phy_out_dstaddr  (phy_out_dstaddr[AW-1:0]),
              .phy_out_srcaddr  (phy_out_srcaddr[AW-1:0]),
              .phy_out_data     (phy_out_data[RW-1:0]),
              .phy_rxrdy        (phy_rxrdy),
              .phy_txdata       (phy_txdata[IOW-1:0]),
              .phy_txvld        (phy_txvld),
              .host_linkactive  (host_linkactive),
              // Inputs
              .devicemode       (1'b0),                  // Templated
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
              .sb_in_valid      (sb_in_valid),
              .sb_in_cmd        (sb_in_cmd[CW-1:0]),
              .sb_in_dstaddr    (sb_in_dstaddr[AW-1:0]),
              .sb_in_srcaddr    (sb_in_srcaddr[AW-1:0]),
              .sb_in_data       (sb_in_data[RW-1:0]),
              .sb_out_ready     (sb_out_ready),
              .phy_in_valid     (phy_in_valid),
              .phy_in_cmd       (phy_in_cmd[CW-1:0]),
              .phy_in_dstaddr   (phy_in_dstaddr[AW-1:0]),
              .phy_in_srcaddr   (phy_in_srcaddr[AW-1:0]),
              .phy_in_data      (phy_in_data[RW-1:0]),
              .phy_out_ready    (phy_out_ready),
              .phy_rxdata       (phy_rxdata[IOW-1:0]),
              .phy_rxvld        (phy_rxvld),
              .phy_txrdy        (phy_txrdy),
              .phy_linkactive   (1'b1),                  // Templated
              .nreset           (nreset),
              .clk              (clk),
              .devicready       (devicready),
              .vss              (vss),
              .vdd              (vdd),
              .vddio            (vddio));

   umiram #(.ADDR_WIDTH(ADDR_WIDTH),
            .DATA_WIDTH(DATA_WIDTH),
            .DW(DW),
            .AW(AW),
            .CW(CW),
            .ATOMIC_WIDTH(ATOMIC_WIDTH))
   umiram_i(// Outputs
            .udev_req_ready(udev_req_ready),
            .udev_resp_valid(udev_resp_valid),
            .udev_resp_cmd(udev_resp_cmd),
            .udev_resp_dstaddr(udev_resp_dstaddr),
            .udev_resp_srcaddr(udev_resp_srcaddr),
            .udev_resp_data(udev_resp_data)
            // Inputs
            .clk(clk),
            .udev_req_valid(udev_req_valid),
            .udev_req_cmd(udev_req_cmd),
            .udev_req_dstaddr(udev_req_dstaddr),
            .udev_req_srcaddr(udev_req_srcaddr),
            .udev_req_data(udev_req_data),
            .udev_resp_ready(udev_resp_ready),
            /*AUTOINST*/);

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

   // VCD

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
// verilog-library-directories:("../rtl" "../../submodules/switchboard/examples/common/verilog/" )
// End:

`default_nettype wire
