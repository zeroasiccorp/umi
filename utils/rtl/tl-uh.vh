/******************************************************************************
 * Function:  TileLink Uncached Heavyweight (TL-UH) definitions
 * Author:    Wenting Zhang
 * Copyright: 2022 Zero ASIC Corporation. All rights reserved.
 * License:
 *
 * Documentation:
 *
 *
 *****************************************************************************/

// Opcode for channel A
`define TL_OP_Get               3'd4
`define TL_OP_PutFullData       3'd0
`define TL_OP_PutPartialData    3'd1
`define TL_OP_ArithmeticData    3'd2
`define TL_OP_LogicalData       3'd3
`define TL_OP_Intent            3'd5

// Opcode for channel D
`define TL_OP_AccessAck         3'd0
`define TL_OP_AccessAckData     3'd1
`define TL_OP_HintAck           3'd2

// Param for arithmetic data
`define TL_PA_MIN               3'd0
`define TL_PA_MAX               3'd1
`define TL_PA_MINU              3'd2
`define TL_PA_MAXU              3'd3
`define TL_PA_ADD               3'd4

// Param for logical data
`define TL_PL_XOR               3'd0
`define TL_PL_OR                3'd1
`define TL_PL_AND               3'd2
`define TL_PL_SWAP              3'd3
