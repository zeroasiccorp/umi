import dataclasses
from typing import Optional


@dataclasses.dataclass
class VRDTransaction:
    data: bytes
    strb: Optional[str] = None
    len: Optional[int] = None
    last: Optional[bool] = None
