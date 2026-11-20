"""Rebuild the inverse disk used to keep slice artwork outside the cancel hub."""

import math
import struct
from pathlib import Path

SIZE = 128
SAMPLES = 4
RADIUS = SIZE / 4

header = bytearray(18)
header[2] = 2
struct.pack_into("<HH", header, 12, SIZE, SIZE)
header[16] = 32
header[17] = 8
pixels = bytearray()
for y in range(SIZE):
    for x in range(SIZE):
        outside = sum(
            math.hypot(
                x + (sx + 0.5) / SAMPLES - SIZE / 2,
                y + (sy + 0.5) / SAMPLES - SIZE / 2,
            ) >= RADIUS
            for sy in range(SAMPLES)
            for sx in range(SAMPLES)
        )
        alpha = round(255 * outside / (SAMPLES * SAMPLES))
        pixels.extend((255, 255, 255, alpha))

destination = Path(__file__).resolve().parents[1] / "Media" / "SliceHubMask.tga"
destination.write_bytes(header + pixels)
