
module testbench();

   localparam N          = 2;
   localparam DW         = 16;
   localparam AW         = 64;
   localparam CW         = 32;
   localparam PERIOD_CLK = 10;

   reg [N*CW-1:0] umi_in_cmd;
   reg [N*AW-1:0] umi_in_dstaddr;
   reg [N*AW-1:0] umi_in_srcaddr;
   reg [N*DW-1:0] umi_in_data;
   reg [N*N-1:0]  umi_in_request;
   reg [N*N-1:0]  mask;
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
        mask = {N*N{1'b0}};
        umi_in_data[0*DW+:DW] = {(DW/4){4'hA}};
	umi_in_data[1*DW+:DW] = {(DW/4){4'hB}};
        umi_in_cmd[CW-1:0] = 'b0;
        umi_in_dstaddr[AW-1:0] = 'b0;
        umi_in_srcaddr[AW-1:0] = 'b0;
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
   wire [N-1:0]         umi_in_ready;
   wire [N*CW-1:0]      umi_out_cmd;
   wire [N*DW-1:0]      umi_out_data;
   wire [N*AW-1:0]      umi_out_dstaddr;
   wire [N*AW-1:0]      umi_out_srcaddr;
   wire [N-1:0]         umi_out_valid;
   // End of automatics

   umi_crossbar #(.N(N),
                  .CW(CW),
                  .AW(AW),
		  .DW(DW))
   umi_crossbar  (.mode			(2'b00),
		  /*AUTOINST*/
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
                  .mask                 (mask[N*N-1:0]),
                  .umi_in_request       (umi_in_request[N*N-1:0]),
                  .umi_in_cmd           (umi_in_cmd[N*CW-1:0]),
                  .umi_in_dstaddr       (umi_in_dstaddr[N*AW-1:0]),
                  .umi_in_srcaddr       (umi_in_srcaddr[N*AW-1:0]),
                  .umi_in_data          (umi_in_data[N*DW-1:0]),
                  .umi_out_ready        (umi_out_ready[N-1:0]));


endmodule
// Local Variables:
// verilog-library-directories:("." "../rtl")
// End:
