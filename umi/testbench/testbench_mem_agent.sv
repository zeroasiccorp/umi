`default_nettype none

module testbench (
                  input clk
                  );

   parameter integer RW=32;
   parameter integer DW=128;
   parameter integer AW=64;
   parameter integer CW=32;
   parameter integer RAMDEPTH=512;


   /*AUTOWIRE*/
   reg                  nreset;
   reg                  go;

   wire                 udev_resp_ready;
   wire [CW-1:0]        udev_resp_cmd;
   wire [DW-1:0]        udev_resp_data;
   wire [AW-1:0]        udev_resp_dstaddr;
   wire [AW-1:0]        udev_resp_srcaddr;
   wire                 udev_resp_valid;

   wire                 udev_req_ready;
   wire [CW-1:0]        udev_req_cmd;
   wire [DW-1:0]        udev_req_data;
   wire [AW-1:0]        udev_req_dstaddr;
   wire [AW-1:0]        udev_req_srcaddr;
   wire                 udev_req_valid;

   ///////////////////////////////////////////
   // Host side umi agents
   ///////////////////////////////////////////

   umi_rx_sim #(.VALID_MODE_DEFAULT(2),
                .DW(DW)
                )
   host_umi_rx_i (.clk(clk),
                  .data(udev_req_data[DW-1:0]),
                  .srcaddr(udev_req_srcaddr[AW-1:0]),
                  .dstaddr(udev_req_dstaddr[AW-1:0]),
                  .cmd(udev_req_cmd[CW-1:0]),
                  .ready(udev_req_ready),
                  .valid(udev_req_valid)
                  );

   umi_tx_sim #(.READY_MODE_DEFAULT(2),
                .DW(DW)
                )
   host_umi_tx_i (.clk(clk),
                  .data(udev_resp_data[DW-1:0]),
                  .srcaddr(udev_resp_srcaddr[AW-1:0]),
                  .dstaddr(udev_resp_dstaddr[AW-1:0]),
                  .cmd(udev_resp_cmd[CW-1:0]),
                  .ready(udev_resp_ready),
                  .valid(udev_resp_valid)
                  );

   // instantiate dut with UMI ports
   /* umi_mem_agent AUTO_TEMPLATE(
    );*/
   umi_mem_agent #(.CW(CW),
                   .AW(AW),
                   .DW(DW),
                   .RAMDEPTH(RAMDEPTH))
   umi_mem_agent_i(/*AUTOINST*/
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
