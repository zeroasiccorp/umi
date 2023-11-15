/*******************************************************************************
 * Function:  umi reg interface testbench
 * Author:    Amir Volk
 *
 * Copyright (c) 2023 Zero ASIC Corporation
 * This code is licensed under Apache License 2.0 (see LICENSE for details)
 *
 * Documentation:
 *
 ******************************************************************************/

module testbench();

`include "umi_messages.vh"

   localparam N          = 1;
   localparam CW         = 32;
   localparam AW         = 64;
   localparam DW         = 64;
   localparam RW         = 32;
   localparam PERIOD_CLK = 10;
   localparam RAMDEPTH   = 1024;

   reg [N-1:0]   udev_req_valid;
   reg [CW-1:0]  udev_req_cmd;
   reg [AW-1:0]  udev_req_dstaddr;
   reg [N-1:0]   udev_resp_ready;
   reg           nreset;
   reg           clk;

   reg [RW-1:0]  ram [1023:0];
   reg [RW-1:0]  reg_rddata;
   reg [$clog2(RAMDEPTH)-1:0] ram_addr;
   reg [AW-1:0]               addr_latch;
   reg                        reg_read_d1;
   reg                        error;
   reg [7:0]                  atomic;
   reg [7:0]                  atomic_latch;

   /*AUTOWIRE*/
   // Beginning of automatic wires (for undeclared instantiated-module outputs)
   wire [AW-1:0]        reg_addr;
   wire [7:0]           reg_len;
   wire [4:0]           reg_opcode;
   wire                 reg_read;
   wire [2:0]           reg_size;
   wire [RW-1:0]        reg_wrdata;
   wire                 reg_write;
   wire                 udev_req_ready;
   wire [CW-1:0]        udev_resp_cmd;
   wire [DW-1:0]        udev_resp_data;
   wire [AW-1:0]        udev_resp_srcaddr;
   wire                 udev_resp_valid;
   // End of automatics

   // Run Sim
   initial
     begin
        $dumpfile("waveform.vcd");
        $dumpvars();
     end

   always @(posedge clk)
     if (nreset)
       begin
//          if (udev_req_valid)
//            $display("addr: %h", udev_req_dstaddr);
          if (!udev_req_valid & (&ram_addr))
            begin
               #100;
               if (error)
                 $display("Test failed :-(");
               else
                 $display("Test passed :-)");
               $finish;
            end
       end

  // Reset/init
   initial
     begin
        #(1)
        addr_latch = 'b0;
        error    = 1'b0;
        nreset   = 1'b0;
        clk      = 1'b0;
        #(PERIOD_CLK * 10)
        nreset        = 1'b1;
     end // initial begin

   // clocks
   always
     #(PERIOD_CLK/2) clk = ~clk;

   // write followed by read/atomic for all addresses
   // ignore LSB of address
   always @ (posedge clk or negedge nreset)
     if(~nreset)
       begin
          ram_addr         <= 0;
          udev_req_valid   <= 1'b0;
          udev_req_dstaddr <= 'b0;
          udev_req_cmd     <= 'b0;
          udev_resp_ready  <= 1'b1;
          atomic           <= 0;
       end
     else if(udev_req_ready)
       if ((&ram_addr) & (udev_req_cmd[4:0] != UMI_REQ_WRITE)) // end of stimuli
         begin
            udev_req_valid <= 1'b0;
         end
       else
         begin
            udev_req_valid   <= (&ram_addr) ? 1'b0 : 1'b1;
            udev_req_cmd     <= (udev_req_cmd[4:0] == UMI_REQ_WRITE) & (atomic > 8)  ? {16'h0,8'h3,3'h0,UMI_REQ_READ}     : // size=0, len=3
                                (udev_req_cmd[4:0] == UMI_REQ_WRITE) & (atomic <= 8) ? {16'h0,atomic,3'h2,UMI_REQ_ATOMIC} : // size=2, len=0
                                                                                       {16'h0,8'h3,3'h0,UMI_REQ_WRITE};
            atomic           <= (udev_req_cmd[4:0] == UMI_REQ_WRITE) ? $random%255  : 0;
            ram_addr         <= (udev_req_cmd[4:0] == UMI_REQ_WRITE) ? ram_addr : ram_addr + 1'b1;
            udev_req_dstaddr <= (udev_req_cmd[4:0] == UMI_REQ_WRITE) ? udev_req_dstaddr : $random%16777215;//reg addr has 24 bits
         end

   //###########################################
   // DUT
   //###########################################
   /*umi_regif AUTO_TEMPLATE(
    .udev_req_srcaddr  ({@"vl-width"{1'b0}}),
    .udev_req_data     ({DW/AW{udev_req_dstaddr[AW-1:0]}}),
    .udev_resp_dstaddr (),
    );*/

   umi_regif #(.CW(CW),
               .AW(AW),
               .DW(DW),
               .RW(RW))
   umi_regif (/*AUTOINST*/
              // Outputs
              .udev_req_ready   (udev_req_ready),
              .udev_resp_valid  (udev_resp_valid),
              .udev_resp_cmd    (udev_resp_cmd[CW-1:0]),
              .udev_resp_dstaddr(),                      // Templated
              .udev_resp_srcaddr(udev_resp_srcaddr[AW-1:0]),
              .udev_resp_data   (udev_resp_data[DW-1:0]),
              .reg_addr         (reg_addr[AW-1:0]),
              .reg_write        (reg_write),
              .reg_read         (reg_read),
              .reg_opcode       (reg_opcode[4:0]),
              .reg_size         (reg_size[2:0]),
              .reg_len          (reg_len[7:0]),
              .reg_wrdata       (reg_wrdata[RW-1:0]),
              // Inputs
              .clk              (clk),
              .nreset           (nreset),
              .udev_req_valid   (udev_req_valid),
              .udev_req_cmd     (udev_req_cmd[CW-1:0]),
              .udev_req_dstaddr (udev_req_dstaddr[AW-1:0]),
              .udev_req_srcaddr ({AW{1'b0}}),            // Templated
              .udev_req_data    ({DW/AW{udev_req_dstaddr[AW-1:0]}}), // Templated
              .udev_resp_ready  (udev_resp_ready),
              .reg_rddata       (reg_rddata[RW-1:0]));

   // Dummy RAM
   always @(posedge clk)
     if (reg_write)
       ram[ram_addr[$clog2(RAMDEPTH)-1:1]] <= reg_wrdata[RW-1:0];

   always @(posedge clk or negedge nreset)
     if (~nreset)
       reg_rddata[RW-1:0] <= 'h0;
     else
       if(reg_read)
         reg_rddata[RW-1:0] <= ram[ram_addr[$clog2(RAMDEPTH)-1:1]];

   // Ram checking
   always @(posedge clk)
     begin
        if (udev_req_valid & udev_req_ready & (udev_req_cmd[4:0] != UMI_REQ_WRITE))
          begin
             addr_latch <= udev_req_dstaddr;
             atomic_latch <= udev_req_cmd[15:8];
          end

        if (udev_resp_valid & udev_resp_ready & (udev_resp_cmd[4:0] == UMI_RESP_READ) & (udev_resp_data[RW-1:0] != addr_latch))
          begin
             $display("Error reading address %h", addr_latch);
             error <= 1'b1;
          end
     end

endmodule
// Local Variables:
// verilog-library-directories:("." "../rtl")
// End:
