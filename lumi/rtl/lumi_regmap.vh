/*****************************************************************************
 * Function:  LUMI Register Map
 * Author:    Amir Volk
 *
 * Copyright (c) 2023 Zero ASIC Corporation. All rights reserved.
 * This code is licensed under Apache License 2.0 (see LICENSE for details)
 *
 * Version history:
 * Ver 1 - convert from CLINK register
 *
 *****************************************************************************/

// registers (addr[7:0]), 32bit aligned
localparam LUMI_CTRL        = 8'h00; // device configuration
localparam LUMI_STATUS      = 8'h04; // device status
localparam LUMI_TXMODE      = 8'h10; // tx operating mode
localparam LUMI_RXMODE      = 8'h14; // rx operating mode
localparam LUMI_CRDTINIT    = 8'h20; // Credit init value
localparam LUMI_CRDTINTRVL  = 8'h24; // Credir update interval
localparam LUMI_CRDTSTAT    = 8'h28; // Credit status
