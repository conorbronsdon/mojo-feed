"""Mutation fuzzer for mojo-feed: mutate real feed bytes, require the
parser to terminate without crashing (raising is fine)."""

import random
import signal
import subprocess
import sys
import os

RUNNER = sys.argv[1]
SEEDS = ["test/data/rss_hn.xml", "test/data/atom_xkcd.xml", "test/data/atom_youtube.xml", "test/data/jsonfeed_recompiled.json", "test/data/rdf_slashdot.xml"]
ITERATIONS = int(sys.argv[2]) if len(sys.argv) > 2 else 600
WORK = os.path.join(os.path.dirname(RUNNER), "fuzz_case.xml")
FAIL_DIR = os.path.join(os.path.dirname(RUNNER), "fuzz_failures")

INTERESTING = [b"<", b">", b"&", b"]]>", b"<!--", b"<![CDATA[", b'"', b"'",
               b"&#", b"&#x", b"</", b"/>", b"<?", b"\x00", b"\xff", b"=",
               b"<item>", b"</item>", b"encoding='latin-1'"]

random.seed(20260705)
seeds = [open(s, "rb").read() for s in SEEDS]
crashes, hangs = [], []

for i in range(ITERATIONS):
    data = bytearray(random.choice(seeds))
    for _ in range(random.randint(1, 8)):
        op = random.randrange(5)
        if op == 0 and data:  # byte flip
            p = random.randrange(len(data))
            data[p] = random.randrange(256)
        elif op == 1 and data:  # truncate
            data = data[: random.randrange(1, len(data) + 1)]
        elif op == 2 and data:  # delete chunk
            a = random.randrange(len(data))
            b = min(len(data), a + random.randrange(1, 64))
            del data[a:b]
        elif op == 3:  # insert interesting token
            p = random.randrange(len(data) + 1)
            data[p:p] = random.choice(INTERESTING)
        elif op == 4 and data:  # duplicate chunk
            a = random.randrange(len(data))
            b = min(len(data), a + random.randrange(1, 128))
            p = random.randrange(len(data) + 1)
            data[p:p] = data[a:b]
    with open(WORK, "wb") as f:
        f.write(bytes(data))
    try:
        r = subprocess.run([RUNNER, WORK], capture_output=True, timeout=10)
        if r.returncode < 0 or r.returncode == 139:
            crashes.append((i, -r.returncode))
            os.makedirs(FAIL_DIR, exist_ok=True)
            open(f"{FAIL_DIR}/crash_{i}.xml", "wb").write(bytes(data))
    except subprocess.TimeoutExpired:
        hangs.append(i)
        os.makedirs(FAIL_DIR, exist_ok=True)
        open(f"{FAIL_DIR}/hang_{i}.xml", "wb").write(bytes(data))

print(f"iterations: {ITERATIONS}")
print(f"crashes (signal): {len(crashes)} {crashes[:10]}")
print(f"hangs (>10s): {len(hangs)} {hangs[:10]}")
sys.exit(1 if crashes or hangs else 0)
