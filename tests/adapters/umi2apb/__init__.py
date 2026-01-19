# Import tests so cocotb can discover them
from adapters.umi2apb.test_basic_WR import test_basic_WR  # noqa: F401
from adapters.umi2apb.test_full_throughput import test_full_throughput  # noqa: F401
from adapters.umi2apb.test_random_stimulus import test_random_stimulus  # noqa: F401
from adapters.umi2apb.test_posted_write import test_posted_write  # noqa: F401
from adapters.umi2apb.test_backpressure import test_backpressure  # noqa: F401
