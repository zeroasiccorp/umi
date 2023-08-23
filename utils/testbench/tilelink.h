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
#pragma once

typedef enum {
    // TL-UL
    OP_Get = 4,
    OP_PutFullData = 0,
    OP_PutPartialData = 1,
    // TL-UH
    OP_ArithmeticData = 2,
    OP_LogicalData = 3,
    OP_Intent = 5
} TLOpcode_AB;

typedef enum {
    // TL-UL
    OP_AccessAckData = 1,
    OP_AccessAck = 0,
    // TL-UH
    OP_HintAck = 2
} TLOpcode_CD;

typedef enum {
    PA_MIN = 0,
    PA_MAX = 1,
    PA_MINU = 2,
    PA_MAXU = 3,
    PA_ADD = 4
} TLParam_Arithmetic;

typedef enum {
    PL_XOR = 0,
    PL_OR = 1,
    PL_AND = 2,
    PL_SWAP = 3
} TLParam_Logical;