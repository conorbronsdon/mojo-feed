"""Strict well-formedness check for a feed you produce.

Usage:
    mojo run -I src examples/validate_feed.mojo <feed.xml>

Exits noisily with a line/column diagnosis on the first violation —
mismatched or stray end tags, unclosed elements, bad entities. Feeds
that pass here will survive any liberal reader; feeds that fail may
still parse in mojo-feed's default mode, but are relying on error
recovery you don't control in other readers.
"""

from std.sys import argv

from feed import parse_feed


def main():
    var args = argv()
    if len(args) < 2:
        print("usage: validate_feed <feed.xml>")
        return
    try:
        var source = open(String(args[1]), "r").read()
        var feed = parse_feed(source^, strict=True)
        print(t"OK: {feed.kind} feed, {len(feed.items)} items, no violations")
    except e:
        print("INVALID:", e)
