import cocotb

from cocotb.handle import SimHandleBase

from adapters.tl2umi.tl_driver import TLTransaction
from adapters.tl2umi.env import TL2UMIEnv, create_expected_write_response, create_expected_read_response


@cocotb.test(timeout_time=50, timeout_unit="ms")
async def test_basic_write(dut: SimHandleBase):
    """
    Basic write test:
      1. Single aligned TileLink write
      2. Verify write acknowledgment received
    """
    env = TL2UMIEnv(dut)
    await env.start()
    dut.tl_d_ready.value = 1

    test_addr = 0x100
    test_data = 0xDEADBEEF
    size = 2  # 4 bytes

    print("=== Basic Write Test ===")

    # Queue expected write response
    env.expected_responses.append(
        create_expected_write_response(size=size, source=0)
    )

    # Send write transaction
    env.tl_driver.append(
        TLTransaction.put_full(address=test_addr, size=size, data=test_data, source=0)
    )

    # Wait for response
    await env.wait_for_responses(max_cycles=100)

    print(f"    Write to 0x{test_addr:08x} with data 0x{test_data:08x}")
    print("    Write acknowledgment verified by scoreboard")

    raise env.scoreboard.result


@cocotb.test(timeout_time=50, timeout_unit="ms")
async def test_basic_read(dut: SimHandleBase):
    """
    Basic read test:
      1. Write data to memory via TileLink
      2. Read it back via TileLink
      3. Verify read response contains correct data
    """
    env = TL2UMIEnv(dut)
    await env.start()
    dut.tl_d_ready.value = 1

    test_addr = 0x200
    test_data = 0xCAFEBABE
    size = 2  # 4 bytes

    print("=== Write then Read Test ===")

    # write data to memory
    env.expected_responses.append(
        create_expected_write_response(size=size, source=1)
    )
    env.tl_driver.append(
        TLTransaction.put_full(address=test_addr, size=size, data=test_data, source=1)
    )
    await env.wait_for_responses(max_cycles=100)
    print(f"    Write complete: 0x{test_data:08x} -> 0x{test_addr:08x}")

    # read it back
    env.expected_responses.append(
        create_expected_read_response(address=test_addr, size=size, data=test_data, source=2)
    )
    env.tl_driver.append(
        TLTransaction.get(address=test_addr, size=size, source=2)
    )
    await env.wait_for_responses(max_cycles=100)
    print(f"    Read complete: got 0x{test_data:08x} from 0x{test_addr:08x}")

    raise env.scoreboard.result


@cocotb.test(timeout_time=50, timeout_unit="ms")
async def test_multiple_writes(dut: SimHandleBase):
    """
    Multiple sequential writes to different addresses
    """
    env = TL2UMIEnv(dut)
    await env.start()
    dut.tl_d_ready.value = 1

    size = 2  # 4 bytes
    test_cases = [
        (0x000, 0x11111111),
        (0x004, 0x22222222),
        (0x008, 0x33333333),
        (0x00C, 0x44444444),
    ]

    print("=== Multiple Writes Test ===")

    for i, (addr, data) in enumerate(test_cases):
        env.expected_responses.append(
            create_expected_write_response(size=size, source=i)
        )
        env.tl_driver.append(
            TLTransaction.put_full(address=addr, size=size, data=data, source=i)
        )
        await env.wait_for_responses(max_cycles=100)
        print(f"    Write {i}: 0x{data:08x} -> 0x{addr:03x}")

    raise env.scoreboard.result


@cocotb.test(timeout_time=50, timeout_unit="ms")
async def test_byte_write(dut: SimHandleBase):
    """
    Single byte write using size=0
    """
    env = TL2UMIEnv(dut)
    await env.start()
    dut.tl_d_ready.value = 1

    test_addr = 0x300
    test_data = 0xAB
    size = 0  # 1 byte

    print("=== Byte Write Test ===")

    env.expected_responses.append(
        create_expected_write_response(size=size, source=0)
    )
    env.tl_driver.append(
        TLTransaction.put_full(address=test_addr, size=size, data=test_data, source=0)
    )
    await env.wait_for_responses(max_cycles=100)

    print(f"    Byte write: 0x{test_data:02x} -> 0x{test_addr:03x}")

    raise env.scoreboard.result


@cocotb.test(timeout_time=50, timeout_unit="ms")
async def test_64bit_write_read(dut: SimHandleBase):
    """
    Full 64-bit (8 byte) write and read
    """
    env = TL2UMIEnv(dut)
    await env.start()
    dut.tl_d_ready.value = 1

    test_addr = 0x400
    test_data = 0xDEADBEEFCAFEBABE
    size = 3  # 8 bytes

    print("=== 64-bit Write/Read Test ===")

    # Write
    env.expected_responses.append(
        create_expected_write_response(size=size, source=0)
    )
    env.tl_driver.append(
        TLTransaction.put_full(address=test_addr, size=size, data=test_data, source=0)
    )
    await env.wait_for_responses(max_cycles=100)
    print(f"    Write: 0x{test_data:016x} -> 0x{test_addr:03x}")

    # Read
    env.expected_responses.append(
        create_expected_read_response(address=test_addr, size=size, data=test_data, source=1)
    )
    env.tl_driver.append(
        TLTransaction.get(address=test_addr, size=size, source=1)
    )
    await env.wait_for_responses(max_cycles=100)
    print(f"    Read: got 0x{test_data:016x}")

    raise env.scoreboard.result
