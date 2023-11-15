/*******************************************************************************
 * Function:  umi arbiter testbench
 * Author:    Andreas Olofsson
 *
 * Copyright (c) 2023 Zero ASIC Corporation
 * This code is licensed under Apache License 2.0 (see LICENSE for details)
 *
 * Documentation:
 *
 ******************************************************************************/

module testbench();

   localparam N=4;
   localparam PERIOD_CLK = 10;

   reg [N-1:0] requests;
   reg         nreset;
   reg         clk;

  // reset initialization
   initial
     begin
        #(1)
        nreset   = 1'b0;
        clk      = 1'b0;
        #(PERIOD_CLK * 10)
        nreset   = 1'b1;
     end // initial begin

   // clocks
   always
     #(PERIOD_CLK/2) clk = ~clk;


   always @ (posedge clk or negedge nreset)
     if(~nreset)
       requests <= 'b0;
     else
       requests <= requests+1'b1;

     initial
       begin
          $dumpfile("waveform.vcd");
          $dumpvars();
          #500
          $finish;
       end

   /*AUTOWIRE*/
   // Beginning of automatic wires (for undeclared instantiated-module outputs)
   wire [N-1:0]         grants;
   // End of automatics

   umi_arbiter #(.N(N))
   umi_arbiter  (.mode                  (2'b00),
                 .mask                  ({(N){1'b0}}),
                 /*AUTOINST*/
                 // Outputs
                 .grants                (grants[N-1:0]),
                 // Inputs
                 .clk                   (clk),
                 .nreset                (nreset),
                 .requests              (requests[N-1:0]));


endmodule
// Local Variables:
// verilog-library-directories:("." "../rtl")
// End:
