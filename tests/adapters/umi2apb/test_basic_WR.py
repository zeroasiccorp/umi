import math
import cocotb

from cocotb.handle import SimHandleBase
from cocotb.triggers import ClockCycles

from sumi import SumiTransaction, SumiCmdType, SumiCmd
from adapters.umi2apb.env import UMI2APBEnv, create_expected_write_response


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

    env.sumi_driver.append(write_txn)

    # Wait for write response
    await env.wait_for_responses(max_cycles=100)

    # Verify APB memory contents
    mem_data = await env.region.read(test_addr, env.data_size)
    assert int.from_bytes(mem_data, byteorder="little") == test_data, (
        f"Write failed: expected 0x{test_data:x}, "
        f"got 0x{int.from_bytes(mem_data, 'little'):x}"
    )

    print(f"    Data written to memory: 0x{test_data:08x}")
    print(f"    UMI write response verified by scoreboard")

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
    env.sumi_driver.append(read_txn)

    # Wait for read response
    await env.wait_for_responses(max_cycles=100)

    print(f"    Read response verified by scoreboard")

    # Check scoreboard results
    raise env.scoreboard.result
