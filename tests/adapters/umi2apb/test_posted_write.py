import math
import cocotb

from cocotb.handle import SimHandleBase
from cocotb.triggers import ClockCycles

from sumi import SumiTransaction, SumiCmdType, SumiCmd
from adapters.umi2apb.env import UMI2APBEnv


@cocotb.test(timeout_time=50, timeout_unit="ms")
async def test_posted_write(dut: SimHandleBase):
    """
    Test posted writes (no UMI response):
      1. Send multiple writes to different addresses
      2. Verify memory contents
    """

    env = UMI2APBEnv(dut)
    await env.start()

    umi_size = int(math.log2(env.data_size))

    print("=== Posted Write Test ===")

    # Test data
    test_data = {
        0x100: 0xDEADBEEF,
        0x200: 0xCAFEBABE,
        0x300: 0x12345678,
        0x400: 0xABCD1234,
    }

    # Send writes
    for addr, data in test_data.items():
        posted_txn = SumiTransaction(
            cmd=SumiCmd.from_fields(
                cmd_type=int(SumiCmdType.UMI_REQ_POSTED),
                size=umi_size,
                len=0,
            ),
            da=addr,
            sa=0x0,
            data=data.to_bytes(env.data_size, byteorder="little"),
        )
        env.sumi_driver.append(posted_txn)
        print(f"Sent posted write: addr=0x{addr:x}, data=0x{data:08x}")

    # Wait for transactions to complete 
    await ClockCycles(env.clk, 50)

    # Verify memory
    print("\n=== Verifying Memory Contents ===")
    for addr, expected_data in test_data.items():
        mem_data = await env.region.read(addr, env.data_size)
        actual_data = int.from_bytes(mem_data, byteorder="little")
        assert actual_data == expected_data, (
            f"Posted write failed at 0x{addr:x}: "
            f"expected 0x{expected_data:x}, got 0x{actual_data:x}"
        )
        print(f"Verified addr=0x{addr:x}: 0x{actual_data:08x}")

    print("\n=== Posted Write Test PASSED ===")
