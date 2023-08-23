/******************************************************************************
 * Function:  Simulator global configurations
 * Author:    Wenting Zhang
 * Copyright: 2022 Zero ASIC Corporation. All rights reserved.
 * License:
 *
 * Documentation:
 *
 *
 *****************************************************************************/
#pragma once

#define CLK_PREIOD_PS       (10000)
#define CLK_HALF_PERIOD_PS  (CLK_PREIOD_PS / 2)

#define UART_BAUD           (115200)

#define RAM_BASE            (0x00000000)
#define RAM_SIZE            (1024 * 1024 * 1024)

#define RAM_LOAD_OFFSET     (0x00000000)
