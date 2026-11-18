#!/usr/bin/env python3
"""Ask a Neverwinter Nights server whether it is up, the way a player's game does.

    nwn-status.py HOST [PORT]        PORT is 5121 unless you give another

Prints the module the server is running and its player limit, and exits 0.
Prints "no answer" and exits 1 if nothing answers within 3 seconds.
Run it from a computer that is not the server, so the question travels the same road a player's would.
"""
import socket
import struct
import sys

if len(sys.argv) < 2:
    sys.exit(__doc__)
host = sys.argv[1]
port = int(sys.argv[2]) if len(sys.argv) > 2 else 5121

sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
sock.settimeout(3)
try:
    sock.sendto(b"BNXI" + struct.pack("<H", port), (host, port))
    reply, _ = sock.recvfrom(2048)
except socket.gaierror:
    sys.exit(f"cannot find the name {host}")
except OSError:
    sys.exit(f"no answer from {host} port {port}")

if reply[:4] != b"BNXR" or len(reply) < 20:
    sys.exit(f"{host} port {port} answered, but not like a game server")
max_players = reply[11]
module = reply[20:20 + reply[19]].decode("utf-8", "replace")
print(f"{host} port {port} is up: module {module}, room for {max_players} players")
