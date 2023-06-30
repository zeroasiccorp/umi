/*******************************************************************************
 * Function:  UMI FIFO with width change
 * Author:    Amir Volk
 * License:   (c) 2023 Zero ASIC Corporation
 *
 * Documentation:
 * This block converts UMI transations between diffent width options
 * Ver 1 - only split large width to small, no merge small->large
 *
 ******************************************************************************/
module umi_fifo_width
  #(parameter TARGET = "DEFAULT", // implementation target
    parameter DEPTH = 4,          // FIFO depth
    parameter CW = 32,            // UMI width
    parameter IAW = 64,           // input UMI AW
    parameter OAW = 64,           // output UMI AW
    parameter IDW = 512,          // input UMI DW
    parameter ODW = 512           // input UMI DW
    )
   (// control/status signals
    input            bypass,       // bypass FIFO
    input            chaosmode,    // enable "random" fifo pushback
    output           fifo_full,
    output           fifo_empty,
    // Input
    input            umi_in_clk,
    input            umi_in_nreset,
    input            umi_in_valid, //per byte valid signal
    input [CW-1:0]   umi_in_cmd,
    input [IAW-1:0]  umi_in_dstaddr,
    input [IAW-1:0]  umi_in_srcaddr,
    input [IDW-1:0]  umi_in_data,
    output           umi_in_ready,
    // Output
    input            umi_out_clk,
    input            umi_out_nreset,
    output           umi_out_valid,
    output [CW-1:0]  umi_out_cmd,
    output [OAW-1:0] umi_out_dstaddr,
    output [OAW-1:0] umi_out_srcaddr,
    output [ODW-1:0] umi_out_data,
    input            umi_out_ready,
    // Supplies
    input            vdd,
    input            vss
    );

   // Local FIFO
   wire [ODW+OAW+OAW+CW-1:0] fifo_dout;
   wire [ODW+OAW+OAW+CW-1:0] fifo_din;
   reg                       packet_latch_valid;
   reg [CW-1:0]              packet_cmd_latch;
   reg [IAW-1:0]             packet_dstaddr_latch;
   reg [IAW-1:0]             packet_srcaddr_latch;
   reg [IDW-1:0]             packet_data_latch;
   wire [CW-1:0]             packet_cmd;
   wire [IAW-1:0]            packet_dstaddr;
   wire [IAW-1:0]            packet_srcaddr;
   wire [IDW-1:0]            packet_data;

   // local wires
   wire                      umi_out_beat;
   wire                      fifo_read;
   wire                      fifo_write;
   wire                      fifo_in_ready;
   wire [7:0]                fifo_len;
   wire [7:0]                latch_len;
   reg                       last_sent;
   wire [8:0]                cmd_len_plus_one;

   /*AUTOWIRE*/
   // Beginning of automatic wires (for undeclared instantiated-module outputs)
   wire [7:0]           cmd_atype;
   wire                 cmd_eof;
   wire                 cmd_eom;
   wire [1:0]           cmd_err;
   wire                 cmd_ex;
   wire [4:0]           cmd_hostid;
   wire [7:0]           cmd_len;
   wire [4:0]           cmd_opcode;
   wire [1:0]           cmd_prot;
   wire [3:0]           cmd_qos;
   wire [2:0]           cmd_size;
   wire [1:0]           cmd_user;
   wire [18:0]          cmd_user_extended;
   wire [CW-1:0]        fifo_cmd;
   wire [CW-1:0]        latch_cmd;
   // End of automatics

   //#################################
   // Packet manipulation
   //#################################
   assign packet_cmd[CW-1:0] = packet_latch_valid ?
                               packet_cmd_latch[CW-1:0] :
                               umi_in_cmd[CW-1:0] & {CW{umi_in_valid}};

   umi_unpack #(.CW(CW))
   umi_unpack_i(/*AUTOINST*/
                // Outputs
                .cmd_opcode     (cmd_opcode[4:0]),
                .cmd_size       (cmd_size[2:0]),
                .cmd_len        (cmd_len[7:0]),
                .cmd_atype      (cmd_atype[7:0]),
                .cmd_qos        (cmd_qos[3:0]),
                .cmd_prot       (cmd_prot[1:0]),
                .cmd_eom        (cmd_eom),
                .cmd_eof        (cmd_eof),
                .cmd_ex         (cmd_ex),
                .cmd_user       (cmd_user[1:0]),
                .cmd_user_extended(cmd_user_extended[18:0]),
                .cmd_err        (cmd_err[1:0]),
                .cmd_hostid     (cmd_hostid[4:0]),
                // Inputs
                .packet_cmd     (packet_cmd[CW-1:0]));

   // Valid will be set when the current command (from latch or new) is bigger than the output bus
   assign cmd_len_plus_one[8:0] = cmd_len[7:0] + 8'h01;

   always @(posedge umi_in_clk or negedge umi_in_nreset)
     if (~umi_in_nreset)
       packet_latch_valid <= 1'b0;
     else
       packet_latch_valid <= fifo_write & (cmd_len_plus_one[8:0] > (ODW >> cmd_size >> 3));

   // Packet latch
   always @(posedge umi_in_clk or negedge umi_in_nreset)
     if (~umi_in_nreset)
       begin
          packet_dstaddr_latch <= {IAW{1'b0}};
          packet_srcaddr_latch <= {IAW{1'b0}};
       end
     else if (~packet_latch_valid & fifo_write)
       begin
          packet_dstaddr_latch <= umi_in_dstaddr;
          packet_srcaddr_latch <= umi_in_srcaddr;
       end

   assign packet_dstaddr = packet_latch_valid ? packet_dstaddr_latch : umi_in_dstaddr;
   assign packet_srcaddr = packet_latch_valid ? packet_srcaddr_latch : umi_in_srcaddr;

   // cmd manipulation - at each cycle need to remove the bytes sent out
   assign latch_len[7:0] = (cmd_len_plus_one[8:0] >= (ODW >> cmd_size >> 3)) ?
                           (cmd_len_plus_one[8:0] - (ODW >> cmd_size >> 3) - 1'b1) :
                           cmd_len[7:0];

   /* umi_pack AUTO_TEMPLATE(
    .packet_cmd (latch_cmd[]),
    .cmd_len    (latch_len),
    );*/

   umi_pack #(.CW(CW))
   umi_pack_latch(/*AUTOINST*/
                  // Outputs
                  .packet_cmd           (latch_cmd[CW-1:0]),     // Templated
                  // Inputs
                  .cmd_opcode           (cmd_opcode[4:0]),
                  .cmd_size             (cmd_size[2:0]),
                  .cmd_len              (latch_len),             // Templated
                  .cmd_atype            (cmd_atype[7:0]),
                  .cmd_prot             (cmd_prot[1:0]),
                  .cmd_qos              (cmd_qos[3:0]),
                  .cmd_eom              (cmd_eom),
                  .cmd_eof              (cmd_eof),
                  .cmd_user             (cmd_user[1:0]),
                  .cmd_err              (cmd_err[1:0]),
                  .cmd_ex               (cmd_ex),
                  .cmd_hostid           (cmd_hostid[4:0]),
                  .cmd_user_extended    (cmd_user_extended[18:0]));

   always @(posedge umi_in_clk or negedge umi_in_nreset)
     if (~umi_in_nreset)
       packet_cmd_latch <= {CW{1'b0}};
     else if (fifo_write)
       packet_cmd_latch <= latch_cmd;

   assign packet_data = packet_latch_valid ? packet_data_latch : umi_in_data;

   always @(posedge umi_in_clk or negedge umi_in_nreset)
     if (~umi_in_nreset)
       packet_data_latch <= {IDW{1'b0}};
     else if (fifo_write)
       packet_data_latch <= packet_data >> ODW;

   //#################################
   // UMI Control Logic
   //#################################

   // cmd manipulation - at each cycle need to remove the bytes sent out
   assign fifo_len[7:0] = (cmd_len_plus_one[8:0] >= (ODW >> cmd_size >> 3)) ?
                          ((ODW >> cmd_size >> 3) - 1'b1) :
                          cmd_len[7:0];

   /* umi_pack AUTO_TEMPLATE(
    .packet_cmd (fifo_cmd[]),
    .cmd_len    (fifo_len),
    );*/

   umi_pack #(.CW(CW))
   umi_pack_fifo(/*AUTOINST*/
                 // Outputs
                 .packet_cmd            (fifo_cmd[CW-1:0]),      // Templated
                 // Inputs
                 .cmd_opcode            (cmd_opcode[4:0]),
                 .cmd_size              (cmd_size[2:0]),
                 .cmd_len               (fifo_len),              // Templated
                 .cmd_atype             (cmd_atype[7:0]),
                 .cmd_prot              (cmd_prot[1:0]),
                 .cmd_qos               (cmd_qos[3:0]),
                 .cmd_eom               (cmd_eom),
                 .cmd_eof               (cmd_eof),
                 .cmd_user              (cmd_user[1:0]),
                 .cmd_err               (cmd_err[1:0]),
                 .cmd_ex                (cmd_ex),
                 .cmd_hostid            (cmd_hostid[4:0]),
                 .cmd_user_extended     (cmd_user_extended[18:0]));

   // Read FIFO when ready (blocked inside fifo when empty)
   assign fifo_read = ~fifo_empty & umi_out_ready;

   // Write fifo when high (blocked inside fifo when full)
   assign fifo_write = ~fifo_full & (umi_in_valid | packet_latch_valid);

   // FIFO pushback
   assign fifo_in_ready = ~fifo_full & ~packet_latch_valid;

   assign fifo_din[OAW+OAW+CW+:ODW] = packet_data[ODW-1:0];
   assign fifo_din[OAW+CW+:OAW]     = packet_srcaddr[OAW-1:0];
   assign fifo_din[CW+:OAW]         = packet_dstaddr[OAW-1:0];
   assign fifo_din[0+:CW]           = fifo_cmd[CW-1:0];

   //#################################
   // Standard Dual Clock FIFO
   //#################################

   la_asyncfifo  #(.DW(CW+OAW+OAW+ODW),
		   .DEPTH(DEPTH))
   fifo  (// Outputs
	  .wr_full	(fifo_full),
	  .rd_dout	(fifo_dout[ODW+OAW+OAW+CW-1:0]),
	  .rd_empty	(fifo_empty),
	  // Inputs
	  .wr_clk	(umi_in_clk),
	  .wr_nreset	(umi_in_nreset),
	  .wr_din	(fifo_din[ODW+OAW+OAW+CW-1:0]),
	  .wr_en	(umi_in_valid | packet_latch_valid),
	  .wr_chaosmode (chaosmode),
	  .rd_clk	(umi_out_clk),
	  .rd_nreset	(umi_out_nreset),
	  .rd_en	(fifo_read),
	  .vss		(vss),
	  .vdd		(vdd),
	  .ctrl		(1'b0),
	  .test		(1'b0));

   //#################################
   // FIFO Bypass
   //#################################

   assign umi_out_cmd[CW-1:0]      = bypass ? umi_in_cmd[CW-1:0]      : fifo_dout[CW-1:0];
   assign umi_out_dstaddr[OAW-1:0] = bypass ? umi_in_dstaddr[OAW-1:0] : fifo_dout[CW+:OAW];
   assign umi_out_srcaddr[OAW-1:0] = bypass ? umi_in_srcaddr[OAW-1:0] : fifo_dout[CW+OAW+:OAW];
   assign umi_out_data[ODW-1:0]    = bypass ? umi_in_data[ODW-1:0]    : fifo_dout[CW+OAW+OAW+:ODW];
   assign umi_out_valid            = bypass ? umi_in_valid            : ~fifo_empty;
   assign umi_in_ready             = bypass ? umi_out_ready           : fifo_in_ready;

   // debug signals
   assign umi_out_beat = umi_out_valid & umi_out_ready;

endmodule // clink_fifo
// Local Variables:
// verilog-library-directories:("." "../../../lambdalib/ramlib/rtl")
// End:
