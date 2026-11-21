"""Rebuild the transparent, uncompressed BGRA BLP2 used by hardware cursors."""

import struct
from pathlib import Path

SIZE = 32
HEADER_SIZE = 1172
header = bytearray(HEADER_SIZE)
header[:4] = b"BLP2"
struct.pack_into("<I", header, 4, 1)
header[8:12] = bytes((3, 8, 2, 0))
struct.pack_into("<II", header, 12, SIZE, SIZE)
struct.pack_into("<I", header, 20, HEADER_SIZE)
struct.pack_into("<I", header, 84, SIZE * SIZE * 4)
pixels = bytes(SIZE * SIZE * 4)

destination = Path(__file__).resolve().parents[1] / "Media" / "Blank.blp"
destination.write_bytes(header + pixels)
