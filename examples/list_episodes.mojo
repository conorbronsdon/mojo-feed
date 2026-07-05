"""List the most recent episodes in a podcast RSS (or Atom) feed.

Usage:
    mojo run -I src examples/list_episodes.mojo <feed.xml> [count]
"""

from std.sys import argv

from feed import parse_feed


def main() raises:
    var args = argv()
    if len(args) < 2:
        print("usage: list_episodes <feed.xml> [count]")
        return
    var count = 5
    if len(args) >= 3:
        count = Int(String(args[2]))

    var source = open(String(args[1]), "r").read()
    var feed = parse_feed(source^)

    print(feed.title)
    print(t"{feed.kind} feed — {len(feed.items)} items")
    print()
    var shown = 0
    for item in feed.items:
        if shown >= count:
            break
        var episode_label = String("     ")
        if item.episode_number.byte_length() > 0:
            episode_label = String(t"#{item.episode_number}")
        print(t"{episode_label}  {item.pub_date}")
        print(t"       {item.title}")
        shown += 1
