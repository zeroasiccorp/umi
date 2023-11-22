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

module tb_umi_fifo
  #(parameter TARGET     = "DEFAULT",   // pass through variable for hard macro
    parameter TIMEOUT    = 5000,        // timeout value (cycles)
    parameter PERIOD_CLK = 10,          // clock period
    parameter FIFODEPTH  = 4,           // fifo depth
    parameter CW         = 32,          // UMI width
    parameter AW         = 64,          // UMI width
    parameter DW         = 512          // UMI width
    )
   ();

   //####################
   // LOCAL PARAMS
   //####################

   localparam STIMDEPTH = 1024;
   localparam NUMI      = 1;
   localparam TCW       = 8;

   //#####################
   //# SIMCTRL
   //#####################
   reg umi_dut2check_ready;

   reg [128*8-1:0] memhfile;
   reg             slowclk;
   reg             clk;
   reg             load;
   reg             nreset;
   reg             dut_nreset;
   reg             go;
   integer         r;

   // reset initialization
   initial
     begin
        #(1)
        nreset   = 1'b0;
        dut_nreset = 1'b0;
        clk      = 1'b0;
        load     = 1'b0;
        go       = 1'b0;
        #(PERIOD_CLK)
        go       = 1'b1;
        nreset   = 1'b1;
        #(PERIOD_CLK * 10)
        dut_nreset   = 1'b1;
//      #(PERIOD_CLK * 10)
//      go       = 1'b1;
     end // initial begin

   // clocks
   always
     #(PERIOD_CLK/2) clk = ~clk;

   // control block
   initial
     begin
        r = $value$plusargs("MEMHFILE=%s", memhfile);
        $readmemh(memhfile, umi_stimulus.ram);
        $timeformat(-9, 0, " ns", 20);
        $dumpfile("waveform.vcd");
        $dumpvars();
        #(TIMEOUT)
        $finish;
     end

   always @ (posedge slowclk or negedge nreset)
     if(~nreset)
       umi_dut2check_ready <= 1'b0;
     else
       umi_dut2check_ready <= ~umi_dut2check_ready;

   // clock divider
   always @ (posedge clk or negedge nreset)
     if (~nreset)
       slowclk <= 1'b0;
     else
       slowclk <= ~slowclk;

   la_rsync la_rsync (// Outputs
                      .nrst_out         (slownreset),
                      // Inputs
                      .clk              (slowclk),
                      .nrst_in          (nreset));


   /*AUTOWIRE*/
   // Beginning of automatic wires (for undeclared instantiated-module outputs)
   wire                 done;
   wire                 error;
   wire [NUMI*CW-1:0]   umi_dut2check_cmd;
   wire [NUMI*DW-1:0]   umi_dut2check_data;
   wire [NUMI*AW-1:0]   umi_dut2check_dstaddr;
   wire [NUMI*AW-1:0]   umi_dut2check_srcaddr;
   wire [NUMI-1:0]      umi_dut2check_valid;
   wire [CW-1:0]        umi_stim2dut_cmd;
   wire [DW-1:0]        umi_stim2dut_data;
   wire                 umi_stim2dut_done;
   wire [AW-1:0]        umi_stim2dut_dstaddr;
   wire [NUMI-1:0]      umi_stim2dut_ready;
   wire [AW-1:0]        umi_stim2dut_srcaddr;
   wire                 umi_stim2dut_valid;
   // End of automatics

   //################################################
   //# DUT
   //#################################################

   /*dut_umi_fifo AUTO_TEMPLATE (
    .clk                (clk),
    .ctrl               (1'b0),
    .status             (),
    .umi_out_clk        (slowclk),
    .umi_out_nreset     (slownreset),
    .umi_out_ready      (1'b1),
    .umi_out_\(.*\)     (umi_dut2check_\1[]),
    .umi_in_clk         (clk),
    .umi_in_nreset      (nreset),
    .umi_in_valid       (umi_stim2dut_valid),
    .umi_in_\(.*\)      (umi_stim2dut_\1[]),
    );
    */

   dut_umi_fifo #(.CW(CW),
                  .AW(AW),
                  .DW(DW),
                  .DEPTH(FIFODEPTH))
   dut_umi_fifo (.umi_out_ready         (umi_dut2check_ready),
                 /*AUTOINST*/
                 // Outputs
                 .error                 (error),
                 .done                  (done),
                 .status                (),                      // Templated
                 .umi_in_ready          (umi_stim2dut_ready[NUMI-1:0]), // Templated
                 .umi_out_valid         (umi_dut2check_valid[NUMI-1:0]), // Templated
                 .umi_out_cmd           (umi_dut2check_cmd[NUMI*CW-1:0]), // Templated
                 .umi_out_dstaddr       (umi_dut2check_dstaddr[NUMI*AW-1:0]), // Templated
                 .umi_out_srcaddr       (umi_dut2check_srcaddr[NUMI*AW-1:0]), // Templated
                 .umi_out_data          (umi_dut2check_data[NUMI*DW-1:0]), // Templated
                 // Inputs
                 .nreset                (dut_nreset),
                 .clk                   (clk),                   // Templated
                 .go                    (go),
                 .ctrl                  (1'b0),                  // Templated
                 .umi_in_clk            (clk),                   // Templated
                 .umi_in_nreset         (dut_nreset),                // Templated
                 .umi_in_valid          (umi_stim2dut_valid),    // Templated
                 .umi_in_cmd            (umi_stim2dut_cmd[NUMI*CW-1:0]), // Templated
                 .umi_in_dstaddr        (umi_stim2dut_dstaddr[NUMI*AW-1:0]), // Templated
                 .umi_in_srcaddr        (umi_stim2dut_srcaddr[NUMI*AW-1:0]), // Templated
                 .umi_in_data           (umi_stim2dut_data[NUMI*DW-1:0]), // Templated
                 .umi_out_clk           (slowclk),               // Templated
                 .umi_out_nreset        (slownreset));           // Templated

   //##################################################
   //# UMI STIMULUS DRIVER (CLK)
   //##################################################

   /*umi_stimulus AUTO_TEMPLATE (
    // Outputs
    .stim_\(.*\)        (umi_stim2dut_\1[]),
    .dut_ready          (umi_stim2dut_ready),
    .ext_valid          (1'b0),
    .ext_packet         ({(DW+AW+AW+CW+TCW){1'b0}}),
    .\(.*\)_clk         (clk),
    );
    */

   umi_stimulus #(.DEPTH(STIMDEPTH),
                  .TARGET(TARGET),
                  .CW(CW),
                  .AW(AW),
                  .DW(DW),
                  .TCW(TCW))
   umi_stimulus (/*AUTOINST*/
                 // Outputs
                 .stim_valid            (umi_stim2dut_valid),    // Templated
                 .stim_cmd              (umi_stim2dut_cmd[CW-1:0]), // Templated
                 .stim_dstaddr          (umi_stim2dut_dstaddr[AW-1:0]), // Templated
                 .stim_srcaddr          (umi_stim2dut_srcaddr[AW-1:0]), // Templated
                 .stim_data             (umi_stim2dut_data[DW-1:0]), // Templated
                 .stim_done             (umi_stim2dut_done),     // Templated
                 // Inputs
                 .nreset                (nreset),
                 .load                  (load),
                 .go                    (go),
                 .ext_clk               (clk),                   // Templated
                 .ext_valid             (1'b0),                  // Templated
                 .ext_packet            ({(DW+AW+AW+CW+TCW){1'b0}}), // Templated
                 .dut_clk               (clk),                   // Templated
                 .dut_ready             (umi_stim2dut_ready));   // Templated

   //###################################################
   //# TRAFFIC MONITOR (SLOWCLK)
   //###################################################

   always @ (negedge slowclk)
     if(umi_dut2check_valid & umi_dut2check_ready)
       $display("dut result: data=%h, srcaddr=%h, dstaddr=%h, cmd=%h", umi_dut2check_data[DW-1:0], umi_dut2check_srcaddr[AW-1:0],umi_dut2check_dstaddr[AW-1:0],umi_dut2check_cmd[CW-1:0]);


endmodule // testbench
// Local Variables:
// verilog-library-directories:("." "../rtl" "../../submodules/oh/stdlib/rtl/" "../../submodules/oh/stdlib/testbench/")
// End:
