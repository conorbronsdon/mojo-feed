"""Corpus test: fetch every feed in a public OPML list, run the compiled
mojo-feed corpus runner on each, and aggregate outcomes.

Usage:
    mojo build -I src test/corpus_runner.mojo -o .corpus/corpus_runner
    python3 test/corpus_run.py .corpus/corpus_runner [feeds.opml]

If no OPML path is given, downloads the default 144-feed list.
"""

import concurrent.futures as cf
import re
import subprocess
import sys
import os

DEFAULT_OPML_URL = (
    "https://gist.githubusercontent.com/noghartt/"
    "70e4ebb9af58df3b66b8efb856cc1ef5/raw"
)

RUNNER = os.path.abspath(sys.argv[1])
WORKDIR = os.path.join(os.path.dirname(RUNNER), "corpus")
os.makedirs(WORKDIR, exist_ok=True)

if len(sys.argv) > 2:
    opml = open(sys.argv[2]).read()
else:
    opml_path = os.path.join(WORKDIR, "feeds.opml")
    if not os.path.exists(opml_path):
        subprocess.run(
            ["curl", "-sSL", "--max-time", "30", "-o", opml_path,
             DEFAULT_OPML_URL],
            check=True)
    opml = open(opml_path).read()

urls = list(dict.fromkeys(re.findall(r'xmlUrl="([^"]+)"', opml)))
print(f"{len(urls)} unique feed urls")


def fetch(idx_url):
    idx, url = idx_url
    path = os.path.join(WORKDIR, f"feed_{idx:03d}.xml")
    try:
        r = subprocess.run(
            ["curl", "-sSL", "--compressed", "--max-time", "25", "-A",
             "mojo-feed-corpus-test/0.1", "-o", path, "-w", "%{http_code}",
             url],
            capture_output=True, text=True, timeout=40)
        code = r.stdout.strip()
        size = os.path.getsize(path) if os.path.exists(path) else 0
        if code == "200" and size > 0:
            return (idx, url, "fetched", size)
        return (idx, url, f"http_{code}", size)
    except Exception:
        return (idx, url, "fetch_err", 0)


with cf.ThreadPoolExecutor(max_workers=12) as ex:
    fetches = list(ex.map(fetch, list(enumerate(urls))))

fetched = [f for f in fetches if f[2] == "fetched"]
print(f"fetched: {len(fetched)}, unfetchable: {len(fetches) - len(fetched)}")

results = {"ok": [], "zero_items": [], "no_title": [], "raised": [],
           "crashed": [], "hung": []}
for idx, url, _, size in fetched:
    path = os.path.join(WORKDIR, f"feed_{idx:03d}.xml")
    try:
        r = subprocess.run([RUNNER, path], capture_output=True, text=True,
                           timeout=15)
        out = r.stdout.strip()
        if r.returncode < 0 or r.returncode == 139:
            results["crashed"].append((url, r.returncode))
        elif out.startswith("raised:"):
            results["raised"].append((url, out[:160]))
        else:
            m = re.match(r"items: (\d+) title_len: (\d+)", out)
            if not m:
                results["raised"].append((url, f"odd output: {out[:120]}"))
            elif int(m.group(1)) == 0:
                results["zero_items"].append((url, out))
            elif int(m.group(2)) == 0:
                results["no_title"].append((url, out))
            else:
                results["ok"].append((url, int(m.group(1))))
    except subprocess.TimeoutExpired:
        results["hung"].append((url, ""))

print()
for k in ["ok", "zero_items", "no_title", "raised", "crashed", "hung"]:
    print(f"{k}: {len(results[k])}")
print()
for k in ["crashed", "hung", "raised", "zero_items", "no_title"]:
    for url, info in results[k]:
        print(f"  [{k}] {url}\n      {info}")

sys.exit(1 if results["crashed"] or results["hung"] else 0)
