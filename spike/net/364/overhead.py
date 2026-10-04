"""M6-1 spike (#364), throwaway: join sniff.py's datagram log with rtc_pair.gd's overhead marks.

    python3 spike/net/364/overhead.py <sniff file> <sender log>

For each (channel, size) window: the datagrams the sender sent (by its port, the one sending the
most bytes) and the receiver's replies (SACKs), their UDP payload sizes, and the overhead per
message: UDP payload minus the message. "+28" adds IPv4 and UDP headers.
"""

import collections
import re
import statistics
import sys


def main() -> None:
    dgrams = []
    for line in open(sys.argv[1]):
        t, sp, dp, n = line.split()
        dgrams.append((float(t), int(sp), int(dp), int(n)))
    marks = []
    start = {}
    for line in open(sys.argv[2]):
        m = re.search(r"SPIKE r1 +\d+ ([\d.]+) mark (start|end) ch=(\d+) size=(\d+)", line)
        if not m:
            continue
        t, kind, ch, size = float(m[1]), m[2], int(m[3]), int(m[4])
        if kind == "start":
            start[(ch, size)] = t
        else:
            marks.append((ch, size, start.pop((ch, size)), t))
    by_port = collections.Counter()
    for _, sp, _, n in dgrams:
        by_port[sp] += n
    sender = by_port.most_common(1)[0][0]
    print(f"sender port {sender}")
    for ch, size, a, b in marks:
        out = [n for t, sp, _, n in dgrams if a <= t <= b and sp == sender]
        back = [n for t, sp, _, n in dgrams if a <= t <= b and sp != sender]
        sizes = collections.Counter(out)
        msgs = 50 if size in (1, 58, 100, 500, 1000, 1031) and len(out) >= 40 else 5
        common = sizes.most_common(1)[0][0] if sizes else 0
        print(
            f"ch={ch} size={size:5d} msgs~{msgs:2d} out_dgrams={len(out):3d} "
            f"out_sizes={dict(sorted(sizes.items()))} back_dgrams={len(back)} "
            f"back_sizes={dict(collections.Counter(back))} "
            f"overhead_udp_payload={common - size} with_ip_udp={common - size + 28} "
            f"median_out={statistics.median(out) if out else 0}"
        )


if __name__ == "__main__":
    main()
