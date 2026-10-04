"""M6-1 spike (#364), throwaway: log every UDP datagram on lo (IPv4) as
"<unix time> <src port> <dst port> <udp payload bytes>". Needs root (AF_PACKET).

    python3 spike/net/364/sniff.py <out file> <seconds>
"""

import socket
import struct
import sys
import time


def main() -> None:
    out_path, seconds = sys.argv[1], float(sys.argv[2])
    s = socket.socket(socket.AF_PACKET, socket.SOCK_RAW, socket.htons(0x0003))
    s.bind(("lo", 0))
    s.settimeout(0.5)
    end = time.time() + seconds
    with open(out_path, "w") as out:
        while time.time() < end:
            try:
                frame, addr = s.recvfrom(70000)
            except socket.timeout:
                continue
            # lo delivers each datagram twice (outgoing and host); keep outgoing only.
            if addr[2] != socket.PACKET_OUTGOING:
                continue
            if len(frame) < 14 + 20 + 8 or frame[12:14] != b"\x08\x00":
                continue
            ihl = (frame[14] & 0x0F) * 4
            if frame[14 + 9] != 17:
                continue
            u = 14 + ihl
            sport, dport, ulen = struct.unpack("!HHH", frame[u : u + 6])
            out.write(f"{time.time():.6f} {sport} {dport} {ulen - 8}\n")


if __name__ == "__main__":
    main()
