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
