"""Throughput benchmark for `parse_feed` over the real feed fixtures.

Reports wall-clock per parse and MB/s. Run compiled for meaningful
numbers: `mojo build -I src bench/bench_parse.mojo -o bench_parse`.
"""

from std.time import perf_counter_ns

from feed import parse_feed


def bench(path: String, iterations: Int) raises:
    var source = open(path, "r").read()
    var size_mb = Float64(source.byte_length()) / (1024.0 * 1024.0)
    # Warmup + correctness anchor.
    var warm = parse_feed(source.copy())
    var items = len(warm.items)
    var start = perf_counter_ns()
    for _ in range(iterations):
        var f = parse_feed(source.copy())
        if len(f.items) != items:
            raise Error("inconsistent parse")
    var elapsed_ns = perf_counter_ns() - start
    var per_parse_ms = Float64(elapsed_ns) / Float64(iterations) / 1e6
    var mb_per_s = size_mb / (per_parse_ms / 1000.0)
    print(path)
    print(t"  {source.byte_length()} bytes, {items} items:")
    print(t"  {per_parse_ms} ms/parse, {mb_per_s} MB/s")


def main() raises:
    bench("test/data/cot_feed.xml", 50)
    bench("test/data/rss_substack.xml", 50)
    bench("test/data/rss_hn.xml", 200)
