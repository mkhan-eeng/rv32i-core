#!/usr/bin/env python3
"""Convert a raw binary (from objcopy -O binary) into a $readmemh file:
one 32-bit little-endian word per line, 8 hex digits."""
import sys

def main():
    if len(sys.argv) != 3:
        sys.exit("usage: bin2hex.py input.bin output.hex")
    data = open(sys.argv[1], "rb").read()
    data += b"\x00" * (-len(data) % 4)      # pad to a whole number of words
    with open(sys.argv[2], "w") as f:
        for i in range(0, len(data), 4):
            f.write(f"{int.from_bytes(data[i:i+4], 'little'):08x}\n")

if __name__ == "__main__":
    main()
