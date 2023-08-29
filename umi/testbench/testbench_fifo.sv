`default_nettype none

module testbench (
                  input clk
                  );

   parameter integer DW=128;
   parameter integer AW=64;
   parameter integer CW=32;
   parameter integer DEPTH=1;

   /*AUTOWIRE*/
   // Beginning of automatic wires (for undeclared instantiated-module outputs)
   wire [CW-1:0]        umi_req_out_cmd;
   wire [DW-1:0]        umi_req_out_data;
   wire [AW-1:0]        umi_req_out_dstaddr;
   wire                 umi_req_out_ready;
   wire [AW-1:0]        umi_req_out_srcaddr;
   wire                 umi_req_out_valid;
   wire [CW-1:0]        umi_resp_in_cmd;
   wire [DW-1:0]        umi_resp_in_data;
   wire [AW-1:0]        umi_resp_in_dstaddr;
   wire                 umi_resp_in_ready;
   wire [AW-1:0]        umi_resp_in_srcaddr;
   wire                 umi_resp_in_valid;
   // End of automatics
   reg               nreset;

   wire              umi_resp_out_ready;
   wire [CW-1:0]     umi_resp_out_cmd;
   wire [DW-1:0]     umi_resp_out_data;
   wire [AW-1:0]     umi_resp_out_dstaddr;
   wire [AW-1:0]     umi_resp_out_srcaddr;
   wire              umi_resp_out_valid;

   wire              umi_req_in_ready;
   wire [CW-1:0]     umi_req_in_cmd;
   wire [DW-1:0]     umi_req_in_data;
   wire [AW-1:0]     umi_req_in_dstaddr;
   wire [AW-1:0]     umi_req_in_srcaddr;
   wire              umi_req_in_valid;

   ///////////////////////////////////////////
   // Host side umi agents
   ///////////////////////////////////////////

   umi_rx_sim #(.VALID_MODE_DEFAULT(2),
                .DW(DW)
                )
   host_umi_rx_i (.clk(clk),
                  .data(umi_req_in_data[DW-1:0]),
                  .srcaddr(umi_req_in_srcaddr[AW-1:0]),
                  .dstaddr(umi_req_in_dstaddr[AW-1:0]),
                  .cmd(umi_req_in_cmd[CW-1:0]),
                  .ready(umi_req_in_ready),
                  .valid(umi_req_in_valid)
                  );

   umi_tx_sim #(.READY_MODE_DEFAULT(2),
                .DW(DW)
                )
   host_umi_tx_i (.clk(clk),
                  .data(umi_resp_out_data[DW-1:0]),
                  .srcaddr(umi_resp_out_srcaddr[AW-1:0]),
                  .dstaddr(umi_resp_out_dstaddr[AW-1:0]),
                  .cmd(umi_resp_out_cmd[CW-1:0]),
                  .ready(umi_resp_out_ready),
                  .valid(umi_resp_out_valid)
                  );

   // instantiate dut with UMI ports
   /* umi_fifo AUTO_TEMPLATE(
    .umi_.*_clk     (clk),
    .umi_.*_nreset  (nreset),
    .umi_in_\(.*\)  (umi_req_in_\1[]),
    .umi_out_\(.*\) (umi_req_out_\1[]),
    .bypass         ('b0),
    .chaosmode      ('b0),
    .v.*            (),
    .fifo_.*        (),
    );*/
   umi_fifo #(.DW(DW),
              .CW(CW),
              .AW(AW),
              .DEPTH(DEPTH))
   umi_fifo_rx_i(/*AUTOINST*/
                 // Outputs
                 .fifo_full             (),                      // Templated
                 .fifo_empty            (),                      // Templated
                 .umi_in_ready          (umi_req_in_ready),      // Templated
                 .umi_out_valid         (umi_req_out_valid),     // Templated
                 .umi_out_cmd           (umi_req_out_cmd[CW-1:0]), // Templated
                 .umi_out_dstaddr       (umi_req_out_dstaddr[AW-1:0]), // Templated
                 .umi_out_srcaddr       (umi_req_out_srcaddr[AW-1:0]), // Templated
                 .umi_out_data          (umi_req_out_data[DW-1:0]), // Templated
                 // Inputs
                 .bypass                ('b0),                   // Templated
                 .chaosmode             ('b0),                   // Templated
                 .umi_in_clk            (clk),                   // Templated
                 .umi_in_nreset         (nreset),                // Templated
                 .umi_in_valid          (umi_req_in_valid),      // Templated
                 .umi_in_cmd            (umi_req_in_cmd[CW-1:0]), // Templated
                 .umi_in_dstaddr        (umi_req_in_dstaddr[AW-1:0]), // Templated
                 .umi_in_srcaddr        (umi_req_in_srcaddr[AW-1:0]), // Templated
                 .umi_in_data           (umi_req_in_data[DW-1:0]), // Templated
                 .umi_out_clk           (clk),                   // Templated
                 .umi_out_nreset        (nreset),                // Templated
                 .umi_out_ready         (umi_req_out_ready),     // Templated
                 .vdd                   (),                      // Templated
                 .vss                   ());                     // Templated

   /* umi_mem_agent AUTO_TEMPLATE(
    .udev_req_\(.*\)  (umi_req_out_\1[]),
    .udev_resp_\(.*\) (umi_resp_in_\1[]),
    );*/

   umi_mem_agent #(.CW(CW),
                   .AW(AW),
                   .DW(DW))
   umi_mem_agent_i(/*AUTOINST*/
                   // Outputs
                   .udev_req_ready      (umi_req_out_ready),     // Templated
                   .udev_resp_valid     (umi_resp_in_valid),     // Templated
                   .udev_resp_cmd       (umi_resp_in_cmd[CW-1:0]), // Templated
                   .udev_resp_dstaddr   (umi_resp_in_dstaddr[AW-1:0]), // Templated
                   .udev_resp_srcaddr   (umi_resp_in_srcaddr[AW-1:0]), // Templated
                   .udev_resp_data      (umi_resp_in_data[DW-1:0]), // Templated
                   // Inputs
                   .clk                 (clk),
                   .nreset              (nreset),
                   .udev_req_valid      (umi_req_out_valid),     // Templated
                   .udev_req_cmd        (umi_req_out_cmd[CW-1:0]), // Templated
                   .udev_req_dstaddr    (umi_req_out_dstaddr[AW-1:0]), // Templated
                   .udev_req_srcaddr    (umi_req_out_srcaddr[AW-1:0]), // Templated
                   .udev_req_data       (umi_req_out_data[DW-1:0]), // Templated
                   .udev_resp_ready     (umi_resp_in_ready));    // Templated

   /* umi_fifo AUTO_TEMPLATE(
    .umi_.*_clk     (clk),
    .umi_.*_nreset  (nreset),
    .umi_in_\(.*\)  (umi_resp_in_\1[]),
    .umi_out_\(.*\) (umi_resp_out_\1[]),
    .bypass         ('b0),
    .chaosmode      ('b0),
    .v.*            (),
    .fifo_.*        (),
    );*/
   umi_fifo #(.DW(DW),
              .CW(CW),
              .AW(AW),
              .DEPTH(DEPTH))
   umi_fifo_tx_i(/*AUTOINST*/
                 // Outputs
                 .fifo_full             (),                      // Templated
                 .fifo_empty            (),                      // Templated
                 .umi_in_ready          (umi_resp_in_ready),     // Templated
                 .umi_out_valid         (umi_resp_out_valid),    // Templated
                 .umi_out_cmd           (umi_resp_out_cmd[CW-1:0]), // Templated
                 .umi_out_dstaddr       (umi_resp_out_dstaddr[AW-1:0]), // Templated
                 .umi_out_srcaddr       (umi_resp_out_srcaddr[AW-1:0]), // Templated
                 .umi_out_data          (umi_resp_out_data[DW-1:0]), // Templated
                 // Inputs
                 .bypass                ('b0),                   // Templated
                 .chaosmode             ('b0),                   // Templated
                 .umi_in_clk            (clk),                   // Templated
                 .umi_in_nreset         (nreset),                // Templated
                 .umi_in_valid          (umi_resp_in_valid),     // Templated
                 .umi_in_cmd            (umi_resp_in_cmd[CW-1:0]), // Templated
                 .umi_in_dstaddr        (umi_resp_in_dstaddr[AW-1:0]), // Templated
                 .umi_in_srcaddr        (umi_resp_in_srcaddr[AW-1:0]), // Templated
                 .umi_in_data           (umi_resp_in_data[DW-1:0]), // Templated
                 .umi_out_clk           (clk),                   // Templated
                 .umi_out_nreset        (nreset),                // Templated
                 .umi_out_ready         (umi_resp_out_ready),    // Templated
                 .vdd                   (),                      // Templated
                 .vss                   ());                     // Templated

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
      /* verilator lint_on IGNOREDRETURN */
   end

   // VCD

   initial
     begin
        nreset   = 1'b0;
     end // initial begin

   always @(negedge clk)
     begin
        nreset <= nreset | 1'b1;
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

   auto_stop_sim #(.CYCLES(50000)) auto_stop_sim_i (.clk(clk));

endmodule
// Local Variables:
// verilog-library-directories:("../rtl" "../../submodules/switchboard/examples/common/verilog/" )
// End:

`default_nettype wire
