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
 * ----
 *
 * Documentation:
 * - LUMI Control Registers
 *
 ******************************************************************************/

module lumi_regs
  #(parameter TARGET = "DEFAULT",                         // LUMI type
    parameter GRPOFFSET = 24,                             // group address offset
    parameter GRPAW = 8,                                  // group address width
    parameter GRPID = 0,                                  // group ID
    // for development only (fixed )
    parameter CW = 32,                                    // umi data width
    parameter AW = 64,                                    // address width
    parameter DW = 128,                                   // register width
    parameter RW = 32,                                    // register width
    parameter IDW = 16,                                   // chipid width
    parameter IOW = 64,                                   // phy-lumi IO width
    parameter ASYNCFIFODEPTH = 8,                         // depth of async fifo
    parameter RXFIFOW = 8,                                // width of Rx fifo (in bits) - cannot be smaller than IOW!!!
    parameter NFIFO = IOW/RXFIFOW,                        // number of parallel fifo's
    parameter CRDTDEPTH = 1+((DW+AW+AW+CW)/RXFIFOW)/NFIFO // total fifo depth, eq is minimum
    )
   (// common controls
    input           devicemode,    // 1=host, 0=device
    input           deviceready,   // ready indication from the brick controller
    input           nreset,        // active low reset
    input           clk,           // common clock
    // register access
    input           udev_req_valid,
    input [CW-1:0]  udev_req_cmd,
    input [AW-1:0]  udev_req_dstaddr,
    input [AW-1:0]  udev_req_srcaddr,
    input [RW-1:0]  udev_req_data,
    output          udev_req_ready,
    output          udev_resp_valid,
    output [CW-1:0] udev_resp_cmd,
    output [AW-1:0] udev_resp_dstaddr,
    output [AW-1:0] udev_resp_srcaddr,
    output [RW-1:0] udev_resp_data,
    input           udev_resp_ready,
    // phy control signals
    input           phy_linkactive,
    input [7:0]     phy_iow,
    // host side signals
    output          host_linkactive,
    // crossbar settings
    output [1:0]    csr_arbmode,
    // tx link controls
    output          csr_txen,
    output          csr_txcrdt_en,
    output [7:0]    csr_txiowidth, // pad bus width
    // rx link controls
    output          csr_rxen,
    output [7:0]    csr_rxiowidth, // pad bus width
    // credit management
    output [15:0]   csr_txcrdt_intrvl,
    output [15:0]   csr_rxcrdt_req_init,
    output [15:0]   csr_rxcrdt_resp_init,
    input [31:0]    csr_txcrdt_status
    );

`include "lumi_regmap.vh"

   genvar     i;

   /*AUTOWIRE*/
   // Beginning of automatic wires (for undeclared instantiated-module outputs)
   wire [7:0]           reg_len;
   wire [4:0]           reg_opcode;
   wire                 reg_read;
   wire [2:0]           reg_size;
   // End of automatics

   // registers
   reg [RW-1:0] ctrl_reg;
   reg [RW-1:0] status_reg;
   reg [RW-1:0] rxmode_reg;
   reg [RW-1:0] txmode_reg;
   reg [15:0]    txcrdt_intrvl_reg;
   reg [RW-1:0]  rxcrdt_init_reg;

   reg           linkactive;
   reg           linkactive_d;
   reg           linkactive_rise;

   // sb interface
   wire [AW-1:0] reg_addr;
   wire [RW-1:0] reg_wrdata;
   reg [RW-1:0]  reg_rddata;
   wire          reg_write;

   wire          write_ctrl;
   wire          write_status;
   wire          write_rxmode;
   wire          write_txmode;
   wire          write_mode;
   wire          write_crdt_init;
   wire          write_crdt_intrvl;

   wire          umi_write;
   wire          umi_read;

   // Link ready is a combination of two things:
   // 1. phy link ready
   // 2. device ready in device mode
   always @ (posedge clk or negedge nreset)
     if (!nreset)
       linkactive <= 1'b0;
     else if (deviceready & devicemode | ~devicemode)
       linkactive <= phy_linkactive;

   always @ (posedge clk or negedge nreset)
     if (!nreset)
       begin
          linkactive_d <= 1'b0;
          linkactive_rise <= 1'b0;
       end
     else
       begin
          linkactive_d <= linkactive;
          linkactive_rise <= linkactive & ~linkactive_d;
       end

   assign host_linkactive = linkactive;

   //###############################################
   // Link Control Register - placeholder for now
   // Previous content moved to ebrick regs
   //###############################################
   always @ (posedge clk or negedge nreset)
     if(!nreset)
       ctrl_reg[RW-1:0] <= 'b0;
     else if(write_ctrl)
       ctrl_reg[RW-1:0] <= reg_wrdata[RW-1:0];

   assign csr_arbmode[1:0] = ctrl_reg[5:4];

   //#################################################
   // Device Status Register
   //#################################################

   always @ (posedge clk or negedge nreset)
     if(!nreset)
       status_reg[RW-1:0] <= 'h0;
     else
       status_reg[RW-1:0] <= {{(RW-5){1'b0}},
                              linkactive,
                              4'h0};

   //######################################
   // TXMODE Register
   //######################################
   // In order to enable lumi to work without a SW sequenece it
   // will enable and sample the parameters from the phy once linkactive
   // goes high

   always @ (posedge clk or negedge nreset)
     if(!nreset)
       txmode_reg[RW-1:0] <= 'h0;
     else if (linkactive_rise)
       txmode_reg[RW-1:0] <= {{(RW-24){1'b0}}, // Unused
                              phy_iow[7:0],    // IOW
                              8'h00,           // Unused
                              4'b0001,         // 3 unused, credit enable
                              4'b0001};        // 3 unused, tx enable
     else if(write_txmode)
       txmode_reg[RW-1:0] <= reg_wrdata[RW-1:0];

   assign csr_txen           = linkactive & txmode_reg[0]; // tx enable
   assign csr_txcrdt_en      = txmode_reg[4];   // Enable sending credit updates
   assign csr_txiowidth[7:0] = txmode_reg[23:16];
   // 00000000 = 1 bytes
   // 00000001 = 2 bytes
   // 00000010 = 4 bytes
   // 00000011 = 8 bytes
   // 00000100 = 16 bytes
   // ...

   //######################################
   // RXMODE Register
   //######################################

   always @ (posedge clk or negedge nreset)
     if(!nreset)
       rxmode_reg[RW-1:0] <= 'h0;
     else if (linkactive_rise)
       rxmode_reg[RW-1:0] <= {{(RW-24){1'b0}}, // Unused
                              phy_iow[7:0],    // IOW
                              12'h000,         // Unused
                              4'b0001};        // 3 unused, rx enable
     else if(write_rxmode)
       rxmode_reg[RW-1:0] <= reg_wrdata[RW-1:0];

   assign csr_rxen           = linkactive & rxmode_reg[0]; // rx enable
   assign csr_rxiowidth[7:0] = rxmode_reg[23:16];
   // 00000000 = 1 bytes
   // 00000001 = 2 bytes
   // 00000010 = 4 bytes
   // 00000011 = 8 bytes
   // 00000100 = 16 bytes
   // ...

   //######################################
   //  Credit init Register
   //######################################
   always @ (posedge clk or negedge nreset)
     if(!nreset)
       rxcrdt_init_reg[31:0] <= 'h0;
     else if (linkactive_rise)
       rxcrdt_init_reg[31:0] <= {CRDTDEPTH[15:0] << phy_iow,
                                 CRDTDEPTH[15:0] << phy_iow};
     else if(write_crdt_init)
       rxcrdt_init_reg[31:0] <= reg_wrdata[31:0];

   assign csr_rxcrdt_req_init[15:0]  = rxcrdt_init_reg[15:0];
   assign csr_rxcrdt_resp_init[15:0] = rxcrdt_init_reg[31:16];

   //######################################
   //  Credit update interval Register
   //######################################
   always @ (posedge clk or negedge nreset)
     if(!nreset)
       txcrdt_intrvl_reg[15:0] <= 16'h00FF;
     else if(write_crdt_intrvl)
       txcrdt_intrvl_reg[15:0] <= reg_wrdata[15:0];

   assign csr_txcrdt_intrvl[15:0]  = txcrdt_intrvl_reg[15:0];

   //######################################
   // UMI Interface
   //######################################

   /* umi_regif AUTO_TEMPLATE(
    .udev_resp_data   (udev_resp_data[RW-1:0]),
    .udev_req_data    (udev_req_data[RW-1:0]),
    );*/
   umi_regif #(.DW(RW),
               .AW(AW),
               .CW(CW),
               .RW(RW),
               .GRPOFFSET(GRPOFFSET),
               .GRPAW(GRPAW),
               .GRPID(GRPID))
   umi_regif (/*AUTOINST*/
              // Outputs
              .udev_req_ready   (udev_req_ready),
              .udev_resp_valid  (udev_resp_valid),
              .udev_resp_cmd    (udev_resp_cmd[CW-1:0]),
              .udev_resp_dstaddr(udev_resp_dstaddr[AW-1:0]),
              .udev_resp_srcaddr(udev_resp_srcaddr[AW-1:0]),
              .udev_resp_data   (udev_resp_data[RW-1:0]), // Templated
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
              .udev_req_srcaddr (udev_req_srcaddr[AW-1:0]),
              .udev_req_data    (udev_req_data[RW-1:0]), // Templated
              .udev_resp_ready  (udev_resp_ready),
              .reg_rddata       (reg_rddata[RW-1:0]));

   // Write Decode
   assign write_ctrl       = reg_write & (reg_addr[7:2]==LUMI_CTRL[7:2]);
   assign write_status     = reg_write & (reg_addr[7:2]==LUMI_STATUS[7:2]);
   assign write_txmode     = reg_write & (reg_addr[7:2]==LUMI_TXMODE[7:2]);
   assign write_rxmode     = reg_write & (reg_addr[7:2]==LUMI_RXMODE[7:2]);
   assign write_crdt_init   = reg_write & (reg_addr[7:2]==LUMI_CRDTINIT[7:2]);
   assign write_crdt_intrvl = reg_write & (reg_addr[7:2]==LUMI_CRDTINTRVL[7:2]);

   always @(posedge clk or negedge nreset)
     if (~nreset)
       reg_rddata[RW-1:0] <= {RW{1'b0}};
     else
       if (reg_read)
         case (reg_addr[7:2])
           LUMI_CTRL[7:2]      : reg_rddata[RW-1:0] <= ctrl_reg[RW-1:0];
           LUMI_STATUS[7:2]    : reg_rddata[RW-1:0] <= status_reg[RW-1:0];
           LUMI_TXMODE[7:2]    : reg_rddata[RW-1:0] <= txmode_reg[RW-1:0];
           LUMI_RXMODE[7:2]    : reg_rddata[RW-1:0] <= rxmode_reg[RW-1:0];
           LUMI_CRDTINIT[7:2]  : reg_rddata[RW-1:0] <= {{RW-32{1'b0}},rxcrdt_init_reg[31:0]};
           LUMI_CRDTINTRVL[7:2]: reg_rddata[RW-1:0] <= {{RW-16{1'b0}},txcrdt_intrvl_reg[15:0]};
           LUMI_CRDTSTAT[7:2]  : reg_rddata[RW-1:0] <= {{RW-32{1'b0}},csr_txcrdt_status[31:0]};
           default:
             reg_rddata[RW-1:0] <= 'b0;
         endcase

endmodule
// Local Variables:
// verilog-library-directories:("." "../../../umi/umi/rtl/")
// End:
