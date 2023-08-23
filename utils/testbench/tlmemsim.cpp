/******************************************************************************
 * Function:  TileLink memory simulator
 * Author:    Wenting Zhang
 * Copyright: 2022 Zero ASIC Corporation. All rights reserved.
 * License:
 *
 * Documentation:
 *   Single-cycle access TL-UH memory model.
 *
 *****************************************************************************/
#include <stdlib.h>
#include <stdio.h>
#include <stdint.h>
#include <assert.h>
#include "tlmemsim.h"
#include "tilelink.h"

//#define VERBOSE

#define ASSERTS

TLMemsim::TLMemsim(uint64_t base, uint64_t size) {
    this->base = base;
    this->size = size;
    this->mem = (uint64_t *)malloc(size);
    assert(this->mem);
    req_beatcount = 0;
}

TLMemsim::~TLMemsim() {
    free(mem);
}

void TLMemsim::reset() {
    // Called during simulator reset
    req_beatcount = 0;
}

uint64_t TLMemsim::read(uint64_t addr) {
    // Unaligned access is legal
    addr -= base;
    addr >>= 3;
    return mem[addr];
}

void TLMemsim::write(uint64_t addr, uint64_t data, uint8_t mask) {
    addr -= base;
    addr >>= 3;
    if (mask == 0xff) {
        mem[addr] = data;
    }
    else {
        uint64_t d = mem[addr];
        uint64_t bm = get_bitmask(mask);
        d &= ~bm;
        d |= data & bm;
        mem[addr] = d;
    }
}

uint64_t TLMemsim::rmwa(uint64_t addr, uint64_t data, uint8_t mask,
        uint8_t param) {
    addr -= base;
    addr >>= 3;
    uint64_t od = mem[addr];
    uint64_t bm = get_bitmask(mask);
    uint64_t r1 = od & bm;
    uint64_t r2 = data & bm;
    int64_t sr1 = (int64_t)r1;
    int64_t sr2 = (int64_t)r2;
    assert(((mask == 0x0f) || (mask == 0xf0) || (mask == 0xff)));
    if (bm == 0x0f) {
        // Fix sign extension
        sr1 = (sr1 << 32) | sr1;
        sr2 = (sr2 << 32) | sr2;
    }
    uint64_t wb = 0;
    switch (param)
    {
    case PA_MIN:
        wb = (uint64_t)((sr1 < sr2) ? sr1 : sr2);
        break;
    case PA_MAX:
        wb = (uint64_t)((sr1 < sr2) ? sr2 : sr1);
        break;
    case PA_MINU:
        wb = (r1 < r2) ? r1 : r2;
        break;
    case PA_MAXU:
        wb = (r1 < r2) ? r2 : r1;
        break;
    case PA_ADD:
        wb = r1 + r2;
        break;
    default:
        fprintf(stderr, "Unknown RMWA operation %d\n", param);
        break;
    }
    mem[addr] = od & ~bm;
    mem[addr] |= wb & bm;
    return od;
}

uint64_t TLMemsim::rmwl(uint64_t addr, uint64_t data, uint8_t mask,
        uint8_t param) {
    addr -= base;
    addr >>= 3;
    uint64_t od = mem[addr];
    uint64_t bm = get_bitmask(mask);
    uint64_t r1 = od & bm;
    uint64_t r2 = data & bm;
    uint64_t wb = 0;
    #ifdef ASSERTS
    assert(((mask == 0x0f) || (mask == 0xf0) || (mask == 0xff)));
    #endif
    switch (param)
    {
    case PL_XOR:
        wb = r1 ^ r2;
        break;
    case PL_OR:
        wb = r1 | r2;
        break;
    case PL_AND:
        wb = r1 & r2;
        break;
    case PL_SWAP:
        wb = r2;
        break;
    default:
        fprintf(stderr, "Unknown RMWL operation %d\n", param);
        break;
    }
    mem[addr] = od & ~bm;
    mem[addr] |= wb & bm;
    return od;
}

int TLMemsim::get_beats(uint8_t size) {
    int byte_size = (1l << size);
    int beats = (byte_size + 7) / 8;
    return beats;
}

uint64_t TLMemsim::get_bitmask(uint8_t mask) {
    uint64_t bm = 0;
    for (int i = 0; i < 8; i++) {
        if (mask & 0x01)
            bm |= (0xffull << i * 8);
        mask >>= 1;
    }
    return bm;
}

void TLMemsim::apply(uint8_t &a_ready, uint8_t a_valid, uint8_t a_opcode,
        uint8_t a_param, uint8_t a_size, uint8_t a_source, uint32_t a_address,
        uint8_t a_mask, uint64_t a_data, uint8_t a_corrupt, uint8_t d_ready,
        uint8_t &d_valid, uint8_t &d_opcode, uint8_t &d_param, uint8_t &d_size,
        uint8_t &d_source, uint8_t &d_sink, uint8_t &d_denied, uint64_t &d_data,
        uint8_t &d_corrupt) {
    // Called during every posedge clk
    // Default values
    d_valid = 0;
    a_ready = 1;
    // Only handle new request if no active request
    if ((req_beatcount == 0) && (a_valid)) {
        req_addr = a_address & 0x7FFFFFFFul;
        req_opcode = a_opcode;
        req_source = a_source;
        req_size = a_size;
        req_param = a_param;
        req_beatcount = get_beats(a_size);
        req_firstbeat = 1;
        req_bubble = 0;
    }
    // Processing request
    if (req_beatcount != 0) {
        switch (req_opcode) {
        case OP_Get:
            if (req_firstbeat) {
                req_beatcount++;
                req_firstbeat = 0;
            }
            if (!d_ready) {
                // Previous beat is processed
                #ifdef VERBOSE
                fprintf(stderr, "Stall\n");
                #endif
                d_valid = 1;
                a_ready = 0;
                break;
            }
            // This is a single beat command
            if (req_beatcount == 1) {
                d_valid = 0;
                a_ready = 1;
                req_beatcount = 0;
                break;
            }
            a_ready = 0;
            #ifdef ASSERTS
            assert(req_param == 0);
            #endif
            d_valid = 1;
            d_param = 0;
            d_size = req_size;
            d_source = req_source;
            d_sink = 0;
            d_corrupt = 0;
            d_denied = 0;
            d_opcode = OP_AccessAckData;
            d_data = read(req_addr);
            #ifdef VERBOSE
            fprintf(stderr, "MEM: GET address %08lx beat %d = %016lx...\n",
                    req_addr, req_beatcount, d_data);
            #endif
            req_beatcount--;
            req_addr += 8;
        break;
        case OP_PutFullData:
        case OP_PutPartialData:
            // This is a multi beat command
            a_ready = 1;
            #ifdef ASSERTS
            assert(req_param == 0);
            #endif
            if (req_bubble) {
                if (d_ready) { 
                    // Accepted
                    a_ready = 1;
                    req_beatcount = 0;
                    #ifdef VERBOSE
                    fprintf(stderr, "Accepted\n");
                    #endif
                }
                else {
                    // Not accepted last cycle, try again
                    d_valid = 1;
                    a_ready = 0;
                }
            }
            else if (a_valid) {
                #ifdef VERBOSE
                fprintf(stderr, "MEM: PUT address %08lx beat %d = %016lx mask %02x...\n",
                        req_addr, req_beatcount, a_data, a_mask);
                #endif
                // TODO: Handle corrupt
                write(req_addr, a_data, a_mask);
                req_beatcount--;
                req_addr += 8;
                if (req_beatcount == 0) {
                    // Finished burst
                    d_valid = 1;
                    d_param = 0;
                    d_size = req_size;
                    d_source = req_source;
                    d_sink = 0;
                    d_corrupt = 0;
                    d_denied = 0;
                    d_opcode = OP_AccessAck;
                    d_data = 0;
                    if (!d_ready) {
                        // Ack not accepted, need to wait more cycles
                        req_bubble = 1;
                        req_beatcount = 1;
                        a_ready = 0;
                    }
                    else {
                        #ifdef VERBOSE
                        fprintf(stderr, "Accepted\n");
                        #endif
                    }
                }
            }
        break;
        case OP_ArithmeticData:
        case OP_LogicalData:
            a_ready = 1;
            if (req_bubble) {
                if (d_ready) {
                    // processing continue next cycle
                    req_bubble = 0;
                }
                else {
                    d_valid = 1;
                }
            }
            else if (a_valid) {
                //#ifdef VERBOSE
                fprintf(stderr, "MEM: ATOM OP %d PA %d address %08lx beat %d = %016lx mask %02x...\n",
                        req_opcode, req_param, req_addr, req_beatcount, a_data, a_mask);
                //#endif
                d_valid = 1;
                d_param = 0;
                d_size = req_size;
                d_source = req_source;
                d_sink = 0;
                d_corrupt = 0;
                d_denied = 0;
                d_opcode = OP_AccessAckData;
                if (req_opcode == OP_ArithmeticData)
                    d_data = rmwa(req_addr, a_data, a_mask, req_param);
                else
                    d_data = rmwl(req_addr, a_data, a_mask, req_param);
                req_beatcount--;
                req_addr += 8;
                if (!d_ready) {
                    // Ack not received, need to insert bubble
                    a_ready = 0;
                    req_bubble = 1;
                }
            }
        break;
        case OP_Intent:
            // Ignore
            #ifdef VERBOSE
            fprintf(stderr, "MEM: INTENT %s (%d) address %08lx size %d...\n", 
                    (req_param == 0) ? "PrefetchRead" :
                    (req_param == 1) ? "PrefetchWrite" : "Unknown",
                    req_param, req_addr, req_size);
            #endif
            if (req_firstbeat) {
                req_firstbeat = 0;
            }
            else {
                // Check if data is accepted last cycle
                if (d_ready) { 
                    // Accepted
                    a_ready = 1;
                    req_beatcount = 0;
                    #ifdef VERBOSE
                    fprintf(stderr, "Accepted\n");
                    #endif
                }
                else {
                    // Not accepted last cycle, try again
                    d_valid = 1;
                    a_ready = 0;
                }
            }
            d_valid = 1;
            d_param = 0;
            d_size = req_size;
            d_source = req_source;
            d_sink = 0;
            d_corrupt = 0;
            d_denied = 0;
            d_opcode = OP_HintAck;
            d_data = 0;
        break;
        }
    }
}

void TLMemsim::load(const char *fn, size_t offset) {
    FILE *fp;
    fp = fopen(fn, "rb+");
    if (!fp) {
        fprintf(stderr, "Error: unable to open file %s\n", fn);
        exit(1);
    }
    fseek(fp, 0, SEEK_END);
    size_t fsize = ftell(fp);
    fseek(fp, 0, SEEK_SET);
    size_t result = fread((void *)((size_t)mem + offset), fsize, 1, fp);
    assert(result == 1);
    fclose(fp);
}
