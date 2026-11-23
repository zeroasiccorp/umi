import math
from random import randbytes

import cocotb
from cocotb.handle import SimHandleBase
from cocotb.triggers import ClockCycles, RisingEdge

from cocotbext.umi.sumi import (
    SumiTransaction,
    SumiCmdType,
    SumiCmd,
    SumiErrorCode
)
from adapters.umi2apb.env import UMI2APBEnv, create_expected_write_response


# Counts completed APB transfers (psel & penable & pready)
async def count_apb_transfers(dut, clk, counter):
    while True:
        await RisingEdge(clk)
        if dut.apb_psel.value and dut.apb_penable.value and dut.apb_pready.value:
            counter[0] += 1


# Waits until the scoreboard has consumed every expected response
async def drain(env):
    while len(env.expected_responses) != 0:
        await ClockCycles(env.clk, 1)
    await ClockCycles(env.clk, 5)


def request(cmd_type, size, addr, data, ln=0):
    return SumiTransaction(
        cmd=SumiCmd.from_fields(cmd_type=int(cmd_type), size=size, len=ln),
        da=addr,
        sa=0x0,
        data=data,
    )


# An error response: RESP_RD (read, atomic) or RESP_WR (write), SIZE and LEN
# of the request, ERR set, zero data
def error_response(req, err, addr_width, bus_bytes):
    req_type = int(req.cmd.cmd_type)
    size = int(req.cmd.size)
    ln = int(req.cmd.len)
    if req_type in (SumiCmdType.UMI_REQ_READ, SumiCmdType.UMI_REQ_ATOMIC):
        resp_type = SumiCmdType.UMI_RESP_READ
    else:
        resp_type = SumiCmdType.UMI_RESP_WRITE
    nbytes = min((ln + 1) << size, bus_bytes)
    return SumiTransaction(
        cmd=SumiCmd.from_fields(cmd_type=int(resp_type), size=size, len=ln, u=int(err)),
        da=int(req.sa),
        sa=int(req.da),
        data=bytearray(nbytes),
        addr_width=addr_width,
    )


@cocotb.test(timeout_time=50, timeout_unit="ms")
async def test_subword(dut: SimHandleBase):
    """
    Every SIZE up to RW at every aligned offset in an APB word:
      1. Fill the word with random bytes
      2. UMI write of 2^SIZE bytes (random bytes above them on the bus)
      3. Only the addressed bytes of the word change
      4. UMI read of the same bytes returns them
    """

    env = UMI2APBEnv(dut, backpressure_on_apb=True)
    await env.start()
    dut.udev_resp_ready.value = 1

    word_bytes = env.data_size
    max_size = int(math.log2(word_bytes))
    base = 0x200

    for size in range(max_size + 1):
        nbytes = 1 << size
        for offset in range(0, word_bytes, nbytes):
            fill = randbytes(word_bytes)
            await env.region.write(base, fill)

            # the bytes above 2^SIZE on the bus are garbage and must be ignored
            wdata = randbytes(word_bytes)
            addr = base + offset

            write_txn = request(SumiCmdType.UMI_REQ_WRITE, size, addr, wdata)
            env.expected_responses.append(
                create_expected_write_response(write_txn, word_bytes, env.addr_width)
            )
            await env.sumi_driver.send(write_txn)
            await drain(env)

            expected = bytearray(fill)
            expected[offset:offset + nbytes] = wdata[:nbytes]
            mem = await env.region.read(base, word_bytes)
            assert mem == expected, (
                f"size {size} offset {offset}: expected {expected.hex()}, got {mem.hex()}"
            )

            read_txn = request(SumiCmdType.UMI_REQ_READ, size, addr, bytearray(word_bytes))
            env.expected_responses.append(SumiTransaction(
                cmd=SumiCmd.from_fields(
                    cmd_type=int(SumiCmdType.UMI_RESP_READ), size=size, len=0
                ),
                da=0x0,
                sa=addr,
                data=bytes(wdata[:nbytes]),
                addr_width=env.addr_width,
            ))
            await env.sumi_driver.send(read_txn)
            await drain(env)

            # the response bytes above 2^SIZE are zero
            resp_data = int(dut.udev_resp_data.value)
            assert resp_data >> (8 * nbytes) == 0, (
                f"size {size} offset {offset}: response data above 2^SIZE not zero: {resp_data:x}"
            )

    raise env.scoreboard.result


@cocotb.test(timeout_time=50, timeout_unit="ms")
async def test_errors(dut: SimHandleBase):
    """
    Requests the adapter cannot execute:
      - read, write or atomic: DEVERR (NETERR outside the group), no APB
        transfer, memory unchanged
      - posted write: dropped, no response, no APB transfer
      - a valid read after each error still completes
    """

    env = UMI2APBEnv(dut, backpressure_on_apb=False)
    await env.start()
    dut.udev_resp_ready.value = 1

    transfers = [0]
    cocotb.start_soon(count_apb_transfers(dut, env.clk, transfers))

    word_bytes = env.data_size
    bus_bytes = len(dut.udev_resp_data) // 8
    max_size = int(math.log2(word_bytes))
    base = 0x400
    grpaw = int(dut.GRPAW.value)
    grpoffset = int(dut.GRPOFFSET.value)

    fill = randbytes(4 * word_bytes)
    await env.region.write(base, fill)

    deverr = SumiErrorCode.UMI_ERR_DEVERR
    neterr = SumiErrorCode.UMI_ERR_NETERR
    rd = SumiCmdType.UMI_REQ_READ
    wr = SumiCmdType.UMI_REQ_WRITE
    at = SumiCmdType.UMI_REQ_ATOMIC
    data = randbytes(word_bytes)

    # (name, opcode, size, address, len, error)
    cases = [
        ("read size > RW", rd, max_size + 1, base, 0, deverr),
        ("write size > RW", wr, max_size + 1, base, 0, deverr),
        ("read misaligned", rd, 1, base + 1, 0, deverr),
        ("write misaligned", wr, 1, base + 1, 0, deverr),
        ("read len > 0", rd, max_size, base, 1, deverr),
        ("write len > 0", wr, max_size, base, 1, deverr),
        ("atomic", at, max_size, base, 0, deverr),
    ]
    if grpaw != 0:
        other_group = base | (1 << grpoffset)
        cases += [
            ("read outside group", rd, max_size, other_group, 0, neterr),
            ("write outside group", wr, max_size, other_group, 0, neterr),
        ]

    for name, opcode, size, addr, ln, err in cases:
        print(f"=== {name} ===")
        before = transfers[0]
        txn = request(opcode, size, addr, data, ln=ln)
        env.expected_responses.append(error_response(txn, err, env.addr_width, bus_bytes))
        await env.sumi_driver.send(txn)
        await drain(env)
        assert transfers[0] == before, f"{name}: APB transfer on an error"

        # the adapter still executes a valid read
        ok = request(rd, max_size, base, bytearray(word_bytes))
        env.expected_responses.append(SumiTransaction(
            cmd=SumiCmd.from_fields(
                cmd_type=int(SumiCmdType.UMI_RESP_READ), size=max_size, len=0
            ),
            da=0x0,
            sa=base,
            data=bytes(fill[:word_bytes]),
            addr_width=env.addr_width,
        ))
        await env.sumi_driver.send(ok)
        await drain(env)
        assert transfers[0] == before + 1, f"{name}: read after the error not executed"

    # posted writes it cannot execute are dropped: no response, no transfer
    posted = [
        ("posted size > RW", max_size + 1, base, 0),
        ("posted misaligned", 1, base + 1, 0),
        ("posted len > 0", max_size, base, 1),
    ]
    if grpaw != 0:
        posted.append(("posted outside group", max_size, base | (1 << grpoffset), 0))

    for name, size, addr, ln in posted:
        print(f"=== {name} ===")
        before = transfers[0]
        txn = request(SumiCmdType.UMI_REQ_POSTED, size, addr, data, ln=ln)
        await env.sumi_driver.send(txn)
        await ClockCycles(env.clk, 20)
        assert transfers[0] == before, f"{name}: APB transfer on a dropped posted write"

    mem = await env.region.read(base, 4 * word_bytes)
    assert mem == fill, f"memory changed by a rejected request: {mem.hex()}"

    raise env.scoreboard.result
