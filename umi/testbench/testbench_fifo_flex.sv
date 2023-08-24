`default_nettype none

module testbench (
                  input clk
                  );

   parameter integer IDW=128;
   parameter integer ODW=32;
   parameter integer AW=64;
   parameter integer CW=32;
   parameter integer DEPTH=512;
   parameter integer SPLIT=0;
   parameter integer BYPASS=1;

   /*AUTOWIRE*/
   // Beginning of automatic wires (for undeclared instantiated-module outputs)
   wire                 fifo_empty;
   wire                 fifo_full;
   // End of automatics
   reg                  nreset;

   wire                 umi_out_ready;
   wire [CW-1:0]        umi_out_cmd;
   wire [ODW-1:0]       umi_out_data;
   wire [AW-1:0]        umi_out_dstaddr;
   wire [AW-1:0]        umi_out_srcaddr;
   wire                 umi_out_valid;

   wire                 umi_in_ready;
   wire [CW-1:0]        umi_in_cmd;
   wire [IDW-1:0]       umi_in_data;
   wire [AW-1:0]        umi_in_dstaddr;
   wire [AW-1:0]        umi_in_srcaddr;
   wire                 umi_in_valid;

   ///////////////////////////////////////////
   // Host side umi agents
   ///////////////////////////////////////////

   umi_rx_sim #(.VALID_MODE_DEFAULT(2),
                .DW(IDW)
                )
   host_umi_rx_i (.clk(clk),
                  .data(umi_in_data[IDW-1:0]),
                  .srcaddr(umi_in_srcaddr[AW-1:0]),
                  .dstaddr(umi_in_dstaddr[AW-1:0]),
                  .cmd(umi_in_cmd[CW-1:0]),
                  .ready(umi_in_ready),
                  .valid(umi_in_valid)
                  );

   umi_tx_sim #(.READY_MODE_DEFAULT(2),
                .DW(ODW)
                )
   host_umi_tx_i (.clk(clk),
                  .data(umi_out_data[ODW-1:0]),
                  .srcaddr(umi_out_srcaddr[AW-1:0]),
                  .dstaddr(umi_out_dstaddr[AW-1:0]),
                  .cmd(umi_out_cmd[CW-1:0]),
                  .ready(umi_out_ready),
                  .valid(umi_out_valid)
                  );

   wire bypass = 1'b1;
   wire chaosmode = 0;

   // instantiate dut with UMI ports
   /* umi_fifo_flex AUTO_TEMPLATE(
    .umi_.*_clk    (clk),
    .umi_.*_nreset (nreset),
    .v.*           (),
    );*/
   umi_fifo_flex #(.BYPASS(BYPASS),
                   .SPLIT(SPLIT),
                   .IDW(IDW),
                   .ODW(ODW),
                   .CW(CW),
                   .AW(AW),
                   .DEPTH(DEPTH))
   umi_fifo_flex_i(/*AUTOINST*/
                   // Outputs
                   .fifo_full           (fifo_full),
                   .fifo_empty          (fifo_empty),
                   .umi_in_ready        (umi_in_ready),
                   .umi_out_valid       (umi_out_valid),
                   .umi_out_cmd         (umi_out_cmd[CW-1:0]),
                   .umi_out_dstaddr     (umi_out_dstaddr[AW-1:0]),
                   .umi_out_srcaddr     (umi_out_srcaddr[AW-1:0]),
                   .umi_out_data        (umi_out_data[ODW-1:0]),
                   // Inputs
                   .bypass              (bypass),
                   .chaosmode           (chaosmode),
                   .umi_in_clk          (clk),                   // Templated
                   .umi_in_nreset       (nreset),                // Templated
                   .umi_in_valid        (umi_in_valid),
                   .umi_in_cmd          (umi_in_cmd[CW-1:0]),
                   .umi_in_dstaddr      (umi_in_dstaddr[AW-1:0]),
                   .umi_in_srcaddr      (umi_in_srcaddr[AW-1:0]),
                   .umi_in_data         (umi_in_data[IDW-1:0]),
                   .umi_out_clk         (clk),                   // Templated
                   .umi_out_nreset      (nreset),                // Templated
                   .umi_out_ready       (umi_out_ready),
                   .vdd                 (),                      // Templated
                   .vss                 ());                     // Templated

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
