/******************************************************************************
 * Function:  CLINK Control Registers
 * Author:    Amir Volk
 * Copyright: 2023 Zero ASIC Corporation
 *
 * License: This file contains confidential and proprietary information of
 * Zero ASIC. This file may only be used in accordance with the terms and
 * conditions of a signed license agreement with Zero ASIC. All other use,
 * reproduction, or distribution of this software is strictly prohibited.
 *
 * Version history:
 * Ver 1 - convert from CLINK register
 *
 *****************************************************************************/

module lumi_regs
  #(parameter TARGET = "DEFAULT", // clink type
    parameter GRPOFFSET = 24,     // group address offset
    parameter GRPAW = 8,          // group address width
    parameter GRPID = 0,          // group ID
    // for development only (fixed )
    parameter DW = 256,           // umi data width
    parameter CW = 32,            // umi data width
    parameter AW = 64,            // address width
    parameter RW = 64,            // register width
    parameter IDW = 16,           // chipid width
    parameter CRDTFIFOD = 64
    )
   (// common controls
    input            devicemode,         // 1=host, 0=device
    output [1:0]     chipdir,            // chiplet direction (from strap)
    output           nreset,             // clink active low reset
    output           clk,                // common clink clock
    // register access
    input            udev_req_valid,
    input [CW-1:0]   udev_req_cmd,
    input [AW-1:0]   udev_req_dstaddr,
    input [AW-1:0]   udev_req_srcaddr,
    input [DW-1:0]   udev_req_data,
    output           udev_req_ready,
    output           udev_resp_valid,
    output [CW-1:0]  udev_resp_cmd,
    output [AW-1:0]  udev_resp_dstaddr,
    output [AW-1:0]  udev_resp_srcaddr,
    output [DW-1:0]  udev_resp_data,
    input            udev_resp_ready,
    // io pins
    input            io_nreset_in,
    input [3:0]      io_clk_in,
    input [3:0]      io_ctrl_in,
    input [3:0]      io_status_in,
    output           io_nreset_out,
    output [3:0]     io_clk_out,
    output [3:0]     io_ctrl_out,
    output [3:0]     io_status_out,
    // host side signals
    input            host_nreset,        // reset
    input [3:0]      host_clk,           // clock
    input            host_scanmode,      // puts host in scanmode
    output [6:0]     host_error,         // errors from device
    // device side signals
    input [AW-1:0]   device_status,      // chiplet control signals (to reg)
    input            device_ready,       // device is ready
    input [6:0]      device_error,
    output           device_nreset,      // from io pin
    output [3:0]     device_clk,         // from io pin
    output           device_go,          // 1=go, go, go
    output           device_testmode,    // puts device in testmode
    output [AW-1:0]  device_ctrl,        // device control interface
    output [IDW-1:0] device_chipid,      // chipid "whoami
    output [1:0]     device_chipdir,     // rotation (00=0, 01=90,10=180,11=270)
    output [1:0]     device_chipletmode, // 00=1X,01=4X,10=16X,11=1024X
    // test interface (host controlled)
    input            host_scanenable,
    input            host_scanclk,
    input            host_scanin,
    output           host_scanout,
    output           device_scanenable,
    output           device_scanclk,
    output           device_scanin,
    input            device_scanout,
    // serial interface
    input            host_scsn,
    input            host_sck,
    output           host_sdi,
    input            host_sdo,
    output           device_scsn,
    output           device_sck,
    output           device_sdi,
    input            device_sdo,
    // crossbar settings
    output [1:0]     csr_arbmode,
    // tx link controls
    output           csr_txen,
    output           csr_txcrdt_en,
    output           csr_txddrmode,      // 1 = ddr, 0 = sdr
    output [7:0]     csr_txiowidth,      // pad bus width
    output [3:0]     csr_txprotocol,     // clink protocol
    output [3:0]     csr_txeccmode,      // error correction mode
    output [1:0]     csr_txarbmode,      // phy arbiter mode
    // rx link controls
    output           csr_rxen,
    output           csr_rxddrmode,      // 1 = ddr, 0 = sdr
    output [7:0]     csr_rxiowidth,      // pad bus width
    output [3:0]     csr_rxprotocol,     // clink protocol
    output [3:0]     csr_rxeccmode,      // error correction mode
    output [1:0]     csr_rxarbmode,      // phy arbiter mode
    // serial spi controls
    output [7:0]     csr_spidiv,         //spi divider settings
    output [31:0]    csr_spitimeout,     //spi timeout setting
    // BIST/DEBUG
    output [1:0]     csr_testmode,
    output           csr_testlfsr,
    output           csr_testinject,
    output [7:0]     csr_testpattern,
    output           csr_txbpprotocol,   // enable tx bypass
    output           csr_txbpfifo,
    output           csr_txbpio,
    output           csr_rxbpprotocol,   // enable rx bypass
    output           csr_rxbpfifo,
    output           csr_rxbpio,
    output           csr_txchaos,        // enable random tx fifo pushback
    output           csr_rxchaos,        // enable random rx fifo pushback
    // fine grain clock control
    output           csr_rxclkchange,    // indicates a parameter change
    output           csr_rxclken,        // clock enable
    output [7:0]     csr_rxclkdiv,       // period (0=bypass, 1=div/2, 2=div/3)
    output [15:0]    csr_rxclkphase,     // [7:0]=rising,[15:8]=falling
    output           csr_txclkchange,
    output           csr_txclken,
    output [7:0]     csr_txclkdiv,
    output [15:0]    csr_txclkphase,
    // credit management
    output [15:0]    csr_txcrdt_intrvl,
    output [15:0]    csr_rxcrdt_req_init,
    output [15:0]    csr_rxcrdt_resp_init,
    input [31:0]     csr_txcrdt_status
    );

`include "clink_regmap.vh"

   genvar     i;

   /*AUTOWIRE*/
   // Beginning of automatic wires (for undeclared instantiated-module outputs)
   wire [7:0]           reg_len;
   wire [4:0]           reg_opcode;
   wire                 reg_read;
   wire [2:0]           reg_size;
   // End of automatics

   // registers
   reg [AW-1:0] ctrl_reg;
   reg [AW-1:0] status_reg;
   reg [31:0]   rxmode_reg;
   reg [31:0]   txmode_reg;
   reg [IDW-1:0] chipid_reg;
   reg [11:0]    errctrl_reg;
   reg [15:0]    errstatus_reg;
   reg [15:0]    errcount_reg;
   reg [23:0]    txclk_reg;
   reg [23:0]    rxclk_reg;
   reg [7:0]     spiclk_reg;
   reg [31:0]    spitimeout_reg;
   reg [31:0]    testctrl_reg;
   reg [AW-1:0]  teststatus_reg;
   reg           soft_reset;
   reg [15:0]    txcrdt_intrvl_reg;
   reg [31:0]    rxcrdt_init_reg;

   // strap pins (requires hard reset)
   reg [1:0]     chipdir_strap;
   reg           testmode_strap;
   reg           autoboot_strap;
   reg           devgo_strap;
   reg           linkactive;

   // sb interface
   wire [AW-1:0] reg_addr;
   wire [4*AW-1:0] reg_wrdata;
   reg [DW-1:0]    reg_rddata;
   wire            reg_write;

   wire [7:0]      testpattern;
   wire            testinject;
   wire [7:0]      test_failcount;
   wire [31:0]     test_failkey;
   wire [63:0]     test_faildata;
   wire            test_fail;
   wire            test_done;
   wire            test_active;

   wire            write_ctrl;
   wire            write_status;
   wire            write_chipid;
   wire            write_rxclk;
   wire            write_txclk;
   wire            write_spiclk;
   wire            write_spitimeout;
   wire            write_rxmode;
   wire            write_txmode;
   wire            write_reset;
   wire            write_errstatus;
   wire            write_errctrl;
   wire            write_errcount;
   wire            write_mode;
   wire            write_testctrl;
   wire            write_teststatus;
   wire            write_crdt_init;
   wire            write_crdt_intrvl;

   wire            umi_write;
   wire            umi_read;

   wire [3:0]      error_mode;
   wire [15:0]     error_in;
   wire [2:0]      error_status;
   wire            error_early;
   wire            error_late;
   wire            error_data;
   wire            error_link;
   wire            error_reset;

   wire [6:0]      shutdown;

   wire            clkfb;

   //#################################
   // Host Outputs
   //#################################

   // TODO: Specify which clock does what
   assign io_clk_out[3:0] = host_clk[3:0];

   // Hold device in reset until ready
   assign io_nreset_out = host_nreset & ~soft_reset;

   // ctrl signals depend on mode
   assign io_ctrl_out[0] = host_scanmode ? host_scanenable :
			   linkactive    ? host_scsn:
			                   ctrl_reg[0];

   assign io_ctrl_out[1] = host_scanmode ? host_scanclk :
			   linkactive    ? host_sck :
                 			   ctrl_reg[1];

   assign io_ctrl_out[2] = host_scanmode ? host_scanin  :
			   linkactive    ? host_sdo :
                                           ctrl_reg[2];

   assign io_ctrl_out[3] = linkactive    ? 1'b0 :    //TODO: purpose??
                                           ctrl_reg[3];

   //#################################
   // Device Outputs
   //#################################

   assign io_status_out[0] = device_testmode ? device_scanout :
			     device_go       ? device_sdo :
			                       linkactive;

   assign io_status_out[3:1] = status_reg[3:1];

   //#################################
   // Clocks
   //#################################

   // TODO: Make use of the rest of the clocks
   assign device_clk[3:0] = io_clk_in[3:0];

   //TODO: Need to find a pin for this signal!
   assign clkfb = clk; //TODO: selector for clk, txclk, rxclk

   // TODO: run fast clock between host/device and slow down by

   assign clk = devicemode ? device_clk[0] : host_clk[0];

   //#################################
   // Reset input
   //#################################

   // hard reset for device
   la_rsync rsync_io (.nrst_out	(device_nreset),
		      .clk	(clk),
		      .nrst_in	(io_nreset_in));

   // select hard reset based on device/host
   assign nreset = devicemode ? device_nreset : host_nreset;

   //#####################################
   // Hard Reset "Straps"
   //#####################################

   /* verilator lint_off LATCH */
   always @*
     if(~device_nreset)
       begin
	  chipdir_strap[1:0]  = io_ctrl_in[1:0];
	  autoboot_strap      = io_ctrl_in[2];
	  testmode_strap      = io_ctrl_in[3];
       end
   /* verilator lint_on LATCH */

   // delayed go signal
   always @ (posedge clk or negedge device_nreset)
     if (~device_nreset)
       devgo_strap <= 1'b0;
     else if (autoboot_strap)
       devgo_strap <= 1'b1;
     else if (io_ctrl_in[2])
       devgo_strap <= 1'b1;

   // initialization done
   // TODO: synchronzie ctrl/status signals?

   always @ (posedge clk or negedge nreset)
     if (!nreset)
       linkactive <= 1'b0;
     else if (device_ready & devicemode)
       linkactive <= 1'b1;
     else if (status_reg[0] & ~devicemode & ~device_testmode)
       linkactive <= 1'b1;

   assign device_testmode     = devicemode ? testmode_strap : ctrl_reg[3];
   assign device_go           = devgo_strap;

   assign device_chipdir[1:0] = devicemode ? chipdir_strap[1:0] : ctrl_reg[1:0];

   //#############################################
   // Scan Interface (direct from pin)
   //#############################################

   assign device_scanenable = io_ctrl_in[0] & device_go;
   assign device_scanclk    = io_ctrl_in[1] & device_go;
   assign device_scanin     = io_ctrl_in[2];
   assign host_scanout      = io_status_in[0];

   //#############################################
   // Serial Interface (direct from pin)
   //#############################################

   // NOTE: need to solve the overlap with
   // Block out error during sideband..

   assign host_sdi    = io_status_in[0];
   assign device_scsn = io_ctrl_in[0] | ~device_go;
   assign device_sck  = io_ctrl_in[1] & device_go;
   assign device_sdi  = io_ctrl_in[2] & device_go;

   //###############################################
   // Host Control Register (PINS)
   //###############################################

   //        reset    --> init   --> normal
   //----------------------------------------
   //[0]   = chipdir  --> x      --> scsn
   //[1]   = chipdir  --> x      --> sck
   //[2]   = autoboot --> go     --> sdo
   //[3]   = testmode --> 1'b0   --> 1'b0
   //[5:4] = arbmode

   always @ (posedge clk or negedge nreset)
     if(!nreset)
       ctrl_reg[AW-1:0] <= 'b0;
     else if(write_ctrl & ~devicemode)
       ctrl_reg[AW-1:0] <= reg_wrdata[AW-1:0];
     else if(write_ctrl & devicemode)
       ctrl_reg[AW-1:0] <= {reg_wrdata[AW-1:4],
			    io_ctrl_in[3:0]};

   assign csr_arbmode[1:0]        = ctrl_reg[5:4];
   assign device_chipletmode[1:0] = ctrl_reg[7:6];

   // Device Outputs
   assign device_ctrl[AW-1:0] = ctrl_reg[AW-1:0];

   //#################################################
   // Device Status Register
   //#################################################

   //     reset --> init      --> normal
   //----------------------------------------
   //[0] = 0    --> initdone  --> clkfb, so
   //[1] = 0    --> error     --> error
   //[2] = 0    --> error     --> error
   //[3] = 0    --> error     --> error

   always @ (posedge clk or negedge nreset)
     if(!nreset)
       status_reg[AW-1:0] <= 'h0;
     else if (~devicemode)
       status_reg[AW-1:0] <= {{(AW-5){1'b0}},
			      linkactive,
			      io_status_in[3:0]};// sampling pins
     else
       status_reg[AW-1:0] <= {device_status[AW-1:5],
			      linkactive,
			      error_status[2:0],
			      1'b0};

   //######################################
   // TXMODE Register
   //######################################
   // Amir - tx enable should not be set out of reset since you need to configure (from the host)
   // the link parameters first.
   always @ (posedge clk or negedge nreset)
     if(!nreset)
       txmode_reg[31:0] <= 'b0;
     else if(write_txmode)
       txmode_reg[31:0] <= reg_wrdata[31:0];

   assign csr_txen        = linkactive & txmode_reg[0]; // clink tx enable
   assign csr_txddrmode   = txmode_reg[1];   // dual data rate mode
   assign csr_txarbmode   = txmode_reg[3:2]; // tx arbiter mode
   assign csr_txcrdt_en   = txmode_reg[4];   // Enable sending credit updates

   assign csr_txprotocol[3:0] = txmode_reg[11:8];
   // 0000 = streaming
   // 0001 = umi
   // 0010 = ethernet
   // 0011 = cxl
   // 0100 = pipe

   assign csr_txeccmode[3:0]   = txmode_reg[15:12];
   //0000=none
   //0001=parity
   //0010=crc
   //TBD

   assign csr_txiowidth[7:0] = txmode_reg[23:16];
   // 00000000 = (0=disabled)
   // 00000001 = 1 bytes
   // 00000010 = 2 bytes
   // 00000011 = 3 bytes
   // 00000100 = 4 bytes
   // 00000101 = 5 bytes
   // 00000110 = 6 bytes
   // ...
   // 11111111 = 255 bytes

   //######################################
   // RXMODE Register
   //######################################

   always @ (posedge clk or negedge nreset)
     if(!nreset)
       rxmode_reg[31:0] <= 'b0;
     else if(write_rxmode)
       rxmode_reg[31:0] <= reg_wrdata[31:0];

   assign csr_rxen      = linkactive & rxmode_reg[0]; // clink rx enable
   assign csr_rxddrmode = rxmode_reg[1];   // dual data rate mode
   assign csr_rxarbmode = rxmode_reg[3:2]; // rx arbiter mode

   assign csr_rxprotocol[3:0] = rxmode_reg[11:8];
   // 0000 = streaming
   // 0001 = umi
   // 0010 = ethernet
   // 0011 = cxl
   // 0100 = pipe
   assign csr_rxeccmode[3:0]  = rxmode_reg[15:12];
   //0000=none
   //0001=parity
   //0010=crc
   //TBD

   assign csr_rxiowidth[7:0]  = rxmode_reg[23:16];
   // 00000000 = (0=disabled)
   // 00000001 = 1 bytes
   // 00000010 = 2 bytes
   // 00000011 = 3 bytes
   // 00000100 = 4 bytes
   // 00000101 = 5 bytes
   // 00000110 = 6 bytes
   // ...
   // 11111111 = 255 bytes

   //######################################
   // CHIP ID
   //######################################

   always @ (posedge clk or negedge nreset)
     if(!nreset)
       chipid_reg[IDW-1:0] <= 'b0;
     else if(write_chipid)
       chipid_reg[IDW-1:0] <= reg_wrdata[IDW-1:0];

   assign device_chipid[IDW-1:0] = chipid_reg[IDW-1:0];

   //######################################
   // Error Control Register
   //######################################

   always @ (posedge clk or negedge nreset)
     if(!nreset)
       errctrl_reg[11:0] <= 'b0;
     else if(write_errctrl)
       errctrl_reg[11:0] <= reg_wrdata[11:0];

   assign shutdown[6:0] = errctrl_reg[6:0];

   assign error_mode[3:0] = errctrl_reg[11:8];

   //######################################
   // Error Status Register
   //######################################

   always @ (posedge clk or negedge nreset)
     if(!nreset)
       errstatus_reg[15:0] <= 'b0;
     else if(write_errstatus)
       errstatus_reg[15:0] <= reg_wrdata[15:0];
     else
       errstatus_reg[15:0] <= errstatus_reg[15:0] |
			      error_in[15:0];

   assign error_in[15:0] =  {4'b0,
			     2'b0,
			     error_early,
			     error_late,
			     error_data,
			     device_error[6:0]};

   // TODO: implement
   assign error_data  = 1'b0;
   assign error_late  = 1'b0;
   assign error_early = 1'b0;
   assign error_link = error_early | error_late | error_data;

   // encode device error for pins (in order of priority)
   assign error_status[2:0] = errstatus_reg[6] ? 3'b111 : // fatal (shutdown)
			      errstatus_reg[5] ? 3'b110 : // link fault (calibrate)
			      errstatus_reg[4] ? 3'b101 : // watchdog fault (reset)
			      errstatus_reg[3] ? 3'b100 : // clk glitch (reset)
			      errstatus_reg[2] ? 3'b011 : // temp out of range (slow)
			      errstatus_reg[1] ? 3'b010 : // under voltage (raise)
			      errstatus_reg[0] ? 3'b001 : // over voltage (lower)
			                         3'b000;  // normal

   // decode device error for host
   assign host_error[6] = (status_reg[3:1] == 3'b111);
   assign host_error[5] = (status_reg[3:1] == 3'b110);
   assign host_error[4] = (status_reg[3:1] == 3'b101);
   assign host_error[3] = (status_reg[3:1] == 3'b100);
   assign host_error[2] = (status_reg[3:1] == 3'b011);
   assign host_error[1] = (status_reg[3:1] == 3'b010);
   assign host_error[0] = (status_reg[3:1] == 3'b001);

   // Trigger device reset on certain events
    assign error_reset = (|(shutdown[6:0] & host_error[6:0]));

   //######################################
   // Error Counter
   //######################################

   always @ (posedge clk or negedge nreset)
     if(!nreset)
       errcount_reg[15:0] <= 'b0;
     else
       errcount_reg[15:0] <= errcount_reg[15:0] +
			     {15'h0000,error_in[error_mode[3:0]]}; //for lint

   //######################################
   // TX Clock Control Register
   //######################################

   always @ (posedge clk or negedge nreset)
     if(!nreset)
       txclk_reg[23:0] <= 'b0;
     else if(write_txclk)
       txclk_reg[23:0] <= reg_wrdata[23:0];

   assign csr_txclkchange = write_txclk;
   assign csr_txclken     = csr_txen;
   assign csr_txclkdiv    = txclk_reg[7:0];
   assign csr_txclkphase  = txclk_reg[15:0];

   //######################################
   // RX Clock Control Register
   //######################################

   always @ (posedge clk or negedge nreset)
     if(!nreset)
       rxclk_reg[23:0] <= 'b0;
     else if(write_rxclk)
       rxclk_reg[23:0] <= reg_wrdata[23:0];

   assign csr_rxclkchange = write_rxclk;
   assign csr_rxclken     = csr_rxen;
   assign csr_rxclkdiv    = rxclk_reg[7:0];
   assign csr_rxclkphase  = rxclk_reg[15:0];

   //######################################
   // SPI Clock Control Register
   //######################################

   always @ (posedge clk or negedge nreset)
     if(!nreset)
       spiclk_reg[7:0] <= DEF_SPICLK;
     else if(write_spiclk)
       spiclk_reg[7:0] <= reg_wrdata[7:0];

   assign csr_spidiv[7:0] = spiclk_reg[7:0];

   //######################################
   // SPI Timeout Register
   //######################################

   always @ (posedge clk or negedge nreset)
     if(!nreset)
       spitimeout_reg[31:0] <= DEF_SPITIMEOUT;
     else if(write_spitimeout)
       spitimeout_reg[31:0] <= reg_wrdata[31:0];

   assign csr_spitimeout[31:0] = spitimeout_reg[31:0];

   //######################################
   // Soft Reset
   //######################################

   // used to keep device/core in reset
   // after nreset is deasserted

   always @ (posedge clk or negedge nreset)
     if(!nreset)
       soft_reset <= 1'b1;
     else if(write_reset)
       soft_reset <= reg_wrdata[0];

   //######################################
   //  Test Control Register
   //######################################

   always @ (posedge clk or negedge nreset)
     if(!nreset)
       testctrl_reg[31:0] <= 'b0;
     else if(write_testctrl)
       testctrl_reg[31:0] <= reg_wrdata[31:0];

   assign csr_testmode[1:0] = testctrl_reg[1:0];
   //00=disable
   //01=on die loop back
   //10=die to die loopback (device die)
   //11=die to die loopback (host die)

   assign csr_testlfsr = testctrl_reg[4];
   //0 = lfsr
   //1 = test pattern

   assign csr_testinject = testctrl_reg[5];
   // 0 = normal
   // 1 = inject error from test pattern

   assign csr_txchaos = testctrl_reg[6];
   // 0 = no delays inserted
   // 1 = random txfifo pushback

   assign csr_rxchaos = testctrl_reg[7];
   // 0 = no delays inserted
   // 1 = random rxfifo pushback

   assign csr_testpattern[7:0] = testctrl_reg[15:8];
   // test pattern driven out in inverted pattern


   assign csr_txbpprotocol = testctrl_reg[16];
   assign csr_txbpfifo     = testctrl_reg[17];
   assign csr_txbpio       = testctrl_reg[18];

   assign csr_rxbpprotocol = testctrl_reg[24];
   assign csr_rxbpfifo     = testctrl_reg[25];
   assign csr_rxbpio       = testctrl_reg[26];

   //######################################
   //  Test Status Register
   //######################################

   // TODO: implement with test
   assign test_fail      = 1'b0;
   assign test_done      = 1'b0;
   assign test_active    = 1'b0;
   assign test_failcount = 'b0;

   always @ (posedge clk or negedge nreset)
     if(!nreset)
       teststatus_reg[63:0] <= 'b0;
     else if(write_teststatus)
       teststatus_reg[63:0] <= reg_wrdata[63:0];
     else
       teststatus_reg[63:0] <= {32'b0, // fail key
				16'b0, // fail pin(s)
				test_failcount[7:0],
				5'b00000,
				test_fail,
				test_done,
				test_active};

   //######################################
   //  Credit init Register
   //######################################
   always @ (posedge clk or negedge nreset)
     if(!nreset)
       rxcrdt_init_reg[31:0] <= {16'd42,16'd42};
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
    );*/
   umi_regif #(.DW(DW),
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
              .udev_req_srcaddr (udev_req_srcaddr[AW-1:0]),
              .udev_req_data    (udev_req_data[DW-1:0]),
              .udev_resp_ready  (udev_resp_ready),
              .reg_rddata       (reg_rddata[RW-1:0]));

   // TODO - implement write size
   // Write Decode
   assign write_ctrl       = reg_write & (reg_addr[7:2]==CLINK_CTRL[7:2]);
   assign write_status     = reg_write & (reg_addr[7:2]==CLINK_STATUS[7:2]);
   assign write_chipid     = reg_write & (reg_addr[7:2]==CLINK_CHIPID[7:2]);
   assign write_reset      = reg_write & (reg_addr[7:2]==CLINK_RESET[7:2]);

   assign write_txmode     = reg_write & (reg_addr[7:2]==CLINK_TXMODE[7:2]);
   assign write_rxmode     = reg_write & (reg_addr[7:2]==CLINK_RXMODE[7:2]);

   assign write_errctrl    = reg_write & (reg_addr[7:2]==CLINK_ERRCTRL[7:2]);
   assign write_errstatus  = reg_write & (reg_addr[7:2]==CLINK_ERRSTATUS[7:2]);
   assign write_errcount   = reg_write & (reg_addr[7:2]==CLINK_ERRCOUNT[7:2]);

   assign write_txclk      = reg_write & (reg_addr[7:2]==CLINK_TXCLK[7:2]);
   assign write_rxclk      = reg_write & (reg_addr[7:2]==CLINK_RXCLK[7:2]);

   assign write_spiclk     = reg_write & (reg_addr[7:2]==CLINK_SPICLK[7:2]);
   assign write_spitimeout = reg_write & (reg_addr[7:2]==CLINK_SPITIMEOUT[7:2]);

   assign write_testctrl   = reg_write & (reg_addr[7:2]==CLINK_TESTCTRL[7:2]);
   assign write_teststatus = reg_write & (reg_addr[7:2]==CLINK_TESTSTATUS[7:2]);

   assign write_crdt_init   = reg_write & (reg_addr[7:2]==CLINK_CRDTINIT[7:2]);
   assign write_crdt_intrvl = reg_write & (reg_addr[7:2]==CLINK_CRDTINTRVL[7:2]);

   always @(posedge clk or negedge nreset)
     if (~nreset)
       reg_rddata[DW-1:0] <= {DW{1'b0}};
     else
       if (reg_read)
         case (reg_addr[7:2])
           CLINK_CTRL[7:2]      : reg_rddata[DW-1:0] <= {{DW-AW{1'b0}},ctrl_reg[AW-1:0]};
           CLINK_STATUS[7:2]    : reg_rddata[DW-1:0] <= {{DW-AW{1'b0}},status_reg[AW-1:0]};
           CLINK_CHIPID[7:2]    : reg_rddata[DW-1:0] <= {{DW-IDW{1'b0}},chipid_reg[IDW-1:0]};
           CLINK_RESET[7:2]     : reg_rddata[DW-1:0] <= {{DW-1{1'b0}},soft_reset};
           CLINK_TXMODE[7:2]    : reg_rddata[DW-1:0] <= {{DW-32{1'b0}},txmode_reg[31:0]};
           CLINK_RXMODE[7:2]    : reg_rddata[DW-1:0] <= {{DW-32{1'b0}},rxmode_reg[31:0]};
           CLINK_ERRCTRL[7:2]   : reg_rddata[DW-1:0] <= {{DW-12{1'b0}},errctrl_reg[11:0]};
           CLINK_ERRSTATUS[7:2] : reg_rddata[DW-1:0] <= {{DW-16{1'b0}},errstatus_reg[15:0]};
           CLINK_ERRCOUNT[7:2]  : reg_rddata[DW-1:0] <= {{DW-16{1'b0}},errcount_reg[15:0]};
           CLINK_TXCLK[7:2]     : reg_rddata[DW-1:0] <= {{DW-24{1'b0}},txclk_reg[23:0]};
           CLINK_RXCLK[7:2]     : reg_rddata[DW-1:0] <= {{DW-24{1'b0}},rxclk_reg[23:0]};
           CLINK_SPICLK[7:2]    : reg_rddata[DW-1:0] <= {{DW-8{1'b0}},spiclk_reg[7:0]};
           CLINK_SPITIMEOUT[7:2]: reg_rddata[DW-1:0] <= {{DW-32{1'b0}},spitimeout_reg[31:0]};
           CLINK_TESTCTRL[7:2]  : reg_rddata[DW-1:0] <= {{DW-32{1'b0}},testctrl_reg[31:0]};
           CLINK_TESTSTATUS[7:2]: reg_rddata[DW-1:0] <= {{DW-AW{1'b0}},teststatus_reg[AW-1:0]};
           CLINK_CRDTINIT[7:2]  : reg_rddata[DW-1:0] <= {{DW-32{1'b0}},rxcrdt_init_reg[31:0]};
           CLINK_CRDTINTRVL[7:2]: reg_rddata[DW-1:0] <= {{DW-16{1'b0}},txcrdt_intrvl_reg[15:0]};
           CLINK_CRDTSTAT[7:2]  : reg_rddata[DW-1:0] <= {{DW-32{1'b0}},csr_txcrdt_status[31:0]};
           default:
             reg_rddata[DW-1:0] <= 'b0;
         endcase

endmodule
// Local Variables:
// verilog-library-directories:("." "../../../umi/umi/rtl/")
// End:
