
module testbench();

   localparam N          = 2;
   localparam UW         = 16;
   localparam PERIOD_CLK = 10;

   reg [N*UW-1:0] umi_in_packet;
   reg [N*N-1:0]  umi_in_request;
   reg [N-1:0] 	  umi_out_ready;
   reg 		  nreset;
   reg 		  clk;

  // reset initialization
   initial
     begin
	#(1)
	nreset   = 1'b0;
	clk      = 1'b0;
	#(PERIOD_CLK * 10)
	nreset   = 1'b1;
	umi_in_packet[0*UW+:UW] = {(UW/4){4'hA}};
	umi_in_packet[1*UW+:UW] = {(UW/4){4'hB}};
     end // initial begin

   // clocks
   always
     #(PERIOD_CLK/2) clk = ~clk;

   // test vectors


   always @ (posedge clk or negedge nreset)
     if(~nreset)
       begin
	  umi_out_ready  <='b0;
	  umi_in_request <='b0;
       end
     else
       begin
	  umi_out_ready  <= umi_out_ready+1'b1;
	  umi_in_request <= umi_in_request+1'b1;
       end
     initial
       begin
          $dumpfile("waveform.vcd");
          $dumpvars();
	  #500
          $finish;
       end

   /*AUTOWIRE*/
   // Beginning of automatic wires (for undeclared instantiated-module outputs)
   wire [N-1:0]		umi_in_ready;		// From umi_crossbar of umi_crossbar.v
   wire [N*UW-1:0]	umi_out_packet;		// From umi_crossbar of umi_crossbar.v
   wire [N-1:0]		umi_out_valid;		// From umi_crossbar of umi_crossbar.v
   // End of automatics

   umi_crossbar #(.N(N),
		  .UW(UW))
   umi_crossbar  (.mode			(2'b00),
		 /*AUTOINST*/
		  // Outputs
		  .umi_in_ready		(umi_in_ready[N-1:0]),
		  .umi_out_valid	(umi_out_valid[N-1:0]),
		  .umi_out_packet	(umi_out_packet[N*UW-1:0]),
		  // Inputs
		  .clk			(clk),
		  .nreset		(nreset),
		  .umi_in_request	(umi_in_request[N*N-1:0]),
		  .umi_in_packet	(umi_in_packet[N*UW-1:0]),
		  .umi_out_ready	(umi_out_ready[N-1:0]));


endmodule
// Local Variables:
// verilog-library-directories:("." "../rtl")
// End:
