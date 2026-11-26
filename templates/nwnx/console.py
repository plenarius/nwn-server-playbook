#!/usr/bin/env python3
"""Types one line at the game server's console and prints what the server says in the next few seconds.

For scripts and agents, which can't sit in `docker attach` the way a person does. Leaves the console with
Ctrl-P Ctrl-Q, never Ctrl-C, so the server keeps running.

    console.py CONTAINER 'evalx WriteTimestampedLogEntry(NWNX_Hello_Greet("Tester"));'
"""

import os
import pty
import re
import select
import sys
import time

container, line = sys.argv[1], sys.argv[2]
pid, fd = pty.fork()
if pid == 0:
    os.execvp("docker", ["docker", "attach", container])

time.sleep(1.5)
os.write(fd, (line + "\r").encode())
output = b""
until = time.time() + 4
while time.time() < until:
    ready, _, _ = select.select([fd], [], [], 0.3)
    if ready:
        try:
            output += os.read(fd, 4096)
        except OSError:
            break
os.write(fd, b"\x10\x11")  # Ctrl-P Ctrl-Q: detach and leave the server running
time.sleep(1)
os.waitpid(pid, 0)
print(re.sub(r"\x1b\[[0-9;]*m", "", output.decode(errors="replace")).replace("\r", ""))
