import math
import cocotb

from cocotb.handle import SimHandleBase
from cocotb.triggers import ClockCycles
from cocotb_bus.drivers import BitDriver

from cocotbext.umi.sumi import SumiTransaction, SumiCmdType, SumiCmd
from cocotbext.umi.utils.generators import random_toggle_generator
from env import UMI2APBEnv, create_expected_write_response


@cocotb.test(timeout_time=50, timeout_unit="ms")
async def test_basic_WR(dut: SimHandleBase):
    """
    Basic sanity test:
      1. Single aligned UMI write
      2. Verify APB memory contents
      3. Single UMI read
      4. Verify response payload
    """

    # Grab shared test environment
    env = UMI2APBEnv(dut)
    await env.start()

    BitDriver(signal=dut.udev_resp_ready, clk=env.clk).start(
        generator=random_toggle_generator()
    )

    umi_size = int(math.log2(env.data_size))
    test_addr = 0x100
    test_data = 0xDEADBEEF

    print("=== Basic Write Test ===")

    # WRITE transaction
    write_txn = SumiTransaction(
        cmd=SumiCmd.from_fields(
            cmd_type=int(SumiCmdType.UMI_REQ_WRITE),
            size=umi_size,
            len=0,
        ),
        da=test_addr,
        sa=0x0,
        data=test_data.to_bytes(env.data_size, byteorder="little"),
    )

    env.expected_responses.append(
        create_expected_write_response(
            write_txn,
            data_size=env.data_size,
            addr_width=env.addr_width,
        )
    )

    await env.sumi_driver.send(write_txn)
    await ClockCycles(env.clk, 20)

    # Verify APB memory contents
    mem_data = await env.region.read(test_addr, env.data_size)
    assert int.from_bytes(mem_data, byteorder="little") == test_data, (
        f"Write failed: expected 0x{test_data:x}, "
        f"got 0x{int.from_bytes(mem_data, 'little'):x}"
    )

    print(f" Data written to memory: 0x{test_data:08x}")
    print(" UMI write response verified by scoreboard")

    print("\n=== Basic Read Test ===")

    # READ transaction
    read_txn = SumiTransaction(
        cmd=SumiCmd.from_fields(
            cmd_type=int(SumiCmdType.UMI_REQ_READ),
            size=umi_size,
            len=0,
        ),
        da=test_addr,
        sa=0x0,
        data=bytearray(env.data_size),
    )

    expected_read_resp = SumiTransaction(
        cmd=SumiCmd.from_fields(
            cmd_type=int(SumiCmdType.UMI_RESP_READ),
            size=umi_size,
            len=0,
        ),
        da=0x0,
        sa=test_addr,
        data=test_data.to_bytes(env.data_size, byteorder="little"),
        addr_width=env.addr_width,
    )

    env.expected_responses.append(expected_read_resp)
    await env.sumi_driver.send(read_txn)

    # Wait for scoreboard to consume all expected outputs
    while len(env.expected_responses) != 0:
        await ClockCycles(env.clk, 1)

    await ClockCycles(env.clk, 10)

    print("Read response verified by scoreboard")

    # Check scoreboard results
    raise env.scoreboard.result
