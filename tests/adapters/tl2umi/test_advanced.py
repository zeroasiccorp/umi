import cocotb

from cocotb.handle import SimHandleBase
from cocotb.triggers import ClockCycles

from adapters.tl2umi.tl_driver import TLTransaction, TLArithParam, TLLogicParam
from adapters.tl2umi.env import TL2UMIEnv, create_expected_write_response, create_expected_read_response


@cocotb.test(timeout_time=50, timeout_unit="ms")
async def test_backpressure(dut: SimHandleBase):
    """
    Test backpressure handling:
      1. Send transaction with ready enabled
      2. Wait for valid to assert
      3. Apply backpressure (ready=0)
      4. Verify response is held
      5. Release backpressure and verify response completes
    """
    env = TL2UMIEnv(dut)
    await env.start()
    dut.tl_d_ready.value = 1

    test_addr = 0x100
    test_data = 0xDEADBEEF
    size = 2

    print("=== Backpressure Test ===")

    # Queue expected response
    env.expected_responses.append(
        create_expected_write_response(size=size, source=0)
    )

    # Send write transaction
    env.tl_driver.append(
        TLTransaction.put_full(address=test_addr, size=size, data=test_data, source=0)
    )
    print(f"Sent write: addr=0x{test_addr:x}, data=0x{test_data:08x}")

    # Wait for first response to complete
    await env.wait_for_responses(max_cycles=100)
    print("First transaction completed")

    # Now test backpressure: send second transaction and apply backpressure mid-flight
    test_addr2 = 0x200
    test_data2 = 0xCAFEBABE

    env.expected_responses.append(
        create_expected_write_response(size=size, source=1)
    )

    env.tl_driver.append(
        TLTransaction.put_full(address=test_addr2, size=size, data=test_data2, source=1)
    )
    print(f"Sent second write: addr=0x{test_addr2:x}, data=0x{test_data2:08x}")

    # Wait a few cycles then apply backpressure
    await ClockCycles(env.clk, 5)
    dut.tl_d_ready.value = 0
    print("Applied backpressure (tl_d_ready=0)")

    # Wait while backpressure is applied
    await ClockCycles(env.clk, 20)

    # Response should still be pending
    assert len(env.expected_responses) == 1, "Response should not have been consumed yet"
    print("Response held with backpressure")

    # Release backpressure
    dut.tl_d_ready.value = 1
    print("Released backpressure (tl_d_ready=1)")

    # Wait for response
    await env.wait_for_responses(max_cycles=10)

    print("=== Backpressure Test PASSED ===")
    raise env.scoreboard.result


@cocotb.test(timeout_time=50, timeout_unit="ms")
async def test_partial_write(dut: SimHandleBase):
    env = TL2UMIEnv(dut)
    await env.start()
    dut.tl_d_ready.value = 1

    test_addr = 0x500
    size = 2  # 4 bytes

    print("=== Partial Write Test ===")

    # Write full word
    init_data = 0xAAAAAAAA
    env.expected_responses.append(
        create_expected_write_response(size=size, source=0)
    )
    env.tl_driver.append(
        TLTransaction.put_full(address=test_addr, size=size, data=init_data, source=0)
    )
    await env.wait_for_responses(max_cycles=100)
    print(f" Init write: 0x{init_data:08x} -> 0x{test_addr:03x}")

    # Partial write
    partial_data = 0x0000BBBB
    # Only supports contiguous masks
    mask = 0b0011
    env.expected_responses.append(
        create_expected_write_response(size=size, source=1)
    )
    env.tl_driver.append(
        TLTransaction.put_partial(address=test_addr, size=size, data=partial_data, mask=mask, source=1)
    )
    await env.wait_for_responses(max_cycles=100)
    print(f" Partial write: 0x{partial_data:08x} mask=0b{mask:04b}")

    # Read back
    expected_data = 0xAAAABBBB
    env.expected_responses.append(
        create_expected_read_response(address=test_addr, size=size, data=expected_data, source=2)
    )
    env.tl_driver.append(
        TLTransaction.get(address=test_addr, size=size, source=2)
    )
    await env.wait_for_responses(max_cycles=100)
    print(f" Read back: expected 0x{expected_data:08x}")

    raise env.scoreboard.result


@cocotb.test(timeout_time=50, timeout_unit="ms")
async def test_back_to_back_writes(dut: SimHandleBase):

    env = TL2UMIEnv(dut)
    await env.start()
    dut.tl_d_ready.value = 1

    size = 2  # 4 bytes
    num_transactions = 8

    print("=== Back-to-Back Writes Test ===")

    # Queue all expected responses
    for i in range(num_transactions):
        env.expected_responses.append(
            create_expected_write_response(size=size, source=i)
        )

    # Queue all transactions
    for i in range(num_transactions):
        addr = 0x1000 + (i * 4)
        data = 0x10000000 + i
        env.tl_driver.append(
            TLTransaction.put_full(address=addr, size=size, data=data, source=i)
        )
        print(f" Queued write {i}: 0x{data:08x} -> 0x{addr:04x}")

    # Wait for all responses
    await env.wait_for_responses(max_cycles=500)
    print(f"All {num_transactions} write responses received")

    raise env.scoreboard.result


@cocotb.test(timeout_time=50, timeout_unit="ms")
async def test_back_to_back_reads(dut: SimHandleBase):

    env = TL2UMIEnv(dut)
    await env.start()
    dut.tl_d_ready.value = 1

    size = 2  # 4 bytes
    num_transactions = 4
    base_addr = 0x2000

    print("=== Back-to-Back Reads Test ===")

    # Write data to memory
    # Use 8-byte aligned addresses since RTL drops lower 3 bits
    for i in range(num_transactions):
        addr = base_addr + (i * 8)
        data = 0xBABE0000 + i
        env.expected_responses.append(
            create_expected_write_response(size=size, source=i)
        )
        env.tl_driver.append(
            TLTransaction.put_full(address=addr, size=size, data=data, source=i)
        )
        await env.wait_for_responses(max_cycles=100)
    print(f" Wrote {num_transactions} words to memory")

    # Now read back
    for i in range(num_transactions):
        addr = base_addr + (i * 8)
        expected_data = 0xBABE0000 + i
        read_source = 16 + i  # Different from write sources, but still <= 31
        env.expected_responses.append(
            create_expected_read_response(address=addr, size=size, data=expected_data, source=read_source)
        )
        env.tl_driver.append(
            TLTransaction.get(address=addr, size=size, source=read_source)
        )
        await env.wait_for_responses(max_cycles=100)
        print(f" Read {i}: 0x{addr:04x}")

    print(f" All {num_transactions} read responses received")

    raise env.scoreboard.result


@cocotb.test(timeout_time=50, timeout_unit="ms")
async def test_different_source_ids(dut: SimHandleBase):

    env = TL2UMIEnv(dut)
    await env.start()
    dut.tl_d_ready.value = 1

    size = 2  # 4 bytes

    print("=== Source ID Matching Test ===")

    # address, data, source_id
    test_cases = [
        (0x100, 0x11111111, 7),
        (0x108, 0x22222222, 3),
        (0x110, 0x33333333, 15),
        (0x118, 0x44444444, 1),
    ]

    # Write
    for addr, data, source in test_cases:
        env.expected_responses.append(
            create_expected_write_response(size=size, source=source)
        )
        env.tl_driver.append(
            TLTransaction.put_full(address=addr, size=size, data=data, source=source)
        )
        await env.wait_for_responses(max_cycles=100)
        print(f" Write source={source}: 0x{data:08x} -> 0x{addr:03x}")

    # Read back with different source IDs
    for addr, data, source in test_cases:
        read_source = source + 16  # Different source for reads
        env.expected_responses.append(
            create_expected_read_response(address=addr, size=size, data=data, source=read_source)
        )
        env.tl_driver.append(
            TLTransaction.get(address=addr, size=size, source=read_source)
        )
        await env.wait_for_responses(max_cycles=100)
        print(f"    Read source={read_source}: 0x{addr:03x} -> 0x{data:08x}")

    raise env.scoreboard.result


@cocotb.test(timeout_time=50, timeout_unit="ms")
async def test_mixed_read_write_same_address(dut: SimHandleBase):

    env = TL2UMIEnv(dut)
    await env.start()
    dut.tl_d_ready.value = 1

    test_addr = 0x800
    size = 2  # 4 bytes

    print("=== Mixed Read/Write Same Address Test ===")

    # Write initial val
    data1 = 0xAAAAAAAA
    env.expected_responses.append(create_expected_write_response(size=size, source=0))
    env.tl_driver.append(TLTransaction.put_full(address=test_addr, size=size, data=data1, source=0))
    await env.wait_for_responses(max_cycles=100)
    print(f" Write 1: 0x{data1:08x}")

    # Read back
    env.expected_responses.append(create_expected_read_response(address=test_addr, size=size, data=data1, source=1))
    env.tl_driver.append(TLTransaction.get(address=test_addr, size=size, source=1))
    await env.wait_for_responses(max_cycles=100)
    print(f" Read 1: 0x{data1:08x}")

    # Write new value
    data2 = 0xBBBBBBBB
    env.expected_responses.append(create_expected_write_response(size=size, source=2))
    env.tl_driver.append(TLTransaction.put_full(address=test_addr, size=size, data=data2, source=2))
    await env.wait_for_responses(max_cycles=100)
    print(f" Write 2: 0x{data2:08x}")

    # Read back new value
    env.expected_responses.append(create_expected_read_response(address=test_addr, size=size, data=data2, source=3))
    env.tl_driver.append(TLTransaction.get(address=test_addr, size=size, source=3))
    await env.wait_for_responses(max_cycles=100)
    print(f" Read 2: 0x{data2:08x}")

    raise env.scoreboard.result


@cocotb.test(timeout_time=50, timeout_unit="ms")
async def test_all_sizes(dut: SimHandleBase):
    """
    Test all supported sizes: 1, 2, 4, 8 byts
    """
    env = TL2UMIEnv(dut)
    await env.start()
    dut.tl_d_ready.value = 1

    base_addr = 0xA00

    print("=== All Sizes Test ===")

    # 1 byte
    addr = base_addr
    data = 0xAB
    env.expected_responses.append(create_expected_write_response(size=0, source=0))
    env.tl_driver.append(TLTransaction.put_full(address=addr, size=0, data=data, source=0))
    await env.wait_for_responses(max_cycles=100)
    env.expected_responses.append(create_expected_read_response(address=addr, size=0, data=data, source=1))
    env.tl_driver.append(TLTransaction.get(address=addr, size=0, source=1))
    await env.wait_for_responses(max_cycles=100)
    print(f" Size 0 (1 byte): 0x{data:02x}")

    # 2 bytes
    addr = base_addr + 0x10
    data = 0xABCD
    env.expected_responses.append(create_expected_write_response(size=1, source=2))
    env.tl_driver.append(TLTransaction.put_full(address=addr, size=1, data=data, source=2))
    await env.wait_for_responses(max_cycles=100)
    env.expected_responses.append(create_expected_read_response(address=addr, size=1, data=data, source=3))
    env.tl_driver.append(TLTransaction.get(address=addr, size=1, source=3))
    await env.wait_for_responses(max_cycles=100)
    print(f" Size 1 (2 bytes): 0x{data:04x}")

    # 4 bytes
    addr = base_addr + 0x20
    data = 0xABCD1234
    env.expected_responses.append(create_expected_write_response(size=2, source=4))
    env.tl_driver.append(TLTransaction.put_full(address=addr, size=2, data=data, source=4))
    await env.wait_for_responses(max_cycles=100)
    env.expected_responses.append(create_expected_read_response(address=addr, size=2, data=data, source=5))
    env.tl_driver.append(TLTransaction.get(address=addr, size=2, source=5))
    await env.wait_for_responses(max_cycles=100)
    print(f" Size 2 (4 bytes): 0x{data:08x}")

    # 8 bytes
    addr = base_addr + 0x30
    data = 0xABCD1234DEADBEEF
    env.expected_responses.append(create_expected_write_response(size=3, source=6))
    env.tl_driver.append(TLTransaction.put_full(address=addr, size=3, data=data, source=6))
    await env.wait_for_responses(max_cycles=100)
    env.expected_responses.append(create_expected_read_response(address=addr, size=3, data=data, source=7))
    env.tl_driver.append(TLTransaction.get(address=addr, size=3, source=7))
    await env.wait_for_responses(max_cycles=100)
    print(f" Size 3 (8 bytes): 0x{data:016x}")

    raise env.scoreboard.result


@cocotb.test(timeout_time=100, timeout_unit="ms")
async def test_atomic_add(dut: SimHandleBase):

    env = TL2UMIEnv(dut)
    await env.start()
    dut.tl_d_ready.value = 1

    test_addr = 0xB00
    size = 2  # 4 bytes
    initial_value = 100
    add_value = 50

    print("=== Atomic ADD Test ===")

    # Write initial value (to be returned by atomic op)
    env.expected_responses.append(create_expected_write_response(size=size, source=0))
    env.tl_driver.append(TLTransaction.put_full(address=test_addr, size=size, data=initial_value, source=0))
    await env.wait_for_responses(max_cycles=100)
    print(f" Initial write: {initial_value}")

    # Atomic ADD - returns old value, stores sum
    env.expected_responses.append(
        create_expected_read_response(address=test_addr, size=size, data=initial_value, source=1)
    )
    env.tl_driver.append(
        TLTransaction.atomic_arith(address=test_addr, size=size, data=add_value, param=TLArithParam.ADD, source=1)
    )
    await env.wait_for_responses(max_cycles=100)
    print(f" Atomic ADD: +{add_value}, returned old value {initial_value}")

    # Read back - should be initial + add
    expected_result = initial_value + add_value
    env.expected_responses.append(
        create_expected_read_response(address=test_addr, size=size, data=expected_result, source=2)
    )
    env.tl_driver.append(TLTransaction.get(address=test_addr, size=size, source=2))
    await env.wait_for_responses(max_cycles=100)
    print(f"    Read back: {expected_result}")

    raise env.scoreboard.result


@cocotb.test(timeout_time=100, timeout_unit="ms")
async def test_atomic_xor(dut: SimHandleBase):
    """
    Test logic (XOR) operation.
    """
    env = TL2UMIEnv(dut)
    await env.start()
    dut.tl_d_ready.value = 1

    test_addr = 0xD00
    size = 2  # 4 bytes
    initial_value = 0xFF00FF00
    xor_value = 0x0F0F0F0F

    print("=== Atomic XOR Test ===")

    # Write initial value
    env.expected_responses.append(create_expected_write_response(size=size, source=0))
    env.tl_driver.append(TLTransaction.put_full(address=test_addr, size=size, data=initial_value, source=0))
    await env.wait_for_responses(max_cycles=100)
    print(f" Initial write: 0x{initial_value:08x}")

    # Atomic XOR - returns old value, stores old XOR operand
    env.expected_responses.append(
        create_expected_read_response(address=test_addr, size=size, data=initial_value, source=1)
    )
    env.tl_driver.append(
        TLTransaction.atomic_logic(address=test_addr, size=size, data=xor_value, param=TLLogicParam.XOR, source=1)
    )
    await env.wait_for_responses(max_cycles=100)
    print(f" Atomic XOR: 0x{xor_value:08x}, returned old 0x{initial_value:08x}")

    # Read back - should be XOR result
    expected_result = initial_value ^ xor_value
    env.expected_responses.append(
        create_expected_read_response(address=test_addr, size=size, data=expected_result, source=2)
    )
    env.tl_driver.append(TLTransaction.get(address=test_addr, size=size, source=2))
    await env.wait_for_responses(max_cycles=100)
    print(f" Read back: 0x{expected_result:08x}")

    raise env.scoreboard.result
