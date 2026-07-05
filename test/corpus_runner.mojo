from std.sys import argv
from feed import parse_feed

def main():
    try:
        var f = parse_feed(open(String(argv()[1]), "r").read())
        print("items:", len(f.items), "title_len:", f.title.byte_length())
    except e:
        print("raised:", e)
