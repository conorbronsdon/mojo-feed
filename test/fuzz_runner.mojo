"""Fuzz target: parse the file given as argv[1]; any in-language error
is fine (exit 0), what must never happen is a crash or a hang."""

from std.sys import argv

from feed import parse_feed


def main():
    try:
        var f = parse_feed(open(String(argv()[1]), "r").read())
        print("items:", len(f.items))
    except e:
        print("raised:", e)
