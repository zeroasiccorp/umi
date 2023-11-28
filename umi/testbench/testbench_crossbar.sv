/*******************************************************************************
 * Copyright 2020 Zero ASIC Corporation
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
 * - Simple umi crossbar testbench
 *
 ******************************************************************************/

module testbench
  #(parameter PORTS=4,
    parameter RW=32,
    parameter DW=512,
    parameter AW=64,
    parameter CW=32)
   (
    input clk
    );

   localparam N = PORTS;

   /*AUTOWIRE*/
   reg               nreset;
   wire [N*N-1:0]    umi_in_request;

   wire [N-1:0]      umi_in_valid;
   wire [N-1:0]      umi_in_ready;
   wire [N*CW-1:0]   umi_in_cmd;
   wire [N*DW-1:0]   umi_in_data;
   wire [N*AW-1:0]   umi_in_dstaddr;
   wire [N*AW-1:0]   umi_in_srcaddr;

   wire [N-1:0]      umi_out_valid;
   wire [N-1:0]      umi_out_ready;
   wire [N*CW-1:0]   umi_out_cmd;
   wire [N*DW-1:0]   umi_out_data;
   wire [N*AW-1:0]   umi_out_dstaddr;
   wire [N*AW-1:0]   umi_out_srcaddr;

   ///////////////////////////////////////////
   // Host side umi agents
   ///////////////////////////////////////////

   genvar            i,j;
   generate
      for(i=0;i<N;i=i+1)
        begin: portif
           umi_rx_sim #(.VALID_MODE_DEFAULT(2),
                        .DW(256))
           umi_rx_i (.clk(clk),
                     .data(umi_in_data[i*DW+:256]),
                     .srcaddr(umi_in_srcaddr[i*AW+:AW]),
                     .dstaddr(umi_in_dstaddr[i*AW+:AW]),
                     .cmd(umi_in_cmd[i*CW+:CW]),
                     .ready(umi_in_ready[i]),
                     .valid(umi_in_valid[i]));

           assign umi_in_data[i*DW+256+:256] = 'h0;

           for (j=0;j<N;j=j+1)
             begin: request
                assign umi_in_request[j*N + i] = umi_in_valid[i] &
                                                 (umi_in_dstaddr[i*AW+40+:16] == j);
             end

           umi_tx_sim #(.READY_MODE_DEFAULT(2),
                        .DW(256))
           umi_tx_i (.clk(clk),
                     .data(umi_out_data[i*DW+:256]),
                     .srcaddr(umi_out_srcaddr[i*AW+:AW]),
                     .dstaddr(umi_out_dstaddr[i*AW+:AW]),
                     .cmd(umi_out_cmd[i*CW+:CW]),
                     .ready(umi_out_ready[i]),
                     .valid(umi_out_valid[i])
                     );
        end
   endgenerate

   // instantiate dut with UMI ports
   /* umi_crossbar AUTO_TEMPLATE(
    .mode (2'b10),
    .mask ({@"vl-width"{1'b0}}),
    );*/
   umi_crossbar #(.CW(CW),
                  .AW(AW),
                  .DW(DW),
                  .N(N))
   umi_crossbar_i(/*AUTOINST*/
                  // Outputs
                  .umi_in_ready         (umi_in_ready[N-1:0]),
                  .umi_out_valid        (umi_out_valid[N-1:0]),
                  .umi_out_cmd          (umi_out_cmd[N*CW-1:0]),
                  .umi_out_dstaddr      (umi_out_dstaddr[N*AW-1:0]),
                  .umi_out_srcaddr      (umi_out_srcaddr[N*AW-1:0]),
                  .umi_out_data         (umi_out_data[N*DW-1:0]),
                  // Inputs
                  .clk                  (clk),
                  .nreset               (nreset),
                  .mode                 (2'b10),                 // Templated
                  .mask                 ({(1+(N*N-1)){1'b0}}),   // Templated
                  .umi_in_request       (umi_in_request[N*N-1:0]),
                  .umi_in_cmd           (umi_in_cmd[N*CW-1:0]),
                  .umi_in_dstaddr       (umi_in_dstaddr[N*AW-1:0]),
                  .umi_in_srcaddr       (umi_in_srcaddr[N*AW-1:0]),
                  .umi_in_data          (umi_in_data[N*DW-1:0]),
                  .umi_out_ready        (umi_out_ready[N-1:0]));

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
      /* verilator lint_on IGNOREDRETURN */
   end

   // This should be made into a loop in order to support any number of ports but
   // that currently does not work in Verilator
   initial
     begin
        portif[0].umi_rx_i.init("client2rtl_0.q");
        portif[0].umi_rx_i.set_valid_mode(valid_mode);
        portif[0].umi_tx_i.init("rtl2client_0.q");
        portif[0].umi_tx_i.set_ready_mode(ready_mode);

        portif[1].umi_rx_i.init("client2rtl_1.q");
        portif[1].umi_rx_i.set_valid_mode(valid_mode);
        portif[1].umi_tx_i.init("rtl2client_1.q");
        portif[1].umi_tx_i.set_ready_mode(ready_mode);

        portif[2].umi_rx_i.init("client2rtl_2.q");
        portif[2].umi_rx_i.set_valid_mode(valid_mode);
        portif[2].umi_tx_i.init("rtl2client_2.q");
        portif[2].umi_tx_i.set_ready_mode(ready_mode);

        portif[3].umi_rx_i.init("client2rtl_3.q");
        portif[3].umi_rx_i.set_valid_mode(valid_mode);
        portif[3].umi_tx_i.init("rtl2client_3.q");
        portif[3].umi_tx_i.set_ready_mode(ready_mode);
     end

   // VCD

   initial
     begin
        nreset   = 1'b0;
     end // initial begin

   // Bring up reset and the go signal on the first clock cycle
   always @(negedge clk)
     begin
        nreset <= nreset | 1'b1;
     end

   // control block
   initial
     begin
        if ($test$plusargs("trace"))
          begin
             $dumpfile("testbench.fst");
             $dumpvars(0, testbench);
          end
     end

   // auto-stop

   auto_stop_sim auto_stop_sim_i (.clk(clk));

endmodule
// Local Variables:
// verilog-library-directories:("../rtl" "../../submodules/switchboard/examples/common/verilog/" "../../submodules/lambdalib/ramlib/rtl/")
// End:
