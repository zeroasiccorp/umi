import dataclasses


class BitField:

    def __init__(self, value, width, offset=0):
        self._value = value
        self._width = width
        self._offset = offset

    def __int__(self):
        return self._value

    def from_int(self, value):
        if value >= 2**self.width:
            raise ValueError(f"Value '{value}' to large for BitField of width {self._width}")
        self._value = value

    @property
    def value(self):
        return self.__int__()

    @value.setter
    def value(self, value):
        self.from_int(value)

    @property
    def width(self):
        return self._width

    @property
    def msb_idx(self):
        return self._offset + self._width

    @property
    def lsb_idx(self):
        return self._offset

    def __add__(self, other):
        if isinstance(other, BitField):
            return BitField(
                value=(int(self) << self.lsb_idx) | (int(other) << other.lsb_idx),
                width=max(self.msb_idx, other.msb_idx) - min(self.lsb_idx, other.lsb_idx),
                offset=min(self._offset, other._offset)
            )
        else:
            return NotImplemented


class BitVector:

    def as_bit_field(self):
        return sum([getattr(self, field.name) for field in dataclasses.fields(self)], start=BitField(value=0, width=0))

    @classmethod
    def from_int(cls, value):
        c = cls()
        for bit_field in [getattr(c, field.name) for field in dataclasses.fields(c)]:
            bit_field.value = (value >> bit_field.lsb_idx) & ((1 << bit_field.width) - 1)
        return c

    @classmethod
    def from_bytes(cls, value):
        return cls.from_int(int.from_bytes(value, byteorder='little'))

    @classmethod
    def from_fields(cls, **kwargs):
        c = cls()
        for name, value in kwargs.items():
            if hasattr(c, name):
                bit_field = getattr(c, name)
                bit_field.value = value
            else:
                raise TypeError(f"BitField '{name}' not found in {cls}")
        return c

    def __int__(self):
        return int(self.as_bit_field())

    def __bytes__(self):
        return int.to_bytes(int(self), length=4, byteorder='little')

    def __repr__(self):
        rtn = ""
        for key, value in dataclasses.asdict(self).items():
            rtn += f"{key} = {int(value)} "
        return rtn