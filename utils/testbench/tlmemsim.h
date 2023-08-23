/******************************************************************************
 * Function:  TileLink (TL-UH) memory simulator
 * Author:    Wenting Zhang
 * Copyright: 2022 Zero ASIC Corporation. All rights reserved.
 * License:
 *
 * Documentation:
 *
 *
 *****************************************************************************/
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
