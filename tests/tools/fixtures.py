"""Writes the two binary test files of the ToolCheck project (run with python3 -I).

Shared/Adder.mlmodel: a tiny Core ML linear model, y = x[0] + x[1], encoded by hand
in the Core ML protobuf format. Shared/Assets.xcassets/AppIcon.appiconset/icon.png:
a plain 1024x1024 PNG.
"""
import os
import struct
import zlib

here = os.path.dirname(os.path.abspath(__file__))


def varint(n):
    out = b""
    while True:
        byte = n & 0x7F
        n >>= 7
        if n:
            out += bytes([byte | 0x80])
        else:
            return out + bytes([byte])


def field(number, wire, payload):
    key = varint(number << 3 | wire)
    if wire == 2:
        return key + varint(len(payload)) + payload
    return key + payload


def message(number, payload):
    return field(number, 2, payload)


def packed_doubles(number, values):
    return message(number, b"".join(struct.pack("<d", v) for v in values))


def feature(name, feature_type):
    return message(1, name.encode()) + message(3, feature_type)


multi_array = message(5, field(1, 0, varint(2)) + field(2, 0, varint(65600)))  # shape [2], double
double_type = message(2, b"")
description = message(1, feature("x", multi_array)) + message(10, feature("y", double_type))
description += message(11, b"y")  # predictedFeatureName
glm = message(1, packed_doubles(1, [1.0, 1.0])) + packed_doubles(2, [0.0])
model = field(1, 0, varint(1)) + message(2, description) + message(300, glm)
with open(os.path.join(here, "Shared", "Adder.mlmodel"), "wb") as f:
    f.write(model)


def chunk(kind, data):
    return struct.pack(">I", len(data)) + kind + data + struct.pack(">I", zlib.crc32(kind + data))


size = 1024
row = b"\x00" + bytes([240, 130, 40]) * size
png = b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB", size, size, 8, 2, 0, 0, 0))
png += chunk(b"IDAT", zlib.compress(row * size, 9)) + chunk(b"IEND", b"")
with open(os.path.join(here, "Shared", "Assets.xcassets", "AppIcon.appiconset", "icon.png"), "wb") as f:
    f.write(png)
