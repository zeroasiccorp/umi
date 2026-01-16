import math
import cocotb

from cocotb.handle import SimHandleBase
from cocotb.triggers import ClockCycles, RisingEdge

from sumi import SumiTransaction, SumiCmdType, SumiCmd
from adapters.umi2apb.env import UMI2APBEnv, create_expected_write_response


@cocotb.test(timeout_time=50, timeout_unit="ms")
async def test_backpressure(dut: SimHandleBase):
    """
    Test response backpressure handling:
      1. Disable response ready
      2. Send transactions
      3. Verify responses are held and not lost
      4. Enable ready and verify all responses arrive correctly
    """

    env = UMI2APBEnv(dut)
    await env.start()

    umi_size = int(math.log2(env.data_size))

    print("=== Backpressure Test ===")

    # Disable response ready
    dut.udev_resp_ready.value = 0

    # Send a write transaction
    test_addr = 0x100
    test_data = 0xDEADBEEF

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
    print(f"Sent write: addr=0x{test_addr:x}, data=0x{test_data:08x}")

    await ClockCycles(env.clk, 20)

    # Verify response is being held
    assert dut.udev_resp_valid.value == 1, "Response should be valid"
    assert len(env.expected_responses) == 1, "Response should not have been consumed yet"
    print("Response held with backpressure")

    # enable response ready
    dut.udev_resp_ready.value = 1
    print("Re-enabled udev_resp_ready")

    await env.wait_for_responses(max_cycles=10)

    # Verify mem was written correctly
    mem_data = await env.region.read(test_addr, env.data_size)
    actual_data = int.from_bytes(mem_data, byteorder="little")
    assert actual_data == test_data, (
        f"Write data mismatch: expected 0x{test_data:x}, got 0x{actual_data:x}"
    )
    print(f"Memory verified: 0x{actual_data:08x}")

    print("\n=== Backpressure Test PASSED ===")
    raise env.scoreboard.result
