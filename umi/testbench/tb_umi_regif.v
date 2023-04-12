
module testbench();

   localparam N          = 1;
   localparam UW         = 256;
   localparam DW         = 64;
   localparam AW         = 64;
   localparam PERIOD_CLK = 10;
   localparam RAMDEPTH   = 1024;

   reg [N-1:0] 	 udev_req_valid;
   reg [N-1:0] 	 udev_req_write;
   reg [AW-1:0]  udev_req_addr;
   reg [N-1:0] 	 udev_resp_ready;
   reg 		 nreset;
   reg 		 clk;
   wire [UW-1:0] udev_req_packet;

   // Run Sim
   initial
     begin
        $dumpfile("waveform.vcd");
        $dumpvars();
	#500
          $finish;
     end

  // Reset/init
   initial
     begin
	#(1)
	nreset   = 1'b0;
	clk      = 1'b0;
	#(PERIOD_CLK * 10)
	nreset        = 1'b1;

     end // initial begin

   // clocks
   always
     #(PERIOD_CLK/2) clk = ~clk;


   // write followed by read for alll addresses
   // ignore LSB of address
   always @ (posedge clk or negedge nreset)
     if(~nreset)
       begin
	  udev_req_valid  <= 1'b1;
	  udev_req_addr   <= 'b0;
	  udev_req_write  <= 1'b1;
	  udev_resp_ready <= 1'b1;
       end
     else if(udev_req_ready)
       begin
	  udev_req_write  <= ~udev_req_write;
	  udev_req_addr   <= udev_req_addr + 1'b1;
       end

   /*AUTOWIRE*/
   // Beginning of automatic wires (for undeclared instantiated-module outputs)
   wire [AW-1:0]	reg_addr;
   wire [7:0]		reg_cmd;
   wire			reg_read;
   wire [3:0]		reg_size;
   wire [4*DW-1:0]	reg_wrdata;
   wire			reg_write;
   wire			udev_req_ready;
   wire [UW-1:0]	udev_resp_packet;
   wire			udev_resp_valid;
   // End of automatics

   //###########################################
   // DUT
   //###########################################

   umi_pack #(.UW(UW))
   umi_pack(// Outputs
	    .packet	(udev_req_packet[UW-1:0]),
	    // Inputs
	    .write	(udev_req_write),
	    .command	(8'b0),
	    .size	(4'b0),
	    .options	(20'b0),
	    .burst	(1'b0),
	    .dstaddr	(udev_req_addr[AW-1:0]),
	    .srcaddr	({(AW){1'b0}}),
	    .data	({(4){udev_req_addr[AW-1:0]}}));

   umi_regif #(.UW(UW))
   umi_regif (/*AUTOINST*/
	      // Outputs
	      .udev_req_ready		(udev_req_ready),
	      .udev_resp_valid		(udev_resp_valid),
	      .udev_resp_packet		(udev_resp_packet[UW-1:0]),
	      .reg_addr			(reg_addr[AW-1:0]),
	      .reg_write		(reg_write),
	      .reg_read			(reg_read),
	      .reg_cmd			(reg_cmd[7:0]),
	      .reg_size			(reg_size[3:0]),
	      .reg_wrdata		(reg_wrdata[4*DW-1:0]),
	      // Inputs
	      .clk			(clk),
	      .nreset			(nreset),
	      .udev_req_valid		(udev_req_valid),
	      .udev_req_packet		(udev_req_packet[UW-1:0]),
	      .udev_resp_ready		(udev_resp_ready),
	      .reg_rddata		(reg_rddata[DW-1:0]));


   reg [DW-1:0] 	ram [1023:0];
   reg [DW-1:0] 	reg_rddata;

   // Dummy RAM
   always @(posedge clk)
     if (reg_write)
       ram[reg_addr[$clog2(RAMDEPTH)-1:1]] <= reg_wrdata[DW-1:0];

   always @ (posedge clk)
     if(reg_read)
       reg_rddata[DW-1:0] <= ram[reg_addr[$clog2(RAMDEPTH)-1:1]];

endmodule
// Local Variables:
// verilog-library-directories:("." "../rtl")
// End:
