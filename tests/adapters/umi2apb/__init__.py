# Import tests so cocotb can discover them
from .test_basic_WR import *  # noqa: F401, F403
from .test_full_throughput import *  # noqa: F401, F403
from .test_random_stimulus import *  # noqa: F401, F403
from .test_posted_write import *  # noqa: F401, F403
from .test_backpressure import *  # noqa: F401, F403
