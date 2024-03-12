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
 ******************************************************************************/

#pragma once

class TLMemsim {
public:
    TLMemsim(uint64_t base, uint64_t size);
    ~TLMemsim();
    void reset();
    void apply(uint8_t &a_ready, uint8_t a_valid, uint8_t a_opcode,
            uint8_t a_param, uint8_t a_size, uint8_t a_source,
            uint32_t a_address, uint8_t a_mask, uint64_t a_data,
            uint8_t a_corrupt, uint8_t d_ready, uint8_t &d_valid,
            uint8_t &d_opcode, uint8_t &d_param, uint8_t &d_size,
            uint8_t &d_source, uint8_t &d_sink, uint8_t &d_denied,
            uint64_t &d_data, uint8_t &d_corrupt);
    void load(const char *fn, size_t offset);
private:
    // Configurations
    uint64_t base;
    uint64_t size;
    uint64_t *mem;
    // Current processing request
    int req_beatcount;
    uint64_t req_addr;
    uint8_t req_opcode;
    uint8_t req_source;
    uint8_t req_size;
    uint8_t req_param;
    int req_firstbeat;
    int req_bubble;
    uint64_t get_bitmask(uint8_t mask);
    int get_beats(uint8_t size);
    uint64_t read(uint64_t addr);
    void write(uint64_t addr, uint64_t data, uint8_t mask);
    uint64_t rmwa(uint64_t addr, uint64_t data, uint8_t mask, uint8_t param);
    uint64_t rmwl(uint64_t addr, uint64_t data, uint8_t mask, uint8_t param);
};
