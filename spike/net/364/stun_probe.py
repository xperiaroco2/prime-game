"""M6-1 spike (#364), throwaway: one RFC 5389 Binding request to a STUN server over UDP.

    python3 spike/net/364/stun_probe.py stun.cloudflare.com 3478
"""

import os
import socket
import struct
import sys
import time

MAGIC = 0x2112A442


def main() -> None:
    host, port = sys.argv[1], int(sys.argv[2])
    addr = socket.getaddrinfo(host, port, socket.AF_INET, socket.SOCK_DGRAM)[0][4]
    print(f"resolved {host} -> {addr[0]}")
    tid = os.urandom(12)
    req = struct.pack("!HHI", 0x0001, 0, MAGIC) + tid
    s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    s.settimeout(3)
    for attempt in range(3):
        t = time.time()
        s.sendto(req, addr)
        try:
            data, _ = s.recvfrom(2048)
        except socket.timeout:
            print(f"attempt {attempt + 1}: no answer in 3 s")
            continue
        kind, length, magic = struct.unpack("!HHI", data[:8])
        print(f"attempt {attempt + 1}: type 0x{kind:04x} in {1000 * (time.time() - t):.1f} ms")
        i = 20
        while i < 20 + length:
            at, al = struct.unpack("!HH", data[i : i + 4])
            v = data[i + 4 : i + 4 + al]
            if at == 0x0020:  # XOR-MAPPED-ADDRESS
                xport = struct.unpack("!H", v[2:4])[0] ^ (MAGIC >> 16)
                ip = struct.unpack("!I", v[4:8])[0] ^ MAGIC
                print(f"mapped address {socket.inet_ntoa(struct.pack('!I', ip))}:{xport}")
            i += 4 + al + (-al % 4)
        return
    print("no STUN answer")
    sys.exit(1)


if __name__ == "__main__":
    main()
