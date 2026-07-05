"""RSS and Atom feed parsing on top of the XML pull parser.

`parse_feed(source)` / `parse_feed_bytes(data)` auto-detect the format
from the root element (RSS 0.9x/2.0, RDF-based RSS 0.90/1.0, Atom 1.0)
and return a `Feed`; JSON Feed documents are dispatched to the JSON
parser. Fields a feed does not provide are empty strings.

Namespace prefixes are resolved by URI: an extension element bound to a
known namespace (iTunes, Dublin Core, content, Media RSS, Podcast Index,
RDF) maps regardless of the prefix the document chose. Resolution is
document-flat — prefix declarations are collected as they appear rather
than lexically scoped, which matches how feeds declare namespaces (on
the root element) while staying single-pass.

Nesting is tracked with an element-name stack, not a bare counter, so
unbalanced markup — a stray `<br>` in a non-CDATA description, crossed
tags — implicitly closes open elements instead of desyncing the rest of
the document. Stray end tags with no matching open element are ignored.
"""

from feed.jsonfeed import parse_json_feed
from feed.model import (
    Feed,
    FeedItem,
    KIND_RSS,
    KIND_ATOM,
    KIND_JSON,
    _set_if_empty,
    _stripped,
)
from feed.xml_parser import (
    XmlPullParser,
    normalize_encoding_bytes,
    EVENT_START,
    EVENT_END,
    EVENT_TEXT,
    EVENT_EOF,
)


def _canonical_ns_prefix(uri: String) -> String:
    """Canonical prefix for a known namespace URI, or "" if unknown."""
    if uri == "http://www.itunes.com/dtds/podcast-1.0.dtd":
        return String("itunes")
    if uri == "http://purl.org/dc/elements/1.1/":
        return String("dc")
    if uri == "http://purl.org/rss/1.0/modules/content/":
        return String("content")
    if (
        uri == "http://search.yahoo.com/mrss/"
        or uri == "https://search.yahoo.com/mrss/"
        or uri == "http://search.yahoo.com/mrss"
    ):
        return String("media")
    if (
        uri == "https://podcastindex.org/namespace/1.0"
        or uri == "http://podcastindex.org/namespace/1.0"
    ):
        return String("podcast")
    if uri == "http://www.w3.org/1999/02/22-rdf-syntax-ns#":
        return String("rdf")
    return String()


def _colon_index(name: String) -> Int:
    """Byte offset of the first ':' in `name`, or -1."""
    var bytes = name.as_bytes()
    for i in range(len(bytes)):
        if bytes[i] == UInt8(ord(":")):
            return i
    return -1


def _canon_name(name: String, ns_map: Dict[String, String]) raises -> String:
    """Rewrite a prefixed name to its canonical prefix if the document
    bound the prefix to a known namespace URI."""
    if len(ns_map) == 0:
        # Fast path: the map only holds bindings that differ from the
        # canonical prefix, so almost every real feed lands here.
        return name.copy()
    var colon = _colon_index(name)
    if colon <= 0:
        return name.copy()
    var bytes = name.as_bytes()
    var prefix = String(StringSlice(unsafe_from_utf8=bytes[0:colon]))
    if prefix in ns_map:
        var local = String(StringSlice(unsafe_from_utf8=bytes[colon + 1 :]))
        return ns_map[prefix] + ":" + local
    return name.copy()


def _collect_ns(attrs: Dict[String, String], mut ns_map: Dict[String, String]):
    """Record xmlns:foo declarations that bind known namespace URIs."""
    for entry in attrs.items():
        if entry.key.startswith("xmlns:"):
            var key_bytes = entry.key.as_bytes()
            var declared = String(StringSlice(unsafe_from_utf8=key_bytes[6:]))
            var canon = _canonical_ns_prefix(entry.value)
            # Only record bindings that actually need rewriting — feeds
            # using conventional prefixes keep the map empty, which
            # keeps _canon_name on its zero-cost fast path.
            if canon.byte_length() > 0 and canon != declared:
                ns_map[declared] = canon^


def parse_feed_bytes(data: Span[UInt8, _], *, strict: Bool = False) raises -> Feed:
    """Parse raw feed bytes (any supported encoding) into a `Feed`."""
    return parse_feed(normalize_encoding_bytes(data), strict=strict)


def parse_feed(var source: String, *, strict: Bool = False) raises -> Feed:
    """Parse an RSS, Atom, or JSON Feed document into a `Feed`.

    With `strict=True` (XML formats only) well-formedness violations —
    mismatched/stray end tags, unclosed elements, bad entities — raise
    with a line/column location instead of being liberally recovered.
    """
    var head = source.as_bytes()
    var i = 0
    while i < len(head) and (
        head[i] == 0x20 or head[i] == 0x09 or head[i] == 0x0A
        or head[i] == 0x0D
    ):
        i += 1
    if i < len(head) and head[i] == UInt8(ord("{")):
        return parse_json_feed(source^)
    var parser = XmlPullParser(source^, strict=strict)
    var feed = Feed()
    var item = FeedItem()
    var stack = List[String]()
    var ns_map = Dict[String, String]()
    var in_item = False
    var item_depth = 0
    var text = String()
    # True once pub_date came from pubDate/published (authoritative),
    # as opposed to the <updated>/<dc:date> fallbacks, which they must
    # override regardless of document order.
    var pub_date_authoritative = False

    while True:
        var event = parser.next_event()
        if event.kind == EVENT_EOF:
            break

        if event.kind == EVENT_START:
            if len(event.attrs) > 0:
                _collect_ns(event.attrs, ns_map)
            if len(ns_map) > 0:
                var canon = _canon_name(event.name, ns_map)
                event.name = canon^
            ref name = event.name
            stack.append(name.copy())
            var depth = len(stack)
            if depth == 1:
                if name == "rss":
                    feed.kind = String(KIND_RSS)
                elif name == "feed":
                    feed.kind = String(KIND_ATOM)
                elif name == "rdf:RDF" or name == "RDF":
                    # RSS 0.90 / RSS 1.0: RDF root; <channel> holds the
                    # metadata and <item> elements are its *siblings*.
                    # Depths line up with RSS 2.0 (channel fields at 3)
                    # and items are tracked by name at any depth, so the
                    # same mapping path applies.
                    feed.kind = String(KIND_RSS)
                else:
                    raise Error(
                        "mojo-feed: unsupported root element: " + event.name
                    )
            # Reset accumulation when a field-level element opens; keep
            # accumulating inside its children so mixed content like
            # <summary>Hello <b>world</b> foo</summary> survives intact.
            if depth <= _field_depth(feed.kind, in_item, item_depth):
                text = String()
            if not in_item and (name == "item" or name == "entry"):
                in_item = True
                item_depth = depth
                item = FeedItem()
                pub_date_authoritative = False
                # RSS 1.0 items identify themselves via rdf:about.
                _set_if_empty(
                    item.guid, String(event.attrs.get("rdf:about", String()))
                )
            elif in_item and name == "enclosure":
                item.enclosure_url = String(event.attrs.get("url", String()))
                item.enclosure_type = String(event.attrs.get("type", String()))
                item.enclosure_length = String(
                    event.attrs.get("length", String())
                )
            elif in_item and name == "media:content":
                # Media RSS (YouTube, Feedburner). May sit directly in the
                # item or nested inside <media:group>. A real <enclosure>
                # wins; this fills in when it's the only media reference.
                _set_if_empty(
                    item.enclosure_url, String(event.attrs.get("url", String()))
                )
                _set_if_empty(
                    item.enclosure_type,
                    String(event.attrs.get("type", String())),
                )
                _set_if_empty(
                    item.enclosure_length,
                    String(event.attrs.get("fileSize", String())),
                )
            elif name == "link" and feed.kind == KIND_ATOM:
                # Atom links carry their payload in attributes. Depth
                # guards keep links inside <source> or other nested
                # containers from masquerading as the entry's.
                var rel = String(event.attrs.get("rel", String()))
                var href = String(event.attrs.get("href", String()))
                if rel.byte_length() == 0 or rel == "alternate":
                    if in_item and depth == item_depth + 1:
                        _set_if_empty(item.link, href)
                    elif not in_item and depth == 2:
                        _set_if_empty(feed.link, href)
                elif rel == "enclosure":
                    # Atom-native podcast media reference.
                    if in_item and depth == item_depth + 1:
                        _set_if_empty(item.enclosure_url, href)
                        _set_if_empty(
                            item.enclosure_type,
                            String(event.attrs.get("type", String())),
                        )
                        _set_if_empty(
                            item.enclosure_length,
                            String(event.attrs.get("length", String())),
                        )

        elif event.kind == EVENT_TEXT:
            text += event.text

        elif event.kind == EVENT_END:
            if len(ns_map) > 0:
                var canon = _canon_name(event.name, ns_map)
                event.name = canon^
            ref name = event.name
            # Liberal recovery: match the nearest open element with this
            # name, implicitly closing anything opened above it (e.g. a
            # bare <br>). A stray end tag matching nothing is ignored.
            var idx = -1
            for i in range(len(stack) - 1, -1, -1):
                if stack[i] == name:
                    idx = i
                    break
            if idx == -1:
                continue
            var effective_depth = idx + 1
            var threshold = _field_depth(feed.kind, in_item, item_depth)
            var value = _stripped(text)

            if in_item:
                if name == "item" or name == "entry":
                    if effective_depth == item_depth:
                        feed.items.append(item^)
                        item = FeedItem()
                        in_item = False
                elif effective_depth == item_depth + 1:
                    _assign_item_field(
                        item, name, value, feed.kind,
                        pub_date_authoritative,
                    )
                elif (
                    effective_depth == item_depth + 2
                    and name == "name"
                    and stack[idx - 1] == "author"
                ):
                    # Atom <author><name>…</name></author>
                    _set_if_empty(item.author, value)
                elif name == "media:description":
                    # Media RSS description, typically nested inside
                    # <media:group> (YouTube) — any depth within the item.
                    _set_if_empty(item.description, value)
            elif (
                effective_depth == 3
                and feed.kind == KIND_RSS
                and stack[idx - 1] == "channel"
            ):
                # Channel-level fields: /rss/channel/* — the parent check
                # keeps RSS 1.0 <image>/<textinput> siblings (which also
                # carry <title>/<link> at depth 3) out of the channel.
                if name == "title":
                    _set_if_empty(feed.title, value)
                elif name == "link":
                    _set_if_empty(feed.link, value)
                elif name == "description":
                    _set_if_empty(feed.description, value)
                elif name == "language":
                    _set_if_empty(feed.language, value)
            elif effective_depth == 2 and feed.kind == KIND_ATOM:
                # Feed-level fields: /feed/*
                if name == "title":
                    _set_if_empty(feed.title, value)
                elif name == "subtitle":
                    _set_if_empty(feed.description, value)

            stack.shrink(idx)
            # Clear accumulation once a field-level element closes; a
            # nested child closing keeps the running text.
            if effective_depth <= threshold:
                text = String()

    return feed^


def _field_depth(kind: String, in_item: Bool, item_depth: Int) -> Int:
    """Stack depth at which capturable field elements live."""
    if in_item:
        return item_depth + 1
    if kind == KIND_ATOM:
        return 2  # /feed/*
    return 3  # /rss/channel/*


def _assign_item_field(
    mut item: FeedItem,
    name: String,
    value: String,
    kind: String,
    mut pub_date_authoritative: Bool,
):
    """Map one closed child element of an item/entry onto the model."""
    if name == "title":
        _set_if_empty(item.title, value)
    elif name == "link":
        # RSS text link; Atom links were handled from attributes.
        if kind == KIND_RSS:
            _set_if_empty(item.link, value)
    elif name == "description" or name == "summary":
        _set_if_empty(item.description, value)
    elif name == "content" or name == "content:encoded":
        _set_if_empty(item.content, value)
    elif name == "pubDate" or name == "published":
        # Authoritative: overrides an <updated>/<dc:date> fallback even
        # when the fallback appeared earlier in the document.
        if not pub_date_authoritative:
            item.pub_date = value.copy()
            pub_date_authoritative = True
    elif name == "updated" or name == "dc:date":
        # Fallbacks when <published>/<pubDate> is absent: Atom <updated>
        # and the Dublin Core date used by RSS 1.0 feeds.
        _set_if_empty(item.pub_date, value)
    elif name == "guid" or name == "id":
        _set_if_empty(item.guid, value)
    elif name == "author" or name == "itunes:author" or name == "dc:creator":
        _set_if_empty(item.author, value)
    elif name == "itunes:duration":
        _set_if_empty(item.duration, value)
    elif name == "itunes:episode" or name == "podcast:episode":
        _set_if_empty(item.episode_number, value)
