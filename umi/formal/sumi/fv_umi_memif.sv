/*******************************************************************************
 * Copyright 2026 Zero ASIC Corporation
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
 *
 * - Proves the read-modify-write unit in umi_memif computes each of the
 *   atomic operations it implements, and pins down what it does with an
 *   ATYPE that names none of them.
 *
 *   README.md section 3.4.6 names eight: ADD, OR, XOR, MAX, MIN, MAXU,
 *   MINU, SWAP. The RTL implements a ninth, ATOMICAND, which
 *   umi_messages.vh:85 assigns ATYPE 0x01 and no section of the
 *   specification lists. It is proven here because it is shipped, not
 *   because the specification asks for it.
 *
 * THE OPERAND ALIGNMENT, AND WHY THE HARNESS REMOVES IT. umi_memif does
 * not feed the ALU the raw operands. It left-justifies both of them --
 * umi_wrdata_r is the request data shifted up by DW minus the transfer
 * width (umi_memif.v:115), and mem_rddata_atomic is the memory word
 * masked and shifted the same way (umi_memif.v:122) -- runs the
 * operation there, and shifts the result back down on the way out
 * (umi_memif.v:156). The justification is what makes the signed
 * comparisons work: it puts the operand's sign bit at bit DW-1 whatever
 * the transfer width is.
 *
 * That shifting is not what these rows are about, and leaving it in
 * would mean asserting the arithmetic through two shifts and a mask --
 * which is the RTL's own expression written twice. So the harness
 * assumes ONE transfer shape: a full-width, size-aligned atomic
 * (m_alu_size, m_alu_len, m_alu_align). At that shape umi_bytes is
 * exactly DW/8, so postatomic_shift is zero, the mask is all ones, and
 * every shift in the path is the identity. What is left at mem_wrdata
 * is the bare operation, and the assertions below state the arithmetic
 * directly.
 *
 * WHAT IS OBSERVED, AND WHAT IS SHADOWED. The atomic cycle is
 * port-visible: umi_ready is exactly ~umi_atomic_r (umi_memif.v:96), so
 * no hierarchical reference into the DUT is needed to know when the
 * result is being written. ATYPE and the request data are not visible a
 * cycle later, so the harness keeps its own one-cycle copies of those
 * two PORT INPUTS. Copying an input is not copying logic: the registers
 * here hold what was presented at the port, and the proof is still
 * against the block's own output.
 *
 * THE LAWS. With a and b the two operands -- a the request data, b the
 * memory word -- one per encoding (umi_messages.vh:84-92):
 *   a_alu_add   0x00  a + b        a_alu_smax  0x04  signed max
 *   a_alu_and   0x01  a & b        a_alu_smin  0x05  signed min
 *   a_alu_or    0x02  a | b        a_alu_umax  0x06  unsigned max
 *   a_alu_xor   0x03  a ^ b        a_alu_umin  0x07  unsigned min
 *   a_alu_swap  0x08  a
 *
 * AND THE TENTH. ATYPE is eight bits and only 0x00-0x08 name an
 * operation, so the case has a default arm, and that arm returns the
 * request data (umi_memif.v:139) -- the same thing SWAP returns.
 * a_alu_default asserts exactly that: an atomic carrying an ATYPE
 * outside the defined set overwrites memory rather than being rejected
 * or ignored. c_alu_default witnesses it is reachable.
 *
 * This is the second half of something fv_umi_decode already showed
 * from the other end: umi_decode raises cmd_atomic on a command whose
 * five-bit opcode is not REQ_ATOMIC, because it compares four bits
 * (see c_dec_alias_atomic there). A command that is not an atomic can
 * therefore reach this ALU, and if its ATYPE field is above 0x08 the
 * result is a write of the request data. Neither block is doing
 * anything its own code does not say; the composition is what is worth
 * having written down. No property here calls it a defect.
 *
 * Outside these laws: partial-width and unaligned atomics (the RTL's
 * own header records partial writes as unsupported), the memory
 * interface timing, and the read path.
 *
 * ROWS (tests/sumi/test_formal_sc.py):
 *   memif:prove           all ten laws, unbounded
 *   memif:cover           witnesses: expect all reached
 *   memif:fault_add       must FAIL, a_alu_add
 *   memif:fault_smax      must FAIL, a_alu_smax
 *   memif:fault_swap      must FAIL, a_alu_swap
 *   memif:fault_default   must FAIL, a_alu_default
 *
 ******************************************************************************/

`default_nettype none

module fv_umi_memif #(
    parameter DW = 64,
    parameter AW = 64
) (
    input wire clk
);

`include "umi_messages.vh"

    localparam SHIFTW = $clog2(DW/8);    // byte offset bits in the address

    // ----------------------------------------------------------------
    // reset: free, but asserted at time zero (grounds all history)
    // ----------------------------------------------------------------
    (* anyseq *) wire nreset;
    reg f_past_exists = 1'b0;
    always @(posedge clk)
        f_past_exists <= 1'b1;
    always @(*)
        if (!f_past_exists)
            assume (!nreset);

    reg past_nreset = 1'b0;
    always @(posedge clk)
        past_nreset <= nreset;

    // ----------------------------------------------------------------
    // free stimulus
    // ----------------------------------------------------------------
    (* anyseq *) wire          umi_read;
    (* anyseq *) wire          umi_write;
    (* anyseq *) wire          umi_atomic;
    (* anyseq *) wire [2:0]    umi_size;
    (* anyseq *) wire [7:0]    umi_len;
    (* anyseq *) wire [7:0]    umi_atype;
    (* anyseq *) wire [AW-1:0] umi_addr;
    (* anyseq *) wire [DW-1:0] umi_wrdata;
    (* anyseq *) wire [DW-1:0] mem_rddata;

    // ONE transfer shape: full width, size aligned. See THE OPERAND
    // ALIGNMENT above -- this is what makes every shift the identity so
    // the arithmetic is readable at the port.
    always @(*) begin
        m_alu_size  : assume (umi_size == SHIFTW[2:0]);
        m_alu_len   : assume (umi_len == 8'd0);
        m_alu_align : assume (umi_addr[SHIFTW-1:0] == {SHIFTW{1'b0}});
    end

    wire          umi_ready;
    wire [DW-1:0] umi_rddata;
    wire          mem_ce;
    wire          mem_we;
    wire [AW-1:0] mem_addr;
    wire [DW-1:0] mem_wrmask;
    wire [DW-1:0] mem_wrdata;

    umi_memif #(
        .DW (DW), .AW (AW)
    ) dut (
        .clk        (clk),
        .nreset     (nreset),
        .umi_read   (umi_read),
        .umi_write  (umi_write),
        .umi_atomic (umi_atomic),
        .umi_size   (umi_size),
        .umi_len    (umi_len),
        .umi_atype  (umi_atype),
        .umi_addr   (umi_addr),
        .umi_wrdata (umi_wrdata),
        .umi_rddata (umi_rddata),
        .umi_ready  (umi_ready),
        .mem_ce     (mem_ce),
        .mem_we     (mem_we),
        .mem_addr   (mem_addr),
        .mem_wrmask (mem_wrmask),
        .mem_wrdata (mem_wrdata),
        .mem_rddata (mem_rddata)
    );

    // ----------------------------------------------------------------
    // the two operands, as the block sees them on the write cycle
    //
    // atomic_active is read off umi_ready, which the block drives as
    // ~umi_atomic_r, so the cycle is port-visible. a and b are the
    // request data held one cycle and the memory word presented now.
    // ----------------------------------------------------------------
    reg [DW-1:0] wrdata_q;
    reg [7:0]    atype_q;
    always @(posedge clk or negedge nreset)
        if (!nreset) begin
            wrdata_q <= {DW{1'b0}};
            atype_q  <= 8'h0;
        end else begin
            wrdata_q <= umi_wrdata;
            atype_q  <= umi_atype;
        end

    wire atomic_active = ~umi_ready;
    wire [DW-1:0] a = wrdata_q;
    wire [DW-1:0] b = mem_rddata;

    // ----------------------------------------------------------------
    // observed result: the faults corrupt what the laws see, never the
    // DUT, and each one is confined to a single encoding so it can
    // convict only its own law. No RTL is copied or edited.
    // ----------------------------------------------------------------
    (* anyseq *) wire f_glitch;

`ifdef FV_FAULT_ADD
    wire [DW-1:0] obs = mem_wrdata
                      ^ ((atype_q == 8'h00) ? {DW{f_glitch}} : {DW{1'b0}});
`elsif FV_FAULT_SMAX
    wire [DW-1:0] obs = mem_wrdata
                      ^ ((atype_q == 8'h04) ? {DW{f_glitch}} : {DW{1'b0}});
`elsif FV_FAULT_SWAP
    wire [DW-1:0] obs = mem_wrdata
                      ^ ((atype_q == 8'h08) ? {DW{f_glitch}} : {DW{1'b0}});
`elsif FV_FAULT_DEFAULT
    wire [DW-1:0] obs = mem_wrdata
                      ^ ((atype_q > 8'h08) ? {DW{f_glitch}} : {DW{1'b0}});
`else
    wire [DW-1:0] obs = mem_wrdata;
`endif

    // ----------------------------------------------------------------
    // the nine implemented operations, and the arm that catches the rest
    // ----------------------------------------------------------------
    always @(posedge clk)
        if (f_past_exists & nreset & past_nreset & atomic_active) begin
            a_alu_add : assert ((atype_q != UMI_REQ_ATOMICADD)
                                || (obs == (a + b)));
            a_alu_and : assert ((atype_q != UMI_REQ_ATOMICAND)
                                || (obs == (a & b)));
            a_alu_or : assert ((atype_q != UMI_REQ_ATOMICOR)
                               || (obs == (a | b)));
            a_alu_xor : assert ((atype_q != UMI_REQ_ATOMICXOR)
                                || (obs == (a ^ b)));
            a_alu_smax : assert ((atype_q != UMI_REQ_ATOMICMAX)
                                 || (obs == (($signed(a) > $signed(b))
                                             ? a : b)));
            a_alu_smin : assert ((atype_q != UMI_REQ_ATOMICMIN)
                                 || (obs == (($signed(a) > $signed(b))
                                             ? b : a)));
            a_alu_umax : assert ((atype_q != UMI_REQ_ATOMICMAXU)
                                 || (obs == ((a > b) ? a : b)));
            a_alu_umin : assert ((atype_q != UMI_REQ_ATOMICMINU)
                                 || (obs == ((a > b) ? b : a)));
            a_alu_swap : assert ((atype_q != UMI_REQ_ATOMICSWAP)
                                 || (obs == a));
            // an ATYPE naming no operation writes the request data --
            // the same result SWAP gives
            a_alu_default : assert ((atype_q <= UMI_REQ_ATOMICSWAP)
                                    || (obs == a));
        end

    // ----------------------------------------------------------------
    // witnesses
    // ----------------------------------------------------------------
`ifdef FORMAL
    always @(posedge clk)
        if (f_past_exists & nreset & past_nreset & atomic_active) begin
            c_alu_add     : cover (atype_q == UMI_REQ_ATOMICADD);
            c_alu_swap    : cover (atype_q == UMI_REQ_ATOMICSWAP);
            // the undefined arm is reachable, and this is the cover the
            // composition note in the header rests on
            c_alu_default : cover (atype_q > UMI_REQ_ATOMICSWAP);
            // an add that actually carries out of the low half, so the
            // law is not passing on trivial operands
            c_alu_carry   : cover ((atype_q == UMI_REQ_ATOMICADD)
                                   && (a[DW/2-1:0] != {(DW/2){1'b0}})
                                   && (b[DW/2-1:0] != {(DW/2){1'b0}})
                                   && (obs[DW-1] != a[DW-1]));
            // signed and unsigned maximum disagreeing on the same pair:
            // the case that separates a_alu_smax from a_alu_umax
            c_alu_signed_distinct : cover ((atype_q == UMI_REQ_ATOMICMAX)
                                           && (($signed(a) > $signed(b))
                                               != (a > b)));
        end
`endif

endmodule

`default_nettype wire
