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
 * ----
 *
 * Documentation:
 * - Simulator global configurations
 *
 ******************************************************************************/

#pragma once

#define CLK_PREIOD_PS       (10000)
#define CLK_HALF_PERIOD_PS  (CLK_PREIOD_PS / 2)

#define UART_BAUD           (115200)

#define RAM_BASE            (0x00000000)
#define RAM_SIZE            (1024 * 1024 * 1024)

#define RAM_LOAD_OFFSET     (0x00000000)
