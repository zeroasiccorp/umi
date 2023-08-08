/*****************************************************************************
 * Function:  CLINK Register Map
 * Author:    Andreas Olofsson
 * Copyright: (c) 2022 Zero ASIC Corporation
 ****************************************************************************/

// registers (addr[7:0]), 32bit aligned
localparam CLINK_CTRL        = 8'h00; // device configuration
localparam CLINK_STATUS      = 8'h04; // device status
localparam CLINK_CHIPID      = 8'h08; // programmable device id
localparam CLINK_RESET       = 8'h0C; // reset device
localparam CLINK_TXMODE      = 8'h10; // tx operating mode
localparam CLINK_RXMODE      = 8'h14; // rx operating mode
localparam CLINK_TXCLK       = 8'h18; // tx clock config
localparam CLINK_RXCLK       = 8'h1c; // rx clock config
localparam CLINK_SPICLK      = 8'h20; // spi(sb) clock config
localparam CLINK_SPITIMEOUT  = 8'h24; // spi timeout value
localparam CLINK_ERRCTRL     = 8'h28; // error control register
localparam CLINK_ERRSTATUS   = 8'h2C; // error status
localparam CLINK_ERRCOUNT    = 8'h30; // error counter
localparam CLINK_TESTCTRL    = 8'h34; // test control
localparam CLINK_TESTSTATUS  = 8'h38; // test status
localparam CLINK_CRDTINIT    = 8'h40; // Credit init value
localparam CLINK_CRDTINTRVL  = 8'h44; // Credir update interval
localparam CLINK_CRDTSTAT    = 8'h48; // Credit status

// Non-Zero Default Values
localparam DEF_SPICLK       = 8'h04;
localparam DEF_SPITIMEOUT   = 32'h10;
