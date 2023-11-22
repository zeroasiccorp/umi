/*******************************************************************************
 * Copyright 2022 Zero ASIC Corporation
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
 ******************************************************************************/

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
