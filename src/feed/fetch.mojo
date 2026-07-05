"""Feed fetching via the system `curl` (the Mojo ecosystem has no
native HTTP client yet; this is the pragmatic bridge until it does)."""

from std.subprocess import run

from feed.feed import parse_feed
from feed.model import Feed


def fetch_feed(url: String) raises -> Feed:
    """Fetch `url` with curl and parse the response as a feed.

    Requires `curl` on PATH. Follows redirects, negotiates compression,
    and times out after 30 seconds.
    """
    if not (url.startswith("http://") or url.startswith("https://")):
        raise Error("mojo-feed: only http(s) URLs can be fetched")
    for b in url.as_bytes():
        # The URL is single-quoted into a shell command; reject anything
        # that could escape the quoting rather than trying to sanitize.
        if (
            b <= 0x20
            or b == UInt8(ord("'"))
            or b == UInt8(ord('"'))
            or b == UInt8(ord("\\"))
            or b == UInt8(ord("`"))
            or b >= 0x7F
        ):
            raise Error("mojo-feed: unsupported character in URL")
    var body = run(
        "curl -fsSL --compressed --max-time 30 -A 'mojo-feed/0.1' '"
        + url
        + "'"
    )
    return parse_feed(body^)
